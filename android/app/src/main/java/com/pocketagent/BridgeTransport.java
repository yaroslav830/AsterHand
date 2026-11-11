package com.pocketagent;

import android.util.Base64;
import org.json.JSONObject;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/** Mutual challenge authentication for the loopback-only ADB channel. */
final class BridgeTransport {
    static final int HELLO_LIMIT=8192,REQUEST_LIMIT=1024*1024,RESPONSE_LIMIT=10*1024*1024;
    static int unusedPort()throws IOException{try(ServerSocket socket=new ServerSocket(0,1,InetAddress.getByName("127.0.0.1"))){return socket.getLocalPort();}}
    private static String nonce(){byte[] bytes=new byte[32];new SecureRandom().nextBytes(bytes);return Base64.encodeToString(bytes,Base64.URL_SAFE|Base64.NO_WRAP|Base64.NO_PADDING);}
    private static boolean validNonce(String value){return value!=null&&value.matches("[A-Za-z0-9_-]{43}");}
    private static String mac(String secret,String role,String client,String server,String payload)throws Exception{
        Mac hmac=Mac.getInstance("HmacSHA256");hmac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8),"HmacSHA256"));
        byte[] bytes=hmac.doFinal(("AsterHand ADB v2\n"+role+"\n"+client+"\n"+server+"\n"+payload).getBytes(StandardCharsets.UTF_8));return Base64.encodeToString(bytes,Base64.NO_WRAP);
    }
    private static boolean matches(String expected,String received){return MessageDigest.isEqual(expected.getBytes(StandardCharsets.UTF_8),received.getBytes(StandardCharsets.UTF_8));}
    static JSONObject read(InputStream input,int maximum)throws Exception{
        DataInputStream data=new DataInputStream(input);int length=data.readInt();if(length<2||length>maximum)throw new IOException("Invalid authenticated frame size");byte[] bytes=new byte[length];data.readFully(bytes);return new JSONObject(new String(bytes,StandardCharsets.UTF_8));
    }
    static void write(OutputStream output,JSONObject value,int maximum)throws Exception{
        byte[] bytes=value.toString().getBytes(StandardCharsets.UTF_8);if(bytes.length>maximum)throw new IOException("Authenticated frame exceeds size limit");DataOutputStream data=new DataOutputStream(output);data.writeInt(bytes.length);data.write(bytes);data.flush();
    }
    static Client connect(JSONObject config)throws Exception{
        int port=config.getInt("port");if(port<1024||port>65535)throw new IOException("Invalid bridge port");Socket socket=new Socket();
        try{
            socket.connect(new InetSocketAddress(InetAddress.getByName("127.0.0.1"),port),2500);socket.setSoTimeout(3500);socket.setTcpNoDelay(true);
            String client=nonce();write(socket.getOutputStream(),new JSONObject().put("version",2).put("nonce",client),HELLO_LIMIT);JSONObject answer=read(socket.getInputStream(),HELLO_LIMIT);String server=answer.optString("nonce");
            if(answer.optInt("version")!=2||answer.optInt("uid",-1)!=2000||!validNonce(server)||!matches(mac(config.getString("token"),"server",client,server,"2000"),answer.optString("mac")))throw new SecurityException("ADB 通道身份校验失败。");
            socket.setSoTimeout(135000);return new Client(socket,config.getString("token"),client,server);
        }catch(Exception failure){try{socket.close();}catch(Exception ignored){}throw failure;}
    }
    static Server accept(Socket socket,String secret)throws Exception{
        if(!socket.getInetAddress().isLoopbackAddress())throw new SecurityException("Loopback clients only");socket.setSoTimeout(3500);socket.setTcpNoDelay(true);
        JSONObject hello=read(socket.getInputStream(),HELLO_LIMIT);String client=hello.optString("nonce");if(hello.optInt("version")!=2||!validNonce(client))throw new SecurityException("Invalid client challenge");String server=nonce();
        write(socket.getOutputStream(),new JSONObject().put("version",2).put("uid",2000).put("nonce",server).put("mac",mac(secret,"server",client,server,"2000")),HELLO_LIMIT);
        JSONObject envelope=read(socket.getInputStream(),REQUEST_LIMIT);String payload=envelope.optString("payload");if(!matches(mac(secret,"request",client,server,payload),envelope.optString("mac")))throw new SecurityException("Invalid request authentication");
        byte[] bytes=Base64.decode(payload,Base64.NO_WRAP);if(bytes.length>REQUEST_LIMIT)throw new IOException("Request payload too large");JSONObject operation=new JSONObject(new String(bytes,StandardCharsets.UTF_8));socket.setSoTimeout(135000);return new Server(socket,secret,client,server,operation);
    }
    static final class Client implements Closeable {
        final Socket socket;private final String secret,client,server;
        Client(Socket socket,String secret,String client,String server){this.socket=socket;this.secret=secret;this.client=client;this.server=server;}
        void send(JSONObject operation)throws Exception{String payload=Base64.encodeToString(operation.toString().getBytes(StandardCharsets.UTF_8),Base64.NO_WRAP);write(socket.getOutputStream(),new JSONObject().put("payload",payload).put("mac",mac(secret,"request",client,server,payload)),REQUEST_LIMIT);}
        JSONObject readResult()throws Exception{JSONObject envelope=read(socket.getInputStream(),RESPONSE_LIMIT);String payload=envelope.optString("payload");if(!matches(mac(secret,"response",client,server,payload),envelope.optString("mac")))throw new SecurityException("ADB 响应身份校验失败。");byte[] bytes=Base64.decode(payload,Base64.NO_WRAP);if(bytes.length>RESPONSE_LIMIT)throw new IOException("Response payload too large");return new JSONObject(new String(bytes,StandardCharsets.UTF_8));}
        void cancel(){try{socket.shutdownOutput();}catch(Exception ignored){}}
        public void close()throws IOException{socket.close();}
    }
    static final class Server {
        final Socket socket;final JSONObject operation;private final String secret,client,server;
        Server(Socket socket,String secret,String client,String server,JSONObject operation){this.socket=socket;this.secret=secret;this.client=client;this.server=server;this.operation=operation;}
        void reply(JSONObject result)throws Exception{String payload=Base64.encodeToString(result.toString().getBytes(StandardCharsets.UTF_8),Base64.NO_WRAP);write(socket.getOutputStream(),new JSONObject().put("payload",payload).put("mac",mac(secret,"response",client,server,payload)),RESPONSE_LIMIT);}
    }
}
