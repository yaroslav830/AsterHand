package com.pocketagent;

import java.io.*;
import java.lang.reflect.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.json.JSONObject;

/** Runs the production LAN HTTP client against disposable loopback fixtures only. */
public final class RemoteControlHttpTest {
    private static int checks;
    private static final Method HTTP;
    static {try{HTTP=RemoteControlHub.class.getDeclaredMethod("http",String.class,int.class,String.class,String.class,JSONObject.class,int.class,AtomicBoolean.class);HTTP.setAccessible(true);}catch(Exception e){throw new ExceptionInInitializerError(e);}}
    private interface Handler {void run(Socket socket)throws Exception;}
    private static final class Fixture implements AutoCloseable {
        final ServerSocket listener=new ServerSocket(0,1,InetAddress.getLoopbackAddress());
        final Thread thread;
        Fixture(Handler handler)throws Exception{thread=new Thread(()->{try(Socket socket=listener.accept()){socket.setSoTimeout(3000);int tail=0;boolean complete=false;for(int n=0;n<16384;n++){int ch=socket.getInputStream().read();if(ch<0)break;tail=(tail<<8)|ch;if(n>=3&&tail==0x0d0a0d0a){complete=true;break;}}if(!complete)throw new IOException("Fixture request incomplete");handler.run(socket);}catch(Exception ignored){}},"AsterHand-local-HTTP-fixture");thread.setDaemon(true);thread.start();}
        public void close()throws Exception{listener.close();thread.join(500);}
    }
    private static JSONObject request(int port,AtomicBoolean cancel)throws Exception{return invoke("127.0.0.1",port,cancel);}
    private static JSONObject invoke(String host,int port,AtomicBoolean cancel)throws Exception{return invoke(host,port,cancel,5000);}
    private static JSONObject invoke(String host,int port,AtomicBoolean cancel,int timeout)throws Exception{try{return (JSONObject)HTTP.invoke(null,host,port,"GET","/info",null,timeout,cancel);}catch(InvocationTargetException e){Throwable cause=e.getCause();if(cause instanceof Exception)throw (Exception)cause;throw e;}}
    private static void send(Socket s,String raw)throws Exception{s.getOutputStream().write(raw.getBytes(StandardCharsets.UTF_8));s.getOutputStream().flush();}
    private static void check(boolean value,String label){if(!value)throw new AssertionError(label);checks++;}
    private static void refused(String raw,String label)throws Exception{try(Fixture f=new Fixture(s->send(s,raw))){try{request(f.listener.getLocalPort(),null);throw new AssertionError(label);}catch(AssertionError e){throw e;}catch(Exception expected){checks++;}}}
    public static void main(String[] args)throws Exception{
        try(Fixture f=new Fixture(s->send(s,"HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\n{\"ok\":true}"))){check(request(f.listener.getLocalPort(),null).getBoolean("ok"),"content length body");}
        try(Fixture f=new Fixture(s->send(s,"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4;ext=1\r\n{\"ok\r\n7\r\n\":true}\r\n0\r\nX-Trailer: harmless\r\n\r\n"))){check(request(f.listener.getLocalPort(),null).getBoolean("ok"),"chunked body and bounded trailers");}
        try(Fixture f=new Fixture(s->send(s,"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n{\"ok\":true}"))){check(request(f.listener.getLocalPort(),null).getBoolean("ok"),"bounded close-delimited body");}
        refused("HTTP/1.1 200 OK\r\nContent-Length: 11\r\nContent-Length: 11\r\n\r\n{\"ok\":true}","duplicate headers");
        refused("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n0\r\n\r\n","ambiguous body framing");
        refused("HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n{}","incomplete response");
        refused("HTTP/1.1 200 OK\r\nContent-Length: 2097153\r\n\r\n","response bound");
        refused("HTTP/1.1 302 Found\r\nLocation: https://example.invalid\r\nContent-Length: 0\r\n\r\n","no redirects");
        try{invoke("8.8.8.8",18769,null);throw new AssertionError("WAN refused");}catch(AssertionError e){throw e;}catch(Exception expected){checks++;}
        try{invoke("127.0.0.1",0,null);throw new AssertionError("port refused");}catch(AssertionError e){throw e;}catch(Exception expected){checks++;}
        try{invoke("127.0.0.1",18769,new AtomicBoolean(true));throw new AssertionError("pre-cancelled request");}catch(CancellationException expected){checks++;}
        try(Fixture f=new Fixture(s->{for(byte b:"HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\n{\"ok\":true}".getBytes(StandardCharsets.US_ASCII)){s.getOutputStream().write(b);s.getOutputStream().flush();Thread.sleep(80);}})){
            long started=System.nanoTime();boolean refused=false;try{invoke("127.0.0.1",f.listener.getLocalPort(),null,300);}catch(IOException expected){refused=true;}
            check(refused&&TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-started)<1300,"absolute timeout stops slow trickle responses, even while bytes keep arriving");
        }
        AtomicBoolean cancel=new AtomicBoolean();CountDownLatch accepted=new CountDownLatch(1),closed=new CountDownLatch(1);
        try(Fixture f=new Fixture(s->{accepted.countDown();while(s.getInputStream().read()!=-1){}closed.countDown();})){
            ExecutorService worker=Executors.newSingleThreadExecutor();try{Future<?> job=worker.submit(()->{try{request(f.listener.getLocalPort(),cancel);throw new AssertionError("cancelled socket must not finish");}catch(CancellationException expected){}catch(Exception e){throw new RuntimeException(e);}});check(accepted.await(2,TimeUnit.SECONDS),"cancellation fixture accepted");long started=System.nanoTime();cancel.set(true);job.get(2,TimeUnit.SECONDS);check(TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-started)<1500&&closed.await(1,TimeUnit.SECONDS),"cancellation closes the live socket promptly");}finally{worker.shutdownNow();}
        }
        System.out.println("Remote LAN HTTP fixtures passed: "+checks+" (loopback only; no device or model requests)");
    }
}
