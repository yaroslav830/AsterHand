package com.pocketagent;

import android.content.Context;
import android.os.SystemClock;
import org.json.JSONObject;
import java.io.File;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

/** Authorized app-UID QA helper; no exported activity or network QA endpoint. */
public final class PrivilegeSelfTest {
    private static void check(JSONObject tests,String name,boolean condition)throws Exception{tests.put(name,condition);if(!condition)throw new Exception("Check failed: "+name);}
    private static Context context()throws Exception{
        if(android.os.Looper.myLooper()==null)android.os.Looper.prepareMainLooper();Class<?> type=Class.forName("android.app.ActivityThread");Object thread=type.getMethod("systemMain").invoke(null);Context system=(Context)type.getMethod("getSystemContext").invoke(thread);return system.createPackageContext("com.pocketagent",Context.CONTEXT_IGNORE_SECURITY);
    }
    private static boolean denied(PrivilegeManager manager,String session,String owner,PrivilegeManager.Mode mode){try{manager.terminal("read",new JSONObject().put("session",session),owner,mode);return false;}catch(Exception expected){return true;}}
    private static boolean closed(PrivilegeManager manager,String session,String owner,PrivilegeManager.Mode mode){try{manager.terminal("close",new JSONObject().put("session",session),owner,mode);return false;}catch(Exception expected){return true;}}
    private static boolean wrongTokenRejected(PrivilegeManager manager)throws Exception{
        JSONObject bad=new JSONObject(manager.bridgeConfiguration().toString());bad.put("token","invalid-qa-token");
        try(BridgeTransport.Client channel=BridgeTransport.connect(bad)){return false;}catch(SecurityException expected){return true;}
    }
    public static void main(String[] arguments){
        try{JSONObject result=run(context(),arguments);System.out.println(result.toString());if(!result.optBoolean("success"))System.exit(1);}catch(Exception failure){System.err.println("Privilege QA: "+failure.getClass().getSimpleName());System.exit(1);}
    }
    public static JSONObject run(Context context){return run(context,new String[0]);}
    public static JSONObject run(Context context,String[] arguments){
        JSONObject tests=new JSONObject();PrivilegeManager manager=null;PrivilegeManager.Mode original=null;File directory=null;String owner="qa-"+UUID.randomUUID();boolean success=false;
        try{
            if(android.os.Process.myUid()<10000)throw new Exception("QA must run in the actual application UID, not shell or Root");
            manager=new PrivilegeManager(context);original=manager.getMode();
            if(arguments.length==1&&arguments[0].equals("--bridge-unavailable")){
                check(tests,"adb_unavailable",!manager.probe(PrivilegeManager.Mode.ADB).optBoolean("available"));boolean denied=false;try{manager.select(PrivilegeManager.Mode.ADB);}catch(Exception expected){denied=true;}check(tests,"adb_failure_has_no_root_fallback",denied);check(tests,"failed_selection_preserves_mode",manager.getMode()==original);success=true;return tests;
            }
            directory=new File(context.getCacheDir(),"privilege-qa-"+UUID.randomUUID());if(!directory.mkdir())throw new Exception("Cannot create isolated test workspace");String cwd=directory.getCanonicalPath();AtomicBoolean stop=new AtomicBoolean(false);
            manager.select(PrivilegeManager.Mode.NORMAL);JSONObject normal=manager.run(PrivilegeManager.Mode.NORMAL,"id -u",cwd,5,stop);
            check(tests,"normal_uid",normal.getInt("uid")==android.os.Process.myUid()&&normal.optString("stdout").trim().equals(Integer.toString(android.os.Process.myUid())));
            JSONObject streams=manager.run(PrivilegeManager.Mode.NORMAL,"printf hello; printf warning >&2; exit 7",cwd,5,stop);
            check(tests,"stdout_stderr_exit",streams.optString("stdout").equals("hello")&&streams.optString("stderr").equals("warning")&&streams.optInt("exit_code")==7);
            JSONObject timed=manager.run(PrivilegeManager.Mode.NORMAL,"sleep 20",cwd,1,stop);check(tests,"shell_timeout",timed.optBoolean("timed_out")&&timed.optInt("exit_code")==124);
            AtomicBoolean cancel=new AtomicBoolean(false);Thread trigger=new Thread(()->{SystemClock.sleep(250);cancel.set(true);});trigger.start();long began=SystemClock.elapsedRealtime();JSONObject cancelled=manager.run(PrivilegeManager.Mode.NORMAL,"sleep 20",cwd,20,cancel);
            check(tests,"shell_cancellation",cancelled.optBoolean("cancelled")&&SystemClock.elapsedRealtime()-began<5000);
            AgentTools files=new AgentTools(context,PrivilegeManager.Mode.NORMAL,cwd);String path="quoted' 文件.txt";files.execute("write_file",new JSONObject().put("path",path).put("content","正常写入 🌟"));
            check(tests,"unicode_quoted_file",files.execute("read_file",new JSONObject().put("path",path)).getString("content").equals("正常写入 🌟"));
            JSONObject replacement=files.execute("write_file",new JSONObject().put("path",path).put("content","替换"));check(tests,"write_backup",!replacement.optString("backup").isEmpty()&&new File(directory,replacement.getString("backup")).isFile());
            boolean escaped=false;try{files.execute("write_file",new JSONObject().put("path","../escape.txt").put("content","blocked"));}catch(Exception expected){escaped=true;}check(tests,"project_escape_rejected",escaped);
            File outside=new File(context.getCacheDir(),"privilege-outside-"+UUID.randomUUID());outside.createNewFile();try{android.system.Os.symlink(outside.getPath(),new File(directory,"link").getPath());boolean rejected=false;try{files.execute("read_file",new JSONObject().put("path","link"));}catch(Exception expected){rejected=true;}check(tests,"symlink_rejected",rejected);}finally{outside.delete();}
            JSONObject term=manager.terminal("open",new JSONObject().put("cwd",cwd),owner,PrivilegeManager.Mode.NORMAL);String normalId=term.getString("session");
            manager.terminal("write",new JSONObject().put("session",normalId).put("text","ASTER_QA=kept; cd /; printf 'TERMINAL:%s:%s\\n' \"$ASTER_QA\" \"$PWD\"\n"),owner,PrivilegeManager.Mode.NORMAL);SystemClock.sleep(150);
            JSONObject read=manager.terminal("read",new JSONObject().put("session",normalId),owner,PrivilegeManager.Mode.NORMAL);check(tests,"persistent_terminal_state",read.optString("output").contains("TERMINAL:kept:/"));check(tests,"terminal_owner_isolation",denied(manager,normalId,owner+"-other",PrivilegeManager.Mode.NORMAL));
            manager.terminal("close",new JSONObject().put("session",normalId),owner,PrivilegeManager.Mode.NORMAL);
            manager.select(PrivilegeManager.Mode.ADB);JSONObject adb=manager.run(PrivilegeManager.Mode.ADB,"id -u","/data/local/tmp",5,stop);check(tests,"adb_uid_2000",adb.optInt("uid")==2000&&adb.optString("stdout").trim().equals("2000"));
            check(tests,"activation_receiver_requires_dump","android.permission.DUMP".equals(context.getPackageManager().getReceiverInfo(new android.content.ComponentName(context,AdbActivationReceiver.class),0).permission));
            check(tests,"bridge_rejects_wrong_token",wrongTokenRejected(manager));
            String deniedProbe="CLASSPATH="+PrivilegedOperations.quote(context.getApplicationInfo().sourceDir)+" /system/bin/app_process /system/bin com.pocketagent.AdbBridgeDeniedProbe "+Integer.toString(manager.bridgeConfiguration().getInt("port"));
            check(tests,"bridge_rejects_unauthenticated_peer",manager.run(PrivilegeManager.Mode.ADB,deniedProbe,"/",8,stop).optString("stdout").contains("ASTERHAND_UNAUTHENTICATED_CLIENT_REJECTED"));
            JSONObject adbTerminal=manager.terminal("open",new JSONObject().put("cwd","/data/local/tmp"),owner,PrivilegeManager.Mode.ADB);String adbId=adbTerminal.getString("session");
            manager.terminal("write",new JSONObject().put("session",adbId).put("text","ASTER_QA=adb_kept; printf '%s\\n' \"$ASTER_QA\"\n"),owner,PrivilegeManager.Mode.ADB);SystemClock.sleep(150);check(tests,"adb_terminal_state",manager.terminal("read",new JSONObject().put("session",adbId),owner,PrivilegeManager.Mode.ADB).optString("output").contains("adb_kept"));
            check(tests,"adb_terminal_owner_isolation",denied(manager,adbId,owner+"-other",PrivilegeManager.Mode.ADB));
            manager.select(PrivilegeManager.Mode.ROOT);JSONObject root=manager.run(PrivilegeManager.Mode.ROOT,"id -u",cwd,5,stop);check(tests,"root_uid_0",root.optInt("uid")==0&&root.optString("stdout").trim().equals("0"));
            new AgentTools(context,PrivilegeManager.Mode.ROOT,cwd).execute("write_file",new JSONObject().put("path","root-created.txt").put("content","root created, app readable"));
            JSONObject rootTerminal=manager.terminal("open",new JSONObject().put("cwd",cwd),owner,PrivilegeManager.Mode.ROOT);String rootId=rootTerminal.getString("session");
            manager.select(PrivilegeManager.Mode.ADB);check(tests,"root_terminal_closed_on_downgrade",closed(manager,rootId,owner,PrivilegeManager.Mode.ROOT));
            String rootState=manager.run(PrivilegeManager.Mode.ADB,"ps -p "+rootTerminal.getInt("pid")+" -o STAT","/",5,stop).optString("stdout").trim();check(tests,"root_terminal_process_terminated",rootState.equals("STAT")||rootState.endsWith("Z")||rootState.isEmpty());
            boolean noRootFallback=false;try{manager.run(PrivilegeManager.Mode.ROOT,"id -u",cwd,5,stop);}catch(Exception expected){noRootFallback=true;}check(tests,"stale_root_tier_rejected",noRootFallback);
            manager.select(PrivilegeManager.Mode.NORMAL);check(tests,"adb_terminal_closed_on_downgrade",closed(manager,adbId,owner,PrivilegeManager.Mode.ADB));check(tests,"root_file_remains_app_readable",new AgentTools(context,PrivilegeManager.Mode.NORMAL,cwd).execute("read_file",new JSONObject().put("path","root-created.txt")).getString("content").equals("root created, app readable"));
            PrivilegeManager.allowForCurrentTask(PrivilegeManager.Mode.ROOT);check(tests,"one_time_root_grant",manager.run(PrivilegeManager.Mode.ROOT,"id -u",cwd,5,stop).getInt("uid")==0);manager.select(PrivilegeManager.Mode.NORMAL);
            boolean revoked=false;try{manager.run(PrivilegeManager.Mode.ROOT,"id -u",cwd,5,stop);}catch(Exception expected){revoked=true;}PrivilegeManager.clearTaskGrant();check(tests,"one_time_grant_revoked",revoked);
            AgentTools elevated=new AgentTools(context,PrivilegeManager.Mode.ROOT,cwd);JSONObject approved=new JSONObject().put("command","id -u").put("timeout",5);
            PrivilegeManager.allowForNextOperation(PrivilegeManager.Mode.ROOT,"run_shell",approved);
            boolean directDenied=false;try{manager.run(PrivilegeManager.Mode.ROOT,"id -u",cwd,5,stop);}catch(Exception expected){directDenied=true;}check(tests,"operation_grant_requires_tool_entry",directDenied&&PrivilegeManager.hasPendingOperationGrant());
            JSONObject reordered=new JSONObject().put("timeout",5.0).put("command","id -u");JSONObject once=elevated.execute("run_shell",reordered);
            check(tests,"operation_grant_exact_canonical_parameters",once.optInt("uid")==0&&once.optString("stdout").trim().equals("0"));
            check(tests,"operation_grant_consumed_after_success",!PrivilegeManager.hasPendingOperationGrant()&&manager.effectiveMode()==PrivilegeManager.Mode.NORMAL&&manager.getMode()==PrivilegeManager.Mode.NORMAL);
            boolean repeatedDenied=false;try{elevated.execute("run_shell",approved);}catch(Exception expected){repeatedDenied=true;}check(tests,"operation_grant_cannot_repeat",repeatedDenied);
            PrivilegeManager.allowForNextOperation(PrivilegeManager.Mode.ROOT,"run_shell",approved);boolean differentArgsDenied=false;try{elevated.execute("run_shell",new JSONObject().put("command","printf unapproved").put("timeout",5));}catch(Exception expected){differentArgsDenied=true;}check(tests,"operation_grant_rejects_changed_parameters",differentArgsDenied&&!PrivilegeManager.hasPendingOperationGrant());
            PrivilegeManager.allowForNextOperation(PrivilegeManager.Mode.ROOT,"run_shell",approved);boolean differentToolDenied=false;try{elevated.execute("read_file",new JSONObject().put("path","root-created.txt"));}catch(Exception expected){differentToolDenied=true;}check(tests,"operation_grant_rejects_changed_tool",differentToolDenied&&!PrivilegeManager.hasPendingOperationGrant());
            JSONObject missing=new JSONObject().put("path","missing-one-operation-file");PrivilegeManager.allowForNextOperation(PrivilegeManager.Mode.ROOT,"read_file",missing);boolean failedOperation=false;try{failedOperation=elevated.execute("read_file",missing).has("error");}catch(Exception expected){failedOperation=true;}check(tests,"operation_grant_consumed_after_failure",failedOperation&&!PrivilegeManager.hasPendingOperationGrant());
            PrivilegeManager.allowForNextOperation(PrivilegeManager.Mode.ROOT,"run_shell",approved);boolean cancelledBeforeExecution=false;try{elevated.execute("run_shell",approved,new AtomicBoolean(true));}catch(Exception expected){cancelledBeforeExecution=true;}check(tests,"operation_grant_consumed_after_cancellation",cancelledBeforeExecution&&!PrivilegeManager.hasPendingOperationGrant());
            PrivilegeManager.allowForNextOperation(PrivilegeManager.Mode.ROOT,"run_shell",approved);manager.select(PrivilegeManager.Mode.NORMAL);boolean selectedRevoked=false;try{elevated.execute("run_shell",approved);}catch(Exception expected){selectedRevoked=true;}check(tests,"operation_grant_revoked_by_reselection",selectedRevoked&&!PrivilegeManager.hasPendingOperationGrant());
            tests.put("closed_terminal_pids",new org.json.JSONArray().put(term.getInt("pid")).put(adbTerminal.getInt("pid")).put(rootTerminal.getInt("pid")));success=true;
        }catch(Exception error){try{tests.put("error",error.getMessage()==null?error.getClass().getSimpleName():error.getMessage());}catch(Exception ignored){}}
        finally{
            PrivilegeManager.clearTaskGrant();if(manager!=null){manager.closeOwner(owner);if(original!=null)try{manager.select(original);}catch(Exception ignored){}}
            if(directory!=null){File[] children=directory.listFiles();if(children!=null)for(File child:children)child.delete();directory.delete();}
            try{tests.put("success",success);}catch(Exception ignored){}
        }
        return tests;
    }
}
