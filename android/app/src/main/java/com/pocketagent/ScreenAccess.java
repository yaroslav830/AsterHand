package com.pocketagent;
import android.content.Context;
import android.content.Intent;
import android.provider.Settings;
import org.json.JSONObject;
final class ScreenAccess {
    static boolean enabled(Context context){return ScreenAccessibilityService.instance()!=null;}
    static void openSettings(Context context){context.startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));}
    static JSONObject execute(String name,JSONObject args)throws Exception{return execute(name,args,new java.util.concurrent.atomic.AtomicBoolean(false));}
    static JSONObject execute(String name,JSONObject args,java.util.concurrent.atomic.AtomicBoolean cancelled)throws Exception{ScreenAccessibilityService service=ScreenAccessibilityService.instance();if(service==null)throw new Exception("请在系统辅助功能中启用 AsterHand 屏幕助手。普通权限不会自动使用 ADB 或 Root。");return service.execute(name,args,cancelled);}
}
