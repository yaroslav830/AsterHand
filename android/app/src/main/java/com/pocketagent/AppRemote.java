package com.pocketagent;
import android.os.*;
import org.json.*;
import java.lang.ref.WeakReference;
import java.util.concurrent.*;
/** Authenticated Hub calls are serialized with the app UI and ProjectStore. */
final class AppRemote {
 static WeakReference<MainActivity> activity=new WeakReference<>(null);
 static void bind(MainActivity value){activity=new WeakReference<>(value);}
 static JSONObject request(JSONObject args)throws Exception{
  MainActivity current=activity.get();if(current==null||current.isDestroyed())throw new Exception("请先打开 AsterHand 应用");
  FutureTask<JSONObject> task=new FutureTask<>(()->current.handleAppRPC(args));new Handler(Looper.getMainLooper()).post(task);
  try{return task.get(10,TimeUnit.SECONDS);}catch(TimeoutException e){task.cancel(false);throw new Exception("应用未回应；请检查操作结果，不要自动重试写入操作。");}
 }
}
