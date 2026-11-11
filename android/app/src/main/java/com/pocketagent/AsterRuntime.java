package com.pocketagent;
import android.content.*;
import android.os.*;
import android.widget.Toast;
import org.json.*;

/** Application-lifetime wiring: callbacks never retain an Activity. */
public final class AsterRuntime implements AgentTaskService.Listener {
    private static AsterRuntime instance;
    private final Context app;
    private final Handler main=new Handler(Looper.getMainLooper());
    private boolean foreground,aiControl,autoOverlay,combinedAiControl;
    private long lastTaskGeneration;
    private final Runnable poll=new Runnable(){public void run(){refreshRemote();main.postDelayed(this,1000);}};
    private AsterRuntime(Context c){app=c.getApplicationContext();UILocalization.initialize(app);}
    static synchronized void ensure(Context c){if(instance==null){instance=new AsterRuntime(c);instance.wire();}}
    public static void configure(Context c){ensure(c);AsterBackgroundService.configure(c);}
    public static synchronized void restart(Context c)throws Exception{boolean visible=instance!=null&&instance.foreground;if(instance!=null){instance.main.removeCallbacksAndMessages(null);AgentTaskService.removeListener(instance);}instance=null;ensure(c);instance.foreground=visible;RemoteControlHub hub=RemoteControlHub.get(c);hub.setUiActive(visible);AsterBackgroundService.configure(c);if(ServiceMaster.enabled(c)&&(visible||c.getSharedPreferences("MainActivity",0).getBoolean("background",true)))hub.start();}
    static boolean isForeground(){return instance!=null&&instance.foreground;}
    public static void setForeground(boolean value){AsterRuntime r=instance;if(r==null)return;r.main.post(()->{r.foreground=value;FloatingOverlayService.setAppForeground(value);RemoteControlHub hub=RemoteControlHub.get(r.app);hub.setUiActive(value&&ServiceMaster.enabled(r.app));if(value&&ServiceMaster.enabled(r.app))try{hub.start();}catch(Exception e){r.toast(e.getMessage());}else if(!ServiceMaster.enabled(r.app)||!r.app.getSharedPreferences("MainActivity",0).getBoolean("background",true))hub.stop();r.refreshConsent();});}
    private void wire(){AgentSession.get(app);VoiceController.get(app);FloatingOverlayService.configure(new FloatingOverlayService.Actions(){
        public void onSend(String text){try{AgentSession.get(app).send(text,new JSONArray());}catch(Exception e){toast(e.getMessage());}}
        public void onContinue(){try{AgentSession.get(app).resume();}catch(Exception e){toast(e.getMessage());}}
        public void onVoice(){VoiceController.get(app).toggle();}
        public void onMicMute(){VoiceController v=VoiceController.get(app);v.setMicMuted(!v.micMuted());}
        public void onSpeechMute(){VoiceController v=VoiceController.get(app);v.setSpeechMuted(!v.speechMuted());}
        public void onOpen(){app.startActivity(new Intent(app,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_SINGLE_TOP));}
    });RemoteControlHub.get(app).setRequestListener(this::refreshConsent);AgentTaskService.addListener(this);main.post(poll);}
    private void toast(String s){main.post(()->Toast.makeText(app,UILocalization.t(s==null?"操作失败":s),Toast.LENGTH_LONG).show());}
    @Override public void onChanged(JSONObject state){boolean running=state.optBoolean("running");String stage=state.optString("stage");if(running&&(stage.contains("屏幕")||stage.contains("输入文字")||stage.contains("返回桌面")))aiControl=true;if(!running)aiControl=false;refreshRemote();}
    private void updateIndicators(boolean remoteAi,boolean manual,boolean connected){
        boolean active=aiControl||remoteAi;
        if(active&&!combinedAiControl){lastTaskGeneration++;if(!FloatingOverlayService.enabled(app)&&FloatingOverlayService.permitted(app)){autoOverlay=true;FloatingOverlayService.showTemporarily(app);}}
        if(!active&&combinedAiControl){long generation=++lastTaskGeneration;if(autoOverlay){autoOverlay=false;main.postDelayed(()->{if(generation==lastTaskGeneration&&!combinedAiControl)FloatingOverlayService.hideTemporary(app);},3000);}}
        combinedAiControl=active;FloatingOverlayService.setControlState(active,manual,connected);
    }
    private void refreshRemote(){try{JSONObject state=RemoteControlHub.get(app).info();updateIndicators(state.optBoolean("remote_ai_controlling"),state.optBoolean("remote_controlling"),state.optBoolean("remote_connected"));}catch(Exception ignored){updateIndicators(false,false,false);}}
    private void refreshConsent(){main.post(()->{try{if(foreground||!app.getSharedPreferences("MainActivity",0).getBoolean("background",true)||RemoteControlHub.get(app).pending().length()==0){RemoteConsentService.close(app);return;}RemoteConsentService.show(app);}catch(Exception ignored){}});}
}
