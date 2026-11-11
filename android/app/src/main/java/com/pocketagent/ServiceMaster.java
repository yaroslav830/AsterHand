package com.pocketagent;

import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;

/** A local master switch. Individual preferences and pairing grants are preserved. */
public final class ServiceMaster {
    private ServiceMaster(){}
    public static boolean enabled(Context c){return c.getApplicationContext().getSharedPreferences("MainActivity",0).getBoolean("servicesEnabled",true);}
    public static void requireEnabled(Context c)throws Exception{if(!enabled(c))throw new Exception("所有服务已关闭，请先在设置中开启。");}
    public static void set(Context context,boolean enabled)throws Exception{
        Context app=context.getApplicationContext();
        if(!app.getSharedPreferences("MainActivity",0).edit().putBoolean("servicesEnabled",enabled).commit())throw new Exception("无法保存服务开关。");
        new Handler(Looper.getMainLooper()).post(()->{
            if(enabled){AsterRuntime.configure(app);FloatingOverlayService.restore(app);if(AsterRuntime.isForeground())try{RemoteControlHub.get(app).start();}catch(Exception ignored){}return;}
            AgentTaskService.stop();VoiceController.get(app).stop();RemoteConsentService.close(app);
            for(Class<?> service:new Class<?>[]{AgentTaskService.class,VoiceService.class,FloatingOverlayService.class,AsterBackgroundService.class})app.stopService(new Intent(app,service));
            TerminalSessions.closeAll();new PrivilegeManager(app).closeOwner("local-ui");RemoteControlHub.get(app).stop();
        });
    }
}
