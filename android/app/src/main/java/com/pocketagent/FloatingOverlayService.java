package com.pocketagent;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.content.res.Configuration;
import android.graphics.*;
import android.graphics.drawable.*;
import android.os.*;
import android.provider.Settings;
import android.text.Editable;
import android.text.TextWatcher;
import android.text.TextUtils;
import android.view.*;
import android.view.inputmethod.InputMethodManager;
import android.widget.*;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

/** Small independently sized overlay windows. Decorative content never occupies the full touch surface. */
public final class FloatingOverlayService extends Service implements AgentTaskService.Listener {
    public interface Actions{void onSend(String text);void onContinue();void onVoice();void onMicMute();void onSpeechMute();void onOpen();}
    private static volatile FloatingOverlayService instance;
    private static volatile Actions actions;
    private static volatile boolean automationHidden,foreground,voiceActive,micMuted,speechMuted;
    private static final java.util.concurrent.atomic.AtomicInteger automationDepth=new java.util.concurrent.atomic.AtomicInteger();
    private static volatile String voiceStatus="";
    private static volatile JSONObject voicePresentation=new JSONObject();
    private static volatile boolean controlAi,controlRemote,controlConnected;
    private static volatile boolean taskActive;
    private static final ArrayList<String> activationOrder=new ArrayList<>();
    private static final Handler main=new Handler(Looper.getMainLooper());
    private WindowManager manager;
    private ImageView bubble;
    private FloatingOverlayEffects effects;
    private WindowManager.LayoutParams effectsParams;
    private ScrollView panel;
    private TextView capsule,summary,heading,voiceLabel,question;
    private LinearLayout optionRows,panelBody,composeRow;
    private AlertDialog fullInfoDialog;
    private final Map<Button,String> localizedButtons=new WeakHashMap<>();private String buttonLanguage="";
    private EditText input;
    private Button stop,resume,voice,mic,speech,voiceSubmit,voiceInterrupt,showCapsule,send;
    private WindowManager.LayoutParams bubbleParams,panelParams,capsuleParams;
    private boolean panelOpen,capsuleWanted,capsuleDismissed,wasRunning,dark;
    private Boolean themeDark;
    private final android.content.SharedPreferences.OnSharedPreferenceChangeListener appearanceListener=(prefs,key)->main.post(()->{colors();if("capsuleLocked".equals(key)&&getSharedPreferences("overlay",0).getBoolean("capsuleLocked",false))resetCapsule();refresh();});
    private int screenWidth,screenHeight,textColor,muted,background,surface,imeHeight;
    private boolean keyboardReadQueued;
    private final Runnable keyboardReader=()->{keyboardReadQueued=false;if(panel!=null)keyboardHeight(displayKeyboardInset());};
    private String taskId="",side="below";
    private JSONObject state=new JSONObject();
    private final ArrayList<String> ringOrder=new ArrayList<>();
    private final HashSet<String> selectedOptions=new HashSet<>();
    private QuestionBinding shownQuestion;
    private static final class QuestionBinding{final String task,id,kind;final boolean multi;QuestionBinding(JSONObject state){task=state.optString("id");id=state.optString("questionId");kind=state.optString("questionKind","question");multi=state.optBoolean("multi");}}
    private boolean aiControl,remoteControl,remoteConnected;
    private long capsuleGeneration;
    private int voicePulse;
    private boolean voiceTicking;
    private final Runnable voiceTicker=new Runnable(){public void run(){voiceTicking=false;if(instance!=FloatingOverlayService.this||!voiceActive||!voicePresentation.optBoolean("listening")||capsuleDismissed)return;voicePulse=(voicePulse+1)%3;refreshCapsuleText();voiceTicking=true;main.postDelayed(this,450);}};

    public static void configure(Actions callback){actions=callback;}
    public static boolean permitted(Context c){return Settings.canDrawOverlays(c);}
    public static boolean enabled(Context c){return c.getSharedPreferences("overlay",MODE_PRIVATE).getBoolean("enabled",true);}
    public static void restore(Context c){if(enabled(c)&&permitted(c))start(c);}
    public static void show(Context c){c.getSharedPreferences("overlay",MODE_PRIVATE).edit().putBoolean("enabled",true).apply();if(permitted(c))start(c);}
    public static void showTemporarily(Context c){if(permitted(c))start(c);}
    public static void hideTemporary(Context c){if(!enabled(c))c.stopService(new Intent(c,FloatingOverlayService.class));}
    public static void hide(Context c){c.getSharedPreferences("overlay",MODE_PRIVATE).edit().putBoolean("enabled",false).apply();c.stopService(new Intent(c,FloatingOverlayService.class));}
    private static void start(Context c){if(!ServiceMaster.enabled(c))return;Intent intent=new Intent(c,FloatingOverlayService.class);try{if(Build.VERSION.SDK_INT>=26)c.startForegroundService(intent);else c.startService(intent);}catch(RuntimeException ignored){}}
    public static void setAppForeground(boolean value){foreground=value;}
    public static void updateVoiceState(boolean active,boolean microphoneMuted,boolean spokenMuted,String status){JSONObject value=new JSONObject();try{value.put("active",active).put("micMuted",microphoneMuted).put("speechMuted",spokenMuted).put("status",status==null?"":status);}catch(JSONException ignored){}updateVoiceState(value);}
    /** Presentation only: accepts a snapshot for diagnostics without enabling microphone or AI. */
    public static void updateVoiceState(JSONObject snapshot){try{voicePresentation=new JSONObject(snapshot==null?"{}":snapshot.toString());}catch(JSONException ignored){voicePresentation=new JSONObject();}voiceActive=voicePresentation.optBoolean("active");micMuted=voicePresentation.optBoolean("micMuted");speechMuted=voicePresentation.optBoolean("speechMuted");voiceStatus=voicePresentation.optString("status");main.post(()->{FloatingOverlayService s=instance;if(s!=null)s.refresh();});}
    public static void refreshAppearance(){main.post(()->{FloatingOverlayService s=instance;if(s!=null){s.colors();s.refresh();}});}
    public static void showGesture(String name,JSONObject args){main.post(()->{FloatingOverlayService s=instance;if(s==null||s.effects==null)return;try{if(name.equals("screen_tap")||name.equals("screen_swipe")){float x=(float)args.getDouble("x"),y=(float)args.getDouble("y"),x2=(float)args.optDouble("x2",x),y2=(float)args.optDouble("y2",y);if(x>=0&&x<=1&&y>=0&&y<=1&&x2>=0&&x2<=1&&y2>=0&&y2<=1){s.effects.gesture(name.equals("screen_swipe"),x,y,x2,y2);s.applyVisibility();}}}catch(Exception ignored){}});}
    private static void activity(String key,boolean active){if(active&&!activationOrder.contains(key))activationOrder.add(key);if(!active)activationOrder.remove(key);FloatingOverlayService s=instance;if(s!=null){s.ringOrder.clear();s.ringOrder.addAll(activationOrder);}}
    static void taskState(boolean running){if(taskActive==running)return;taskActive=running;main.post(()->{activity("task",running);FloatingOverlayService s=instance;if(s!=null)s.refresh();});}
    public static void setControlState(boolean ai,boolean remote,boolean connected){if(controlAi==ai&&controlRemote==remote&&controlConnected==connected)return;main.post(()->{controlAi=ai;controlRemote=remote;controlConnected=connected;activity("ai",ai);activity("remote",remote);activity("connected",connected);FloatingOverlayService s=instance;if(s!=null){s.aiControl=ai;s.remoteControl=remote;s.remoteConnected=connected;s.refresh();}});}

    /** Hide only for the duration of an automation step, never change the user's enabled preference. */
    public static void setAutomationHidden(boolean value){boolean changed;if(value){changed=automationDepth.incrementAndGet()==1;}else{int previous,next;do{previous=automationDepth.get();next=Math.max(0,previous-1);}while(!automationDepth.compareAndSet(previous,next));changed=previous==1;}automationHidden=automationDepth.get()>0;if(!changed)return;CountDownLatch latch=new CountDownLatch(1);Runnable change=()->{FloatingOverlayService s=instance;if(s!=null)s.applyVisibility();latch.countDown();};if(Looper.myLooper()==Looper.getMainLooper())change.run();else{main.post(change);try{latch.await(1,TimeUnit.SECONDS);if(value)Thread.sleep(80);}catch(InterruptedException e){Thread.currentThread().interrupt();}}}
    @Override public void onCreate(){super.onCreate();UILocalization.initialize(this);if(!permitted(this)){stopSelf();return;}instance=this;aiControl=controlAi;remoteControl=controlRemote;remoteConnected=controlConnected;ringOrder.addAll(activationOrder);manager=(WindowManager)getSystemService(WINDOW_SERVICE);colors();metrics();foregroundNotification();buildEffects();buildBubble();buildPanel();buildCapsule();for(String prefs:new String[]{"MainActivity","effects","overlay"})getSharedPreferences(prefs,0).registerOnSharedPreferenceChangeListener(appearanceListener);AgentTaskService.addListener(this);}
    @Override public int onStartCommand(Intent intent,int flags,int id){return START_NOT_STICKY;}
    @Override public IBinder onBind(Intent intent){return null;}
    @Override public void onConfigurationChanged(Configuration c){super.onConfigurationChanged(c);colors();metrics();if(effectsParams!=null){effectsParams.width=screenWidth;effectsParams.height=screenHeight;update(effects,effectsParams);}if(bubbleParams!=null){bubbleParams.x=Math.min(bubbleParams.x,screenWidth-dp(60));bubbleParams.y=Math.max(statusHeight(),Math.min(bubbleParams.y,screenHeight-dp(74)));update(bubble,bubbleParams);positionPanel(true);if(capsuleParams!=null){capsuleParams.x=Math.max(dp(8),Math.min(capsuleParams.x,screenWidth-capsuleParams.width-dp(8)));capsuleParams.y=Math.min(capsuleParams.y,screenHeight-dp(60));update(capsule,capsuleParams);}refresh();}}
    @Override public void onDestroy(){if(fullInfoDialog!=null)fullInfoDialog.dismiss();AgentTaskService.removeListener(this);for(String prefs:new String[]{"MainActivity","effects","overlay"})getSharedPreferences(prefs,0).unregisterOnSharedPreferenceChangeListener(appearanceListener);if(instance==this)instance=null;main.removeCallbacks(voiceTicker);main.removeCallbacks(keyboardReader);voiceTicking=false;keyboardReadQueued=false;remove(panel);remove(capsule);remove(bubble);remove(effects);stopForeground(true);super.onDestroy();}
    private void colors(){String appearance=getSharedPreferences("MainActivity",0).getString("appearance","system");dark=appearance.equals("dark")||(appearance.equals("system")&&(getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES);textColor=dark?0xfff1f2f4:0xff18191b;muted=dark?0xffa1a5ae:0xff6b707a;background=dark?0xf2222326:0xfafafafa;surface=dark?0xff34363b:0xffededf0;}
    private void metrics(){android.util.DisplayMetrics m=new android.util.DisplayMetrics();manager.getDefaultDisplay().getRealMetrics(m);screenWidth=m.widthPixels;screenHeight=m.heightPixels;}
    private int dp(float n){return (int)(getResources().getDisplayMetrics().density*n+.5f);}
    private int statusHeight(){int id=getResources().getIdentifier("status_bar_height","dimen","android");return id==0?dp(24):getResources().getDimensionPixelSize(id);}
    private WindowManager.LayoutParams params(int width,int height){WindowManager.LayoutParams p=new WindowManager.LayoutParams(width,height,Build.VERSION.SDK_INT>=26?WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY:WindowManager.LayoutParams.TYPE_PHONE,WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE|WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL|WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,PixelFormat.TRANSLUCENT);p.gravity=Gravity.TOP|Gravity.LEFT;p.softInputMode=WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE;if(Build.VERSION.SDK_INT>=28)p.layoutInDisplayCutoutMode=WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;return p;}
    private GradientDrawable rounded(int color,int radius){GradientDrawable g=new GradientDrawable();g.setColor(color);g.setCornerRadius(dp(radius));return g;}
    private TextView text(String s,int size){TextView v=new TextView(this);v.setOnLongClickListener(view->{showFullInfo(v.getText().toString(),null);return true;});v.setText(s);v.setTextSize(size);v.setTextColor(textColor);return v;}
    private LinearLayout row(){LinearLayout l=new LinearLayout(this);l.setOrientation(LinearLayout.HORIZONTAL);l.setGravity(Gravity.CENTER_VERTICAL);l.setClipChildren(true);l.setClipToPadding(true);return l;}
    private final class InfoButton extends Button {
        private final GestureDetector disabledHold;
        InfoButton(Context context){super(context);disabledHold=new GestureDetector(context,new GestureDetector.SimpleOnGestureListener(){
            @Override public boolean onDown(android.view.MotionEvent e){return true;}
            @Override public void onLongPress(android.view.MotionEvent e){String source=localizedButtons.get(InfoButton.this);showFullInfo(getText().toString(),source==null?null:fullInfoDescription(source));}
        });}
        @Override public boolean dispatchTouchEvent(android.view.MotionEvent event){if(!isEnabled()){disabledHold.onTouchEvent(event);return true;}return super.dispatchTouchEvent(event);}
    }
    private Button localizedButton(String source,Runnable action){Button b=button(UILocalization.t(source),action);localizedButtons.put(b,source);b.setOnLongClickListener(view->{showFullInfo(b.getText().toString(),fullInfoDescription(source));return true;});return b;}
    private String fullInfoDescription(String source){switch(source){
        case "继续":return "暂停或继续当前任务。长按不会执行任务操作。";case "停止":return "停止当前任务。已完成的操作不会撤销。";
        case "打开":return "在应用中查看完整任务、对话和设置。";case "显示胶囊":return "查看或隐藏状态胶囊。";
        case "发送":return state.optBoolean("attention")?"提交当前问题的回答。长按不会提交答案。":"向当前任务或所选对话发送消息。";case "隐藏":return "隐藏悬浮窗，可在应用中重新显示。";
        case "语音":return "开始或结束连续语音对话。";case "发送这句话":case "打断朗读":return "发送当前识别文字；正在朗读时可打断朗读。";
        case "麦克风":return "只切换麦克风静音，不结束语音会话。";case "朗读":return "只切换朗读静音，文字回复仍保留。";
        case "收起":return "收起悬浮菜单，保留悬浮按钮。";case "收起键盘":return "收起系统键盘。";default:return null;}}
    private void showFullInfo(String text,String description){if(text==null||text.isEmpty())return;if(fullInfoDialog!=null)fullInfoDialog.dismiss();
        String message=description==null?text:text+"\n\n"+UILocalization.t(description);
        int theme=dark?android.R.style.Theme_Material_Dialog_Alert:android.R.style.Theme_Material_Light_Dialog_Alert;
        AlertDialog dialog=new AlertDialog.Builder(this,theme).setTitle(UILocalization.t("完整信息")).setMessage(message).setPositiveButton(UILocalization.t("关闭"),(d,w)->d.dismiss()).create();
        dialog.getWindow().setType(Build.VERSION.SDK_INT>=26?WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY:WindowManager.LayoutParams.TYPE_PHONE);
        dialog.setOnDismissListener(d->{if(fullInfoDialog==dialog)fullInfoDialog=null;});fullInfoDialog=dialog;dialog.show();TextView content=dialog.findViewById(android.R.id.message);if(content!=null)content.setTextIsSelectable(true);
    }
    private Button button(String title,Runnable action){Button b=new InfoButton(this);b.setText(title);b.setOnLongClickListener(view->{showFullInfo(b.getText().toString(),null);return true;});b.setTextSize(12);b.setTextColor(textColor);b.setAllCaps(false);b.setSingleLine(true);b.setEllipsize(TextUtils.TruncateAt.END);b.setHorizontallyScrolling(false);b.setIncludeFontPadding(false);b.setGravity(Gravity.CENTER);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(0);b.setMinimumHeight(0);b.setPadding(dp(9),dp(4),dp(9),dp(4));b.setBackground(rounded(surface,11));b.setStateListAnimator(null);b.setElevation(0);b.setClipToOutline(true);String glyph=buttonGlyph(title);if(glyph!=null){Glyph icon=new Glyph(glyph,textColor);icon.setBounds(0,0,dp(14),dp(14));b.setCompoundDrawablePadding(dp(4));b.setCompoundDrawablesRelative(icon,null,null,null);}String reason=title.contains(UILocalization.t("停止"))?"stop":title.contains(UILocalization.t("发送"))?"start":"select";b.setOnClickListener(v->{Haptics.play(this,b,reason);action.run();});return b;}
    private static String buttonGlyph(String title){if(title.equals(UILocalization.t("收起")))return "collapse";if(title.equals(UILocalization.t("发送")))return "send";if(title.equals(UILocalization.t("收起键盘")))return "keyboard";if(title.equals(UILocalization.t("停止")))return "stop";if(title.equals(UILocalization.t("继续")))return "play";if(title.equals(UILocalization.t("语音")))return "voice";if(title.equals(UILocalization.t("麦克风")))return "mic";if(title.equals(UILocalization.t("朗读")))return "speech";if(title.equals(UILocalization.t("发送这句话")))return "check";if(title.equals(UILocalization.t("打断朗读")))return "pause";if(title.equals(UILocalization.t("显示胶囊")))return "capsule";if(title.equals(UILocalization.t("打开")))return "open";if(title.equals(UILocalization.t("隐藏")))return "hide";return null;}
    private void ring(String name,boolean active){if(active&&!ringOrder.contains(name))ringOrder.add(name);if(!active)ringOrder.remove(name);}
    private boolean effectEnabled(String name){return getSharedPreferences("effects",0).getBoolean(name,true);}
    private float effectNumber(String name,float fallback,float min,float max){Object v=getSharedPreferences("effects",0).getAll().get(name);float f=fallback;try{if(v instanceof Number)f=((Number)v).floatValue();else if(v instanceof String)f=Float.parseFloat((String)v);}catch(Exception ignored){}if(Float.isNaN(f)||Float.isInfinite(f))f=fallback;return Math.max(min,Math.min(max,f));}
    private ArrayList<String> activeRings(){ArrayList<String> visible=new ArrayList<>();for(String n:ringOrder){String key=n.equals("ai")?"ai_control":n.equals("remote")?"remote_control":n.equals("connected")?"remote_connected":"task";if(effectEnabled(key))visible.add(n);}return visible;}
    private void buildEffects(){effects=new FloatingOverlayEffects(this);effectsParams=params(screenWidth,screenHeight);effectsParams.x=0;effectsParams.y=0;effectsParams.flags|=WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE|WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS;effectsParams.alpha=.5f;manager.addView(effects,effectsParams);effects.setVisibility(View.GONE);}
    private void buildBubble(){bubble=new ImageView(this);bubble.setPadding(dp(8),dp(8),dp(8),dp(8));bubble.setContentDescription(UILocalization.t("AsterHand 悬浮菜单"));bubble.setScaleType(ImageView.ScaleType.FIT_CENTER);applyBubbleIcon();bubble.setBackground(new Rings());bubble.setElevation(dp(8));bubbleParams=params(dp(56),dp(56));bubbleParams.x=getSharedPreferences("overlay",0).getInt("x",screenWidth-dp(68));bubbleParams.y=getSharedPreferences("overlay",0).getInt("y",screenHeight/2);bubbleParams.x=Math.max(0,Math.min(bubbleParams.x,screenWidth-dp(56)));bubbleParams.y=Math.max(statusHeight(),Math.min(bubbleParams.y,screenHeight-dp(70)));bubble.setOnTouchListener(new View.OnTouchListener(){float x,y;int bx,by;boolean moved;public boolean onTouch(View v,android.view.MotionEvent e){switch(e.getActionMasked()){case MotionEvent.ACTION_DOWN:x=e.getRawX();y=e.getRawY();bx=bubbleParams.x;by=bubbleParams.y;moved=false;return true;case MotionEvent.ACTION_MOVE:float dx=e.getRawX()-x,dy=e.getRawY()-y;if(Math.hypot(dx,dy)>dp(5))moved=true;if(moved){bubbleParams.x=Math.max(0,Math.min(screenWidth-dp(56),bx+(int)dx));bubbleParams.y=Math.max(statusHeight(),Math.min(screenHeight-dp(64),by+(int)dy));update(bubble,bubbleParams);if(panelOpen)positionPanel(false);}return true;case MotionEvent.ACTION_UP:if(moved){getSharedPreferences("overlay",0).edit().putInt("x",bubbleParams.x).putInt("y",bubbleParams.y).apply();if(panelOpen)positionPanel(true);}else togglePanel();return true;case MotionEvent.ACTION_CANCEL:return true;}return false;}});manager.addView(bubble,bubbleParams);}
    // Resolve the complete artwork in the same appearance as the panel. A separate
    // configuration context also honors an explicit app appearance without restarting.
    private void applyBubbleIcon(){
        if(bubble==null)return;
        int resource=getResources().getIdentifier("asterhand_icon","drawable",getPackageName());
        Configuration appearance=new Configuration(getResources().getConfiguration());
        appearance.uiMode=(appearance.uiMode&~Configuration.UI_MODE_NIGHT_MASK)|(dark?Configuration.UI_MODE_NIGHT_YES:Configuration.UI_MODE_NIGHT_NO);
        bubble.clearColorFilter();
        if(resource!=0)bubble.setImageDrawable(createConfigurationContext(appearance).getDrawable(resource));
        else try{bubble.setImageDrawable(getPackageManager().getApplicationIcon(getPackageName()));}catch(Exception ignored){}
    }
    private void buildPanel(){panel=new ScrollView(this);panel.setFillViewport(false);panel.setClipChildren(true);panel.setClipToPadding(true);panel.setClipToOutline(true);panel.setOverScrollMode(View.OVER_SCROLL_NEVER);panel.setScrollBarStyle(View.SCROLLBARS_INSIDE_INSET);panel.setBackground(rounded(background,24));panel.setElevation(dp(12));LinearLayout body=new LinearLayout(this);panelBody=body;body.setOrientation(LinearLayout.VERTICAL);body.setPadding(dp(12),dp(12),dp(12),dp(12));body.setClipChildren(true);body.setClipToPadding(true);body.setClipToOutline(true);body.setBackground(rounded(background,22));LinearLayout top=row();heading=text("AsterHand",16);heading.setTypeface(null,Typeface.BOLD);top.addView(heading,new LinearLayout.LayoutParams(0,-2,1));Button close=localizedButton("收起",()->togglePanel());top.addView(close,new LinearLayout.LayoutParams(dp(68),dp(34)));body.addView(top);summary=text(UILocalization.t("就绪"),13);summary.setTextColor(muted);summary.setPadding(0,dp(10),0,dp(8));summary.setMaxLines(2);summary.setEllipsize(TextUtils.TruncateAt.END);body.addView(summary);question=text("",14);question.setVisibility(View.GONE);body.addView(question);optionRows=new LinearLayout(this);optionRows.setOrientation(LinearLayout.VERTICAL);body.addView(optionRows);input=new OverlayInput(this);input.setTextSize(14);input.setTextColor(textColor);input.setHintTextColor(muted);input.setHint(UILocalization.t("给 AI 发消息"));input.setMinLines(1);input.setMaxLines(3);input.setImeOptions(android.view.inputmethod.EditorInfo.IME_FLAG_NO_EXTRACT_UI|android.view.inputmethod.EditorInfo.IME_FLAG_NO_FULLSCREEN);input.setPadding(dp(12),dp(8),dp(12),dp(8));input.setBackground(rounded(surface,14));body.addView(input,new LinearLayout.LayoutParams(-1,-2));input.setOnTouchListener((v,e)->{if(e.getAction()==MotionEvent.ACTION_DOWN){panelParams.flags&=~WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;update(panel,panelParams);input.requestFocus();main.postDelayed(()->((InputMethodManager)getSystemService(INPUT_METHOD_SERVICE)).showSoftInput(input,InputMethodManager.SHOW_IMPLICIT),120);}return false;});LinearLayout compose=row();composeRow=compose;send=localizedButton("发送",()->sendMessage());compose.addView(send,new LinearLayout.LayoutParams(0,dp(38),1));Button keyboard=localizedButton("收起键盘",()->hideKeyboard());LinearLayout.LayoutParams kp=new LinearLayout.LayoutParams(dp(88),dp(38));kp.leftMargin=dp(8);compose.addView(keyboard,kp);LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(-1,-2);cp.topMargin=dp(8);body.addView(compose,cp);
        LinearLayout run=row();stop=localizedButton("停止",()->AgentTaskService.stop());resume=localizedButton("继续",()->{Actions a=actions;if(a!=null)a.onContinue();});run.addView(stop,new LinearLayout.LayoutParams(0,dp(36),1));LinearLayout.LayoutParams rp=new LinearLayout.LayoutParams(0,dp(36),1);rp.leftMargin=dp(8);run.addView(resume,rp);LinearLayout.LayoutParams rr=new LinearLayout.LayoutParams(-1,-2);rr.topMargin=dp(10);body.addView(run,rr);
        LinearLayout audio=row();voice=localizedButton("语音",()->{Actions a=actions;if(a!=null)a.onVoice();});mic=localizedButton("麦克风",()->{Actions a=actions;if(a!=null)a.onMicMute();});speech=localizedButton("朗读",()->{Actions a=actions;if(a!=null)a.onSpeechMute();});audio.addView(voice,new LinearLayout.LayoutParams(0,dp(38),1));LinearLayout.LayoutParams ap=new LinearLayout.LayoutParams(0,dp(38),1);ap.leftMargin=dp(6);audio.addView(mic,ap);LinearLayout.LayoutParams ap2=new LinearLayout.LayoutParams(0,dp(38),1);ap2.leftMargin=dp(6);audio.addView(speech,ap2);LinearLayout.LayoutParams ar=new LinearLayout.LayoutParams(-1,-2);ar.topMargin=dp(8);body.addView(audio,ar);voiceLabel=text("",11);voiceLabel.setTextColor(muted);voiceLabel.setMaxLines(2);voiceLabel.setEllipsize(TextUtils.TruncateAt.END);body.addView(voiceLabel);
        LinearLayout utterance=row();voiceSubmit=localizedButton("发送这句话",()->VoiceController.get(this).submitUtterance());voiceInterrupt=localizedButton("打断朗读",()->VoiceController.get(this).interruptSpeech());utterance.addView(voiceSubmit,new LinearLayout.LayoutParams(0,dp(36),1));LinearLayout.LayoutParams vi=new LinearLayout.LayoutParams(0,dp(36),1);vi.leftMargin=dp(8);utterance.addView(voiceInterrupt,vi);LinearLayout.LayoutParams ur=new LinearLayout.LayoutParams(-1,-2);ur.topMargin=dp(6);body.addView(utterance,ur);
        LinearLayout bottom=row();showCapsule=localizedButton("显示胶囊",()->{capsuleDismissed=!capsuleDismissed;refresh();});bottom.addView(showCapsule,new LinearLayout.LayoutParams(0,dp(36),1));Button open=localizedButton("打开",()->{Actions a=actions;if(a!=null)a.onOpen();else startActivity(new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_SINGLE_TOP));});LinearLayout.LayoutParams op=new LinearLayout.LayoutParams(dp(76),dp(36));op.leftMargin=dp(6);bottom.addView(open,op);Button hide=localizedButton("隐藏",()->hide(this));LinearLayout.LayoutParams hp=new LinearLayout.LayoutParams(dp(76),dp(36));hp.leftMargin=dp(6);bottom.addView(hide,hp);LinearLayout.LayoutParams br=new LinearLayout.LayoutParams(-1,-2);br.topMargin=dp(8);body.addView(bottom,br);panel.addView(body);panelParams=params(Math.min(dp(344),screenWidth-dp(24)),dp(420));manager.addView(panel,panelParams);watchKeyboard();panel.setVisibility(View.GONE);}
    private void buildCapsule(){capsule=text("",13);capsule.setGravity(Gravity.CENTER_VERTICAL);capsule.setSingleLine(true);capsule.setEllipsize(TextUtils.TruncateAt.END);capsule.setPadding(dp(14),dp(7),dp(14),dp(7));capsule.setBackground(rounded(background,18));capsule.setElevation(dp(5));capsule.setContentDescription(UILocalization.t("AI 状态，点按隐藏或拖动"));capsuleParams=params(Math.min(dp(310),screenWidth-dp(36)),dp(38));resetCapsule();capsule.setOnTouchListener(new View.OnTouchListener(){float x,y;int cx,cy;boolean moved;public boolean onTouch(View v,MotionEvent e){switch(e.getActionMasked()){case MotionEvent.ACTION_DOWN:x=e.getRawX();y=e.getRawY();cx=capsuleParams.x;cy=capsuleParams.y;moved=false;return true;case MotionEvent.ACTION_MOVE:if(!getSharedPreferences("overlay",0).getBoolean("capsuleLocked",false)&&Math.hypot(e.getRawX()-x,e.getRawY()-y)>dp(5)){moved=true;capsuleParams.x=Math.max(dp(4),Math.min(screenWidth-capsuleParams.width-dp(4),cx+(int)(e.getRawX()-x)));capsuleParams.y=Math.max(statusHeight(),Math.min(screenHeight-dp(48),cy+(int)(e.getRawY()-y)));update(capsule,capsuleParams);}return true;case MotionEvent.ACTION_UP:if(!moved){capsuleDismissed=true;refresh();}return true;case MotionEvent.ACTION_CANCEL:return true;}return false;}});manager.addView(capsule,capsuleParams);capsule.setVisibility(View.GONE);}
    private void resetCapsule(){capsuleParams.x=(screenWidth-capsuleParams.width)/2;capsuleParams.y=statusHeight()+dp(8);if(capsule!=null)update(capsule,capsuleParams);}
    private void togglePanel(){panelOpen=!panelOpen;if(panelOpen){positionPanel(true);hideKeyboard();}else hideKeyboard();refresh();}
    private void positionPanel(boolean choose){
        if(panel==null)return;
        int oldWidth=panelParams.width,oldHeight=panelParams.height,oldX=panelParams.x,oldY=panelParams.y;
        OverlayGeometry.Panel placed=OverlayGeometry.panel(screenWidth,screenHeight,statusHeight()+dp(4),bubbleParams.x,bubbleParams.y,bubbleParams.width,bubbleParams.height,dp(344),dp(420),dp(12),dp(12),dp(96),imeHeight,side,choose);
        side=placed.side;panelParams.width=placed.width;panelParams.height=placed.height;panelParams.x=placed.x;panelParams.y=placed.y;
        if(oldWidth!=panelParams.width||oldHeight!=panelParams.height||oldX!=panelParams.x||oldY!=panelParams.y)update(panel,panelParams);
    }
    private void watchKeyboard(){
        // Applied insets can already be consumed, whereas root insets are not. Mixing both
        // produced alternating zero/nonzero IME heights and an endless layout loop.
        panel.setOnApplyWindowInsetsListener((view,insets)->{scheduleKeyboardRead();return insets;});
        panel.getViewTreeObserver().addOnGlobalLayoutListener(this::scheduleKeyboardRead);
    }
    private void scheduleKeyboardRead(){if(keyboardReadQueued)return;keyboardReadQueued=true;main.post(keyboardReader);}
    private int displayKeyboardInset(){
        // Small-window IME insets describe only its intersection with the keyboard. Moving
        // that window above the keyboard makes that intersection zero; it is not a close.
        int nativeInset=ScreenAccessibilityService.keyboardInset(screenHeight);if(nativeInset>0)return nativeInset;
        if(Build.VERSION.SDK_INT>=30){
            try{WindowMetrics metrics=manager.getMaximumWindowMetrics();WindowInsets global=metrics.getWindowInsets();if(global.isVisible(WindowInsets.Type.ime())){int height=global.getInsets(WindowInsets.Type.ime()).bottom;if(height>0)return height;}metrics=manager.getCurrentWindowMetrics();global=metrics.getWindowInsets();if(global.isVisible(WindowInsets.Type.ime())){int height=global.getInsets(WindowInsets.Type.ime()).bottom;if(height>0)return height;}}catch(RuntimeException unavailable){}
            WindowInsets insets=panel.getRootWindowInsets();if(insets!=null&&insets.isVisible(WindowInsets.Type.ime()))return OverlayGeometry.imeHeight(true,insets.getInsets(WindowInsets.Type.ime()).bottom,imeHeight);
        }
        if((panelParams.flags&WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)==0){Rect frame=new Rect();panel.getWindowVisibleDisplayFrame(frame);int hidden=screenHeight-frame.bottom;if(hidden>dp(100))return hidden;}
        return 0;
    }
    private void keyboardHeight(int value){
        int next=Math.max(0,Math.min(screenHeight-statusHeight()-dp(90),value));if(next==imeHeight)return;
        imeHeight=next;if(panelOpen){positionPanel(true);if(imeHeight>0)main.post(()->{if(input!=null)panel.smoothScrollTo(0,Math.max(0,input.getTop()-dp(8)));});}
    }
    private void hideKeyboard(){if(input!=null){((InputMethodManager)getSystemService(INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(input.getWindowToken(),0);input.clearFocus();}if(panelParams!=null){panelParams.flags|=WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;update(panel,panelParams);}keyboardHeight(0);}
    private final class OverlayInput extends EditText{
        OverlayInput(Context context){super(context);}
        @Override public boolean onKeyPreIme(int code,KeyEvent event){if(code==KeyEvent.KEYCODE_BACK){if(event.getAction()==KeyEvent.ACTION_UP)hideKeyboard();return true;}return super.onKeyPreIme(code,event);}
    }
    private void sendMessage(){String value=input.getText().toString().trim();QuestionBinding shown=shownQuestion;if(shown!=null){JSONArray chosen=new JSONArray();for(String option:selectedOptions)chosen.put(option);if(AgentTaskService.answer(value,chosen,shown.task,shown.id)){input.setText("");selectedOptions.clear();hideKeyboard();}else Toast.makeText(this,UILocalization.t("问题已更新，请查看当前选项"),Toast.LENGTH_SHORT).show();}else if(!value.isEmpty()){Actions a=actions;if(a!=null){input.setText("");hideKeyboard();a.onSend(value);}}}
    @Override public void onChanged(JSONObject next){state=next;String id=next.optString("id");boolean running=next.optBoolean("running");if(running&&!id.equals(taskId)){taskId=id;if(!voiceActive)capsuleDismissed=false;resetCapsule();capsuleWanted=true;capsuleGeneration++;}if(wasRunning&&!running){capsuleWanted=true;long generation=++capsuleGeneration;main.postDelayed(()->{if(generation==capsuleGeneration&&!state.optBoolean("running")){capsuleWanted=false;refresh();}},3000);}wasRunning=running;activity("task",running);if(next.optBoolean("attention")&&!foreground&&!panelOpen){panelOpen=true;positionPanel(true);}refresh();}
    private void theme(View view){if(view instanceof TextView){((TextView)view).setTextColor(textColor);if(view instanceof EditText){((EditText)view).setHintTextColor(muted);view.setBackground(rounded(surface,14));}else if(view instanceof Button){view.setBackground(rounded(surface,11));for(Drawable glyph:((Button)view).getCompoundDrawablesRelative())if(glyph instanceof Glyph)((Glyph)glyph).color(textColor);}}if(view instanceof android.view.ViewGroup){android.view.ViewGroup g=(android.view.ViewGroup)view;for(int i=0;i<g.getChildCount();i++)theme(g.getChildAt(i));}}
    private void refresh(){if(bubble==null||panel==null||capsule==null)return;if(themeDark==null||themeDark!=dark){themeDark=dark;theme(panel);voiceLabel.setTextColor(muted);applyBubbleIcon();panel.setBackground(rounded(background,24));if(panelBody!=null)panelBody.setBackground(rounded(background,22));capsule.setBackground(rounded(background,18));capsule.setTextColor(textColor);heading.setTextColor(textColor);}bubble.invalidate();if(effects!=null)effects.configure(aiControl&&effectEnabled("ai_control"),effectNumber("edge_width",10,2,28),effectNumber("edge_opacity",.7f,.05f,1));if(!buttonLanguage.equals(UILocalization.language())){buttonLanguage=UILocalization.language();for(Map.Entry<Button,String> entry:localizedButtons.entrySet())entry.getKey().setText(UILocalization.t(entry.getValue()));}
        String stage=UILocalization.t(state.optString("stage",UILocalization.t("就绪"))),reply=state.optString("reply");String text=!reply.isEmpty()?reply:stage;summary.setText(text);summary.setTextColor(muted);refreshCapsuleText();boolean running=state.optBoolean("running");stop.setEnabled(running);resume.setEnabled(!running&&!state.optString("id").isEmpty());voice.setText(voiceActive?UILocalization.t("结束语音"):UILocalization.t("语音"));mic.setText(micMuted?UILocalization.t("麦克风已静音"):UILocalization.t("麦克风"));speech.setText(speechMuted?UILocalization.t("朗读已静音"):UILocalization.t("朗读"));updateVoiceControls();showCapsule.setEnabled(capsuleWanted||voiceActive);showCapsule.setAlpha(capsuleWanted||voiceActive?1:.4f);showCapsule.setText((capsuleWanted||voiceActive)&&!capsuleDismissed?UILocalization.t("隐藏胶囊"):UILocalization.t("显示胶囊"));question.setText(state.optString("question"));question.setVisibility(state.optBoolean("attention")?View.VISIBLE:View.GONE);JSONArray choices=state.optJSONArray("options");String signature=state.optString("id")+":"+state.optString("questionId")+":"+(choices==null?"":choices.toString())+state.optString("question");if(!signature.equals(optionRows.getTag())){optionRows.setTag(signature);optionRows.removeAllViews();selectedOptions.clear();if(shownQuestion!=null||state.optBoolean("attention"))input.setText("");shownQuestion=state.optBoolean("attention")?new QuestionBinding(state):null;if(state.optBoolean("attention")&&choices!=null)for(int i=0;i<choices.length();i++){String choice=choices.optString(i);final QuestionBinding binding=shownQuestion;Button option=button(binding.kind.equals("question")?choice:UILocalization.t(choice),()->{if(binding.multi){if(!selectedOptions.add(choice))selectedOptions.remove(choice);View child=optionRows.findViewWithTag(choice);if(child!=null)child.setAlpha(selectedOptions.contains(choice)?.55f:1f);}else AgentTaskService.answer("",new JSONArray().put(choice),binding.task,binding.id);});option.setTag(choice);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(38));p.bottomMargin=dp(6);optionRows.addView(option,p);}}if(shownQuestion!=null&&!shownQuestion.kind.equals("question"))for(int i=0;i<optionRows.getChildCount();i++){View child=optionRows.getChildAt(i);if(child instanceof Button&&child.getTag() instanceof String)((Button)child).setText(UILocalization.t((String)child.getTag()));}input.setHint(state.optBoolean("attention")?UILocalization.t("输入回答"):UILocalization.t("给 AI 发消息"));boolean composeAllowed=shownQuestion==null||shownQuestion.kind.equals("question");if(!composeAllowed&&input.hasFocus())hideKeyboard();int composeVisibility=composeAllowed?View.VISIBLE:View.GONE;if(input.getVisibility()!=composeVisibility){input.setVisibility(composeVisibility);if(composeRow!=null)composeRow.setVisibility(composeVisibility);if(panelOpen)positionPanel(true);}input.setEnabled(composeAllowed);send.setEnabled(composeAllowed);send.setText(state.optBoolean("attention")?UILocalization.t("回答"):UILocalization.t("发送"));applyVisibility();}
    private void updateVoiceControls(){JSONObject value=voicePresentation;String partial=value.optString("transcript");voiceLabel.setText(UILocalization.t(voiceStatus)+(partial.isEmpty()?"":UILocalization.t("\n你：")+partial));voiceSubmit.setEnabled(value.optBoolean("canSubmit"));voiceInterrupt.setEnabled(value.optBoolean("canInterrupt"));voiceSubmit.setAlpha(voiceSubmit.isEnabled()?1:.4f);voiceInterrupt.setAlpha(voiceInterrupt.isEnabled()?1:.4f);}
    static String capsuleVoiceText(JSONObject value,int pulse){
        if(value==null||!value.optBoolean("active"))return "";
        String detail=value.optString("transcript");
        if(value.optBoolean("micMuted"))return value.optBoolean("speaking")?UILocalization.t("正在朗读 · 麦克风已静音"):UILocalization.t("麦克风已静音");
        if(value.optBoolean("speaking")){String reply=value.optString("reply");return UILocalization.t("正在朗读")+(reply.isEmpty()?"":" · "+reply);}
        if(value.optBoolean("listening")){String dots=pulse%3==0?"·":pulse%3==1?"··":"···";return UILocalization.t("正在聆听 ")+dots+(detail.isEmpty()?"":"  "+detail);}
        if(value.optBoolean("waiting"))return UILocalization.t("等待 AI 回复");
        return value.optString("status",UILocalization.t("正在识别"));
    }
    private void refreshCapsuleText(){
        if(capsule==null)return;String voiceText=capsuleVoiceText(voicePresentation,voicePulse);
        if(!voiceText.isEmpty())capsule.setText(voiceText);else{String value=state.optString("reply");if(value.isEmpty())value=UILocalization.t(state.optString("stage",UILocalization.t("就绪")));capsule.setText(aiControl?UILocalization.t("AI 正在操控 · ")+value:remoteControl?UILocalization.t("正在被远控 · ")+value:value);}
        boolean animate=voiceActive&&voicePresentation.optBoolean("listening")&&!capsuleDismissed;
        if(animate&&!voiceTicking){voiceTicking=true;main.postDelayed(voiceTicker,450);}else if(!animate&&voiceTicking){main.removeCallbacks(voiceTicker);voiceTicking=false;}
    }
    private void applyVisibility(){if(bubble!=null)bubble.setVisibility(automationHidden?View.INVISIBLE:View.VISIBLE);if(panel!=null)panel.setVisibility(!automationHidden&&panelOpen?View.VISIBLE:View.GONE);if(capsule!=null)capsule.setVisibility(!automationHidden&&(capsuleWanted||voiceActive)&&!capsuleDismissed?View.VISIBLE:View.GONE);if(effects!=null)effects.setVisibility(!automationHidden&&effects.active()?View.VISIBLE:View.GONE);}
    private void update(View v,WindowManager.LayoutParams p){if(v==null||v.getWindowToken()==null)return;try{manager.updateViewLayout(v,p);}catch(IllegalArgumentException ignored){}}
    private void remove(View v){if(v!=null)try{manager.removeViewImmediate(v);}catch(IllegalArgumentException ignored){}}
    private void foregroundNotification(){String channel="asterhand.overlay";NotificationManager n=(NotificationManager)getSystemService(NOTIFICATION_SERVICE);if(Build.VERSION.SDK_INT>=26)n.createNotificationChannel(new NotificationChannel(channel,UILocalization.t("悬浮助手"),NotificationManager.IMPORTANCE_LOW));PendingIntent open=PendingIntent.getActivity(this,2201,new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);Notification.Builder b=Build.VERSION.SDK_INT>=26?new Notification.Builder(this,channel):new Notification.Builder(this);Notification note=b.setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(UILocalization.t("AsterHand 悬浮助手")).setContentText(UILocalization.t("悬浮菜单可发送消息、回答和停止任务")).setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).build();try{if(Build.VERSION.SDK_INT>=34)startForeground(2201,note,ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);else if(Build.VERSION.SDK_INT>=29)startForeground(2201,note,0);else startForeground(2201,note);}catch(RuntimeException e){stopSelf();}}
    private static final class Glyph extends Drawable{
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);private final String kind;
        Glyph(String kind,int color){this.kind=kind;paint.setColor(color);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(1.7f);paint.setStrokeCap(Paint.Cap.ROUND);paint.setStrokeJoin(Paint.Join.ROUND);}
        void color(int value){paint.setColor(value);invalidateSelf();}
        private void line(Canvas c,float x,float y,float x2,float y2){c.drawLine(x,y,x2,y2,paint);}
        @Override public void draw(Canvas canvas){Rect b=getBounds();canvas.save();canvas.translate(b.left,b.top);canvas.scale(b.width()/24f,b.height()/24f);Path p=new Path();
            switch(kind){
                case "collapse":line(canvas,6,9,12,15);line(canvas,12,15,18,9);break;
                case "send":line(canvas,12,20,12,4);line(canvas,6,10,12,4);line(canvas,12,4,18,10);break;
                case "keyboard":canvas.drawRoundRect(3,4,21,17,2,2,paint);line(canvas,6,8,7,8);line(canvas,10,8,11,8);line(canvas,14,8,15,8);line(canvas,18,8,18,8);line(canvas,8,13,16,13);line(canvas,9,20,12,22);line(canvas,12,22,15,20);break;
                case "stop":canvas.drawRoundRect(5,5,19,19,2,2,paint);break;
                case "play":p.moveTo(8,4);p.lineTo(20,12);p.lineTo(8,20);p.close();canvas.drawPath(p,paint);break;
                case "voice":line(canvas,4,10,4,14);line(canvas,8,6,8,18);line(canvas,12,3,12,21);line(canvas,16,7,16,17);line(canvas,20,10,20,14);break;
                case "mic":canvas.drawRoundRect(9,3,15,15,3,3,paint);canvas.drawArc(6,6,18,19,0,180,false,paint);line(canvas,12,19,12,22);line(canvas,9,22,15,22);break;
                case "speech":p.moveTo(3,9);p.lineTo(8,9);p.lineTo(13,5);p.lineTo(13,19);p.lineTo(8,15);p.lineTo(3,15);p.close();canvas.drawPath(p,paint);canvas.drawArc(12,7,20,17,-60,120,false,paint);canvas.drawArc(12,3,24,21,-55,110,false,paint);break;
                case "check":line(canvas,5,12,10,17);line(canvas,10,17,20,6);break;
                case "pause":line(canvas,8,5,8,19);line(canvas,16,5,16,19);break;
                case "capsule":canvas.drawRoundRect(3,7,21,17,5,5,paint);line(canvas,7,12,10,12);line(canvas,14,12,17,12);break;
                case "open":line(canvas,14,4,21,4);line(canvas,21,4,21,11);line(canvas,21,4,10,15);p.moveTo(10,4);p.lineTo(4,4);p.lineTo(4,20);p.lineTo(20,20);p.lineTo(20,14);canvas.drawPath(p,paint);break;
                case "hide":p.moveTo(3,12);p.cubicTo(7,5,17,5,21,12);p.cubicTo(17,19,7,19,3,12);canvas.drawPath(p,paint);canvas.drawCircle(12,12,3,paint);line(canvas,4,3,20,21);break;
            }
            canvas.restore();
        }
        @Override public void setAlpha(int alpha){paint.setAlpha(alpha);invalidateSelf();}
        @Override public void setColorFilter(ColorFilter filter){paint.setColorFilter(filter);invalidateSelf();}
        @Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    private final class Rings extends Drawable{private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);@Override public void draw(Canvas c){Rect b=getBounds();float cx=b.exactCenterX(),cy=b.exactCenterY(),r=Math.min(b.width(),b.height())/2f-dp(2);paint.setStyle(Paint.Style.FILL);paint.setColor(dark?0xff121212:Color.WHITE);c.drawCircle(cx,cy,r,paint);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(dp(2));ArrayList<String> visible=activeRings();for(int i=0;i<visible.size();i++){String name=visible.get(i);paint.setColor("ai".equals(name)?0xff6698ff:"remote".equals(name)?0xffffad64:"connected".equals(name)?0xff42d6a4:0xffb08aff);float radius=r-dp(2)*(visible.size()-1-i);c.drawCircle(cx,cy,radius,paint);}}@Override public void setAlpha(int alpha){paint.setAlpha(alpha);}@Override public void setColorFilter(ColorFilter color){paint.setColorFilter(color);}@Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}}
}
