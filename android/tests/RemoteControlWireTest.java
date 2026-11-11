package com.pocketagent;
import java.io.*;
import java.nio.charset.StandardCharsets;
import org.json.*;
/** CLI fixture adapter for cross-runtime protocol tests; never included in the APK. */
public final class RemoteControlWireTest {
    public static void main(String[] args)throws Exception{
        String line;BufferedReader r=new BufferedReader(new InputStreamReader(System.in,StandardCharsets.UTF_8));while((line=r.readLine())!=null){JSONObject out=new JSONObject();try{JSONObject a=new JSONObject(line);String op=a.getString("op");if(op.equals("identity"))out.put("result",RemoteControlWire.newIdentity());else if(op.equals("secret"))out.put("result",RemoteControlWire.pairingSecret(a.getJSONObject("identity"),a.getJSONObject("remote"),a.getString("id")));else if(op.equals("open"))out.put("result",RemoteControlWire.open(a.getJSONObject("packet"),a.getString("key"),a.getString("direction")));else if(op.equals("seal"))out.put("result",RemoteControlWire.seal(a.getString("id"),a.getString("key"),a.getJSONObject("payload"),a.getString("direction")));else if(op.equals("frame"))out.put("result",RemoteControlWire.b64(RemoteControlWire.sealFrame(a.getString("key"),a.getString("nonce"),3,new byte[]{(byte)255,(byte)216,(byte)255,(byte)217},393,852,7)));else if(op.equals("openFrame"))out.put("result",RemoteControlWire.b64(RemoteControlWire.openFrame(a.getString("key"),a.getString("nonce"),RemoteControlWire.unb64(a.getString("packet")))));else if(op.equals("base64"))out.put("result",RemoteControlWire.b64(RemoteControlWire.unb64(a.getString("value"))));else throw new Exception("Unknown fixture");}catch(Exception e){out.put("error",e.getClass().getSimpleName());}System.out.println(out);}
    }
}
