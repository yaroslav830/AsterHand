package com.pocketagent;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.os.*;
import android.speech.*;
import android.speech.tts.*;
import org.json.*;
import java.util.*;

/** Application-owned continuous voice. Floating controls never open an Activity. */
public final class VoiceController implements AgentTaskService.Listener, RecognitionListener {
    private static VoiceController instance;
    public static synchronized VoiceController get(Context context) {
        if (instance == null) instance = new VoiceController(context.getApplicationContext());
        return instance;
    }
    private final Context app;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final SharedPreferences prefs;
    private final VoiceIdlePolicy idle = new VoiceIdlePolicy();
    private SpeechRecognizer recognizer;
    private TextToSpeech speaker;
    private volatile boolean active, microphoneMuted, spokenMuted, listening, speaking, waiting, engineReady, serviceReady, recognitionPending;
    private volatile String status = "语音未开启", transcript = "", spokenText = "";
    private int generation, captureGeneration, failures;
    private String spokenState = "", lastUtterance = "", captureTaskId = "", captureQuestionId = "";
    private boolean idleTicking;
    private final Runnable idleTicker = new Runnable() { public void run() {
        idleTicking=false;if(!active||idle.timeout()==0)return;
        refreshIdle(false);
        if(idle.expired(SystemClock.elapsedRealtime())){int seconds=idle.timeout();stopInternal("因 "+seconds+" 秒无回应已结束语音",true);return;}
        idleTicking=true;main.postDelayed(this,500);
    }};

    private VoiceController(Context context) {
        app = context; prefs = app.getSharedPreferences("voice", 0);
        microphoneMuted = prefs.getBoolean("micMuted", false);
        spokenMuted = prefs.getBoolean("speechMuted", false);
        int stored=prefs.getInt("idleTimeoutSeconds",5),timeout=VoiceIdlePolicy.productTimeout(stored);idle.configure(timeout,SystemClock.elapsedRealtime());if(stored!=timeout)prefs.edit().putInt("idleTimeoutSeconds",timeout).apply();
        AgentTaskService.addListener(this);
    }
    public boolean enabled() { return active; }
    public boolean micMuted() { return microphoneMuted; }
    public boolean speechMuted() { return spokenMuted; }
    public boolean listening() { return listening; }
    public boolean speaking() { return speaking; }
    public String status() { return status; }
    public String transcript() { return transcript; }
    public String reply() { return spokenText; }
    public JSONObject snapshot() {
        JSONObject state = new JSONObject();
        try {
            state.put("active", active).put("status", status).put("micMuted", microphoneMuted).put("speechMuted", spokenMuted)
                    .put("listening", listening).put("speaking", speaking).put("waiting", waiting)
                    .put("transcript", transcript).put("reply", spokenText)
                    .put("canSubmit", active && recognitionPending && !microphoneMuted && !transcript.trim().isEmpty())
                    .put("canInterrupt", active && speaking).put("language", prefs.getString("language", "system"))
                    .put("silenceSeconds", silenceSeconds()).put("idleTimeoutSeconds",idle.timeout())
                    .put("idleRemainingSeconds",idle.remaining(SystemClock.elapsedRealtime())).put("idlePaused",idle.paused());
        } catch (JSONException ignored) {}
        return state;
    }
    public void setLanguage(String tag) {
        final String value = tag == null || tag.trim().isEmpty() ? "system" : tag.trim();
        if (!value.equals("system") && !value.matches("[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*")) throw new IllegalArgumentException("识别语言无效");
        main.post(() -> {
            prefs.edit().putString("language", value).apply();
            if (speaker != null && !speaking) updateSpeakerLanguage();
            if (recognitionPending) { cancelCapture(); generation++; scheduleListen(200); }
            updateOverlay();
        });
    }
    public void setSilenceSeconds(float seconds) {
        if (Float.isNaN(seconds) || Float.isInfinite(seconds) || seconds < 1 || seconds > 5) throw new IllegalArgumentException("停顿时间须为 1 至 5 秒");
        main.post(() -> { prefs.edit().putFloat("silenceSeconds", seconds).apply(); updateOverlay(); });
    }
    private float silenceSeconds() {
        float seconds = prefs.getFloat("silenceSeconds", 1.5f);
        return Float.isNaN(seconds) || Float.isInfinite(seconds) ? 1.5f : Math.max(1, Math.min(5, seconds));
    }
    public void setIdleTimeoutSeconds(int seconds) {
        VoiceIdlePolicy.requireProductTimeout(seconds);
        main.post(()->{prefs.edit().putInt("idleTimeoutSeconds",seconds).apply();idle.configure(seconds,SystemClock.elapsedRealtime());updateOverlay();});
    }
    public void toggle() { if (active) stop(); else start(); }
    public void start() { if(!ServiceMaster.enabled(app))return;main.post(() -> {
        if (active) return;
        if (app.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) { state("请先在应用中允许麦克风权限"); return; }
        if (!SpeechRecognizer.isRecognitionAvailable(app)) { state("系统未安装语音识别服务，可在系统设置中安装或启用后重试"); return; }
        active = true; serviceReady = false; failures = 0; generation++;
        JSONObject existing = AgentTaskService.snapshot(app);
        spokenState = !existing.optBoolean("running") ? existing.optString("id") + ":reply:" + existing.optString("reply") : "";
        state("正在开启语音");
        try { Intent intent = new Intent(app, VoiceService.class); if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(intent); else app.startService(intent); }
        catch (RuntimeException error) { failedStart("系统暂不允许后台开启麦克风，请先在应用内开启语音"); }
    }); }
    public void stop() { main.post(() -> stopInternal("语音已结束", true)); }
    private void stopInternal(String message, boolean stopService) {
        active = false; serviceReady = false; waiting = false; speaking = false; generation++;
        main.removeCallbacks(idleTicker);idleTicking=false;idle.update(false,false,SystemClock.elapsedRealtime());
        cancelCapture(); lastUtterance = "";
        if (speaker != null) { speaker.stop(); speaker.shutdown(); speaker = null; }
        engineReady = false; state(message);
        if (stopService) app.stopService(new Intent(app, VoiceService.class));
    }
    /** Sends the current partial immediately, without waiting for the recognizer endpoint. */
    public void submitUtterance() { main.post(() -> {
        if (!active || !recognitionPending || microphoneMuted) return;
        String text = transcript.trim();
        if (text.isEmpty()) { state("尚未识别到文字，请继续说话"); return; }
        cancelCapture(); sendText(text);
    }); }
    /** One-off interruption: does not change the persistent read-aloud mute. */
    public void interruptSpeech() { main.post(() -> {
        if (!active || !speaking) return;
        lastUtterance = ""; speaking = false; generation++;
        if (speaker != null) speaker.stop();
        state(microphoneMuted ? "麦克风已静音" : "准备聆听"); scheduleListen(200);
    }); }
    public void setMicMuted(boolean value) { main.post(() -> {
        microphoneMuted = value; prefs.edit().putBoolean("micMuted", value).apply();
        if (value) { cancelCapture(); state("麦克风已静音"); }
        else { state(active ? "麦克风已开启" : "语音未开启"); scheduleListen(150); }
        updateOverlay();
    }); }
    public void setSpeechMuted(boolean value) { main.post(() -> {
        spokenMuted = value; prefs.edit().putBoolean("speechMuted", value).apply();
        if (value && speaker != null) { lastUtterance = ""; speaker.stop(); speaking = false; generation++; }
        state(value ? "朗读已静音" : active ? "朗读已开启" : "语音未开启");
        if (value) scheduleListen(200); updateOverlay();
    }); }
    void serviceReady() { main.post(() -> {
        if (!active || serviceReady) return;
        serviceReady = true;
        try { initSpeaker(); scheduleListen(150); } catch (RuntimeException error) { stopInternal("无法启动系统语音服务", true); }
    }); }
    void serviceStopped() { main.post(() -> { if (active) stopInternal("语音服务已停止", false); }); }
    void failedStart(String message) { main.post(() -> stopInternal(message, true)); }
    private void initSpeaker() {
        if (speaker != null) return;
        speaker = new TextToSpeech(app, result -> main.post(() -> { if (result == TextToSpeech.SUCCESS && speaker != null) updateSpeakerLanguage(); else engineReady = false; }));
        speaker.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build());
        speaker.setOnUtteranceProgressListener(new UtteranceProgressListener() {
            public void onStart(String id) {}
            public void onDone(String id) { main.post(() -> { if (id.equals(lastUtterance)) { speaking = false; lastUtterance = ""; updateOverlay(); scheduleListen(300); } }); }
            public void onError(String id) { main.post(() -> { if (id.equals(lastUtterance)) { speaking = false; lastUtterance = ""; state("朗读失败，文字回复已保留"); scheduleListen(300); } }); }
        });
    }
    private void updateSpeakerLanguage() {
        int result = speaker.setLanguage(language());
        engineReady = result != TextToSpeech.LANG_MISSING_DATA && result != TextToSpeech.LANG_NOT_SUPPORTED;
        if (!engineReady) state("当前语言没有系统朗读声音，可继续使用文字回复");
    }
    private Locale language() {
        String tag = prefs.getString("language", "system");
        if (tag == null || tag.equals("system")) return Locale.getDefault();
        Locale result = Locale.forLanguageTag(tag); return result.getLanguage().isEmpty() ? Locale.getDefault() : result;
    }
    private void scheduleListen(long delay) { int epoch = generation; main.postDelayed(() -> { if (epoch == generation) listen(); }, delay); }
    private void cancelCapture() {
        captureGeneration++; recognitionPending = false; listening = false;
        if (recognizer != null) { try { recognizer.cancel(); recognizer.destroy(); } catch (RuntimeException ignored) {} recognizer = null; }
    }
    private void listen() {
        if (!active || !serviceReady || microphoneMuted || speaking || recognitionPending) return;
        JSONObject task = AgentTaskService.snapshot(app);
        if (task.optBoolean("running") && !task.optBoolean("attention")) { waiting = true; state("等待 AI 回复"); return; }
        if(task.optBoolean("attention")&&!task.optString("questionKind","question").equals("question")){waiting=true;state("请在界面明确选择授权选项，语音不会代替授权");return;}
        captureTaskId=task.optBoolean("attention")?task.optString("id"):"";
        captureQuestionId=task.optBoolean("attention")?task.optString("questionId"):"";
        waiting = false;
        try {
            cancelCapture(); final int token = ++captureGeneration;
            recognizer = SpeechRecognizer.createSpeechRecognizer(app);
            // Each capture owns its callbacks. A cancelled/manual-send capture cannot submit twice.
            recognizer.setRecognitionListener(new RecognitionListener() {
                private boolean current() { return token == captureGeneration && active; }
                public void onReadyForSpeech(Bundle value) { if (current()) VoiceController.this.onReadyForSpeech(value); }
                public void onBeginningOfSpeech() { if (current()) VoiceController.this.onBeginningOfSpeech(); }
                public void onRmsChanged(float value) { if (current()) VoiceController.this.onRmsChanged(value); }
                public void onBufferReceived(byte[] value) { if (current()) VoiceController.this.onBufferReceived(value); }
                public void onEndOfSpeech() { if (current()) VoiceController.this.onEndOfSpeech(); }
                public void onError(int value) { if (current()) VoiceController.this.onError(value); }
                public void onResults(Bundle value) { if (current()) VoiceController.this.onResults(value); }
                public void onPartialResults(Bundle value) { if (current()) VoiceController.this.onPartialResults(value); }
                public void onEvent(int type, Bundle value) { if (current()) VoiceController.this.onEvent(type, value); }
            });
            Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, language().toLanguageTag());
            intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
            intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
            intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, (long) Math.round(silenceSeconds() * 1000));
            transcript = ""; listening = true; recognitionPending = true; recognizer.startListening(intent); state("正在聆听"); updateOverlay();
        } catch (RuntimeException error) { cancelCapture(); stopInternal("系统无法开始录音，请检查麦克风和语音服务", true); }
    }
    private void speak(String value) {
        if (!active) return;
        cancelCapture(); spokenText = value == null ? "" : value.trim();
        if (spokenMuted || !engineReady || speaker == null || spokenText.isEmpty()) { speaking = false; updateOverlay(); scheduleListen(200); return; }
        speaking = true; state("正在朗读"); updateOverlay();
        String base = UUID.randomUUID().toString(); int size = Math.max(256, TextToSpeech.getMaxSpeechInputLength() - 64);
        int chunks = (spokenText.length() + size - 1) / size; lastUtterance = base + ":" + (chunks - 1);
        for (int i = 0; i < chunks; i++) {
            String part = spokenText.substring(i * size, Math.min(spokenText.length(), (i + 1) * size));
            if (speaker.speak(part, i == 0 ? TextToSpeech.QUEUE_FLUSH : TextToSpeech.QUEUE_ADD, new Bundle(), base + ":" + i) == TextToSpeech.ERROR) {
                lastUtterance = ""; speaking = false; state("系统朗读不可用，文字回复已保留"); scheduleListen(200); break;
            }
        }
    }
    @Override public void onChanged(JSONObject task) {
        if (!active) return;
        boolean running = task.optBoolean("running"), attention = task.optBoolean("attention");
        if (running && !attention) { waiting = true; if (recognitionPending) cancelCapture(); state("等待 AI 回复"); return; }
        if (!running && (!task.optString("error").isEmpty() || task.optString("stage").contains("停止") || task.optString("stage").contains("中断"))) {
            waiting = false; state("任务已结束，可继续说话"); scheduleListen(350); return;
        }
        String value = attention ? task.optString("question") : task.optString("reply");
        String signature = task.optString("id") + ":" + (attention ? "question:"+task.optString("questionId")+":" : "reply:") + value;
        waiting = false;
        if (!value.isEmpty() && !signature.equals(spokenState)) { spokenState = signature; speak(value); }
        else if (!speaking && !recognitionPending) scheduleListen(250);
    }
    private void sendText(String text) {
        if (!active || text.trim().isEmpty()) return;
        transcript = text.trim(); failures = 0; waiting = true; refreshIdle(true);state("正在发送语音消息"); updateOverlay();
        try {
            JSONObject task=AgentTaskService.snapshot(app);
            if(task.optBoolean("attention")&&!task.optString("questionKind","question").equals("question"))throw new Exception("请在界面明确选择授权选项，语音不会代替授权");
            if(!captureQuestionId.isEmpty()){
                if(!AgentTaskService.answer(transcript,new JSONArray(),captureTaskId,captureQuestionId))throw new Exception("问题已更新，请查看当前问题后重新回答");
            }else if(task.optBoolean("attention"))throw new Exception("问题已更新，请查看当前问题后重新回答");
            else AgentSession.get(app).send(transcript,new JSONArray());
            if (!AgentTaskService.snapshot(app).optBoolean("running")) { waiting = false; scheduleListen(300); }
        }
        catch (Exception error) { waiting = false; state(error.getMessage() == null ? "语音消息发送失败" : error.getMessage()); scheduleListen(700); }
    }
    @Override public void onResults(Bundle results) {
        if (!active || !recognitionPending) return;
        ArrayList<String> values = results == null ? null : results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
        String text = values == null || values.isEmpty() ? transcript.trim() : values.get(0).trim();
        cancelCapture(); if (text.isEmpty()) { scheduleListen(350); return; } sendText(text);
    }
    @Override public void onError(int code) {
        cancelCapture(); if (!active || microphoneMuted || speaking || waiting) return;
        if (code == SpeechRecognizer.ERROR_NO_MATCH || code == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) { scheduleListen(650); return; }
        if (code == SpeechRecognizer.ERROR_RECOGNIZER_BUSY) { scheduleListen(900); if (++failures > 3) stopInternal("语音服务持续忙碌，请稍后重新开启", true); return; }
        String message = code == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ? "麦克风权限未允许" : code == SpeechRecognizer.ERROR_NETWORK || code == SpeechRecognizer.ERROR_NETWORK_TIMEOUT ? "语音识别网络不可用" : code == SpeechRecognizer.ERROR_AUDIO ? "麦克风暂不可用" : "语音识别失败（" + code + "）";
        if (++failures >= 3 || code == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) stopInternal(message, true);
        else { state(message + "，正在重试"); scheduleListen(1500); }
    }
    @Override public void onReadyForSpeech(Bundle params) { if (recognitionPending) state("正在聆听"); }
    @Override public void onBeginningOfSpeech() { if (recognitionPending) { failures = 0; state("正在听你说"); } }
    @Override public void onEndOfSpeech() { if (recognitionPending) { listening = false; state("正在识别"); } }
    @Override public void onPartialResults(Bundle partial) {
        if (!active || !recognitionPending || microphoneMuted || partial == null) return;
        ArrayList<String> values = partial.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
        if (values != null && !values.isEmpty() && values.get(0) != null && !values.get(0).equals(transcript)) {
            transcript = values.get(0); refreshIdle(true);updateOverlay();
        }
    }
    @Override public void onRmsChanged(float level) {}
    @Override public void onBufferReceived(byte[] buffer) {}
    @Override public void onEvent(int type, Bundle params) {}
    private void state(String value) { String next = value == null ? "" : value; if (!next.equals(status)) { status = next; updateOverlay(); } }
    private void updateOverlay() {
        refreshIdle(false);
        if(active&&idle.timeout()>0&&!idleTicking){idleTicking=true;main.postDelayed(idleTicker,500);}
        else if((!active||idle.timeout()==0)&&idleTicking){main.removeCallbacks(idleTicker);idleTicking=false;}
        FloatingOverlayService.updateVoiceState(snapshot());
        VoiceService.updateStatus(status);
    }
    private void refreshIdle(boolean userInput){JSONObject task=AgentTaskService.snapshot(app);boolean waitingForUser=active&&!speaking&&!(task.optBoolean("running")&&!task.optBoolean("attention"));idle.update(waitingForUser,userInput,SystemClock.elapsedRealtime());}
}
