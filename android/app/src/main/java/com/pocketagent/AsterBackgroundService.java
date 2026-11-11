package com.pocketagent;
import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.net.wifi.WifiManager;
import android.os.*;
/** Passive authorized LAN listener. This service never restarts unfinished AI tools. */
public final class AsterBackgroundService extends Service {
    private static final int ID=2401;
    private static final String CHANNEL="asterhand.connections";
    private WifiManager.WifiLock wifiLock;
    @SuppressWarnings("deprecation") private void holdWifiForBackground(){
        // Android 14+ substitutes a foreground-only low-latency lock, so it does
        // not provide the screen-off guarantee required by this service.
        if(Build.VERSION.SDK_INT>=34||wifiLock!=null)return;
        try{WifiManager manager=(WifiManager)getApplicationContext().getSystemService(WIFI_SERVICE);if(manager!=null){wifiLock=manager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF,"AsterHand:RemoteConnection");wifiLock.setReferenceCounted(false);wifiLock.acquire();}}catch(RuntimeException e){wifiLock=null;}
    }
    private void releaseWifi(){if(wifiLock!=null){try{if(wifiLock.isHeld())wifiLock.release();}catch(RuntimeException ignored){}wifiLock=null;}}
    public static void configure(Context context){Context app=context.getApplicationContext();boolean wanted=ServiceMaster.enabled(app)&&app.getSharedPreferences("MainActivity",0).getBoolean("background",true);try{RemoteControlHub.get(app).setBackground(wanted);if(wanted){Intent i=new Intent(app,AsterBackgroundService.class);if(Build.VERSION.SDK_INT>=26)app.startForegroundService(i);else app.startService(i);}else app.stopService(new Intent(app,AsterBackgroundService.class));}catch(Exception ignored){}}
    @Override public void onCreate(){super.onCreate();UILocalization.initialize(this);if(Build.VERSION.SDK_INT>=26)((NotificationManager)getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(new NotificationChannel(CHANNEL,UILocalization.t("远程连接后台服务"),NotificationManager.IMPORTANCE_LOW));}
    @Override public int onStartCommand(Intent intent,int flags,int startId){if(!ServiceMaster.enabled(this)||!getSharedPreferences("MainActivity",0).getBoolean("background",true)){stopSelf();return START_NOT_STICKY;}try{PendingIntent open=PendingIntent.getActivity(this,2401,new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);Notification.Builder builder=Build.VERSION.SDK_INT>=26?new Notification.Builder(this,CHANNEL):new Notification.Builder(this);Notification notification=builder.setSmallIcon(android.R.drawable.ic_menu_share).setContentTitle(UILocalization.t("AsterHand 远程连接")).setContentText(UILocalization.t("等待已授权的远程连接和新连接申请")).setOngoing(true).setOnlyAlertOnce(true).setContentIntent(open).build();if(Build.VERSION.SDK_INT>=34)startForeground(ID,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);else if(Build.VERSION.SDK_INT>=29)startForeground(ID,notification,0);else startForeground(ID,notification);holdWifiForBackground();AsterRuntime.ensure(this);RemoteControlHub.get(this).start();return START_STICKY;}catch(Exception e){releaseWifi();stopSelf();return START_NOT_STICKY;}}
    @Override public IBinder onBind(Intent intent){return null;}
    @Override public void onDestroy(){releaseWifi();RemoteConsentService.close(this);stopForeground(true);if(!getSharedPreferences("MainActivity",0).getBoolean("background",true)&&!AsterRuntime.isForeground())RemoteControlHub.get(this).stop();super.onDestroy();}
}
