package com.pocketagent;

import java.net.ServerSocket;
import java.net.Socket;
import java.net.InetAddress;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.AtomicBoolean;

/** Shell-owned loopback-only bridge, with mutual challenge and per-request HMAC authentication. */
public final class AdbBridgeServer {
    public static void main(String[] arguments){
        try{
            if(android.os.Process.myUid()!=2000)throw new Exception("ADB bridge must run as UID 2000; Root is not accepted");
            JSONObject config=PrivilegedOperations.readFrame(System.in);
            int applicationUid=config.getInt("uid");String name=config.getString("socket"),token=config.getString("token");
            if(applicationUid<10000||token.length()<40||!name.matches("asterhand\\.adb\\.[0-9]+\\.[a-f0-9]{24}"))throw new Exception("Invalid bridge configuration");
            int port=config.getInt("port");if(port<1024||port>65535)throw new Exception("Invalid loopback port");
            ServerSocket server=new ServerSocket(port,4,InetAddress.getByName("127.0.0.1"));Semaphore jobs=new Semaphore(4);
            File installedApk=new File(config.getString("apk"));
            Thread lifetime=new Thread(()->{while(true){android.os.SystemClock.sleep(5000);if(!installedApk.isFile()){TerminalSessions.closeAll();try{server.close();}catch(Exception ignored){}System.exit(0);return;}}},"AsterHand-ADB-package-lifetime");lifetime.setDaemon(true);lifetime.start();
            System.out.println("ASTERHAND_ADB_READY uid=2000");System.out.flush();
            while(true){
                Socket peer=server.accept();
                if(!peer.getInetAddress().isLoopbackAddress()||!jobs.tryAcquire()){peer.close();continue;}
                Thread worker=new Thread(()->{try{handle(peer,token);}finally{jobs.release();}},"AsterHand-ADB-job");worker.setDaemon(true);worker.start();
            }
        }catch(Exception error){System.err.println("AsterHand ADB bridge: "+error.getClass().getSimpleName());System.exit(1);}
    }
    private static void handle(Socket peer,String token){
        AtomicBoolean cancelled=new AtomicBoolean(false);
        try{
            BridgeTransport.Server channel=BridgeTransport.accept(peer,token);JSONObject operation=channel.operation;
            if(operation.optString("kind").equals("shutdown")){
                TerminalSessions.closeAll();channel.reply(new JSONObject().put("uid",2000).put("stopped",true));peer.close();System.exit(0);return;
            }
            Thread monitor=new Thread(()->{try{peer.getInputStream().read();}catch(Exception ignored){}cancelled.set(true);},"AsterHand-ADB-cancel");monitor.setDaemon(true);monitor.start();
            JSONObject result;
            try{result=PrivilegedOperations.execute(PrivilegeManager.Mode.ADB,operation,cancelled);}
            catch(Exception error){result=new JSONObject().put("uid",android.os.Process.myUid()).put("mode","ADB").put("error",PrivilegeManager.safeError(error));}
            channel.reply(result);
        }catch(Exception ignored){}
        finally{cancelled.set(true);try{peer.close();}catch(Exception ignored){}}
    }
}
