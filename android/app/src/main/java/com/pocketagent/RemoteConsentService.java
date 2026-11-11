package com.pocketagent;
import android.app.*;
import android.content.*;
import android.content.res.Configuration;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.util.concurrent.*;
/** A connection request is independent of the AI's question queue and never grants itself permission. */
public final class RemoteConsentService extends Service {
    private static final String CHANNEL="asterhand.pairing";
    private static final int NOTICE=2501;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService decisions=Executors.newSingleThreadExecutor();
    private WindowManager manager;
    private LinearLayout card;
    private ScrollView window;
    private String requestId="";
    private boolean deciding;
    private final Runnable poll=new Runnable(){public void run(){refresh();main.postDelayed(this,1000);}};
    static void show(Context context){try{context.startService(new Intent(context,RemoteConsentService.class));}catch(RuntimeException e){try{JSONArray p=RemoteControlHub.get(context).pending();if(p.length()>0)notifyRequest(context,p.optJSONObject(0));}catch(Exception ignored){}}}
    static void close(Context context){context.stopService(new Intent(context,RemoteConsentService.class));((NotificationManager)context.getSystemService(NOTIFICATION_SERVICE)).cancel(NOTICE);}
    @Override public void onCreate(){super.onCreate();UILocalization.initialize(this);manager=(WindowManager)getSystemService(WINDOW_SERVICE);channels(this);main.post(poll);}
    @Override public int onStartCommand(Intent intent,int flags,int startId){refresh();return START_NOT_STICKY;}
    @Override public IBinder onBind(Intent intent){return null;}
    @Override public void onDestroy(){main.removeCallbacks(poll);decisions.shutdownNow();removeCard();((NotificationManager)getSystemService(NOTIFICATION_SERVICE)).cancel(NOTICE);super.onDestroy();}
    @Override public void onConfigurationChanged(Configuration c){super.onConfigurationChanged(c);requestId="";removeCard();refresh();}
    private void refresh(){try{JSONArray requests=RemoteControlHub.get(this).pending();if(requests.length()==0||AsterRuntime.isForeground()||!getSharedPreferences("MainActivity",0).getBoolean("background",true)){stopSelf();return;}JSONObject request=requests.optJSONObject(0);if(request==null){stopSelf();return;}String id=request.optString("id");if(id.isEmpty())return;boolean permitted=Settings.canDrawOverlays(this);if(!permitted&&card!=null)removeCard();if(id.equals(requestId)&&(!permitted||card!=null))return;requestId=id;notifyRequest(this,request);if(permitted)build(request);}catch(Exception e){stopSelf();}}
    private void build(JSONObject request){removeCard();boolean dark=(getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES;int foreground=dark?0xfff1f2f5:0xff18191b,muted=dark?0xffb2b7c2:0xff6b707a;card=new LinearLayout(this);card.setOrientation(LinearLayout.VERTICAL);card.setPadding(dp(22),dp(20),dp(22),dp(18));GradientDrawable bg=new GradientDrawable();bg.setCornerRadius(dp(24));bg.setColor(dark?0xff25272b:0xfffafafa);card.setBackground(bg);card.setElevation(dp(16));TextView title=label(UILocalization.t("连接申请"),21,foreground);title.setTypeface(null,Typeface.BOLD);card.addView(title);String name=request.optString("name",UILocalization.t("另一台设备")).replace('\n',' ');if(name.length()>80)name=name.substring(0,80);TextView detail=label(name+UILocalization.t(" 希望连接这台设备"),15,foreground);detail.setPadding(0,dp(12),0,dp(8));card.addView(detail);String code=request.optString("code","");TextView verify=label(UILocalization.t("核对码  ")+code,24,foreground);verify.setTypeface(Typeface.MONOSPACE,Typeface.BOLD);verify.setPadding(0,dp(8),0,dp(8));card.addView(verify);String device=request.optString("device_id");TextView foot=label(UILocalization.t("设备标识 ")+(device.length()>12?device.substring(0,12):device)+UILocalization.t("\n允许一次仅限本次连接；始终允许可在远程设置中撤销。"),12,muted);foot.setPadding(0,0,0,dp(14));card.addView(foot);for(String[] action:new String[][]{{UILocalization.t("允许一次"),"once"},{UILocalization.t("始终允许"),"always"},{UILocalization.t("不允许"),"deny"}}){Button button=new Button(this);button.setAllCaps(false);button.setText(action[0]);button.setTextColor(action[1].equals("deny")?muted:foreground);button.setTextSize(15);button.setMinHeight(0);button.setPadding(dp(12),dp(9),dp(12),dp(9));GradientDrawable shape=new GradientDrawable();shape.setCornerRadius(dp(14));shape.setColor(dark?0xff3a3c42:0xffe9e9ed);button.setBackground(shape);String id=request.optString("id");button.setOnClickListener(v->decide(id,action[1]));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(44));p.topMargin=dp(8);card.addView(button,p);}android.util.DisplayMetrics display=new android.util.DisplayMetrics();manager.getDefaultDisplay().getRealMetrics(display);WindowManager.LayoutParams params=new WindowManager.LayoutParams(Math.min(dp(348),display.widthPixels-dp(32)),-2,Build.VERSION.SDK_INT>=26?WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY:WindowManager.LayoutParams.TYPE_PHONE,WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE|WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,PixelFormat.TRANSLUCENT);params.gravity=Gravity.CENTER;card.measure(View.MeasureSpec.makeMeasureSpec(params.width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));params.height=Math.min(card.getMeasuredHeight(),display.heightPixels-dp(48));window=new ScrollView(this);window.setFillViewport(true);window.addView(card);try{manager.addView(window,params);}catch(RuntimeException e){card=null;window=null;}}
    private void decide(String id,String mode){if(deciding)return;deciding=true;if(card!=null)setChildrenEnabled(card,false);decisions.execute(()->{String failure=null;try{RemoteControlHub.get(this).decide(id,mode);}catch(Exception e){failure=e.getMessage();}String result=failure;main.post(()->{deciding=false;if(result!=null){Toast.makeText(this,UILocalization.t(result),Toast.LENGTH_LONG).show();if(card!=null)setChildrenEnabled(card,true);}else{requestId="";removeCard();refresh();}});});}
    private void setChildrenEnabled(android.view.ViewGroup group,boolean enabled){for(int i=0;i<group.getChildCount();i++){View v=group.getChildAt(i);v.setEnabled(enabled);if(v instanceof android.view.ViewGroup)setChildrenEnabled((android.view.ViewGroup)v,enabled);}}
    private void removeCard(){if(window!=null)try{manager.removeViewImmediate(window);}catch(RuntimeException ignored){}window=null;card=null;}
    private TextView label(String text,int size,int color){TextView view=new TextView(this);view.setText(text);view.setTextSize(size);view.setTextColor(color);return view;}
    private int dp(float n){return (int)(getResources().getDisplayMetrics().density*n+.5f);}
    private static void channels(Context c){if(Build.VERSION.SDK_INT>=26)((NotificationManager)c.getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(new NotificationChannel(CHANNEL,UILocalization.t("远程连接申请"),NotificationManager.IMPORTANCE_HIGH));}
    private static void notifyRequest(Context c,JSONObject request){try{channels(c);PendingIntent open=PendingIntent.getActivity(c,2501,new Intent(c,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);Notification.Builder b=Build.VERSION.SDK_INT>=26?new Notification.Builder(c,CHANNEL):new Notification.Builder(c);String name=request.optString("name",UILocalization.t("另一台设备"));((NotificationManager)c.getSystemService(NOTIFICATION_SERVICE)).notify(NOTICE,b.setSmallIcon(android.R.drawable.ic_menu_share).setContentTitle(UILocalization.t("AsterHand 连接申请")).setContentText(name+UILocalization.t(" · 核对码 ")+request.optString("code")).setContentIntent(open).setPriority(Notification.PRIORITY_HIGH).setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE).build());}catch(SecurityException ignored){}}
}
