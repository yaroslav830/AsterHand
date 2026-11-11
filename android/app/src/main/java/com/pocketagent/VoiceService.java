package com.pocketagent;
import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.os.*;
/** Microphone foreground lifetime is distinct from the agent task and stops with continuous voice. */
public final class VoiceService extends Service {
    private static final String CHANNEL="asterhand.voice",STOP="com.pocketagent.STOP_VOICE";
    private static final int ID=2301;
    private static VoiceService instance;
    private String lastStatus="";
    @Override public void onCreate(){super.onCreate();UILocalization.initialize(this);instance=this;if(Build.VERSION.SDK_INT>=26)((NotificationManager)getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(new NotificationChannel(CHANNEL,UILocalization.t("连续语音"),NotificationManager.IMPORTANCE_LOW));}
    @Override public int onStartCommand(Intent intent,int flags,int startId){if(intent!=null&&STOP.equals(intent.getAction())){VoiceController.get(this).stop();stopSelf();return START_NOT_STICKY;}try{Notification n=notification("正在开启语音");if(Build.VERSION.SDK_INT>=30)startForeground(ID,n,ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE);else if(Build.VERSION.SDK_INT>=29)startForeground(ID,n,0);else startForeground(ID,n);VoiceController.get(this).serviceReady();}catch(RuntimeException e){VoiceController.get(this).failedStart("系统不允许在当前页面开启麦克风，请在应用内重试");stopSelf();}return START_NOT_STICKY;}
    @Override public IBinder onBind(Intent intent){return null;}
    @Override public void onDestroy(){if(instance==this)instance=null;VoiceController.get(this).serviceStopped();stopForeground(true);super.onDestroy();}
    @Override public void onTimeout(int startId,int type){VoiceController.get(this).stop();stopSelf();}
    static void updateStatus(String text){VoiceService s=instance;if(s!=null&&!s.lastStatus.equals(text))try{s.lastStatus=text;((NotificationManager)s.getSystemService(NOTIFICATION_SERVICE)).notify(ID,s.notification(text));}catch(SecurityException ignored){}}
    private Notification notification(String status){PendingIntent open=PendingIntent.getActivity(this,2301,new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);PendingIntent stop=PendingIntent.getService(this,2302,new Intent(this,VoiceService.class).setAction(STOP),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);Notification.Builder b=Build.VERSION.SDK_INT>=26?new Notification.Builder(this,CHANNEL):new Notification.Builder(this);return b.setSmallIcon(android.R.drawable.ic_btn_speak_now).setContentTitle(UILocalization.t("AsterHand 连续语音")).setContentText(UILocalization.t(status)).setContentIntent(open).addAction(new Notification.Action.Builder(android.R.drawable.ic_media_pause,UILocalization.t("结束语音"),stop).build()).setOngoing(true).setOnlyAlertOnce(true).setVisibility(Notification.VISIBILITY_PRIVATE).build();}
}
