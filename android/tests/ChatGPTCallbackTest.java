package com.pocketagent;
import java.net.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Exercises the real bounded loopback callback reader without any OAuth account. */
public final class ChatGPTCallbackTest {
    static int checks;
    static void ok(boolean value,String label){checks++;if(!value)throw new AssertionError(label);}
    static String request(int port,String path,boolean split)throws Exception{
        try(Socket s=new Socket("127.0.0.1",port)){s.setSoTimeout(3000);String req="GET "+path+" HTTP/1.1\r\nHost: 127.0.0.1:"+port+"\r\n\r\n";OutputStream out=s.getOutputStream();byte[] data=req.getBytes(StandardCharsets.US_ASCII);if(split){out.write(data,0,11);out.flush();Thread.sleep(30);out.write(data,11,data.length-11);}else out.write(data);out.flush();ByteArrayOutputStream result=new ByteArrayOutputStream();byte[] buffer=new byte[1024];int n;while((n=s.getInputStream().read(buffer))!=-1)result.write(buffer,0,n);return result.toString("UTF-8");}
    }
    public static void main(String[] args)throws Exception{
        Method read=ChatGPTAuth.class.getDeclaredMethod("accept",ServerSocket.class,String.class,int.class,AtomicBoolean.class);read.setAccessible(true);Method scope=ChatGPTAuth.class.getDeclaredMethod("hasScope",String.class);scope.setAccessible(true);
        try(ServerSocket listener=new ServerSocket(0,4,InetAddress.getByName("127.0.0.1"))){listener.setSoTimeout(100);int port=listener.getLocalPort();AtomicBoolean cancelled=new AtomicBoolean();FutureTask<String> task=new FutureTask<>(()->(String)read.invoke(null,listener,"fixture-state",port,cancelled));new Thread(task).start();
            new Socket("127.0.0.1",port).close();ok(request(port,"/favicon.ico",false).startsWith("HTTP/1.1 404"),"Unrelated request rejected");ok(!task.isDone(),"Preconnect and favicon keep listener alive");
            ok(request(port,"/auth/callback?state=wrong&code=not-used",false).startsWith("HTTP/1.1 404"),"Wrong state rejected");ok(!task.isDone(),"Wrong state does not consume callback");
            request(port,"/auth/callback?state=fixture-state&state=wrong&code=not-used",false);ok(!task.isDone(),"Duplicate state rejected");
            String page=request(port,"/auth/callback?state=fixture-state&code=private-fixture",true);ok(task.get(2,TimeUnit.SECONDS).endsWith("code=private-fixture"),"Fragmented valid callback accepted");ok(!page.contains("private-fixture")&&!page.contains("fixture-state"),"Browser page does not echo OAuth secrets");ok(page.contains("asterhand://oauth/complete"),"Explicit return link");ok(page.contains("已完成登录，返回 AsterHand"),"Visible return button");ok(page.contains("应用会验证登录状态"),"Return does not claim verified login");
        }
        ok((Boolean)scope.invoke(null,"openid  chatgpt.tokens.use.direct\nprofile"),"Exact scope with whitespace");ok(!(Boolean)scope.invoke(null,"not_chatgpt.tokens.use.direct"),"Substring scope rejected");
        System.out.println("OAuth loopback fixtures passed: "+checks+" (no account login)");
    }
}
