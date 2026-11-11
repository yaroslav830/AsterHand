package com.pocketagent;

import android.content.Context;
import android.content.Intent;
import android.app.ActivityManager;
import android.os.Handler;
import android.os.Looper;
import org.json.JSONObject;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Explicit local recovery. Never changes execution permission or replays a task. */
public final class ServiceRecovery {
    private static final Handler MAIN=new Handler(Looper.getMainLooper());
    private static String id="",status="",error="";
    private static boolean running;
    private ServiceRecovery(){}
    public static synchronized JSONObject snapshot(){JSONObject out=new JSONObject();try{return out.put("id",id).put("running",running).put("status",status).put("error",error);}catch(Exception ignored){return out;}}
    public static synchronized JSONObject restart(Context context){
        if(running)return snapshot();
        final Context app=context.getApplicationContext();id=UUID.randomUUID().toString();final String request=id;running=true;status="正在停止任务与服务";error="";
        CountDownLatch stopped=new CountDownLatch(1);
        // Keep the existing foreground connection anchor while rebuilding workers.
        // Stopping every foreground service first can make Android reject recovery
        // from the background, leaving an otherwise valid pairing unreachable.
        MAIN.post(()->{try{AgentTaskService.stop();VoiceController.get(app).stop();RemoteConsentService.close(app);for(Class<?> service:new Class<?>[]{AgentTaskService.class,VoiceService.class,FloatingOverlayService.class})app.stopService(new Intent(app,service));}finally{stopped.countDown();}});
        Thread work=new Thread(()->{
            try{
                if(!stopped.await(3,TimeUnit.SECONDS))throw new Exception("界面线程未响应，请从系统重新打开 AsterHand。");
                TerminalSessions.closeAll();new PrivilegeManager(app).closeOwner("local-ui");RemoteControlHub.get(app).stop();
                synchronized(ServiceRecovery.class){if(!id.equals(request))return;status="正在恢复已开启的服务";}
                MAIN.postDelayed(()->{try{AsterRuntime.restart(app);FloatingOverlayService.restore(app);MAIN.postDelayed(()->finish(app,request),700);}catch(Exception e){failed(request,e);}},350);
            }catch(Exception e){failed(request,e);}
        },"AsterHand-service-recovery");work.setDaemon(true);work.start();return snapshot();
    }
    private static synchronized void failed(String request,Exception failure){if(!id.equals(request))return;running=false;status="部分服务未恢复";error=failure.getMessage()==null?failure.getClass().getSimpleName():failure.getMessage();}
    private static void finish(Context app,String request){try{
        if(AgentTaskService.snapshot(app).optBoolean("running")||VoiceController.get(app).enabled())throw new Exception("旧任务或语音尚未停止，请重新打开应用。");
        if(app.getSharedPreferences("MainActivity",0).getBoolean("background",true)&&!active(app,AsterBackgroundService.class))throw new Exception("后台连接服务未恢复，请重新打开应用。");
        if(FloatingOverlayService.enabled(app)&&FloatingOverlayService.permitted(app)&&!active(app,FloatingOverlayService.class))throw new Exception("悬浮服务未恢复，请检查悬浮窗权限。");
        synchronized(ServiceRecovery.class){if(id.equals(request)){running=false;status="服务已重启，原任务未自动重试";}}
    }catch(Exception e){failed(request,e);}}
    private static boolean active(Context app,Class<?> service){ActivityManager manager=(ActivityManager)app.getSystemService(Context.ACTIVITY_SERVICE);for(ActivityManager.RunningServiceInfo item:manager.getRunningServices(64))if(item.uid==android.os.Process.myUid()&&item.service.getClassName().equals(service.getName()))return true;return false;}
}
