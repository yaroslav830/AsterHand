package com.pocketagent;

import org.json.JSONObject;
import java.io.*;

/** Invoked by the authorized computer, with bootstrap configuration on stdin only. */
public final class AdbBridgeBootstrap {
    public static void main(String[] arguments){
        try{
            if(android.os.Process.myUid()!=2000)throw new Exception("ADB bootstrap requires UID 2000");
            JSONObject config=PrivilegedOperations.readFrame(System.in);
            String apk=config.getString("apk");if(!apk.startsWith("/data/app/")||!apk.endsWith(".apk"))throw new Exception("Unexpected installed APK path");
            ProcessBuilder builder=new ProcessBuilder("/system/bin/setsid","/system/bin/app_process","/system/bin","com.pocketagent.AdbBridgeServer");
            builder.environment().put("CLASSPATH",apk);builder.redirectError(new File("/dev/null"));
            java.lang.Process child=builder.start();PrivilegedOperations.writeFrame(child.getOutputStream(),config);child.getOutputStream().close();
            BufferedReader reader=new BufferedReader(new InputStreamReader(child.getInputStream(),"UTF-8"));
            String ready=reader.readLine();if(!"ASTERHAND_ADB_READY uid=2000".equals(ready))throw new Exception("Bridge did not start");
            System.out.println(ready);System.out.flush();reader.close();
        }catch(Exception error){System.err.println("ADB bootstrap failed: "+error.getClass().getSimpleName());System.exit(1);}
    }
}
