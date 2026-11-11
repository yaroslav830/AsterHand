package com.pocketagent;

import org.json.JSONObject;
import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.interfaces.*;
import java.security.spec.*;
import java.util.Arrays;
import javax.crypto.*;
import javax.crypto.spec.*;

/** Exact AgentGo/AsterHand v1 wire codec; no Android API dependencies. */
final class RemoteControlWire {
    static final int LIMIT=2*1024*1024;
    private static final SecureRandom RANDOM=new SecureRandom();
    static String hex(byte[] bytes){StringBuilder s=new StringBuilder();for(byte b:bytes)s.append(String.format(java.util.Locale.ROOT,"%02x",b&255));return s.toString();}
    static byte[] hash(byte[] bytes)throws Exception{return MessageDigest.getInstance("SHA-256").digest(bytes);}
    static byte[] join(byte[]... pieces){int n=0;for(byte[] p:pieces)n+=p.length;byte[] out=new byte[n];int at=0;for(byte[] p:pieces){System.arraycopy(p,0,out,at,p.length);at+=p.length;}return out;}
    static String b64(byte[] data){final char[] chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".toCharArray();StringBuilder out=new StringBuilder((data.length+2)/3*4);for(int i=0;i<data.length;i+=3){int a=data[i]&255,b=i+1<data.length?data[i+1]&255:0,c=i+2<data.length?data[i+2]&255:0;out.append(chars[a>>2]).append(chars[((a&3)<<4)|(b>>4)]).append(i+1<data.length?chars[((b&15)<<2)|(c>>6)]:'=').append(i+2<data.length?chars[c&63]:'=');}return out.toString();}
    static byte[] unb64(String value)throws Exception{if(value==null||value.length()%4!=0||!value.matches("[A-Za-z0-9+/]*={0,2}"))throw new Exception("Invalid base64");java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();int bits=0,count=0;for(int i=0;i<value.length();i++){char c=value.charAt(i);if(c=='=')break;int n="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".indexOf(c);if(n<0)throw new Exception("Invalid base64");bits=(bits<<6)|n;count+=6;if(count>=8){count-=8;out.write((bits>>count)&255);}}byte[] result=out.toByteArray();if(!b64(result).equals(value))throw new Exception("Noncanonical base64");return result;}
    private static byte[] unhex(String text)throws Exception{if(text==null||!text.matches("[a-f0-9]{64}"))throw new Exception("Invalid pairing key");byte[] data=new byte[32];for(int i=0;i<data.length;i++)data[i]=(byte)Integer.parseInt(text.substring(i*2,i*2+2),16);return data;}
    private static byte[] hmac(byte[] key,byte[] bytes)throws Exception{Mac m=Mac.getInstance("HmacSHA256");m.init(new SecretKeySpec(key,"HmacSHA256"));return m.doFinal(bytes);}
    private static byte[] key(String secret,String purpose)throws Exception{return hmac(unhex(secret),("AgentGo/v1/"+purpose).getBytes(StandardCharsets.UTF_8));}
    static JSONObject seal(String pair,String secret,JSONObject payload,String direction)throws Exception{
        byte[] iv=new byte[16];RANDOM.nextBytes(iv);Cipher c=Cipher.getInstance("AES/CBC/PKCS5Padding");c.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key(secret,"encryption/"+direction),"AES"),new IvParameterSpec(iv));String data=b64(c.doFinal(payload.toString().getBytes(StandardCharsets.UTF_8))),encodedIV=b64(iv);
        return new JSONObject().put("v",1).put("pair",pair).put("iv",encodedIV).put("data",data).put("mac",b64(hmac(key(secret,"authentication/"+direction),("v1\n"+direction+"\n"+pair+"\n"+encodedIV+"\n"+data).getBytes(StandardCharsets.UTF_8))));
    }
    static JSONObject open(JSONObject packet,String secret,String direction)throws Exception{
        String pair=packet.optString("pair"),data=packet.optString("data"),iv=packet.optString("iv");if(!(packet.opt("v") instanceof Number)||packet.optInt("v")!=1||!(packet.opt("data") instanceof String)||!pair.matches("[a-f0-9-]{36}")||data.length()>LIMIT)throw new Exception("Invalid encrypted packet");byte[] rawIV=unb64(iv),mac=unb64(packet.optString("mac"));if(rawIV.length!=16||mac.length!=32)throw new Exception("Invalid encrypted packet");byte[] expected=hmac(key(secret,"authentication/"+direction),("v1\n"+direction+"\n"+pair+"\n"+iv+"\n"+data).getBytes(StandardCharsets.UTF_8));if(!MessageDigest.isEqual(mac,expected))throw new Exception("Pairing authentication failed");
        Cipher cipher=Cipher.getInstance("AES/CBC/PKCS5Padding");cipher.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key(secret,"encryption/"+direction),"AES"),new IvParameterSpec(rawIV));JSONObject payload=new JSONObject(new String(cipher.doFinal(unb64(data)),StandardCharsets.UTF_8));double ts=payload.optDouble("ts",Double.NaN);String id=payload.optString("id");if(!(payload.opt("id") instanceof String)||!(payload.opt("ts") instanceof Number)||id.isEmpty()||id.length()>80||Double.isInfinite(ts)||Double.isNaN(ts)||Math.abs(System.currentTimeMillis()/1000d-ts)>90)throw new Exception("Expired packet");return payload;
    }
    private static ECParameterSpec parameters()throws Exception{AlgorithmParameters p=AlgorithmParameters.getInstance("EC");p.init(new ECGenParameterSpec("secp256r1"));return p.getParameterSpec(ECParameterSpec.class);}
    private static byte[] fixed(BigInteger value){byte[] src=value.toByteArray(),out=new byte[32];System.arraycopy(src,Math.max(0,src.length-32),out,Math.max(0,32-src.length),Math.min(src.length,32));return out;}
    static JSONObject newIdentity()throws Exception{KeyPairGenerator g=KeyPairGenerator.getInstance("EC");g.initialize(new ECGenParameterSpec("secp256r1"),RANDOM);KeyPair p=g.generateKeyPair();ECPrivateKey priv=(ECPrivateKey)p.getPrivate();ECPoint point=((ECPublicKey)p.getPublic()).getW();return new JSONObject().put("private_key",b64(fixed(priv.getS()))).put("public_key",b64(join(new byte[]{4},fixed(point.getAffineX()),fixed(point.getAffineY()))));}
    static String deviceID(String publicKey)throws Exception{byte[] p=unb64(publicKey);if(p.length!=65||p[0]!=4)throw new Exception("Invalid device identity");return hex(hash(p));}
    static String pairingSecret(JSONObject ownIdentity,JSONObject remote,String request)throws Exception{
        if(!request.matches("[a-f0-9-]{36}"))throw new Exception("Invalid pairing request");String pub=remote.optString("public_key");if(!deviceID(pub).equals(remote.optString("device_id")))throw new Exception("Device identity mismatch");byte[] point=unb64(pub),privateKey=unb64(ownIdentity.getString("private_key"));if(privateKey.length!=32)throw new Exception("Invalid device identity");ECParameterSpec params=parameters();KeyFactory f=KeyFactory.getInstance("EC");PublicKey key=f.generatePublic(new ECPublicKeySpec(new ECPoint(new BigInteger(1,Arrays.copyOfRange(point,1,33)),new BigInteger(1,Arrays.copyOfRange(point,33,65))),params));PrivateKey secret=f.generatePrivate(new ECPrivateKeySpec(new BigInteger(1,privateKey),params));KeyAgreement ecdh=KeyAgreement.getInstance("ECDH");ecdh.init(secret);ecdh.doPhase(key,true);return hex(hash(join("AgentGo/pairing/v2\0".getBytes(StandardCharsets.UTF_8),ecdh.generateSecret(),request.getBytes(StandardCharsets.UTF_8))));
    }
    static String code(String secret){return String.format(java.util.Locale.ROOT,"%06d",Long.parseLong(secret.substring(0,8),16)%1000000);}
    static byte[] sealFrame(String secret,String nonce,int sequence,byte[] jpeg,int width,int height,int source)throws Exception{
        String direction="stream/"+nonce;ByteBuffer header=ByteBuffer.allocate(16).putInt(sequence).putInt(width).putInt(height).putInt(source);byte[] iv=new byte[16];RANDOM.nextBytes(iv);Cipher c=Cipher.getInstance("AES/CBC/PKCS5Padding");c.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key(secret,"encryption/"+direction),"AES"),new IvParameterSpec(iv));byte[] body=join(iv,c.doFinal(join(header.array(),jpeg)));return join(body,hmac(key(secret,"authentication/"+direction),body));
    }
    static byte[] openFrame(String secret,String nonce,byte[] frame)throws Exception{if(frame.length<80||frame.length>LIMIT)throw new Exception("Invalid video frame");String direction="stream/"+nonce;byte[] body=Arrays.copyOf(frame,frame.length-32),mac=Arrays.copyOfRange(frame,frame.length-32,frame.length);if(!MessageDigest.isEqual(mac,hmac(key(secret,"authentication/"+direction),body)))throw new Exception("Video authentication failed");Cipher c=Cipher.getInstance("AES/CBC/PKCS5Padding");c.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key(secret,"encryption/"+direction),"AES"),new IvParameterSpec(Arrays.copyOf(body,16)));byte[] plain=c.doFinal(Arrays.copyOfRange(body,16,body.length));if(plain.length<18)throw new Exception("Invalid video frame");return plain;}
}
