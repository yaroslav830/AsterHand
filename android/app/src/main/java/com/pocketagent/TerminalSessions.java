package com.pocketagent;

import android.os.SystemClock;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Persistent command shells, intentionally not a PTY/VT emulator. */
final class TerminalSessions {
    private static final HashMap<String,Session> sessions=new HashMap<>();
    private static final int CAPACITY=262144;
    private static final long IDLE=20*60*1000L;
    static {
        Thread reaper=new Thread(()->{while(true){SystemClock.sleep(30000);ArrayList<Session> stale=new ArrayList<>();synchronized(sessions){long now=SystemClock.elapsedRealtime();for(Session session:sessions.values())if(now-session.touched>IDLE)stale.add(session);for(Session session:stale)sessions.remove(session.id);}for(Session session:stale)session.close();}},"AsterHand-terminal-idle");reaper.setDaemon(true);reaper.start();
    }
    static JSONObject invoke(String action,JSONObject args,String owner,PrivilegeManager.Mode mode)throws Exception{
        if(owner==null||owner.isEmpty()||owner.length()>128)throw new Exception("终端所有者无效。");
        if(action.equals("open")){
            synchronized(sessions){if(sessions.size()>=8)throw new Exception("最多同时打开 8 个终端。");Session session=new Session(mode,owner,args.optString("cwd","/"));sessions.put(session.id,session);return session.read(0);}
        }
        String id=args.optString("session",args.optString("id"));Session session;
        synchronized(sessions){session=sessions.get(id);}
        if(session==null)throw new Exception("终端已关闭或已过期。");if(!session.owner.equals(owner)||session.mode!=mode)throw new Exception("此终端不属于当前连接或权限级别。");
        session.touched=SystemClock.elapsedRealtime();
        if(action.equals("read"))return session.read(Math.max(0,args.optLong("offset",0)));
        if(action.equals("write")){String text=args.optString("text");byte[] bytes=text.getBytes(StandardCharsets.UTF_8);if(bytes.length>65536)throw new Exception("单次终端输入上限为 64 KiB。");session.write(bytes);return session.read(Math.max(0,args.optLong("offset",session.end())));}
        if(action.equals("close")||action.equals("interrupt")){
            synchronized(sessions){sessions.remove(id);}session.close();return new JSONObject().put("session",id).put("mode",mode.name()).put("uid",session.uid).put("closed",true).put("interrupted",action.equals("interrupt"));
        }
        throw new Exception("未知终端操作。");
    }
    static void closeAbove(PrivilegeManager.Mode level){
        ArrayList<Session> closing=new ArrayList<>();synchronized(sessions){for(Session session:sessions.values())if(session.mode.ordinal()>level.ordinal())closing.add(session);for(Session session:closing)sessions.remove(session.id);}for(Session session:closing)session.close();
    }
    static void closeAll(){ArrayList<Session> closing;synchronized(sessions){closing=new ArrayList<>(sessions.values());sessions.clear();}for(Session session:closing)session.close();}
    static void closeOwner(String owner){ArrayList<Session> closing=new ArrayList<>();synchronized(sessions){for(Session session:sessions.values())if(session.owner.equals(owner))closing.add(session);for(Session session:closing)sessions.remove(session.id);}for(Session session:closing)session.close();}
    private static boolean alive(java.lang.Process process){try{process.exitValue();return false;}catch(IllegalThreadStateException running){return true;}}
    private static final class Session {
        final String id=UUID.randomUUID().toString(),owner;
        final PrivilegeManager.Mode mode;
        final java.lang.Process process;
        final byte[] ring=new byte[CAPACITY];
        long base=0,limit=0;volatile long touched=SystemClock.elapsedRealtime();
        volatile int uid=-1,pid=-1;volatile boolean closed=false;
        final boolean group;
        final CountDownLatch ready=new CountDownLatch(1);
        Session(PrivilegeManager.Mode mode,String owner,String cwd)throws Exception{
            this.mode=mode;this.owner=owner;group=new File("/system/bin/setsid").canExecute();
            String shell="cd "+PrivilegedOperations.quote(new File(cwd).getCanonicalPath())+" || exit 126; printf '__ASTERHAND_TERMINAL__%s:%s\\n' \"$(id -u)\" \"$$\"; exec /system/bin/sh";
            String launch=(group?"/system/bin/setsid ":"")+"/system/bin/sh -c "+PrivilegedOperations.quote(shell);
            process=mode==PrivilegeManager.Mode.ROOT?new ProcessBuilder(RootBinaries.su(),"-c",launch).start():new ProcessBuilder("/system/bin/sh","-c","exec "+launch).start();
            Thread stdout=new Thread(()->{try(InputStream input=process.getInputStream()){
                ByteArrayOutputStream header=new ByteArrayOutputStream();int value;while((value=input.read())!=-1&&value!='\n'){if(header.size()>120)throw new IOException("Invalid terminal identity");header.write(value);}
                String line=header.toString("UTF-8");if(!line.matches("__ASTERHAND_TERMINAL__[0-9]+:[0-9]+"))throw new IOException("Terminal identity missing");String[] identity=line.substring("__ASTERHAND_TERMINAL__".length()).split(":");uid=Integer.parseInt(identity[0]);pid=Integer.parseInt(identity[1]);ready.countDown();drain(input);
            }catch(Exception ignored){}finally{ready.countDown();}},"AsterHand-terminal-stdout");stdout.setDaemon(true);stdout.start();
            Thread stderr=new Thread(()->{try(InputStream input=process.getErrorStream()){drain(input);}catch(Exception ignored){}},"AsterHand-terminal-stderr");stderr.setDaemon(true);stderr.start();
            int expected=mode==PrivilegeManager.Mode.ROOT?0:mode==PrivilegeManager.Mode.ADB?2000:android.os.Process.myUid();
            if(!ready.await(8,TimeUnit.SECONDS)||uid!=expected||pid<2){close();throw new Exception("终端身份校验失败；当前权限未建立。");}
        }
        void drain(InputStream input)throws Exception{byte[] bytes=new byte[4096];int count;while((count=input.read(bytes))!=-1)append(bytes,count);}
        synchronized void append(byte[] bytes,int count){for(int i=0;i<count;i++){ring[(int)(limit%CAPACITY)]=bytes[i];limit++;if(limit-base>CAPACITY)base=limit-CAPACITY;}}
        synchronized long end(){return limit;}
        synchronized JSONObject read(long offset)throws Exception{
            long from=Math.max(base,Math.min(limit,offset));int count=(int)(limit-from);byte[] bytes=new byte[count];for(int i=0;i<count;i++)bytes[i]=ring[(int)((from+i)%CAPACITY)];
            return new JSONObject().put("session",id).put("mode",mode.name()).put("uid",uid).put("pid",pid).put("output",new String(bytes,StandardCharsets.UTF_8)).put("base_offset",base).put("next_offset",limit).put("truncated",offset<base).put("running",!closed&&alive(process)).put("pty",false);
        }
        synchronized void write(byte[] bytes)throws Exception{if(closed||!alive(process))throw new Exception("终端进程已结束。");process.getOutputStream().write(bytes);process.getOutputStream().flush();}
        void signal(String signal){
            if(pid<2)return;String command="/system/bin/kill "+signal+" -- "+(group?"-":"")+pid;
            try{java.lang.Process killer=mode==PrivilegeManager.Mode.ROOT?new ProcessBuilder(RootBinaries.su(),"-c",command).start():new ProcessBuilder("/system/bin/sh","-c",command).start();long until=SystemClock.elapsedRealtime()+750;while(alive(killer)&&SystemClock.elapsedRealtime()<until)SystemClock.sleep(20);if(alive(killer))killer.destroy();}catch(Exception ignored){}
        }
        void close(){
            if(closed)return;closed=true;signal("-TERM");SystemClock.sleep(100);signal("-KILL");
            try{process.getOutputStream().close();process.getInputStream().close();process.getErrorStream().close();}catch(Exception ignored){}if(alive(process))process.destroy();
        }
    }
}
