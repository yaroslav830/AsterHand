package com.pocketagent;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.util.Base64;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.math.BigInteger;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.URI;
import java.net.URL;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.AlgorithmParameters;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.ECParameterSpec;
import java.security.spec.ECPoint;
import java.security.spec.ECPublicKeySpec;
import java.security.spec.RSAPublicKeySpec;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class ChatGPTAuth {
    interface Done { void result(String message, Exception error); }
    private static final String AUTH="https://auth.openai.com";
    private static final ExecutorService EXEC=Executors.newSingleThreadExecutor();
    private static final Object AUTH_LOCK=new Object();
    private static volatile ServerSocket activeServer;
    private static volatile java.util.concurrent.atomic.AtomicBoolean activeCancel;
    static boolean signingIn(){return activeServer!=null;}
    static void cancelSignIn(){synchronized(AUTH_LOCK){if(activeCancel!=null)activeCancel.set(true);if(activeServer!=null)try{activeServer.close();}catch(Exception ignored){}}}
    static void signIn(Activity activity,Vault vault,Done done){signIn(activity,vault,false,done);}
    static void signIn(Activity activity,Vault vault,boolean chooseAnotherAccount,Done done){
        java.util.concurrent.atomic.AtomicBoolean cancelled=new java.util.concurrent.atomic.AtomicBoolean(false);
        java.util.concurrent.atomic.AtomicReference<Exception> browserError=new java.util.concurrent.atomic.AtomicReference<>();
        synchronized(AUTH_LOCK){if(activeCancel!=null){done.result(null,new Exception("已有登录正在进行，请完成或取消后再试。"));return;}activeCancel=cancelled;}
        new Thread(()->{ServerSocket listener=null;try{
            listener=new ServerSocket(0,4,InetAddress.getByName("127.0.0.1"));listener.setSoTimeout(1000);synchronized(AUTH_LOCK){if(cancelled.get())throw new Exception("已取消登录。");activeServer=listener;}
            int port=listener.getLocalPort();String redirect="http://127.0.0.1:"+port+"/auth/callback";
            String state=random(),nonce=random(),verifier=random()+random();String challenge=enc(MessageDigest.getInstance("SHA-256").digest(verifier.getBytes(StandardCharsets.UTF_8)));
            String client=chooseAnotherAccount?"":vault.get("oauth.client_id");boolean first=client.isEmpty();if(first)client="dynamic_agent_client";
            String host=vault.get("oauth.host_id");if(host.isEmpty()){host="urn:uuid:"+java.util.UUID.randomUUID().toString();vault.put("oauth.host_id",host);}
            Map<String,String> q=new LinkedHashMap<>();q.put("client_id",client);q.put("response_type","code");q.put("redirect_uri",redirect);q.put("scope","openid profile email offline_access resource.invoke chatgpt.tokens.use.direct");q.put("resource","https://api.openai.com/v1");q.put("state",state);q.put("nonce",nonce);q.put("code_challenge_method","S256");q.put("code_challenge",challenge);q.put("ext_agent_host_id",host);
            if(first)q.put("agent_name_hint","AsterHand");else {if(!vault.get("oauth.id_token").isEmpty())q.put("id_token_hint",vault.get("oauth.id_token"));if(!vault.get("oauth.email").isEmpty())q.put("login_hint",vault.get("oauth.email"));}
            StringBuilder uri=new StringBuilder(AUTH+"/api/accounts/authorize?");for(Map.Entry<String,String> e:q.entrySet()){if(uri.charAt(uri.length()-1)!='?')uri.append('&');uri.append(encode(e.getKey())).append('=').append(encode(e.getValue()));}
            ServerSocket server=listener;activity.runOnUiThread(()->{try{activity.startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(uri.toString())));}catch(Exception e){browserError.set(new Exception("手机没有可用的浏览器，或浏览器无法打开。请启用浏览器后重试。"));cancelled.set(true);try{server.close();}catch(Exception ignored){}}});
            String callback=accept(server,state,port,cancelled);Map<String,String> values=query(callback);
            if(values.containsKey("error"))throw new Exception("OpenAI 未完成授权："+safeCode(values.get("error")));
            String code=values.get("code");if(code==null||code.isEmpty())throw new Exception("OAuth 回调缺少授权码。");String issued=values.get("client_id");
            if(first){if(issued==null||issued.isEmpty()||issued.equals("dynamic_agent_client"))throw new Exception("OpenAI 没有返回已注册的应用 client_id。");client=issued;}else if(issued!=null&&!issued.equals(client))throw new Exception("OAuth 回调 client_id 不匹配。");
            Map<String,String> form=new LinkedHashMap<>();form.put("grant_type","authorization_code");form.put("client_id",client);form.put("code",code);form.put("code_verifier",verifier);form.put("redirect_uri",redirect);form.put("resource","https://api.openai.com/v1");JSONObject token=postForm(AUTH+"/api/accounts/oauth/token",form);
            JSONObject claims=verify(token.optString("id_token"),client,nonce);String scope=token.optString("scope",values.containsKey("scope")?values.get("scope"):"");
            if(!hasScope(scope))throw new Exception("已登录，但没有授予 ChatGPT 套餐使用权限；请重新开始并在 OpenAI 页面确认该权限。");
            if(token.optString("access_token").isEmpty()||token.optString("refresh_token").isEmpty()||token.optLong("expires_in")<=0)throw new Exception("授权服务没有返回完整的登录凭据。");
            JSONObject old=vault.get("oauth.credentials").isEmpty()?new JSONObject():new JSONObject(vault.get("oauth.credentials"));if(!chooseAnotherAccount&&old.optString("client_id").equals(client)&&!old.optString("sub").isEmpty()&&!old.optString("sub").equals(claims.optString("sub")))throw new Exception("返回的账户与原账户不同，已保留原登录。请使用重新选择账户。");
            JSONObject saved=new JSONObject().put("client_id",client).put("ext_agent_host_id",host).put("access_token",token.getString("access_token")).put("refresh_token",token.getString("refresh_token")).put("id_token",token.getString("id_token")).put("scope",scope).put("email",claims.optString("email")).put("sub",claims.optString("sub")).put("expires_at",System.currentTimeMillis()/1000+token.optLong("expires_in"));
            synchronized(AUTH_LOCK){if(cancelled.get())throw new Exception("登录已取消，未保存新凭据。");vault.put("oauth.credentials",saved.toString());vault.put("oauth.client_id",client);vault.put("oauth.id_token",token.getString("id_token"));vault.put("oauth.email",claims.optString("email"));}
            done.result(claims.optString("email","ChatGPT 账户"),null);
            activity.runOnUiThread(()->{try{Intent back=new Intent(activity,MainActivity.class);back.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT|Intent.FLAG_ACTIVITY_SINGLE_TOP);activity.startActivity(back);}catch(Exception ignored){}});
        }catch(Exception e){done.result(null,browserError.get()!=null?browserError.get():cancelled.get()?new Exception("已取消 ChatGPT 登录。"):e);}finally{
            if(listener!=null)try{listener.close();}catch(Exception ignored){}synchronized(AUTH_LOCK){if(activeCancel==cancelled){activeCancel=null;activeServer=null;}}
        }},"AsterHand-phone-oauth").start();
    }
    private static boolean hasScope(String scope){return java.util.Arrays.asList(scope.trim().split("\\s+")).contains("chatgpt.tokens.use.direct");}
    private static String safeCode(String value){return value!=null&&value.matches("[A-Za-z0-9_-]{1,80}")?value:"授权失败";}
    static synchronized String accessToken(Vault vault)throws Exception{
        String raw=vault.get("oauth.credentials");if(raw.isEmpty())throw new Exception("请先在手机登录 ChatGPT 并授权套餐用量。");JSONObject c=new JSONObject(raw);if(!hasScope(c.optString("scope")))throw new Exception("当前登录未授权 ChatGPT 套餐用量。");
        if(c.optLong("expires_at")>System.currentTimeMillis()/1000+180&&!c.optString("access_token").isEmpty())return c.getString("access_token");
        if(c.optString("refresh_token").isEmpty())throw new Exception("ChatGPT 登录已过期，请重新登录。");
        Map<String,String> form=new LinkedHashMap<>();form.put("grant_type","refresh_token");form.put("client_id",c.getString("client_id"));form.put("refresh_token",c.getString("refresh_token"));form.put("resource","https://api.openai.com/v1");JSONObject fresh=postForm(AUTH+"/api/accounts/oauth/token",form);
        if(fresh.optString("access_token").isEmpty()||fresh.optLong("expires_in")<=0)throw new Exception("ChatGPT 刷新未返回有效凭据。");
        if(fresh.has("scope")&&!hasScope(fresh.optString("scope")))throw new Exception("ChatGPT 刷新未保留套餐授权，请重新登录。");
        if(!fresh.optString("id_token").isEmpty()){
            JSONObject claims=verify(fresh.getString("id_token"),c.getString("client_id"),null);
            if(!c.optString("sub").isEmpty()&&!c.optString("sub").equals(claims.optString("sub")))throw new Exception("ChatGPT 刷新返回了其他账户，已保留原登录。");
            c.put("sub",claims.optString("sub"));c.put("id_token",fresh.getString("id_token"));
        }
        c.put("access_token",fresh.getString("access_token"));if(!fresh.optString("refresh_token").isEmpty())c.put("refresh_token",fresh.getString("refresh_token"));if(fresh.has("scope"))c.put("scope",fresh.optString("scope"));c.put("expires_at",System.currentTimeMillis()/1000+fresh.optLong("expires_in"));
        synchronized(AUTH_LOCK){if(!vault.get("oauth.credentials").equals(raw))throw new Exception("登录状态已改变，请重新发送任务。");vault.put("oauth.credentials",c.toString());if(!c.optString("id_token").isEmpty())vault.put("oauth.id_token",c.getString("id_token"));}return c.getString("access_token");
    }
    static String account(Vault vault){String email=vault.get("oauth.email");return email.isEmpty()?"未登录":"已连接："+email;}
    static void signOut(Vault vault){cancelSignIn();synchronized(AUTH_LOCK){vault.remove("oauth.credentials");vault.remove("oauth.id_token");vault.remove("oauth.email");vault.remove("oauth.client_id");}}
    private static String accept(ServerSocket server,String expectedState,int port,java.util.concurrent.atomic.AtomicBoolean cancelled)throws Exception{
        long deadline=System.currentTimeMillis()+600000;
        while(System.currentTimeMillis()<deadline&&!cancelled.get()){
            try(java.net.Socket socket=server.accept()){
                socket.setSoTimeout(2000);InputStream in=socket.getInputStream();ByteArrayOutputStream bytes=new ByteArrayOutputStream();int x,last=0;boolean complete=false;
                while(bytes.size()<16384&&(x=in.read())!=-1){bytes.write(x);last=((last<<8)|x);if(bytes.size()>=4&&last==0x0d0a0d0a){complete=true;break;}}
                if(!complete)continue;String request=bytes.toString("US-ASCII");String first=request.split("\\r?\\n",2)[0];String[] parts=first.split(" ");String path=parts.length==3?parts[1]:"";boolean valid=false;
                if(parts.length==3&&parts[0].equals("GET")&&(parts[2].equals("HTTP/1.1")||parts[2].equals("HTTP/1.0"))&&path.startsWith("/auth/callback?")){
                    Map<String,String> values=query(path);String state=values.get("state");valid=state!=null&&MessageDigest.isEqual(expectedState.getBytes(StandardCharsets.UTF_8),state.getBytes(StandardCharsets.UTF_8));
                    String host="";for(String line:request.split("\\r?\\n"))if(line.toLowerCase(java.util.Locale.ROOT).startsWith("host:"))host=line.substring(5).trim();valid&=host.equals("127.0.0.1:"+port)||host.equals("localhost:"+port);
                }
                String text=callbackPage(valid);
                byte[] page=text.getBytes(StandardCharsets.UTF_8);OutputStream out=socket.getOutputStream();out.write(((valid?"HTTP/1.1 200 OK":"HTTP/1.1 404 Not Found")+"\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\nContent-Length: "+page.length+"\r\n\r\n").getBytes(StandardCharsets.US_ASCII));out.write(page);out.flush();if(valid)return path;
            }catch(java.net.SocketTimeoutException ignored){}catch(IllegalArgumentException ignored){}
        }
        throw new Exception(cancelled.get()?"已取消登录。":"登录等待已超时，请重新开始。");
    }
    private static String html(String text){return text.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;").replace("'","&#39;");}
    static String callbackPage(boolean valid){
        String head="<!doctype html><html lang='"+UILocalization.language()+"'><meta charset=utf-8><meta name=referrer content=no-referrer><meta name=viewport content='width=device-width,initial-scale=1'><title>AsterHand</title><style>body{font:16px system-ui,sans-serif;max-width:30em;margin:12vh auto;padding:24px;color:#171717}a{display:block;margin-top:24px;padding:16px 20px;text-align:center;border-radius:14px;background:#171717;color:white;text-decoration:none;font-weight:600;font-size:18px}</style>";
        return head+(valid?"<h2>"+html(UILocalization.t("授权结果已收到"))+"</h2><p>"+html(UILocalization.t("请返回 AsterHand，应用会验证登录状态。"))+"</p><a href='asterhand://oauth/complete'>"+html(UILocalization.t("已完成登录，返回 AsterHand"))+"</a>":"<p>"+html(UILocalization.t("此请求不是当前登录回调。"))+"</p>")+"</html>";
    }
    private static JSONObject httpJSON(String address,String method,byte[] body,String type)throws Exception{
        URI uri=new URI(address);if(!uri.getScheme().equals("https")||uri.getHost()==null||!uri.getHost().equals("auth.openai.com")||uri.getUserInfo()!=null||uri.getFragment()!=null||(uri.getPort()!=-1&&uri.getPort()!=443))throw new Exception("OAuth 请求目标不受信任。");
        HttpURLConnection c=(HttpURLConnection)new URL(address).openConnection();c.setInstanceFollowRedirects(false);c.setConnectTimeout(20000);c.setReadTimeout(30000);c.setRequestMethod(method);if(type!=null)c.setRequestProperty("Content-Type",type);
        try{
            if(body!=null){c.setDoOutput(true);try(OutputStream out=c.getOutputStream()){out.write(body);}}
            int status=c.getResponseCode();InputStream input=status>=400?c.getErrorStream():c.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream();if(input!=null)try(InputStream in=input){byte[] bytes=new byte[4096];int n;while((n=in.read(bytes))!=-1){if(out.size()+n>1024*1024)throw new Exception("OAuth 响应过大。");out.write(bytes,0,n);}}
            String text=out.toString("UTF-8");if(status<200||status>=300){String error="授权服务请求失败";try{error=safeCode(new JSONObject(text).optString("error"));}catch(Exception ignored){}throw new Exception("OAuth HTTP "+status+"："+error);}
            return new JSONObject(text);
        }finally{c.disconnect();}
    }
    private static JSONObject postForm(String url,Map<String,String> values)throws Exception{StringBuilder body=new StringBuilder();for(Map.Entry<String,String> e:values.entrySet()){if(body.length()>0)body.append('&');body.append(encode(e.getKey())).append('=').append(encode(e.getValue()));}return httpJSON(url,"POST",body.toString().getBytes(StandardCharsets.UTF_8),"application/x-www-form-urlencoded");}
    private static JSONObject verify(String jwt,String client,String nonce)throws Exception{if(jwt==null||jwt.length()>65536)throw new Exception("ID token 格式错误。");String[] p=jwt.split("\\.");if(p.length!=3)throw new Exception("ID token 格式错误。");JSONObject header=new JSONObject(new String(Base64.decode(p[0],Base64.URL_SAFE|Base64.NO_WRAP|Base64.NO_PADDING),StandardCharsets.UTF_8));JSONObject claims=new JSONObject(new String(Base64.decode(p[1],Base64.URL_SAFE|Base64.NO_WRAP|Base64.NO_PADDING),StandardCharsets.UTF_8));JSONObject oidc=httpJSON(AUTH+"/.well-known/openid-configuration","GET",null,null);String issuer=oidc.optString("issuer"),jwksURL=oidc.optString("jwks_uri");if(!issuer.equals(AUTH)||!jwksURL.startsWith(AUTH+"/"))throw new Exception("OpenID 服务配置无效。");JSONObject jwks=httpJSON(jwksURL,"GET",null,null);JSONArray keys=jwks.optJSONArray("keys");JSONObject jwk=null;if(keys!=null)for(int i=0;i<keys.length();i++){JSONObject k=keys.optJSONObject(i);if(k!=null&&k.optString("kid").equals(header.optString("kid"))){jwk=k;break;}}if(jwk==null)throw new Exception("找不到 OpenID 签名公钥。");String alg=header.optString("alg");java.security.PublicKey key;
        if(alg.equals("RS256")){if(!jwk.optString("kty").equals("RSA"))throw new Exception("OpenID 公钥类型不匹配。");BigInteger n=new BigInteger(1,dec(jwk.optString("n"))),e=new BigInteger(1,dec(jwk.optString("e")));key=KeyFactory.getInstance("RSA").generatePublic(new RSAPublicKeySpec(n,e));}
        else if(alg.equals("ES256")){if(!jwk.optString("kty").equals("EC")||!jwk.optString("crv").equals("P-256"))throw new Exception("OpenID 曲线不匹配。");AlgorithmParameters params=AlgorithmParameters.getInstance("EC");params.init(new ECGenParameterSpec("secp256r1"));ECParameterSpec spec=params.getParameterSpec(ECParameterSpec.class);key=KeyFactory.getInstance("EC").generatePublic(new ECPublicKeySpec(new ECPoint(new BigInteger(1,dec(jwk.optString("x"))),new BigInteger(1,dec(jwk.optString("y")))),spec));}
        else throw new Exception("不支持的 ID token 签名算法。");Signature verifier=Signature.getInstance(alg.equals("RS256")?"SHA256withRSA":"SHA256withECDSA");verifier.initVerify(key);verifier.update((p[0]+"."+p[1]).getBytes(StandardCharsets.US_ASCII));byte[] sig=dec(p[2]);if(alg.equals("ES256")&&sig.length==64)sig=ecdsaDER(sig);if(!verifier.verify(sig))throw new Exception("ID token 签名验证失败。");Object aud=claims.opt("aud");boolean audOK=client.equals(aud);if(aud instanceof JSONArray)for(int i=0;i<((JSONArray)aud).length();i++)audOK|=client.equals(((JSONArray)aud).optString(i));if((aud instanceof JSONArray&&((JSONArray)aud).length()>1&&!client.equals(claims.optString("azp")))||claims.optLong("nbf")>System.currentTimeMillis()/1000+120||claims.optLong("iat")>System.currentTimeMillis()/1000+120||!audOK||!issuer.equals(claims.optString("iss"))||(nonce!=null&&!nonce.equals(claims.optString("nonce")))||claims.optLong("exp")<=System.currentTimeMillis()/1000||claims.optString("sub").isEmpty())throw new Exception("ID token 的 issuer、audience、nonce 或有效期校验失败。");return claims;}
    private static byte[] ecdsaDER(byte[] raw){byte[] r=integer(raw,0),s=integer(raw,32);byte[] seq=new byte[2+r.length+s.length];seq[0]=0x30;seq[1]=(byte)(r.length+s.length);System.arraycopy(r,0,seq,2,r.length);System.arraycopy(s,0,seq,2+r.length,s.length);return seq;}
    private static byte[] integer(byte[] raw,int offset){int start=offset;while(start<offset+31&&raw[start]==0)start++;int len=offset+32-start;boolean pad=(raw[start]&0x80)!=0;byte[] result=new byte[2+len+(pad?1:0)];result[0]=2;result[1]=(byte)(len+(pad?1:0));System.arraycopy(raw,start,result,2+(pad?1:0),len);return result;}
    private static byte[] dec(String value){return Base64.decode(value,Base64.URL_SAFE|Base64.NO_WRAP|Base64.NO_PADDING);}
    private static String enc(byte[] value){return Base64.encodeToString(value,Base64.URL_SAFE|Base64.NO_WRAP|Base64.NO_PADDING);}
    private static String random(){byte[] b=new byte[32];new SecureRandom().nextBytes(b);return enc(b);}
    private static String encode(String value){try{return URLEncoder.encode(value,"UTF-8");}catch(Exception e){return "";}}
    private static Map<String,String> query(String value)throws Exception{Map<String,String> result=new LinkedHashMap<>();String q=value.contains("?")?value.substring(value.indexOf('?')+1):"";for(String pair:q.split("&")){int at=pair.indexOf('=');if(at>=0){String key=URLDecoder.decode(pair.substring(0,at),"UTF-8");if(result.containsKey(key))throw new IllegalArgumentException("重复 OAuth 参数");result.put(key,URLDecoder.decode(pair.substring(at+1),"UTF-8"));}}return result;}
}
