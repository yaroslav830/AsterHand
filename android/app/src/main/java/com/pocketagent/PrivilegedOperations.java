package com.pocketagent;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.SystemClock;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructStat;
import android.util.Base64;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/** Operations shared by the app UID, the shell bridge and the short-lived Root worker. */
final class PrivilegedOperations {
    static final int MAX_FRAME=10*1024*1024;
    static JSONObject readFrame(InputStream input)throws Exception{
        DataInputStream stream=new DataInputStream(input);int length=stream.readInt();
        if(length<2||length>MAX_FRAME)throw new IOException("Invalid IPC frame length");
        byte[] bytes=new byte[length];stream.readFully(bytes);return new JSONObject(new String(bytes,StandardCharsets.UTF_8));
    }
    static void writeFrame(OutputStream output,JSONObject value)throws Exception{
        byte[] bytes=value.toString().getBytes(StandardCharsets.UTF_8);if(bytes.length>MAX_FRAME)throw new IOException("IPC response exceeds limit");
        DataOutputStream stream=new DataOutputStream(output);stream.writeInt(bytes.length);stream.write(bytes);stream.flush();
    }
    static byte[] readLimited(InputStream input,int limit)throws Exception{
        try(InputStream stream=input;ByteArrayOutputStream out=new ByteArrayOutputStream()){
            byte[] bytes=new byte[8192];int count;while((count=stream.read(bytes))!=-1){if(out.size()+count>limit)throw new IOException("File exceeds read limit");out.write(bytes,0,count);}return out.toByteArray();
        }
    }
    static String quote(String value){return "'"+value.replace("'","'\\''")+"'";}
    static JSONObject execute(PrivilegeManager.Mode mode,JSONObject operation,AtomicBoolean cancelled)throws Exception{
        int uid=android.os.Process.myUid();
        if(mode==PrivilegeManager.Mode.ADB&&uid!=2000||mode==PrivilegeManager.Mode.ROOT&&uid!=0||mode==PrivilegeManager.Mode.NORMAL&&uid<10000)throw new Exception("Executor UID does not match selected tier");
        if(cancelled.get())throw new Exception("操作已停止。");
        String kind=operation.optString("kind");JSONObject result;
        if(kind.equals("probe"))result=new JSONObject().put("available",true);
        else if(kind.equals("terminal"))result=TerminalSessions.invoke(operation.optString("action"),operation.optJSONObject("args"),operation.optString("owner"),mode);
        else if(kind.equals("terminal_cleanup")){TerminalSessions.closeAll();result=new JSONObject().put("closed",true);}
        else if(kind.equals("terminal_owner_cleanup")){TerminalSessions.closeOwner(operation.optString("owner"));result=new JSONObject().put("closed",true);}
        else if(kind.equals("shell"))result=shell(operation.optString("command"),operation.optString("cwd"),operation.optInt("timeout",120),cancelled);
        else if(kind.equals("tool")){
            String name=operation.optString("name");JSONObject args=operation.optJSONObject("args");if(args==null)args=new JSONObject();
            if(name.startsWith("screen_"))result=screen(name,args,cancelled);
            else result=fileTool(operation.optString("workspace"),name,args,cancelled,operation.getJSONArray("file_exclusions"));
        }else throw new Exception("未知执行请求。");
        return result.put("uid",uid).put("mode",mode.name());
    }
    static Thread drain(InputStream stream,ByteArrayOutputStream out,int limit){
        Thread thread=new Thread(()->{try(InputStream input=stream){byte[] bytes=new byte[8192];int count;while((count=input.read(bytes))!=-1){synchronized(out){if(out.size()<limit)out.write(bytes,0,Math.min(count,limit-out.size()));}}}catch(Exception ignored){}},"AsterHand-output");thread.setDaemon(true);thread.start();return thread;
    }
    private static boolean alive(java.lang.Process process){try{process.exitValue();return false;}catch(IllegalThreadStateException running){return true;}}
    private static void signalGroup(int pid,boolean group,String signal){
        if(pid<2)return;
        try{
            java.lang.Process killer=new ProcessBuilder("/system/bin/kill",signal,"--",group?"-"+pid:Integer.toString(pid)).start();
            long until=SystemClock.elapsedRealtime()+500;while(alive(killer)&&SystemClock.elapsedRealtime()<until)SystemClock.sleep(15);if(alive(killer))killer.destroy();
        }catch(Exception ignored){}
    }
    static JSONObject shell(String command,String cwd,int timeoutSeconds,AtomicBoolean cancelled)throws Exception{
        if(command==null||command.trim().isEmpty())throw new Exception("命令不能为空。");if(command.length()>8192)throw new Exception("命令超过 8192 字符。");
        if(cwd==null||cwd.isEmpty())throw new Exception("工作目录不能为空。");File directory=new File(cwd).getCanonicalFile();if(!directory.isDirectory())throw new Exception("工作目录不存在或当前权限无法访问。");
        int timeout=Math.max(1,Math.min(120,timeoutSeconds));boolean group=new File("/system/bin/setsid").canExecute();
        String wrapper="printf '__ASTERHAND_PID__%s\\n' \"$$\"; exec /system/bin/sh -c "+quote(command);
        ArrayList<String> argv=new ArrayList<>();if(group)argv.add("/system/bin/setsid");argv.add("/system/bin/sh");argv.add("-c");argv.add(wrapper);
        java.lang.Process process=new ProcessBuilder(argv).directory(directory).start();
        ByteArrayOutputStream stdout=new ByteArrayOutputStream(),stderr=new ByteArrayOutputStream();AtomicInteger pid=new AtomicInteger(0);
        Thread out=new Thread(()->{try(InputStream input=process.getInputStream()){
            ByteArrayOutputStream first=new ByteArrayOutputStream();int value;while((value=input.read())!=-1&&value!='\n'){if(first.size()>100)throw new IOException("Invalid worker header");first.write(value);}
            String header=first.toString("UTF-8");if(!header.matches("__ASTERHAND_PID__[0-9]+"))throw new IOException("Invalid worker identity");pid.set(Integer.parseInt(header.substring("__ASTERHAND_PID__".length())));
            byte[] bytes=new byte[4096];int count;while((count=input.read(bytes))!=-1){synchronized(stdout){if(stdout.size()<65536)stdout.write(bytes,0,Math.min(count,65536-stdout.size()));}}
        }catch(Exception ignored){}},"AsterHand-command-output");out.setDaemon(true);out.start();Thread err=drain(process.getErrorStream(),stderr,65536);
        long deadline=SystemClock.elapsedRealtime()+timeout*1000L;boolean timedOut=false,stopped=false;
        try{
            while(alive(process)){
                if(cancelled.get()){stopped=true;break;}if(SystemClock.elapsedRealtime()>=deadline){timedOut=true;break;}SystemClock.sleep(25);
            }
            if(timedOut||stopped){signalGroup(pid.get(),group,"-TERM");process.destroy();SystemClock.sleep(150);signalGroup(pid.get(),group,"-KILL");}
            out.join(700);err.join(700);
            // A bounded noninteractive command must not leave inherited output pipes open.
            if(out.isAlive()||err.isAlive()){signalGroup(pid.get(),group,"-TERM");SystemClock.sleep(50);signalGroup(pid.get(),group,"-KILL");}
            int exit=stopped?130:timedOut?124:alive(process)?124:process.exitValue();
            String output,error;synchronized(stdout){output=stdout.toString("UTF-8");}synchronized(stderr){error=stderr.toString("UTF-8");}
            return new JSONObject().put("exit_code",exit).put("timed_out",timedOut).put("cancelled",stopped).put("stdout",output).put("stderr",error).put("output",output+(error.isEmpty()?"":"\n"+error)).put("truncated",stdout.size()>=65536||stderr.size()>=65536);
        }finally{
            try{process.getOutputStream().close();process.getInputStream().close();process.getErrorStream().close();}catch(Exception ignored){}if(alive(process))process.destroy();
        }
    }
    private static boolean symlink(File file){try{return OsConstants.S_ISLNK(Os.lstat(file.getAbsolutePath()).st_mode);}catch(Exception ignored){return false;}}
    private static File resolve(File root,String path)throws Exception{
        if(path==null||path.isEmpty())throw new Exception("路径不能为空。");File raw=new File(path);if(!raw.isAbsolute())raw=new File(root,path);if(symlink(raw))throw new Exception("拒绝符号链接目标。");
        File target=raw.getCanonicalFile();String base=root.getCanonicalPath();if(!target.getPath().equals(base)&&!target.getPath().startsWith(base+File.separator))throw new Exception("路径必须位于当前项目内。");return target;
    }
    static boolean isFileTool(String name){return name.equals("read_file")||name.equals("write_file")||name.equals("list_directory");}
    private static boolean inTree(String path,String root){return path.equals(root)||path.startsWith(root+File.separator);}
    private static boolean excluded(File target,JSONArray exclusions,boolean hideBranches)throws Exception{
        String path=target.getCanonicalPath();
        for(int i=0;i<exclusions.length();i++){String value=exclusions.getString(i);if(!new File(value).isAbsolute())throw new Exception("项目文件围栏格式无效。");String root=new File(value).getCanonicalPath();if(inTree(path,root)||(hideBranches&&inTree(root,path)))return true;}
        return false;
    }
    private static File scopedTarget(String workspace,String name,JSONObject args,JSONArray exclusions)throws Exception{
        File root=new File(workspace).getCanonicalFile(),target=resolve(root,args.optString("path",name.equals("list_directory")?".":""));
        if(excluded(target,exclusions,false))throw new Exception("此目录属于其他项目，当前项目不能通过文件工具访问。");return target;
    }
    static void validateFileRequest(JSONObject operation)throws Exception{
        String name=operation.getString("name");if(!isFileTool(name))throw new Exception("未知文件工具。");scopedTarget(operation.getString("workspace"),name,operation.getJSONObject("args"),operation.getJSONArray("file_exclusions"));
    }
    /** Filter at the App boundary too: an older authenticated executor may lack this fence. */
    static JSONObject filterFileResult(String workspace,String name,JSONObject args,JSONArray exclusions,JSONObject result)throws Exception{
        File target=scopedTarget(workspace,name,args,exclusions);if(!name.equals("list_directory")||result.has("error"))return result;
        JSONArray entries=result.optJSONArray("entries");if(entries==null)throw new Exception("文件执行器没有返回有效目录列表。");JSONArray visible=new JSONArray();File root=new File(workspace).getCanonicalFile();
        for(int i=0;i<entries.length();i++){JSONObject entry=entries.getJSONObject(i);String child=entry.getString("name");if(child.isEmpty()||child.equals(".")||child.equals("..")||child.indexOf('/')>=0||child.indexOf('\\')>=0)throw new Exception("文件执行器返回了无效条目。");File file=new File(target,child);if(inTree(file.getCanonicalPath(),root.getPath())&&!excluded(file,exclusions,true))visible.put(entry);}
        result.put("entries",visible);return result;
    }
    private static void makeDirectories(File directory)throws Exception{
        if(directory.isDirectory())return;
        ArrayList<File> missing=new ArrayList<>();File ancestor=directory;while(ancestor!=null&&!ancestor.exists()){missing.add(ancestor);ancestor=ancestor.getParentFile();}
        StructStat owner=null;try{if(ancestor!=null)owner=Os.stat(ancestor.getPath());}catch(Exception ignored){}
        for(int i=missing.size()-1;i>=0;i--){File next=missing.get(i);if(!next.mkdir()&&!next.isDirectory())throw new IOException("当前权限无法创建目录。");if(android.os.Process.myUid()==0&&owner!=null)try{Os.chown(next.getPath(),owner.st_uid,owner.st_gid);}catch(Exception ignored){}}
    }
    private static void copy(File source,File target)throws Exception{
        try(InputStream input=new FileInputStream(source);FileOutputStream output=new FileOutputStream(target)){
            byte[] bytes=new byte[8192];int count;while((count=input.read(bytes))!=-1)output.write(bytes,0,count);output.getFD().sync();
        }
    }
    static JSONObject fileTool(String workspace,String name,JSONObject args,AtomicBoolean cancelled,JSONArray exclusions)throws Exception{
        File root=new File(workspace).getCanonicalFile(),target=scopedTarget(workspace,name,args,exclusions);makeDirectories(root);
        if(name.equals("read_file")){
            if(!target.isFile())throw new Exception("目标不是可读取的普通文件。");if(target.length()>49152)throw new Exception("单次读取上限为 48 KiB。");
            byte[] bytes=readLimited(new FileInputStream(target),49152);return new JSONObject().put("path",target.getPath()).put("content",new String(bytes,StandardCharsets.UTF_8)).put("bytes",bytes.length);
        }
        if(name.equals("list_directory")){
            if(!target.isDirectory())throw new Exception("目标不是可访问的目录。");File[] entries=target.listFiles();if(entries==null)throw new Exception("当前权限无法读取此目录。");Arrays.sort(entries,(a,b)->a.getName().compareToIgnoreCase(b.getName()));JSONArray list=new JSONArray();
            int shown=0;for(File f:entries){if(excluded(f,exclusions,true))continue;if(++shown<=200)list.put(new JSONObject().put("name",f.getName()).put("type",symlink(f)?"symlink":f.isDirectory()?"directory":"file").put("bytes",f.isFile()?f.length():0));}
            return new JSONObject().put("path",target.getPath()).put("entries",list).put("truncated",shown>200);
        }
        if(name.equals("write_file")){
            byte[] bytes=args.optString("content").getBytes(StandardCharsets.UTF_8);if(bytes.length>262144)throw new Exception("单次写入上限为 256 KiB。");File parent=target.getParentFile();if(parent==null)throw new Exception("缺少父目录。");makeDirectories(parent);
            if(target.exists()&&!target.isFile())throw new Exception("拒绝覆盖特殊文件。");boolean existed=target.exists();StructStat owner=Os.stat(existed?target.getPath():parent.getPath());String backup="";
            if(target.exists()){if(target.length()>8*1024*1024)throw new Exception("原文件过大，无法建立自动备份。");backup=target.getName()+".asterhand-backup-"+UUID.randomUUID();File backupFile=new File(parent,backup);copy(target,backupFile);if(android.os.Process.myUid()==0)try{Os.chown(backupFile.getPath(),owner.st_uid,owner.st_gid);Os.chmod(backupFile.getPath(),owner.st_mode&0777);}catch(Exception ignored){}}
            File temporary=File.createTempFile(".asterhand-",".tmp",parent);
            try{try(FileOutputStream output=new FileOutputStream(temporary)){output.write(bytes);output.getFD().sync();}if(cancelled.get())throw new Exception("写入已停止，原文件未替换。");if(!temporary.renameTo(target))throw new IOException("无法原子替换目标文件。");if(android.os.Process.myUid()==0)try{Os.chown(target.getPath(),owner.st_uid,owner.st_gid);Os.chmod(target.getPath(),existed?owner.st_mode&0777:0600);}catch(Exception ignored){}}
            finally{temporary.delete();}
            return new JSONObject().put("path",target.getPath()).put("backup",backup).put("bytes",bytes.length);
        }
        throw new Exception("未知文件工具："+name);
    }
    private static byte[] capturePng(AtomicBoolean cancelled)throws Exception{
        java.lang.Process process=new ProcessBuilder("/system/bin/screencap","-p").start();ByteArrayOutputStream bytes=new ByteArrayOutputStream(),errors=new ByteArrayOutputStream();Thread out=drain(process.getInputStream(),bytes,8*1024*1024),err=drain(process.getErrorStream(),errors,8192);long deadline=SystemClock.elapsedRealtime()+10000;
        try{while(alive(process)&&SystemClock.elapsedRealtime()<deadline&&!cancelled.get())SystemClock.sleep(25);if(alive(process)){process.destroy();throw new Exception(cancelled.get()?"截图已停止。":"截图超时。");}out.join(1000);err.join(1000);byte[] result=bytes.toByteArray();if(process.exitValue()!=0||result.length<32||result[0]!=(byte)137||result[1]!=80)throw new Exception("当前执行器无法采集屏幕；请检查系统屏幕权限。");return result;}
        finally{try{process.getInputStream().close();process.getErrorStream().close();}catch(Exception ignored){}}
    }
    private static int[] dimensions(byte[] png)throws Exception{BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(png,0,png.length,options);if(options.outWidth<1||options.outHeight<1)throw new Exception("屏幕尺寸无效。");return new int[]{options.outWidth,options.outHeight};}
    private static double coordinate(JSONObject args,String key)throws Exception{double value=args.optDouble(key,Double.NaN);if(Double.isNaN(value)||Double.isInfinite(value)||value<0||value>1)throw new Exception("屏幕坐标必须介于 0 和 1。");return value;}
    private static int pixel(double value,int size){return (int)Math.round(value*Math.max(0,size-1));}
    private static JSONObject screen(String name,JSONObject args,AtomicBoolean cancelled)throws Exception{
        if(name.equals("screen_capture")){
            byte[] png=capturePng(cancelled);int[] bounds=dimensions(png);Bitmap bitmap=BitmapFactory.decodeByteArray(png,0,png.length);if(bitmap==null)throw new Exception("无法解码屏幕。");Bitmap image=bitmap;
            try{double factor=Math.min(1,1280.0/Math.max(bounds[0],bounds[1]));if(factor<1)image=Bitmap.createScaledBitmap(bitmap,Math.max(1,(int)(bounds[0]*factor)),Math.max(1,(int)(bounds[1]*factor)),true);ByteArrayOutputStream jpeg=new ByteArrayOutputStream();image.compress(Bitmap.CompressFormat.JPEG,75,jpeg);return new JSONObject().put("image_base64",Base64.encodeToString(jpeg.toByteArray(),Base64.NO_WRAP)).put("mime_type","image/jpeg").put("width",image.getWidth()).put("height",image.getHeight()).put("display_width",bounds[0]).put("display_height",bounds[1]);}
            finally{if(image!=bitmap)image.recycle();bitmap.recycle();}
        }
        String command;
        if(name.equals("screen_home"))command="/system/bin/input keyevent 3";
        else if(name.equals("screen_type")){
            if(args.optBoolean("replace",false))throw new Exception("覆盖输入框文字需要启用 AsterHand 辅助功能；未执行追加输入。");
            String text=args.optString("text");if(text.isEmpty()||text.length()>2000)throw new Exception("输入文字须为 1 至 2000 字。");if(!text.matches("[\\x20-\\x7e]+"))throw new Exception("Unicode 输入需要先启用 AsterHand 辅助功能。");command="/system/bin/input text "+quote(text.replace("%","\\%").replace(" ","%s"));
        }else if(name.equals("screen_tap")||name.equals("screen_swipe")){
            double x=coordinate(args,"x"),y=coordinate(args,"y");int[] bounds=dimensions(capturePng(cancelled));
            command="/system/bin/input "+(name.equals("screen_tap")?"tap ":"swipe ")+pixel(x,bounds[0])+" "+pixel(y,bounds[1]);
            if(name.equals("screen_swipe")){double x2=coordinate(args,"x2"),y2=coordinate(args,"y2"),duration=args.optDouble("duration",.4);if(Double.isNaN(duration)||Double.isInfinite(duration)||duration<.1||duration>2)throw new Exception("滑动时长须为 0.1 至 2 秒。");command+=" "+pixel(x2,bounds[0])+" "+pixel(y2,bounds[1])+" "+Math.round(duration*1000);}
        }else throw new Exception("未知屏幕工具。");
        JSONObject result=shell(command,"/",12,cancelled);if(result.optInt("exit_code")!=0)throw new Exception("系统输入执行失败："+result.optString("stderr"));return result.put("dispatched",true);
    }
}
