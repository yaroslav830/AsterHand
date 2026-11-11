package com.pocketagent;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.Process;
import android.util.Base64;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/** Chooses the executor identity, without silently falling back to another identity. */
public final class PrivilegeManager {
    private static final AtomicLong taskEpoch=new AtomicLong(),selectionEpoch=new AtomicLong();
    private static final Object policyLock=new Object(),configurationLock=new Object();
    private static final ThreadLocal<TaskGrant> taskGrant=new ThreadLocal<>();
    private static final class TaskGrant {
        final Mode mode;final long epoch;final boolean oneOperation;final String operation,digest;boolean active;
        TaskGrant(Mode mode){this(mode,false,"","");}
        TaskGrant(Mode mode,boolean once,String operation,String digest){this.mode=mode;epoch=taskEpoch.get();oneOperation=once;this.operation=operation;this.digest=digest;}
    }
    public static void allowForCurrentTask(Mode mode){if(mode==null)throw new IllegalArgumentException("Mode required");taskGrant.set(new TaskGrant(mode));}
    public static void clearTaskGrant(){taskGrant.remove();}
    public static boolean hasPendingOperationGrant(){TaskGrant grant=taskGrant.get();return grant!=null&&grant.oneOperation&&grant.epoch==taskEpoch.get();}
    public static void consumeOperationGrant(){TaskGrant grant=taskGrant.get();if(grant!=null&&grant.oneOperation)taskGrant.remove();}
    public static void allowForNextOperation(Mode mode,String tool,JSONObject args)throws Exception{
        if(mode==null||tool==null||!java.util.Arrays.asList("run_shell","read_file","write_file","list_directory","screen_capture","screen_tap","screen_swipe","screen_type","screen_home").contains(tool))throw new Exception("一次权限只能绑定具体的本机工具。");
        taskGrant.set(new TaskGrant(mode,true,tool,argumentDigest(args==null?new JSONObject():args)));
    }
    void beginOperation(Mode mode,String tool,JSONObject args)throws Exception{
        TaskGrant grant=taskGrant.get();
        if(mode!=getMode()&&grant!=null&&grant.oneOperation&&grant.epoch==taskEpoch.get()&&grant.mode==mode){
            if(!grant.operation.equals(tool)||!grant.digest.equals(argumentDigest(args==null?new JSONObject():args)))throw new Exception("本次权限只适用于已确认的具体工具和参数，请重新申请。");grant.active=true;
        }
        requireSelected(mode);
    }
    private static String argumentDigest(Object value)throws Exception{return Base64.encodeToString(java.security.MessageDigest.getInstance("SHA-256").digest(canonical(value).getBytes(StandardCharsets.UTF_8)),Base64.NO_WRAP);}
    private static String canonical(Object value)throws Exception{
        if(value==null||value==JSONObject.NULL)return "null";
        if(value instanceof JSONObject){JSONObject object=(JSONObject)value;java.util.TreeSet<String> keys=new java.util.TreeSet<>();java.util.Iterator<String> iterator=object.keys();while(iterator.hasNext())keys.add(iterator.next());StringBuilder result=new StringBuilder("{");for(String key:keys){if(result.length()>1)result.append(',');result.append(JSONObject.quote(key)).append(':').append(canonical(object.get(key)));}return result.append('}').toString();}
        if(value instanceof org.json.JSONArray){org.json.JSONArray array=(org.json.JSONArray)value;StringBuilder result=new StringBuilder("[");for(int i=0;i<array.length();i++){if(i>0)result.append(',');result.append(canonical(array.get(i)));}return result.append(']').toString();}
        if(value instanceof Number)return new java.math.BigDecimal(value.toString()).stripTrailingZeros().toPlainString();
        if(value instanceof Boolean)return value.toString();return JSONObject.quote(String.valueOf(value));
    }
    public enum Mode {
        NORMAL, ADB, ROOT;
        public static Mode parse(String value) { try{return valueOf(value==null?"NORMAL":value.toUpperCase(java.util.Locale.ROOT));}catch(Exception ignored){return NORMAL;} }
        public String label(){return this==ROOT?"Root":this==ADB?"ADB":"普通用户";}
    }
    private final Context context;
    private final SharedPreferences preferences;
    public PrivilegeManager(Context context){
        Context application=context.getApplicationContext();this.context=application==null?context:application;
        preferences=this.context.getSharedPreferences("privileges",Context.MODE_PRIVATE);
        if(!preferences.contains("mode")){
            boolean legacy=this.context.getSharedPreferences("MainActivity",Context.MODE_PRIVATE).getBoolean("root",false);
            preferences.edit().putString("mode",legacy?"ROOT":"NORMAL").apply();
        }
        try{bridgeConfiguration();}catch(Exception ignored){}
    }
    public Mode getMode(){return Mode.parse(preferences.getString("mode","NORMAL"));}
    public Mode effectiveMode(){TaskGrant grant=taskGrant.get();return grant!=null&&grant.epoch==taskEpoch.get()?grant.mode:getMode();}
    public JSONObject select(Mode mode)throws Exception{
        if(mode==null)throw new Exception("请选择权限级别。");
        JSONObject check=probe(mode);
        if(!check.optBoolean("available"))throw new Exception(check.optString("error","此权限当前不可用。"));
        Mode previous;
        synchronized(policyLock){previous=getMode();taskEpoch.incrementAndGet();if(previous!=mode)selectionEpoch.incrementAndGet();preferences.edit().putString("mode",mode.name()).commit();}
        if(mode.ordinal()<previous.ordinal()){
            TerminalSessions.closeAbove(mode);
            if(previous==Mode.ADB||mode==Mode.NORMAL){try{adbRequest(new JSONObject().put("kind","terminal_cleanup"),new AtomicBoolean(false));}catch(Exception ignored){}}
        }
        return check;
    }
    public JSONObject probe(Mode mode){
        try{
            JSONObject result=request(mode,new JSONObject().put("kind","probe"),new AtomicBoolean(false));
            int expected=mode==Mode.ROOT?0:mode==Mode.ADB?2000:Process.myUid();
            boolean valid=result.optInt("uid",-1)==expected;
            result.put("available",valid).put("mode",mode.name()).put("expected_uid",expected);
            if(!valid)result.put("error","执行器身份不匹配；没有执行操作。");return result;
        }catch(Exception error){
            JSONObject result=new JSONObject();try{result.put("mode",mode.name()).put("available",false).put("error",safeError(error));}catch(Exception ignored){}return result;
        }
    }
    public JSONObject run(Mode mode,String command,String cwd,int timeoutSeconds,AtomicBoolean cancelled)throws Exception{
        requireSelected(mode);
        return request(mode,new JSONObject().put("kind","shell").put("command",command).put("cwd",cwd==null?context.getFilesDir().getAbsolutePath():cwd).put("timeout",Math.max(1,Math.min(120,timeoutSeconds))),cancelled);
    }
    public JSONObject executeTool(Mode mode,String workspace,String name,JSONObject args,AtomicBoolean cancelled)throws Exception{
        requireSelected(mode);
        if(PrivilegedOperations.isFileTool(name)){
            ProjectStore projects=new ProjectStore(context);JSONObject operation=projects.scopedFileOperation(workspace,name,args);
            // App-side validation also protects against a still-running older ADB executor.
            PrivilegedOperations.validateFileRequest(operation);
            JSONObject result=request(mode,operation,cancelled);
            return PrivilegedOperations.filterFileResult(workspace,name,operation.getJSONObject("args"),projects.fileExclusions(workspace),result);
        }
        return request(mode,new JSONObject().put("kind","tool").put("workspace",workspace).put("name",name).put("args",args==null?new JSONObject():args),cancelled);
    }
    public JSONObject terminal(String action,JSONObject args,String owner,Mode mode)throws Exception{
        if(!action.equals("close")&&!action.equals("interrupt"))requireSelected(mode);
        long openingEpoch=selectionEpoch.get();
        JSONObject result=mode==Mode.ADB?request(mode,new JSONObject().put("kind","terminal").put("action",action).put("args",args==null?new JSONObject():args).put("owner",owner),new AtomicBoolean(false)):TerminalSessions.invoke(action,args==null?new JSONObject():args,owner,mode);
        if(result.has("error"))throw new Exception(result.optString("error","终端操作失败。"));
        if(action.equals("open"))try{requireSelected(mode);if(selectionEpoch.get()!=openingEpoch)throw new Exception("权限已切换。");}catch(Exception revoked){try{terminal("close",new JSONObject().put("session",result.optString("session")),owner,mode);}catch(Exception ignored){}throw revoked;}
        return result;
    }
    public void closeOwner(String owner){
        if(owner==null||owner.isEmpty()||owner.length()>128)return;
        TerminalSessions.closeOwner(owner);
        try{adbRequest(new JSONObject().put("kind","terminal_owner_cleanup").put("owner",owner),new AtomicBoolean(false));}catch(Exception ignored){}
    }
    private void requireSelected(Mode mode)throws Exception{TaskGrant grant=taskGrant.get();if(mode!=getMode()&&(grant==null||grant.mode!=mode||grant.epoch!=taskEpoch.get()||grant.oneOperation&&!grant.active))throw new Exception("权限已切换或本次授权已结束；请按当前权限重新发起操作。");}
    public JSONObject bridgeConfiguration()throws Exception{
        synchronized(configurationLock){
            File file=new File(context.getFilesDir(),"adb-bridge.json");
            if(file.isFile()){
                JSONObject old=new JSONObject(new String(PrivilegedOperations.readLimited(new android.util.AtomicFile(file).openRead(),16384),StandardCharsets.UTF_8));
                if(old.optInt("uid")==Process.myUid()&&old.optString("token").length()>=40&&old.optString("socket").startsWith("asterhand.adb.")){
                    String current=context.getApplicationInfo().sourceDir;boolean changed=!current.equals(old.optString("apk"));old.put("apk",current);if(old.optInt("port")<1024){old.put("port",BridgeTransport.unusedPort());changed=true;}if(!old.optString("transport").equals("loopback_hmac_v2")){old.put("transport","loopback_hmac_v2");changed=true;}if(changed)writeBridgeConfiguration(file,old);return old;
                }
            }
            byte[] bytes=new byte[32];new SecureRandom().nextBytes(bytes);
            String token=Base64.encodeToString(bytes,Base64.NO_WRAP);
            byte[] suffix=new byte[12];new SecureRandom().nextBytes(suffix);StringBuilder hex=new StringBuilder();for(byte value:suffix)hex.append(String.format(java.util.Locale.ROOT,"%02x",value&255));
            JSONObject result=new JSONObject().put("version",1).put("uid",Process.myUid()).put("socket","asterhand.adb."+Process.myUid()+"."+hex).put("token",token).put("apk",context.getApplicationInfo().sourceDir).put("port",BridgeTransport.unusedPort()).put("transport","loopback_hmac_v2");
            writeBridgeConfiguration(file,result);return result;
        }
    }
    private static void writeBridgeConfiguration(File file,JSONObject value)throws Exception{
        android.util.AtomicFile atomic=new android.util.AtomicFile(file);FileOutputStream out=atomic.startWrite();
        try{out.write(value.toString().getBytes(StandardCharsets.UTF_8));out.getFD().sync();atomic.finishWrite(out);}catch(Exception failure){atomic.failWrite(out);throw failure;}
        file.setReadable(false,false);file.setWritable(false,false);file.setReadable(true,true);file.setWritable(true,true);
    }
    JSONObject relocateBridgePort()throws Exception{synchronized(configurationLock){JSONObject config=bridgeConfiguration();config.put("port",BridgeTransport.unusedPort());writeBridgeConfiguration(new File(context.getFilesDir(),"adb-bridge.json"),config);return config;}}
    public JSONObject bridgeStatus(){return probe(Mode.ADB);}
    private JSONObject request(Mode mode,JSONObject operation,AtomicBoolean cancelled)throws Exception{
        if(mode==null)throw new Exception("权限级别缺失。");
        AtomicBoolean caller=cancelled==null?new AtomicBoolean(false):cancelled,stop=new AtomicBoolean(caller.get()),finished=new AtomicBoolean(false);
        if(stop.get())throw new Exception("操作已停止。");
        boolean watchSelection=operation.optString("kind").equals("shell")||operation.optString("kind").equals("tool");
        final TaskGrant grant;final boolean temporary;final long selectedAt;
        synchronized(policyLock){if(watchSelection)requireSelected(mode);grant=taskGrant.get();temporary=mode!=getMode()&&grant!=null&&grant.mode==mode&&grant.epoch==taskEpoch.get();selectedAt=selectionEpoch.get();}
        Thread guard=new Thread(()->{while(!finished.get()){
            if(caller.get()||(watchSelection&&(temporary?grant.epoch!=taskEpoch.get():selectionEpoch.get()!=selectedAt))){stop.set(true);return;}
            try{Thread.sleep(40);}catch(InterruptedException end){return;}
        }},"AsterHand-privilege-revocation");guard.setDaemon(true);guard.start();
        try{
            JSONObject result;
            if(mode==Mode.NORMAL)result=PrivilegedOperations.execute(mode,operation,stop);
            else if(mode==Mode.ADB)result=adbRequest(operation,stop);
            else result=rootRequest(operation,stop);
            int expected=mode==Mode.ROOT?0:mode==Mode.ADB?2000:Process.myUid();
            if(result.optInt("uid",-1)!=expected)throw new Exception("执行器身份不匹配，拒绝此结果。");
            result.put("mode",mode.name());return result;
        }finally{finished.set(true);guard.interrupt();}
    }
    private JSONObject adbRequest(JSONObject operation,AtomicBoolean cancelled)throws Exception{
        try(BridgeTransport.Client channel=BridgeTransport.connect(bridgeConfiguration())){
            channel.send(operation);
            final JSONObject[] answer=new JSONObject[1];final Exception[] error=new Exception[1];AtomicBoolean finished=new AtomicBoolean(false);
            Thread reader=new Thread(()->{try{answer[0]=channel.readResult();}catch(Exception failure){error[0]=failure;}finally{finished.set(true);}},"AsterHand-ADB-response");reader.setDaemon(true);reader.start();
            long deadline=android.os.SystemClock.elapsedRealtime()+135000;
            while(!finished.get()&&android.os.SystemClock.elapsedRealtime()<deadline){
                if(cancelled.get()){channel.cancel();reader.join(2500);break;}reader.join(80);
            }
            if(answer[0]!=null)return answer[0];
            if(cancelled.get())throw new Exception("ADB 操作已停止。");
            if(error[0]!=null)throw error[0];throw new Exception("ADB 通道响应超时。");
        }catch(Exception failure){throw new Exception("ADB 通道不可用："+safeError(failure)+"。请通过电脑运行 ADB 启动脚本；不会改用 Root。",failure);}
    }
    private JSONObject rootRequest(JSONObject operation,AtomicBoolean cancelled)throws Exception{
        String apk=context.getApplicationInfo().sourceDir;
        String command="CLASSPATH="+PrivilegedOperations.quote(apk)+" /system/bin/app_process /system/bin com.pocketagent.PrivilegedJob";
        java.lang.Process process=new ProcessBuilder(RootBinaries.su(),"-c",command).start();
        ByteArrayOutputStream stderr=new ByteArrayOutputStream();Thread errors=PrivilegedOperations.drain(process.getErrorStream(),stderr,16384);
        final JSONObject[] answer=new JSONObject[1];final Exception[] failure=new Exception[1];AtomicBoolean finished=new AtomicBoolean(false);
        Thread reader=new Thread(()->{try{answer[0]=PrivilegedOperations.readFrame(process.getInputStream());}catch(Exception error){failure[0]=error;}finally{finished.set(true);}},"AsterHand-root-response");reader.setDaemon(true);reader.start();
        try{
            PrivilegedOperations.writeFrame(process.getOutputStream(),operation);
            long deadline=android.os.SystemClock.elapsedRealtime()+135000;boolean signalled=false;
            while(!finished.get()&&android.os.SystemClock.elapsedRealtime()<deadline){
                if(cancelled.get()&&!signalled){signalled=true;try{process.getOutputStream().write(1);process.getOutputStream().flush();}catch(Exception ignored){}}
                if(signalled){reader.join(2500);break;}reader.join(80);
            }
            if(answer[0]!=null)return answer[0];
            if(cancelled.get())throw new Exception("Root 操作已停止。");
            String detail=new String(stderr.toByteArray(),StandardCharsets.UTF_8).trim();
            if(detail.toLowerCase(java.util.Locale.ROOT).contains("denied"))throw new Exception("Root 授权被拒绝。");
            throw new Exception(failure[0]==null?"Root 执行器启动或响应超时。":"Root 执行器未正常返回；请检查 su 授权。");
        }finally{
            try{process.getOutputStream().close();}catch(Exception ignored){}
            try{reader.join(1500);}catch(InterruptedException ignored){Thread.currentThread().interrupt();}
            if(!finished.get())process.destroy();
            try{process.getInputStream().close();process.getErrorStream().close();}catch(Exception ignored){}
        }
    }
    static String safeError(Exception error){String message=error.getMessage();return message==null||message.trim().isEmpty()?error.getClass().getSimpleName():message;}
}
