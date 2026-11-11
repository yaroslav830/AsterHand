package com.pocketagent;

import android.content.Context;
import android.content.SharedPreferences;
import android.media.AudioAttributes;
import android.os.*;
import android.provider.Settings;
import android.view.HapticFeedbackConstants;
import android.view.View;
import java.util.Locale;
import org.json.JSONObject;

/** Four app styles; the operating system still owns touch-feedback and hardware policy. */
public final class Haptics {
    private static long lastFeedback,count;
    private static JSONObject last;
    private Haptics() {}
    public static String normalizeStyle(String style){
        String value=style==null?"system":style.toLowerCase(Locale.ROOT);
        if(value.equals("firm"))return "strong";
        if(value.equals("selection"))return "crisp";
        return value.equals("soft")||value.equals("crisp")||value.equals("strong")?value:"system";
    }
    public static String normalizeKind(String reason){
        String value=reason==null?"select":reason.toLowerCase(Locale.ROOT);
        if(value.equals("select")||value.equals("selection")||value.equals("toggle"))return "select";
        if(value.equals("success")||value.equals("complete")||value.equals("completed")||value.equals("connect"))return "complete";
        if(value.equals("warning")||value.equals("question")||value.equals("disconnect")||value.equals("delete"))return "warning";
        if(value.equals("start")||value.equals("resume")||value.equals("send"))return "start";
        return value.equals("stop")||value.equals("pause")||value.equals("error")?value:"tap";
    }
    public static synchronized JSONObject lastEvent(){try{return last==null?new JSONObject():new JSONObject(last.toString());}catch(Exception ignored){return new JSONObject();}}
    private static synchronized void record(String kind,String style,String backend,boolean accepted,String status){try{last=new JSONObject().put("kind",kind).put("style",style).put("backend",backend).put("accepted",accepted).put("status",status).put("count",++count).put("hardware_verified",false).put("updated",System.currentTimeMillis());}catch(Exception ignored){}}
    public static void play(Context context,View view,String reason){
        if(context==null)return;Context application=context.getApplicationContext();final Context app=application==null?context:application;
        if(Looper.myLooper()!=Looper.getMainLooper()){new Handler(Looper.getMainLooper()).post(()->play(app,view,reason));return;}
        SharedPreferences prefs=app.getSharedPreferences("MainActivity",Context.MODE_PRIVATE);String saved=prefs.getString("hapticStyle","system"),style=normalizeStyle(saved),kind=normalizeKind(reason);
        // Old off/disabled preferences no longer represent an app feature. Do not alter OS settings.
        if(!style.equals(saved)||!prefs.getBoolean("haptics",true))prefs.edit().putString("hapticStyle",style).remove("haptics").apply();
        if(view!=null&&!view.isHapticFeedbackEnabled()){record(kind,style,"none",false,"view_disabled");return;}
        try{if(Settings.System.getInt(app.getContentResolver(),Settings.System.HAPTIC_FEEDBACK_ENABLED,1)==0){record(kind,style,"none",false,"system_disabled");return;}}
        catch(RuntimeException unavailable){if(view!=null&&!tooSoon()){boolean accepted=view.performHapticFeedback(systemConstant(kind));record(kind,style,"view",accepted,"system_policy");}return;}
        if(tooSoon()){record(kind,style,"none",false,"throttled");return;}
        // A view request is the sole path for the system style. Never add a second vibration.
        if(style.equals("system")&&view!=null){boolean accepted=view.performHapticFeedback(systemConstant(kind));record(kind,style,"view",accepted,"requested");return;}
        try{
            Vibrator vibrator;if(Build.VERSION.SDK_INT>=31){VibratorManager manager=app.getSystemService(VibratorManager.class);vibrator=manager==null?null:manager.getDefaultVibrator();}else vibrator=(Vibrator)app.getSystemService(Context.VIBRATOR_SERVICE);
            if(vibrator==null||!vibrator.hasVibrator()){record(kind,style,"none",false,"unsupported");return;}
            boolean semantic=style.equals("system"),complete=semantic&&kind.equals("complete"),error=semantic&&kind.equals("error"),warning=semantic&&kind.equals("warning"),strong=style.equals("strong")||(semantic&&kind.equals("stop")),soft=style.equals("soft")||(semantic&&kind.equals("select"));
            AudioAttributes attributes=new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build();
            if(Build.VERSION.SDK_INT>=29&&!error&&!warning){int effect=complete?VibrationEffect.EFFECT_DOUBLE_CLICK:strong?VibrationEffect.EFFECT_HEAVY_CLICK:soft?VibrationEffect.EFFECT_TICK:VibrationEffect.EFFECT_CLICK;vibrator.vibrate(VibrationEffect.createPredefined(effect),attributes);}
            else if(complete||error||warning){long[] pattern=error?new long[]{0,25,55,25,65,30}:warning?new long[]{0,22,75,22}:new long[]{0,16,65,24};if(Build.VERSION.SDK_INT>=26)vibrator.vibrate(VibrationEffect.createWaveform(pattern,-1),attributes);else vibrator.vibrate(pattern,-1,attributes);}
            else{long duration=strong?28:soft?10:14;int amplitude=strong?220:soft?65:style.equals("crisp")?160:120;if(Build.VERSION.SDK_INT>=26)vibrator.vibrate(VibrationEffect.createOneShot(duration,amplitude),attributes);else vibrator.vibrate(duration,attributes);}
            record(kind,style,"vibrator",true,"requested");
        }catch(RuntimeException unavailable){record(kind,style,"none",false,"system_rejected");}
    }
    private static boolean tooSoon(){long now=SystemClock.uptimeMillis();if(lastFeedback!=0&&now-lastFeedback<45)return true;lastFeedback=now;return false;}
    private static int systemConstant(String kind){
        if(Build.VERSION.SDK_INT>=30){if(kind.equals("complete"))return HapticFeedbackConstants.CONFIRM;if(kind.equals("error")||kind.equals("warning"))return HapticFeedbackConstants.REJECT;if(kind.equals("start"))return HapticFeedbackConstants.GESTURE_START;if(kind.equals("pause"))return HapticFeedbackConstants.GESTURE_END;}
        if(kind.equals("select"))return HapticFeedbackConstants.CLOCK_TICK;
        if(kind.equals("stop")||kind.equals("error")||kind.equals("warning"))return HapticFeedbackConstants.LONG_PRESS;
        return HapticFeedbackConstants.KEYBOARD_TAP;
    }
}
