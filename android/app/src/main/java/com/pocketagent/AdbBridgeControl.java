package com.pocketagent;

import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import org.json.JSONObject;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;

/** Computer-side updater uses run-as to stop only this application's authenticated bridge. */
public final class AdbBridgeControl {
    public static void main(String[] arguments){
        try{
            if(arguments.length!=1||!arguments[0].equals("stop")||android.os.Process.myUid()<10000)throw new Exception("Application UID and stop action required");
            JSONObject config=new JSONObject(new String(PrivilegedOperations.readLimited(new FileInputStream("files/adb-bridge.json"),16384),StandardCharsets.UTF_8));
            if(config.getInt("uid")!=android.os.Process.myUid())throw new Exception("Application identity mismatch");
            try(BridgeTransport.Client channel=BridgeTransport.connect(config)){
                channel.socket.setSoTimeout(5000);channel.send(new JSONObject().put("kind","shutdown"));JSONObject response=channel.readResult();
                if(response.optInt("uid")!=2000||!response.optBoolean("stopped"))throw new Exception("Bridge did not acknowledge stop");System.out.println("ASTERHAND_ADB_STOPPED");
            }catch(java.net.ConnectException absent){System.out.println("ASTERHAND_ADB_NOT_RUNNING");}

        }catch(Exception error){System.err.println("ADB bridge stop failed: "+error.getClass().getSimpleName());System.exit(1);}
    }
}
