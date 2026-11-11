package com.pocketagent;

import org.json.JSONObject;
import java.util.concurrent.atomic.AtomicBoolean;

/** Short-lived Root worker. All payloads travel over owned pipes, never command arguments. */
public final class PrivilegedJob {
    public static void main(String[] arguments){
        try{
            if(android.os.Process.myUid()!=0)throw new Exception("Root worker requires UID 0");
            JSONObject operation=PrivilegedOperations.readFrame(System.in);AtomicBoolean cancelled=new AtomicBoolean(false);
            Thread monitor=new Thread(()->{try{System.in.read();}catch(Exception ignored){}cancelled.set(true);},"AsterHand-root-cancel");monitor.setDaemon(true);monitor.start();
            JSONObject result;
            try{result=PrivilegedOperations.execute(PrivilegeManager.Mode.ROOT,operation,cancelled);}
            catch(Exception error){result=new JSONObject().put("uid",android.os.Process.myUid()).put("mode","ROOT").put("error",PrivilegeManager.safeError(error));}
            PrivilegedOperations.writeFrame(System.out,result);
        }catch(Exception error){System.err.println("AsterHand Root worker failed: "+error.getClass().getSimpleName());System.exit(1);}
    }
}
