package com.pocketagent;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.app.Service;
import android.graphics.Bitmap;
import android.graphics.Path;
import android.hardware.HardwareBuffer;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.util.DisplayMetrics;
import android.view.Display;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import java.io.ByteArrayOutputStream;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;
import org.json.JSONObject;

/** Ordinary Android user access: only the explicitly enabled system accessibility grant. */
public final class ScreenAccessibilityService extends AccessibilityService {
    private static volatile ScreenAccessibilityService instance;
    private static final ExecutorService screenshots=Executors.newSingleThreadExecutor();
    private final Handler main=new Handler(Looper.getMainLooper());
    static ScreenAccessibilityService instance(){return instance;}
    /** Geometry only, never keyboard contents. -1 means this system source is unavailable. */
    static int keyboardInset(int displayHeight){
        ScreenAccessibilityService service=instance;if(service==null)return -1;
        java.util.List<android.view.accessibility.AccessibilityWindowInfo> windows;
        try{windows=service.getWindows();}catch(RuntimeException unavailable){return -1;}
        if(windows==null||windows.isEmpty())return -1;int bottom=0;
        for(android.view.accessibility.AccessibilityWindowInfo window:windows)try{
            if(window.getType()==android.view.accessibility.AccessibilityWindowInfo.TYPE_INPUT_METHOD){android.graphics.Rect bounds=new android.graphics.Rect();window.getBoundsInScreen(bounds);if(!bounds.isEmpty()&&bounds.top>0&&bounds.top<displayHeight)bottom=Math.max(bottom,displayHeight-bounds.top);}
        }finally{window.recycle();}
        return bottom;
    }
    @Override protected void onServiceConnected(){super.onServiceConnected();instance=this;}
    @Override public void onAccessibilityEvent(AccessibilityEvent event){}
    @Override public void onInterrupt(){}
    @Override public void onDestroy(){if(instance==this)instance=null;super.onDestroy();}
    JSONObject execute(String name,JSONObject args)throws Exception{return execute(name,args,new java.util.concurrent.atomic.AtomicBoolean(false));}
    JSONObject execute(String name,JSONObject args,java.util.concurrent.atomic.AtomicBoolean cancelled)throws Exception{
        if(Looper.myLooper()==Looper.getMainLooper())throw new Exception("屏幕操作应在任务线程执行。");
        if(cancelled.get())throw new InterruptedException("操作已停止。");
        switch(name){
            case "screen_capture":return capture();
            case "screen_tap":return gesture(args,false);
            case "screen_swipe":return gesture(args,true);
            case "screen_type":return type(args,cancelled);
            case "screen_home":return home();
            default:throw new Exception("未知屏幕工具："+name);
        }
    }
    private JSONObject capture()throws Exception{
        if(Build.VERSION.SDK_INT<30)throw new Exception("普通权限截图需要 Android 11 及以上和屏幕辅助授权；当前权限不会自动升级。");
        CountDownLatch latch=new CountDownLatch(1);JSONObject[] result={null};String[] error={null};
        takeScreenshot(Display.DEFAULT_DISPLAY,screenshots,new TakeScreenshotCallback(){
            @Override public void onSuccess(ScreenshotResult shot){
                HardwareBuffer buffer=shot.getHardwareBuffer();Bitmap raw=null,copy=null,scaled=null;
                try{
                    raw=Bitmap.wrapHardwareBuffer(buffer,shot.getColorSpace());if(raw==null)throw new Exception("系统没有返回截图位图。");
                    copy=raw.copy(Bitmap.Config.ARGB_8888,false);if(copy==null)throw new Exception("无法读取系统截图。");
                    double factor=Math.min(1.0,1280.0/Math.max(copy.getWidth(),copy.getHeight()));
                    scaled=factor<1?Bitmap.createScaledBitmap(copy,Math.max(1,(int)(copy.getWidth()*factor)),Math.max(1,(int)(copy.getHeight()*factor)),true):copy;
                    ByteArrayOutputStream out=new ByteArrayOutputStream();if(!scaled.compress(Bitmap.CompressFormat.JPEG,82,out))throw new Exception("截图编码失败。");
                    result[0]=new JSONObject().put("image_base64",Base64.encodeToString(out.toByteArray(),Base64.NO_WRAP)).put("mime_type","image/jpeg").put("width",scaled.getWidth()).put("height",scaled.getHeight()).put("screen_width",copy.getWidth()).put("screen_height",copy.getHeight()).put("permission","normal");
                }catch(Exception e){error[0]=e.getMessage();}finally{if(scaled!=null&&scaled!=copy)scaled.recycle();if(copy!=null)copy.recycle();if(raw!=null)raw.recycle();buffer.close();latch.countDown();}
            }
            @Override public void onFailure(int code){error[0]="系统截图失败（"+code+"）。受保护页面不会被绕过。";latch.countDown();}
        });
        if(!latch.await(6,TimeUnit.SECONDS))throw new Exception("系统截图超时。");if(error[0]!=null)throw new Exception(error[0]);return result[0];
    }
    private JSONObject gesture(JSONObject args,boolean swipe)throws Exception{
        if(Build.VERSION.SDK_INT<24)throw new Exception("普通权限手势需要 Android 7 及以上。");
        double x=coordinate(args,"x"),y=coordinate(args,"y"),x2=swipe?coordinate(args,"x2"):x,y2=swipe?coordinate(args,"y2"):y;
        double seconds=swipe?args.optDouble("duration",0.35):0.07;if(!Double.isFinite(seconds)||seconds<0.05||seconds>2)throw new Exception("手势时长应为 0.05–2 秒。");
        DisplayMetrics metrics=new DisplayMetrics();((WindowManager)getSystemService(Service.WINDOW_SERVICE)).getDefaultDisplay().getRealMetrics(metrics);
        Path path=new Path();path.moveTo((float)(x*(metrics.widthPixels-1)),(float)(y*(metrics.heightPixels-1)));if(swipe)path.lineTo((float)(x2*(metrics.widthPixels-1)),(float)(y2*(metrics.heightPixels-1)));
        CountDownLatch latch=new CountDownLatch(1);boolean[] ok={false};GestureDescription gesture=new GestureDescription.Builder().addStroke(new GestureDescription.StrokeDescription(path,0,(long)(seconds*1000))).build();
        main.post(()->{boolean accepted=dispatchGesture(gesture,new GestureResultCallback(){@Override public void onCompleted(GestureDescription g){ok[0]=true;latch.countDown();}@Override public void onCancelled(GestureDescription g){latch.countDown();}},main);if(!accepted)latch.countDown();});
        if(!latch.await(4,TimeUnit.SECONDS))throw new Exception("系统手势超时。");if(!ok[0])throw new Exception("系统未完成手势，请检查辅助功能授权。");return new JSONObject().put(swipe?"swiped":"tapped",true).put("permission","normal");
    }
    private JSONObject type(JSONObject args,java.util.concurrent.atomic.AtomicBoolean cancelled)throws Exception{
        String text=args.optString("text","");boolean replace=args.optBoolean("replace",false);if((text.isEmpty()&&!replace)||text.length()>2000)throw new Exception("输入文本最多 2000 字符；清空输入框请使用 replace。");
        CountDownLatch latch=new CountDownLatch(1);String[] error={null};JSONObject result=new JSONObject();java.util.concurrent.atomic.AtomicBoolean abandoned=new java.util.concurrent.atomic.AtomicBoolean(false);
        main.post(()->{AccessibilityNodeInfo node=null,root=null;boolean handedOff=false;try{
            if(abandoned.get()||cancelled.get())throw new InterruptedException("文字输入已停止，未发送。");
            root=getRootInActiveWindow();node=focusedInput(root,cancelled,abandoned);
            if(node==null)throw new Exception("没有聚焦的可编辑输入框。");if(!node.refresh())throw new Exception("输入框已更新，请重新聚焦后重试。");if(node.isPassword())throw new Exception("密码输入请在手机上完成。");if(!node.isEditable()||!node.isFocused())throw new Exception("当前控件不支持文字输入。");
            boolean hint=Build.VERSION.SDK_INT>=26&&node.isShowingHintText();String old=node.getText()==null?"":node.getText().toString();
            InputTextPolicy.Plan plan=InputTextPolicy.plan(old,hint,node.getTextSelectionStart(),node.getTextSelectionEnd(),text,replace);
            Bundle bundle=new Bundle();bundle.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,plan.value);
            if(!node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,bundle))throw new Exception("目标应用拒绝了文字设置；请重新截图确认输入框。");
            final AccessibilityNodeInfo target=node;handedOff=true;result.put("hint_ignored",plan.hintIgnored).put("selection_used",plan.selectionUsed).put("replace",replace).put("inserted_characters",text.length());
            main.postDelayed(()->{try{
                if(abandoned.get()||cancelled.get())throw new InterruptedException("操作已停止；请截图确认已发送的内容。");
                boolean refreshed=target.refresh();CharSequence actual=refreshed?target.getText():null;boolean stillHint=refreshed&&Build.VERSION.SDK_INT>=26&&target.isShowingHintText();
                boolean verified=refreshed&&(plan.value.isEmpty()?(stillHint||actual==null||actual.length()==0):!stillHint&&plan.value.equals(actual==null?"":actual.toString()));
                result.put("typed",verified).put("verified",verified).put("permission","normal");
                if(verified){Bundle cursor=new Bundle();cursor.putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT,plan.cursor);cursor.putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT,plan.cursor);target.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION,cursor);}
                else result.put("error","已发送文字设置，但目标控件未返回预期内容；请先截图检查，避免直接重复输入。");
            }catch(Exception failure){error[0]=failure.getMessage();}finally{target.recycle();latch.countDown();}},160);
        }catch(Exception failure){error[0]=failure.getMessage();}finally{if(root!=null&&root!=node)root.recycle();if(!handedOff){if(node!=null)node.recycle();latch.countDown();}}});
        try{if(!latch.await(3,TimeUnit.SECONDS)){abandoned.set(true);throw new Exception("文字设置尚未完成，勿直接重复输入，请先截图确认。");}}catch(InterruptedException stopped){abandoned.set(true);throw stopped;}if(error[0]!=null)throw new Exception(error[0]);return result;
    }
    /** Some WebViews return their container from findFocus. Never guess an unfocused field. */
    private AccessibilityNodeInfo focusedInput(AccessibilityNodeInfo root,java.util.concurrent.atomic.AtomicBoolean cancelled,java.util.concurrent.atomic.AtomicBoolean abandoned)throws Exception{
        if(root==null)return null;
        AccessibilityNodeInfo direct=root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if(direct!=null){
            if(direct.isPassword()){direct.recycle();throw new Exception("密码输入请在手机上完成。");}
            if(direct.isEditable()&&direct.isFocused())return direct;
            direct.recycle();
        }
        final class Frame{final AccessibilityNodeInfo node;final int depth;Frame(AccessibilityNodeInfo n,int d){node=n;depth=d;}}
        java.util.ArrayDeque<Frame> queue=new java.util.ArrayDeque<>();
        queue.add(new Frame(AccessibilityNodeInfo.obtain(root),0));AccessibilityNodeInfo selected=null;
        int visited=0;long deadline=android.os.SystemClock.uptimeMillis()+1200;
        try{
            while(!queue.isEmpty()){
                if(cancelled.get()||abandoned.get())throw new InterruptedException("文字输入已停止，未发送。");
                if(++visited>512||android.os.SystemClock.uptimeMillis()>deadline)throw new Exception("当前窗口结构较复杂，无法安全确认唯一输入框，请重新聚焦后重试。");
                Frame frame=queue.removeFirst();AccessibilityNodeInfo current=frame.node;
                try{
                    if(current.isEditable()&&current.isFocused()){
                        if(current.isPassword())throw new Exception("密码输入请在手机上完成。");
                        if(selected!=null)throw new Exception("当前窗口有多个聚焦输入框，请在手机上重新选择输入框。");
                        selected=AccessibilityNodeInfo.obtain(current);
                    }
                    int children=current.getChildCount();
                    if((children>0&&frame.depth>=24)||children>512-visited-queue.size())throw new Exception("当前窗口结构较复杂，无法安全确认唯一输入框，请重新聚焦后重试。");
                    for(int i=0;i<children;i++){AccessibilityNodeInfo child=current.getChild(i);if(child!=null)queue.addLast(new Frame(child,frame.depth+1));}
                }finally{current.recycle();}
            }
            AccessibilityNodeInfo result=selected;selected=null;return result;
        }finally{if(selected!=null)selected.recycle();while(!queue.isEmpty())queue.removeFirst().node.recycle();}
    }
    /** Debug bridge only. Deliberately never reads text, hints, IDs or package names. */
    static JSONObject focusMetadata()throws Exception{
        ScreenAccessibilityService service=instance;if(service==null)throw new Exception("请先启用 AsterHand 屏幕助手。");
        JSONObject[] result={null};Exception[] error={null};CountDownLatch done=new CountDownLatch(1);
        Runnable read=()->{AccessibilityNodeInfo root=null,direct=null,global=null;java.util.List<android.view.accessibility.AccessibilityWindowInfo> windows=null;
            try{JSONObject out=new JSONObject().put("diagnostic",true).put("content_read",false);root=service.getRootInActiveWindow();out.put("active_root",nodeMetadata(root));
                direct=root==null?null:root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);global=service.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);out.put("root_focus",nodeMetadata(direct)).put("service_focus",nodeMetadata(global));
                org.json.JSONArray rows=new org.json.JSONArray();windows=service.getWindows();if(windows!=null)for(int i=0;i<Math.min(32,windows.size());i++){android.view.accessibility.AccessibilityWindowInfo window=windows.get(i);AccessibilityNodeInfo windowRoot=null;try{windowRoot=window.getRoot();rows.put(new JSONObject().put("id",window.getId()).put("type",window.getType()).put("active",window.isActive()).put("focused",window.isFocused()).put("root_class",windowRoot==null?JSONObject.NULL:String.valueOf(windowRoot.getClassName())));}finally{if(windowRoot!=null)windowRoot.recycle();}}out.put("windows",rows);result[0]=out;
            }catch(Exception failure){error[0]=failure;}finally{if(direct!=null)direct.recycle();if(global!=null)global.recycle();if(root!=null)root.recycle();if(windows!=null)for(android.view.accessibility.AccessibilityWindowInfo window:windows)window.recycle();done.countDown();}};
        if(Looper.myLooper()==Looper.getMainLooper())read.run();else service.main.post(read);
        if(!done.await(3,TimeUnit.SECONDS))throw new Exception("窗口诊断超时。");if(error[0]!=null)throw error[0];return result[0];
    }
    private static JSONObject nodeMetadata(AccessibilityNodeInfo node)throws Exception{
        JSONObject out=new JSONObject().put("present",node!=null);if(node==null)return out;
        android.graphics.Rect bounds=new android.graphics.Rect();node.getBoundsInScreen(bounds);
        return out.put("class",String.valueOf(node.getClassName())).put("editable",node.isEditable()).put("focused",node.isFocused()).put("password",node.isPassword()).put("window_id",node.getWindowId()).put("bounds",new org.json.JSONArray().put(bounds.left).put(bounds.top).put(bounds.right).put(bounds.bottom));
    }
    private JSONObject home()throws Exception{CountDownLatch latch=new CountDownLatch(1);boolean[] ok={false};main.post(()->{ok[0]=performGlobalAction(GLOBAL_ACTION_HOME);latch.countDown();});if(!latch.await(3,TimeUnit.SECONDS)||!ok[0])throw new Exception("系统未接受主屏幕操作。");return new JSONObject().put("home",true).put("permission","normal");}
    private static double coordinate(JSONObject args,String key)throws Exception{double v=args.optDouble(key,Double.NaN);if(!Double.isFinite(v)||v<0||v>1)throw new Exception(key+" 应为 0–1 的屏幕坐标。");return v;}
}
