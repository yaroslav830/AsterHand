package com.pocketagent;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.AtomicFile;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Authenticated, device-identity-based LAN control. AI credentials are never paired or exported. */
public final class RemoteControlHub implements AgentSession.RemoteExecutor {
    private static RemoteControlHub instance;
    public static synchronized RemoteControlHub get(Context c){if(instance==null)instance=new RemoteControlHub(c);return instance;}
    private final Context app;
    private final SharedPreferences prefs;
    private final AtomicFile file;
    private final Object lock=new Object();
    private JSONObject state;
    private String error="";
    private volatile boolean uiActive;
    private volatile Runnable requestListener;
    private volatile ServerSocket server;
    private ExecutorService workers;
    private ScheduledExecutorService timers;
    private final ConcurrentMap<String,Pending> pending=new ConcurrentHashMap<>(),outgoing=new ConcurrentHashMap<>();
    private final ConcurrentMap<String,Long> seen=new ConcurrentHashMap<>();
    private final ConcurrentMap<String,Set<AtomicBoolean>> jobs=new ConcurrentHashMap<>();
    private final AtomicInteger streams=new AtomicInteger();
    private final ActorLeases aiLeases=new ActorLeases(),manualLeases=new ActorLeases();
    interface LeaseAuthority {boolean allows(String owner);}
    /** Monotonic, memory-only state; no grants or indicators survive a process restart. */
    static final class ActorLeases {
        private final ConcurrentMap<String,Long> until=new ConcurrentHashMap<>();
        void begin(String owner,long milliseconds,long now){
            if(owner==null||owner.isEmpty())throw new IllegalArgumentException("Missing owner");
            long end=now+TimeUnit.MILLISECONDS.toNanos(Math.max(1,Math.min(120000,milliseconds)));
            while(true){Long old=until.get(owner);if(old!=null&&old-now>=end-now)return;if(old==null){if(until.putIfAbsent(owner,end)==null)return;}else if(until.replace(owner,old,end))return;}
        }
        void end(String owner){until.remove(owner);}
        void clear(){until.clear();}
        boolean any(long now,LeaseAuthority authority){boolean active=false;for(Map.Entry<String,Long> e:until.entrySet()){if(e.getValue()-now<=0||!authority.allows(e.getKey()))until.remove(e.getKey(),e.getValue());else active=true;}return active;}
    }
    static long leaseMilliseconds(Object raw)throws Exception{double value=raw==null?6:raw instanceof Number?((Number)raw).doubleValue():Double.NaN;if(Double.isNaN(value)||Double.isInfinite(value))throw new Exception("控制状态租约需要是有效秒数。");return (long)(Math.max(6,Math.min(120,value))*1000);}

    private final Semaphore sockets=new Semaphore(12);
    private final Set<Socket> activeSockets=Collections.newSetFromMap(new ConcurrentHashMap<Socket,Boolean>());
    private String rotatingCode="";
    private long codeDeadline;
    private static final int PORT=18769;
    private static final Set<String> METHODS=new HashSet<>(Arrays.asList("info","presence","hello","session.close","app","execute","terminal.open","terminal.read","terminal.write","terminal.close","terminal.interrupt"));
    private static final Set<String> TOOLS=new HashSet<>(Arrays.asList("run_shell","read_file","write_file","list_directory","screen_capture","screen_tap","screen_swipe","screen_type","screen_home"));
    private static final class Pending {
        String id,key,host,name,device,publicKey,status="pending",mode="";int port;double created;
        JSONObject publicView()throws Exception{return new JSONObject().put("id",id).put("name",name).put("device_id",device).put("code",RemoteControlWire.code(key)).put("status",status).put("created",created);}
    }
    private RemoteControlHub(Context c){
        app=c.getApplicationContext();prefs=app.getSharedPreferences("MainActivity",0);File dir=new File(app.getFilesDir(),"control");dir.mkdirs();file=new AtomicFile(new File(dir,"control.json"));
        try{
            if(file.getBaseFile().exists()){try(InputStream in=file.openRead()){state=new JSONObject(new String(readLimited(in,2*1024*1024),StandardCharsets.UTF_8));}}
            else state=new JSONObject().put("name",Build.MODEL).put("enabled",false).put("background",true).put("peers",new JSONArray()).put("trust",new JSONObject());
            if(state.optJSONObject("identity")==null)state.put("identity",RemoteControlWire.newIdentity());
            RemoteControlWire.deviceID(state.getJSONObject("identity").getString("public_key"));if(state.optJSONArray("peers")==null||state.optJSONObject("trust")==null)throw new Exception("Invalid control store");save();
        }catch(Exception e){state=null;error="远程连接数据无法读取，原文件已保留。";}
    }
    public void setRequestListener(Runnable listener){requestListener=listener;}
    public void setUiActive(boolean active){uiActive=active;if(!active&&!available())closeIncomingAsync();}
    public synchronized void start()throws Exception{
        ServiceMaster.requireEnabled(app);
        if(server!=null&&!server.isClosed())return;if(state==null)throw new Exception(error);
        ServerSocket s=new ServerSocket();s.setReuseAddress(true);s.bind(new InetSocketAddress(PORT),12);server=s;
        workers=new ThreadPoolExecutor(4,12,30,TimeUnit.SECONDS,new ArrayBlockingQueue<>(24),r->{Thread t=new Thread(r,"AsterHand-control-worker");t.setDaemon(true);return t;},new ThreadPoolExecutor.AbortPolicy());
        timers=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"AsterHand-control-limits");t.setDaemon(true);return t;});
        timers.scheduleWithFixedDelay(()->{try{expire();}catch(Exception ignored){}},1,1,TimeUnit.SECONDS);
        Thread listener=new Thread(()->{while(server==s&&!s.isClosed()){try{Socket socket=s.accept();if(!sockets.tryAcquire()){socket.close();continue;}activeSockets.add(socket);try{workers.execute(()->{try{receive(socket);}finally{activeSockets.remove(socket);sockets.release();try{socket.close();}catch(Exception ignored){}}});}catch(RejectedExecutionException e){activeSockets.remove(socket);sockets.release();socket.close();}}catch(IOException e){if(!s.isClosed())error="远程连接监听暂时中断。";}}},"AsterHand-control-listener");listener.setDaemon(true);listener.start();
        AgentSession.remote=this;
    }
    public synchronized void stop(){ServerSocket s=server;server=null;if(s!=null)try{s.close();}catch(Exception ignored){}for(Socket active:activeSockets)try{active.close();}catch(Exception ignored){}activeSockets.clear();if(timers!=null)timers.shutdownNow();if(workers!=null)workers.shutdownNow();for(String owner:jobs.keySet())cancelOwner(owner);aiLeases.clear();manualLeases.clear();lastAuthenticated=0;connectedName="";try{for(int i=0;i<state.getJSONArray("peers").length();i++)new PrivilegeManager(app).closeOwner(state.getJSONArray("peers").getJSONObject(i).optString("id"));}catch(Exception ignored){}if(AgentSession.remote==this)AgentSession.remote=null;}
    private boolean available(){synchronized(lock){return state!=null&&(state.optBoolean("background",true)||uiActive);}}
    private void save()throws Exception{synchronized(lock){if(state==null)return;FileOutputStream out=null;try{out=file.startWrite();out.write(state.toString().getBytes(StandardCharsets.UTF_8));file.finishWrite(out);}catch(Exception e){if(out!=null)file.failWrite(out);throw e;}}}
    private JSONObject identity()throws Exception{synchronized(lock){String pub=state.getJSONObject("identity").getString("public_key");return new JSONObject().put("device_id",RemoteControlWire.deviceID(pub)).put("public_key",pub).put("name",state.optString("name",Build.MODEL));}}
    private JSONObject advertised()throws Exception{synchronized(lock){JSONObject result=identity().put("pairing",2).put("port",PORT).put("pair_code_fixed",state.optString("pair_code_mode").equals("fixed"));if(result.optBoolean("pair_code_fixed"))result.put("pair_code",state.getString("pair_code_fixed"));else{if(rotatingCode.isEmpty()||System.currentTimeMillis()>codeDeadline){rotatingCode=String.format(Locale.ROOT,"%06d",new SecureRandom().nextInt(1000000));codeDeadline=System.currentTimeMillis()+120000;}result.put("pair_code",rotatingCode);}return result;}}
    public JSONObject info()throws Exception{
        synchronized(lock){if(state==null)return new JSONObject().put("error",error);JSONObject result=new JSONObject().put("name",state.optString("name")).put("platform","android").put("port",PORT).put("enabled",state.optBoolean("enabled")).put("background",state.optBoolean("background",true)).put("available",available()).put("addresses",addresses()).put("identity",advertised()).put("device_id",identity().getString("device_id")).put("public_key",identity().getString("public_key")).put("pending",pending()).put("trust",trust()).put("peers",peers()).put("permission",new PrivilegeManager(app).getMode().name()).put("remote_connected",System.currentTimeMillis()-lastAuthenticated<15000).put("remote_controlling",activeLeases(manualLeases)).put("remote_ai_controlling",activeLeases(aiLeases)).put("ai_controlling",activeLeases(aiLeases)).put("connected_name",connectedName);if(!error.isEmpty())result.put("error",error);return result;}
    }
    public JSONArray peers()throws Exception{synchronized(lock){JSONArray result=new JSONArray(),all=state.getJSONArray("peers");for(int i=0;i<all.length();i++){JSONObject p=all.getJSONObject(i);if(p.optBoolean("incoming",true)&&p.optString("mode").equals("once")&&p.optDouble("expires_at")<now())continue;result.put(new JSONObject().put("id",p.optString("id")).put("name",p.optString("name")).put("host",p.optString("host")).put("port",p.optInt("port",PORT)).put("device_id",p.optString("device_id")).put("mode",p.optString("mode")).put("incoming",p.optBoolean("incoming",true)));}return result;}}
    public JSONArray devices()throws Exception{return peers();}
    public JSONArray pending()throws Exception{JSONArray result=new JSONArray();for(Pending p:pending.values())if(p.status.equals("pending")&&now()-p.created<=120)result.put(p.publicView());return result;}
    public JSONArray trust()throws Exception{synchronized(lock){JSONArray result=new JSONArray();JSONObject all=state.getJSONObject("trust");Iterator<String> ids=all.keys();while(ids.hasNext()){String id=ids.next();JSONObject p=all.getJSONObject(id);result.put(new JSONObject().put("device_id",id).put("name",p.optString("name")).put("mode",p.optString("mode","ask")));}return result;}}
    public JSONObject setEnabled(boolean enabled)throws Exception{synchronized(lock){state.put("enabled",enabled);save();}if(!enabled)closeIncomingAsync();return info();}
    public JSONObject setBackground(boolean background)throws Exception{synchronized(lock){state.put("background",background);save();}if(!background&&!uiActive)closeIncomingAsync();return info();}
    public JSONObject setName(String name)throws Exception{String n=cleanName(name);synchronized(lock){state.put("name",n);save();}return info();}
    public JSONObject setPairCode(boolean fixed,String code)throws Exception{synchronized(lock){if(fixed){if(code==null||!code.matches("[0-9]{6}"))throw new Exception("配对码需要 6 位数字。");state.put("pair_code_mode","fixed").put("pair_code_fixed",code);}else state.put("pair_code_mode","rotating");save();return info();}}
    public JSONObject rename(String id,String name)throws Exception{String n=cleanName(name);synchronized(lock){JSONObject p=findPeer(id);if(p==null)throw new Exception("未找到此连接。");p.put("name",n);JSONObject t=state.getJSONObject("trust").optJSONObject(p.optString("device_id"));if(t!=null)t.put("name",n);save();return info();}}
    public JSONObject revoke(String id)throws Exception{String pair;synchronized(lock){JSONObject p=findPeer(id);if(p==null)throw new Exception("未找到此连接。");pair=p.getString("id");JSONArray all=state.getJSONArray("peers"),next=new JSONArray();for(int i=0;i<all.length();i++)if(!all.getJSONObject(i).optString("id").equals(pair))next.put(all.get(i));state.put("peers",next);save();}cancelOwner(pair);clearPresence(pair);new PrivilegeManager(app).closeOwner(pair);return info();}
    public JSONObject forgetDevice(String device)throws Exception{if(device==null||!device.matches("[a-f0-9]{64}"))throw new Exception("无效设备标识。");ArrayList<String> remove=new ArrayList<>();synchronized(lock){JSONArray all=state.getJSONArray("peers");for(int i=0;i<all.length();i++){JSONObject p=all.getJSONObject(i);if(p.optString("device_id").equals(device))remove.add(p.getString("id"));}}for(String id:remove)revoke(id);synchronized(lock){state.getJSONObject("trust").remove(device);for(Pending p:pending.values())if(p.device.equals(device))pending.remove(p.id);for(Pending p:outgoing.values())if(p.device.equals(device))outgoing.remove(p.id);save();}return info();}
    public JSONObject setTrust(String device,String mode)throws Exception{
        if(!Arrays.asList("ask","always","deny").contains(mode))throw new Exception("无效的连接权限。");ArrayList<String> remove=new ArrayList<>();synchronized(lock){JSONObject all=state.getJSONObject("trust"),t=all.optJSONObject(device);if(t==null)throw new Exception("未找到已授权设备。");t.put("mode",mode);JSONArray peers=state.getJSONArray("peers");for(int i=0;i<peers.length();i++){JSONObject p=peers.getJSONObject(i);if(p.optBoolean("incoming",true)&&p.optString("device_id").equals(device)){if(mode.equals("always"))p.put("mode","always").put("expires_at",0);else remove.add(p.optString("id"));}}save();}for(String id:remove)revoke(id);return info();
    }
    public JSONObject decide(String id,String mode)throws Exception{
        if(!Arrays.asList("once","always","deny").contains(mode))throw new Exception("无效的连接授权。");ArrayList<String> obsolete=new ArrayList<>();synchronized(lock){Pending r=pending.get(id);if(r==null||!r.status.equals("pending")||now()-r.created>120)throw new Exception("连接申请已过期。");r.status=mode.equals("deny")?"denied":"accepted";r.mode=mode;state.getJSONObject("trust").put(r.device,new JSONObject().put("name",r.name).put("public_key",r.publicKey).put("mode",mode.equals("once")?"ask":mode));if(!mode.equals("deny")){JSONArray peers=state.getJSONArray("peers");for(int i=0;i<peers.length();i++){JSONObject p=peers.getJSONObject(i);if(p.optBoolean("incoming",true)&&p.optString("device_id").equals(r.device))obsolete.add(p.getString("id"));}JSONArray next=new JSONArray();for(int i=0;i<peers.length();i++)if(!obsolete.contains(peers.getJSONObject(i).optString("id")))next.put(peers.get(i));next.put(new JSONObject().put("id",r.id).put("key",r.key).put("host",r.host).put("port",r.port).put("name",r.name).put("device_id",r.device).put("public_key",r.publicKey).put("incoming",true).put("mode",mode).put("expires_at",mode.equals("once")?now()+600:0));state.put("peers",next).put("enabled",true);}save();}for(String old:obsolete){cancelOwner(old);new PrivilegeManager(app).closeOwner(old);}changed();return info();
    }
    private void changed(){Runnable listener=requestListener;if(listener!=null)new Handler(Looper.getMainLooper()).post(listener);}
    private static double now(){return System.currentTimeMillis()/1000d;}
    private static String cleanName(String name)throws Exception{String n=name==null?"":name.replaceAll("[\\p{Cntrl}\u202a-\u202e\u2066-\u2069]"," ").trim();if(n.isEmpty()||n.length()>80||n.indexOf('\0')>=0)throw new Exception("设备名称需要 1–80 个字符。");return n;}
    private JSONObject findPeer(String id)throws Exception{JSONArray all=state.getJSONArray("peers");JSONObject byDevice=null;for(int i=0;i<all.length();i++){JSONObject p=all.getJSONObject(i);if(p.optString("id").equals(id))return p;if(p.optString("device_id").equals(id)&&!p.optBoolean("incoming",true))byDevice=p;}if(byDevice==null)for(int i=0;i<all.length();i++){JSONObject p=all.getJSONObject(i);if(p.optString("device_id").equals(id))return p;}return byDevice;}
    private void expire()throws Exception{activeLeases(aiLeases);activeLeases(manualLeases);for(Pending p:pending.values())if(now()-p.created>120)pending.remove(p.id);for(Pending p:outgoing.values())if(now()-p.created>120)outgoing.remove(p.id);for(Map.Entry<String,Long> e:seen.entrySet())if(System.currentTimeMillis()-e.getValue()>180000)seen.remove(e.getKey(),e.getValue());ArrayList<String> old=new ArrayList<>();synchronized(lock){if(state==null)return;JSONArray all=state.getJSONArray("peers");for(int i=0;i<all.length();i++){JSONObject p=all.getJSONObject(i);if(p.optBoolean("incoming",true)&&p.optString("mode").equals("once")&&p.optDouble("expires_at")<now())old.add(p.optString("id"));}}for(String id:old)try{revoke(id);}catch(Exception ignored){}}
    private void replay(String pair,JSONObject payload)throws Exception{String key=pair+":"+payload.getString("id");if(seen.size()>=4096)throw new Exception("Too many requests");if(seen.putIfAbsent(key,System.currentTimeMillis())!=null)throw new Exception("Replay");}
    private Set<AtomicBoolean> ownerJobs(String owner){Set<AtomicBoolean> value=jobs.get(owner);if(value!=null)return value;Set<AtomicBoolean> fresh=Collections.newSetFromMap(new ConcurrentHashMap<AtomicBoolean,Boolean>());Set<AtomicBoolean> old=jobs.putIfAbsent(owner,fresh);return old==null?fresh:old;}
    private static boolean privateAddress(InetAddress address){byte[] b=address.getAddress();return address.isLoopbackAddress()||address.isSiteLocalAddress()||address.isLinkLocalAddress()||(b.length==16&&(b[0]&0xfe)==0xfc);}
    private void cancelOwner(String owner){Set<AtomicBoolean> work=jobs.get(owner);if(work!=null)for(AtomicBoolean flag:work)flag.set(true);}
    /** Closing the receiver also closes idle terminal processes owned by incoming sessions. */
    private void closeIncomingAsync(){
        aiLeases.clear();manualLeases.clear();lastAuthenticated=0;connectedName="";
        final ArrayList<String> owners=new ArrayList<>();synchronized(lock){try{JSONArray peers=state.getJSONArray("peers");for(int i=0;i<peers.length();i++){JSONObject p=peers.getJSONObject(i);if(p.optBoolean("incoming",true))owners.add(p.getString("id"));}}catch(Exception ignored){}}
        for(String owner:owners)cancelOwner(owner);
        Thread close=new Thread(()->{for(String owner:owners)try{new PrivilegeManager(app).closeOwner(owner);}catch(Exception ignored){}},"AsterHand-control-close");close.setDaemon(true);close.start();
    }
    private static void checkCancelled(AtomicBoolean cancelled){if(cancelled!=null&&cancelled.get())throw new CancellationException("远程任务已停止。");}

    private volatile long lastAuthenticated;
    private volatile String connectedName="",lastAuthenticatedOwner="";
    private boolean activeLeases(ActorLeases leases){if(!prefs.getBoolean("remoteScreen",false)){leases.clear();return false;}return leases.any(System.nanoTime(),this::authorised);}
    private void clearPresence(String owner){aiLeases.end(owner);manualLeases.end(owner);if(owner.equals(lastAuthenticatedOwner)){lastAuthenticated=0;connectedName="";lastAuthenticatedOwner="";}}
    private JSONObject presence(String owner,JSONObject args)throws Exception{
        String actor=args.optString("actor");if(actor.isEmpty()||actor.equals("connected"))return new JSONObject().put("ok",true);
        if(!actor.equals("ai")&&!actor.equals("manual"))throw new Exception("未知控制状态。");
        Object raw=args.opt("active");if(raw!=null&&!(raw instanceof Boolean))throw new Exception("控制状态需要明确的 active 布尔值。");
        boolean active=raw==null||Boolean.TRUE.equals(raw);ActorLeases leases=actor.equals("ai")?aiLeases:manualLeases;
        if(!active){leases.end(owner);return new JSONObject().put("ok",true).put("actor",actor).put("active",false);}
        if(!authorised(owner)||!prefs.getBoolean("remoteScreen",false))throw new Exception("手机尚未允许远程屏幕控制。");
        long duration=leaseMilliseconds(args.opt("lease_seconds"));leases.begin(owner,duration,System.nanoTime());return new JSONObject().put("ok",true).put("actor",actor).put("active",true).put("lease_seconds",duration/1000d);
    }
    private static final class Header {String first;Map<String,String> values=new HashMap<>();}
    private static Header header(InputStream in)throws Exception{
        ByteArrayOutputStream out=new ByteArrayOutputStream();int ch,last=0;boolean complete=false;while(out.size()<16384&&(ch=in.read())!=-1){out.write(ch);last=(last<<8)|ch;if(out.size()>=4&&last==0x0d0a0d0a){complete=true;break;}}if(!complete)throw new IOException("Invalid HTTP header");String[] lines=out.toString("US-ASCII").split("\r\n");Header h=new Header();h.first=lines[0];for(int i=1;i<lines.length;i++){int at=lines[i].indexOf(':');if(at<1)throw new IOException("Invalid HTTP header");String key=lines[i].substring(0,at).trim().toLowerCase(Locale.ROOT),value=lines[i].substring(at+1).trim();if(h.values.containsKey(key))throw new IOException("Duplicate HTTP header");h.values.put(key,value);}return h;
    }
    private static byte[] readLimited(InputStream in,int limit)throws IOException{ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] data=new byte[8192];int n;while((n=in.read(data))!=-1){if(out.size()+n>limit)throw new IOException("Response too large");out.write(data,0,n);}return out.toByteArray();}
    private static byte[] exact(InputStream in,int count)throws IOException{byte[] b=new byte[count];int offset=0,n;while(offset<count&&(n=in.read(b,offset,count-offset))!=-1)offset+=n;if(offset!=count)throw new EOFException("Incomplete HTTP body");return b;}
    private static String line(InputStream in)throws IOException{ByteArrayOutputStream out=new ByteArrayOutputStream();int c;while((c=in.read())!=-1){out.write(c);if(c=='\n')break;if(out.size()>1024)throw new IOException("Invalid chunk");}if(c==-1&&out.size()==0)throw new EOFException();String text=out.toString("US-ASCII");if(!text.endsWith("\r\n"))throw new IOException("Invalid chunk");return text.substring(0,text.length()-2);}
    private static byte[] body(InputStream in,Header h,int limit)throws Exception{
        String length=h.values.get("content-length"),encoding=h.values.get("transfer-encoding");
        if(encoding!=null){if(length!=null||!encoding.equalsIgnoreCase("chunked"))throw new IOException("Invalid transfer encoding");ByteArrayOutputStream out=new ByteArrayOutputStream();while(true){String size=line(in).split(";",2)[0];if(!size.matches("[0-9A-Fa-f]{1,8}"))throw new IOException("Invalid chunk");long n=Long.parseLong(size,16);if(n==0){int trailer=0;while(!line(in).isEmpty()){if(++trailer>32)throw new IOException("Invalid trailer");}return out.toByteArray();}if(n>limit-out.size())throw new IOException("Response too large");out.write(exact(in,(int)n));if(!line(in).isEmpty())throw new IOException("Invalid chunk ending");}}
        if(length!=null){if(!length.matches("[0-9]{1,9}"))throw new IOException("Invalid content length");long n=Long.parseLong(length);if(n>limit)throw new IOException("Response too large");return exact(in,(int)n);}return readLimited(in,limit);
    }
    private static InetAddress lan(String host)throws Exception{
        if(host==null||host.isEmpty()||host.length()>253||!host.matches("[A-Za-z0-9.:%_-]+"))throw new Exception("无效的局域网地址。");
        for(InetAddress address:InetAddress.getAllByName(host)){if(privateAddress(address))return address;}throw new Exception("此连接入口仅支持局域网设备。");
    }
    private static JSONObject http(String host,int port,String method,String path,JSONObject payload,int timeout)throws Exception{return http(host,port,method,path,payload,timeout,null);}
    private static JSONObject http(String host,int port,String method,String path,JSONObject payload,int timeout,AtomicBoolean cancelled)throws Exception{
        checkCancelled(cancelled);
        if(port<1||port>65535)throw new Exception("无效的设备端口。");InetAddress address=lan(host);byte[] content=payload==null?new byte[0]:payload.toString().getBytes(StandardCharsets.UTF_8);if(content.length>RemoteControlWire.LIMIT)throw new Exception("请求超过大小限制。");
        try(Socket socket=new Socket()){
            AtomicBoolean finished=new AtomicBoolean(false),expired=new AtomicBoolean(false);final long deadline=System.nanoTime()+TimeUnit.MILLISECONDS.toNanos(timeout);
            Thread watcher=new Thread(()->{while(!finished.get()){boolean overdue=System.nanoTime()>=deadline;if(overdue||(cancelled!=null&&cancelled.get())){expired.set(overdue);try{socket.close();}catch(Exception ignored){}return;}try{Thread.sleep(100);}catch(InterruptedException e){return;}}},"AsterHand-remote-cancel");watcher.setDaemon(true);watcher.start();
            try{socket.connect(new InetSocketAddress(address,port),Math.min(timeout,8000));socket.setSoTimeout(timeout);socket.setTcpNoDelay(true);OutputStream out=socket.getOutputStream();String authority=host.indexOf(':')>=0?"["+host+"]":host;String headers=method+" "+path+" HTTP/1.1\r\nHost: "+authority+":"+port+"\r\nConnection: close\r\nAccept: application/json\r\n"+(payload==null?"":"Content-Type: application/json\r\nContent-Length: "+content.length+"\r\n")+"\r\n";out.write(headers.getBytes(StandardCharsets.US_ASCII));out.write(content);out.flush();Header reply=header(socket.getInputStream());String[] first=reply.first.split(" ",3);if(first.length<2||!first[1].equals("200"))throw new Exception("对方拒绝连接或请求已过期。");byte[] data=body(socket.getInputStream(),reply,RemoteControlWire.LIMIT);checkCancelled(cancelled);return new JSONObject(new String(data,StandardCharsets.UTF_8));}
            catch(Exception e){checkCancelled(cancelled);if(expired.get())throw new IOException("远程设备请求超过总时间限制。",e);throw e;}
            finally{finished.set(true);watcher.interrupt();}
        }
    }
    private static void finish(Socket socket,int code,JSONObject object)throws Exception{byte[] bytes=object.toString().getBytes(StandardCharsets.UTF_8);if(bytes.length>RemoteControlWire.LIMIT)throw new Exception("Response too large");OutputStream out=socket.getOutputStream();String h="HTTP/1.1 "+code+(code==200?" OK":" Forbidden")+"\r\nContent-Type: application/json\r\nContent-Length: "+bytes.length+"\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n";out.write(h.getBytes(StandardCharsets.US_ASCII));out.write(bytes);out.flush();}
    private void receive(Socket socket){
        ScheduledFuture<?> readLimit=null;
        try{
            readLimit=timers.schedule(()->{try{socket.close();}catch(Exception ignored){}},10,TimeUnit.SECONDS);
            if(!privateAddress(socket.getInetAddress()))throw new Exception("LAN only");socket.setSoTimeout(10000);socket.setTcpNoDelay(true);Header h=header(socket.getInputStream());String[] request=h.first.split(" ");if(request.length!=3)throw new Exception("Invalid request");
            if(request[0].equals("GET")&&request[1].equals("/info")){JSONObject data=advertised().put("agentgo",1).put("platform","android").put("enabled",state.optBoolean("enabled")).put("available",available());finish(socket,200,data);return;}
            if(!request[0].equals("POST")||h.values.containsKey("origin")||!available()||h.values.containsKey("transfer-encoding")||!h.values.containsKey("content-length"))throw new Exception("Refused");
            int limit=request[1].equals("/pair")?32768:RemoteControlWire.LIMIT;byte[] bytes=body(socket.getInputStream(),h,limit);JSONObject data=new JSONObject(new String(bytes,StandardCharsets.UTF_8));
            if(request[1].equals("/pair")){finish(socket,200,pairing(data,socket.getInetAddress().getHostAddress()));return;}
            if(!request[1].equals("/rpc"))throw new Exception("Refused");JSONObject peer;
            synchronized(lock){peer=findPeer(data.optString("pair"));if(peer==null||!peer.optBoolean("incoming",true)||!state.optBoolean("enabled"))throw new Exception("Unpaired");peer=new JSONObject(peer.toString());}
            JSONObject message=RemoteControlWire.open(data,peer.getString("key"),"req");replay(peer.getString("id"),message);if(!authorised(peer.getString("id")))throw new Exception("Revoked");readLimit.cancel(false);renew(peer.getString("id"));lastAuthenticated=System.currentTimeMillis();lastAuthenticatedOwner=peer.getString("id");connectedName=peer.optString("name");
            if(message.optString("method").equals("stream2")){stream(socket,peer,message);return;}
            socket.setSoTimeout(0);String method=message.optString("method");JSONObject args=message.optJSONObject("args");if(args==null)args=new JSONObject();JSONObject result;
            boolean close=method.equals("session.close")&&peer.optString("mode").equals("once");
            if(method.equals("hello")){String name=cleanName(args.optString("name"));int port=args.optInt("port");if(port<1||port>65535)throw new Exception("Invalid hello");synchronized(lock){JSONObject p=findPeer(peer.getString("id"));if(p==null)throw new Exception("Revoked");p.put("name",name).put("host",socket.getInetAddress().getHostAddress()).put("port",port);save();}result=new JSONObject().put("ok",true).put("name",state.optString("name"));}
            else if(method.equals("session.close")){clearPresence(peer.getString("id"));result=new JSONObject().put("closed",true);}
            else result=executeOwned(method,args,peer.getString("id"),socket);
            if(!authorised(peer.getString("id")))throw new Exception("Revoked");finish(socket,200,RemoteControlWire.seal(peer.getString("id"),peer.getString("key"),new JSONObject().put("id",message.getString("id")).put("ts",now()).put("result",result),"res"));if(close)revoke(peer.getString("id"));
        }catch(Exception e){try{finish(socket,403,new JSONObject());}catch(Exception ignored){}}finally{if(readLimit!=null)readLimit.cancel(false);}
    }
    private JSONObject pairing(JSONObject body,String address)throws Exception{
        if(body.optInt("v")!=2)throw new Exception("Unsupported pairing");String id=body.optString("request");JSONObject remote=body.getJSONObject("identity"),local=advertised();String key; synchronized(lock){key=RemoteControlWire.pairingSecret(state.getJSONObject("identity"),remote,id);}
        JSONObject packet=body.getJSONObject("packet"),payload=RemoteControlWire.open(packet,key,"req"),args=payload.optJSONObject("args");String method=payload.optString("method");if(!packet.optString("pair").equals(id)||args==null||!args.optString("receiver_id").equals(local.getString("device_id"))||(!method.equals("pair.request")&&!method.equals("pair.status")))throw new Exception("Pairing identity mismatch");replay(id,payload);
        Pending r;boolean notify=false;synchronized(lock){r=pending.get(id);if(r==null){if(!method.equals("pair.request")||pending.size()>=64||pending().length()>=8)throw new Exception("Pairing expired or busy");r=new Pending();r.id=id;r.key=key;r.host=address;r.port=args.optInt("port");if(r.port<1||r.port>65535)throw new Exception("Invalid port");r.name=cleanName(args.optString("name"));r.device=remote.getString("device_id");r.publicKey=remote.getString("public_key");r.created=now();pending.put(id,r);JSONObject trusted=state.getJSONObject("trust").optJSONObject(r.device);String mode=trusted==null?"ask":trusted.optString("mode","ask");if(mode.equals("deny")||mode.equals("always"))decide(id,mode);else notify=true;}else if(!r.key.equals(key)||!r.device.equals(remote.optString("device_id"))||now()-r.created>120)throw new Exception("Pairing mismatch");}
        if(notify)changed();JSONObject result=r.publicView().put("mode",r.mode.isEmpty()?JSONObject.NULL:r.mode).put("receiver",local);return RemoteControlWire.seal(id,key,new JSONObject().put("id",payload.getString("id")).put("ts",now()).put("result",result),"res");
    }
    private boolean authorised(String id){synchronized(lock){try{JSONObject p=findPeer(id);return server!=null&&!server.isClosed()&&p!=null&&p.optBoolean("incoming",true)&&state.optBoolean("enabled")&&available()&&(!p.optString("mode").equals("once")||p.optDouble("expires_at")>=now());}catch(Exception e){return false;}}}
    private void renew(String id)throws Exception{synchronized(lock){JSONObject p=findPeer(id);if(p!=null&&p.optString("mode").equals("once")&&p.optDouble("expires_at")<now()+540){p.put("expires_at",now()+600);save();}}}
    private JSONObject executeOwned(String method,JSONObject args,String owner,Socket socket)throws Exception{
        AtomicBoolean cancelled=new AtomicBoolean();ownerJobs(owner).add(cancelled);PrivilegeManager manager=new PrivilegeManager(app);PrivilegeManager.Mode mode=manager.getMode();
        ScheduledFuture<?> check=timers.scheduleAtFixedRate(()->{if(!authorised(owner)||new PrivilegeManager(app).getMode()!=mode)cancelled.set(true);},0,200,TimeUnit.MILLISECONDS);
        Thread disconnected=new Thread(()->{try{socket.getInputStream().read();cancelled.set(true);}catch(Exception ignored){cancelled.set(true);}},"AsterHand-control-disconnect");disconnected.setDaemon(true);disconnected.start();
        try{return localExecute(method,args,owner,mode,cancelled);}catch(Exception e){return new JSONObject().put("error",e.getMessage()==null?"操作失败。":e.getMessage());}finally{check.cancel(false);Set<AtomicBoolean> work=jobs.get(owner);if(work!=null){work.remove(cancelled);if(work.isEmpty())jobs.remove(owner,work);}if(cancelled.get()&&args.optString("actor").equals("ai"))aiLeases.end(owner);if(!authorised(owner)){clearPresence(owner);try{manager.closeOwner(owner);}catch(Exception ignored){}}}
    }
    private String workspace()throws Exception{JSONObject project=new ProjectStore(app).currentProject();return project==null?new AgentTools(app,false).workspace():project.optString("workspace",new AgentTools(app,false).workspace());}
    private JSONObject localExecute(String method,JSONObject args,String owner,PrivilegeManager.Mode mode,AtomicBoolean cancelled)throws Exception{
        if(method.equals("app")){ServiceMaster.requireEnabled(app);switch(args.optString("action")){case "device.list":return new JSONObject().put("devices",peers());case "device.app":JSONObject forwarded=args.getJSONObject("arguments");if(forwarded.optString("action").equals("device.app"))throw new Exception("不允许递归转发");return request(args.getString("id"),"app",forwarded,cancelled);case "device.discover":return new JSONObject().put("devices",discover());case "device.begin":return begin(args.getString("host"),args.optInt("port",PORT));case "device.poll":return poll(args.getString("id"));case "device.pending":return new JSONObject().put("pending",pending());case "device.decide":if(!args.optBoolean("confirm"))throw new Exception("授权变更需要明确确认");return decide(args.getString("id"),args.getString("mode"));default:return AppRemote.request(args);}}
        if(!METHODS.contains(method))throw new Exception("未知控制方法。");if(method.equals("info"))return info();if(method.equals("presence"))return presence(owner,args);
        if(method.startsWith("terminal.")){JSONObject values=new JSONObject(args.toString());if(method.equals("terminal.open"))values.put("cwd",workspace());return new PrivilegeManager(app).terminal(method.substring(9),values,owner,mode);}
        if(!method.equals("execute"))throw new Exception("未知控制方法。");String tool=args.optString("tool");JSONObject values=args.optJSONObject("arguments");if(!TOOLS.contains(tool)||values==null)throw new Exception("无效的控制工具。");
        if(tool.startsWith("screen_")){if(!prefs.getBoolean("remoteScreen",false))throw new Exception("手机尚未允许远程屏幕控制。");if(args.optString("actor").equals("ai"))presence(owner,new JSONObject().put("actor","ai").put("active",true).put("lease_seconds",6));else if(!tool.equals("screen_capture"))manualLeases.begin(owner,2000,System.nanoTime());}
        values=new JSONObject(values.toString());if(tool.equals("run_shell")&&!values.has("timeout"))values.put("timeout",values.optInt("timeout_seconds",30));JSONObject result=new AgentTools(app,mode,workspace()).execute(tool,values,cancelled);if(tool.equals("read_file")&&result.has("content")&&!result.has("text"))result.put("text",result.optString("content"));return result;
    }
    private void stream(Socket socket,JSONObject peer,JSONObject request)throws Exception{
        if(!prefs.getBoolean("remoteScreen",false))throw new Exception("Screen unavailable");if(streams.incrementAndGet()>2){streams.decrementAndGet();throw new Exception("Screen unavailable");}
        String owner=peer.getString("id");AtomicBoolean cancelled=new AtomicBoolean();ownerJobs(owner).add(cancelled);PrivilegeManager.Mode mode=new PrivilegeManager(app).getMode();AtomicLong sent=new AtomicLong(System.currentTimeMillis());ScheduledFuture<?> check=timers.scheduleAtFixedRate(()->{if(!authorised(owner)||!prefs.getBoolean("remoteScreen",false)||new PrivilegeManager(app).getMode()!=mode||System.currentTimeMillis()-sent.get()>15000){cancelled.set(true);try{socket.close();}catch(Exception ignored){}}},300,300,TimeUnit.MILLISECONDS);
        boolean wroteHeader=false;try{
            JSONObject capture=new AgentTools(app,mode,workspace()).execute("screen_capture",new JSONObject(),cancelled);if(capture.has("error")||!capture.has("image_base64"))throw new Exception("Screen unavailable");socket.setSendBufferSize(128*1024);socket.setSoTimeout(0);OutputStream out=socket.getOutputStream();out.write("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".getBytes(StandardCharsets.US_ASCII));wroteHeader=true;int sequence=0;
            while(!cancelled.get()&&authorised(owner)){
                byte[] jpeg=RemoteControlWire.unb64(capture.getString("image_base64"));byte[] frame=RemoteControlWire.sealFrame(peer.getString("key"),request.getString("id"),++sequence,jpeg,capture.optInt("width"),capture.optInt("height"),sequence);if(frame.length>RemoteControlWire.LIMIT)throw new Exception("Screen frame too large");out.write(ByteBuffer.allocate(4).putInt(frame.length).array());out.write(frame);out.flush();sent.set(System.currentTimeMillis());lastAuthenticated=System.currentTimeMillis();lastAuthenticatedOwner=peer.getString("id");connectedName=peer.optString("name");renew(owner);Thread.sleep(mode==PrivilegeManager.Mode.NORMAL?350:40);capture=new AgentTools(app,mode,workspace()).execute("screen_capture",new JSONObject(),cancelled);if(capture.has("error")||!capture.has("image_base64"))break;
            }
        }finally{if(wroteHeader)try{socket.close();}catch(Exception ignored){}cancelled.set(true);check.cancel(false);streams.decrementAndGet();Set<AtomicBoolean> work=jobs.get(owner);if(work!=null){work.remove(cancelled);if(work.isEmpty())jobs.remove(owner,work);}}
    }
    public JSONObject begin(String host,int port)throws Exception{return begin(host,port,null);}
    public JSONObject begin(String host,int port,String expectedDeviceId)throws Exception{
        JSONObject remote=http(host,port,"GET","/info",null,8000);if(remote.optInt("agentgo")!=1||remote.optInt("pairing")!=2)throw new Exception("对方不是支持配对的 AsterHand 设备。");if(!remote.optBoolean("available",true))throw new Exception("对方未开启后台连接，请先打开应用。");String remoteID=RemoteControlWire.deviceID(remote.optString("public_key"));if((expectedDeviceId!=null&&!remoteID.equals(expectedDeviceId))||!remoteID.equals(remote.optString("device_id"))||remoteID.equals(identity().getString("device_id")))throw new Exception("设备身份无效，或选择了本机。");
        if(outgoing.size()>=8)throw new Exception("已有多个连接申请，请等待处理。");Pending p=new Pending();p.id=UUID.randomUUID().toString();p.host=host;p.port=port;p.name=cleanName(remote.optString("name"));p.device=remoteID;p.publicKey=remote.getString("public_key");p.created=now();synchronized(lock){p.key=RemoteControlWire.pairingSecret(state.getJSONObject("identity"),remote,p.id);}outgoing.put(p.id,p);return pollInternal(p.id,true);
    }
    public JSONObject poll(String id)throws Exception{return pollInternal(id,false);}
    private JSONObject pollInternal(String id,boolean first)throws Exception{
        Pending p=outgoing.get(id);if(p==null||now()-p.created>120)throw new Exception("连接申请已过期。");String nonce=UUID.randomUUID().toString();JSONObject request=new JSONObject().put("id",nonce).put("ts",now()).put("method",first?"pair.request":"pair.status").put("args",new JSONObject().put("receiver_id",p.device).put("name",identity().optString("name")).put("port",PORT));JSONObject envelope=http(p.host,p.port,"POST","/pair",new JSONObject().put("v",2).put("request",p.id).put("identity",advertised()).put("packet",RemoteControlWire.seal(p.id,p.key,request,"req")),8000);JSONObject response=RemoteControlWire.open(envelope,p.key,"res");JSONObject result=response.optJSONObject("result"),receiver=result==null?null:result.optJSONObject("receiver");if(!envelope.optString("pair").equals(p.id)||!response.optString("id").equals(nonce)||receiver==null||!receiver.optString("device_id").equals(p.device)||!receiver.optString("public_key").equals(p.publicKey))throw new Exception("连接响应身份不匹配。");String status=result.optString("status"),mode=result.optString("mode");
        if(status.equals("accepted")){if(!mode.equals("once")&&!mode.equals("always"))throw new Exception("无效的连接授权。");synchronized(lock){JSONArray all=state.getJSONArray("peers"),next=new JSONArray();for(int i=0;i<all.length();i++){JSONObject old=all.getJSONObject(i);if(!old.optString("device_id").equals(p.device)||old.optBoolean("incoming",true))next.put(old);}next.put(new JSONObject().put("id",p.id).put("key",p.key).put("name",p.name).put("host",p.host).put("port",p.port).put("device_id",p.device).put("public_key",p.publicKey).put("mode",mode).put("incoming",false));state.put("peers",next);save();}outgoing.remove(id);}else if(status.equals("denied"))outgoing.remove(id);
        return new JSONObject().put("id",id).put("status",status).put("mode",mode).put("code",RemoteControlWire.code(p.key)).put("device_id",p.device);
    }
    public JSONObject execute(String device,String method,JSONObject args)throws Exception{return request(device,method,args);}
    public JSONObject execute(String device,String method,JSONObject args,AtomicBoolean cancelled)throws Exception{return request(device,method,args,cancelled);}
    public JSONObject request(String id,String method,JSONObject args)throws Exception{return request(id,method,args,null);}
    public JSONObject request(String id,String method,JSONObject args,AtomicBoolean cancelled)throws Exception{
        checkCancelled(cancelled);
        if(!METHODS.contains(method))throw new Exception("不允许此远程控制方法。");JSONObject peer;synchronized(lock){JSONObject value=findPeer(id);if(value==null||value.optBoolean("incoming",true))throw new Exception("请先向此设备申请连接。");peer=new JSONObject(value.toString());}JSONObject values=args==null?new JSONObject():new JSONObject(args.toString());if(method.equals("info"))values.put("identity",advertised());String nonce=UUID.randomUUID().toString();JSONObject packet=RemoteControlWire.seal(peer.getString("id"),peer.getString("key"),new JSONObject().put("id",nonce).put("ts",now()).put("method",method).put("args",values),"req");JSONObject envelope=http(peer.getString("host"),peer.optInt("port",PORT),"POST","/rpc",packet,130000,cancelled);JSONObject response=RemoteControlWire.open(envelope,peer.getString("key"),"res");if(!envelope.optString("pair").equals(peer.getString("id"))||!response.optString("id").equals(nonce))throw new Exception("远程响应身份不匹配。");JSONObject result=response.optJSONObject("result");if(result==null)throw new Exception("远程响应格式无效。");if(method.equals("info")){if(!peer.optString("device_id").equals(result.optString("device_id"))||!peer.optString("public_key").equals(result.optString("public_key")))throw new Exception("远程设备身份已经改变。");String name=result.optString("name");if(!name.isEmpty()&&name.length()<=80)synchronized(lock){JSONObject current=findPeer(peer.getString("id"));if(current!=null){current.put("name",name);save();}}}if(method.equals("session.close")&&peer.optString("mode").equals("once"))revoke(peer.getString("id"));return result;
    }
    private static JSONArray addresses()throws Exception{JSONArray result=new JSONArray();Enumeration<NetworkInterface> all=NetworkInterface.getNetworkInterfaces();while(all!=null&&all.hasMoreElements()){NetworkInterface n=all.nextElement();if(!n.isUp()||n.isLoopback())continue;String name=n.getName().toLowerCase(Locale.ROOT);if(!name.matches("(wlan|wifi|eth|ap|rndis|en|usb).*"))continue;for(InterfaceAddress value:n.getInterfaceAddresses()){InetAddress address=value.getAddress();if(address instanceof Inet4Address&&address.isSiteLocalAddress())result.put(address.getHostAddress());}}return result;}
    public JSONArray discover()throws Exception{
        JSONArray local=addresses();Set<String> targets=new LinkedHashSet<>();
        // Known addresses are only scan hints: every response still has its public-key identity checked.
        synchronized(lock){JSONArray peers=state.optJSONArray("peers");if(peers!=null)for(int i=0;i<peers.length();i++){JSONObject peer=peers.optJSONObject(i);String host=peer==null?"":peer.optString("host");for(int j=0;j<local.length();j++){String own=local.getString(j),prefix=own.substring(0,own.lastIndexOf('.')+1);if(host.startsWith(prefix)&&!host.equals(own)&&host.matches("(?:[0-9]{1,3}\\.){3}[0-9]{1,3}"))targets.add(host);}}}
        Set<String> known=new LinkedHashSet<>(targets);for(int i=0;i<local.length();i++){String own=local.getString(i),prefix=own.substring(0,own.lastIndexOf('.')+1);for(int n=1;n<255;n++){String candidate=prefix+n;if(!candidate.equals(own))targets.add(candidate);if(targets.size()>=508)break;}}
        ConcurrentMap<String,JSONObject> found=new ConcurrentHashMap<>();
        // Probe remembered peers before the subnet sweep, so Wi-Fi ARP traffic
        // cannot starve devices that are waking from power save.
        ExecutorService priority=Executors.newFixedThreadPool(4);for(String host:known)priority.submit(()->discoverHost(found,host,3000));priority.shutdown();if(!priority.awaitTermination(5,TimeUnit.SECONDS))priority.shutdownNow();
        ExecutorService scan=Executors.newFixedThreadPool(32);for(String host:targets)if(!known.contains(host))scan.submit(()->discoverHost(found,host,1000));
        scan.shutdown();if(!scan.awaitTermination(25,TimeUnit.SECONDS)){scan.shutdownNow();throw new Exception("设备搜索超时，请重试。");}JSONArray result=new JSONArray();for(JSONObject info:found.values())result.put(info);return result;
    }
    private static void discoverHost(ConcurrentMap<String,JSONObject> found,String host,int timeout){try{JSONObject info=http(host,PORT,"GET","/info",null,timeout);String id=RemoteControlWire.deviceID(info.optString("public_key"));if(info.optInt("agentgo")==1&&info.optInt("pairing")==2&&id.equals(info.optString("device_id")))found.put(id,info.put("host",host));}catch(Exception ignored){}}
}
