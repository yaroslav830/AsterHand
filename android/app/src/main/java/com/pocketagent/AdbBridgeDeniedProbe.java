package com.pocketagent;

import java.net.*;
import org.json.JSONObject;
import android.util.Base64;
import java.nio.charset.StandardCharsets;

/** Negative QA: a local client without the application secret must not execute a request. */
public final class AdbBridgeDeniedProbe {
    public static void main(String[] arguments){
        try(Socket socket=new Socket()){
            if(android.os.Process.myUid()!=2000||arguments.length!=1)throw new Exception("Unexpected test identity");int port=Integer.parseInt(arguments[0]);if(port<1024||port>65535)throw new Exception("Invalid test port");
            socket.connect(new InetSocketAddress("127.0.0.1",port),2500);socket.setSoTimeout(3500);
            BridgeTransport.write(socket.getOutputStream(),new JSONObject().put("version",2).put("nonce","AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),BridgeTransport.HELLO_LIMIT);
            JSONObject challenge=BridgeTransport.read(socket.getInputStream(),BridgeTransport.HELLO_LIMIT);if(challenge.optInt("uid")!=2000)throw new Exception("Unexpected bridge identity");
            String payload=Base64.encodeToString("{\"kind\":\"probe\"}".getBytes(StandardCharsets.UTF_8),Base64.NO_WRAP);
            BridgeTransport.write(socket.getOutputStream(),new JSONObject().put("payload",payload).put("mac","AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="),BridgeTransport.REQUEST_LIMIT);
            if(socket.getInputStream().read()!=-1)throw new Exception("Unauthenticated request was not refused");System.out.println("ASTERHAND_UNAUTHENTICATED_CLIENT_REJECTED");
        }catch(Exception failure){System.err.println("ADB authentication QA failed: "+failure.getClass().getSimpleName());System.exit(1);}
    }
}
