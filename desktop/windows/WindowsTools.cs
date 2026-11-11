using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace AsterHand {
    internal static class WindowsScreen {
        [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type;public INPUTUNION data; }
        [StructLayout(LayoutKind.Explicit)] struct INPUTUNION { [FieldOffset(0)]public MOUSEINPUT mouse;[FieldOffset(0)]public KEYBDINPUT key; }
        [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx,dy;public uint mouseData,dwFlags,time;public UIntPtr extra; }
        [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk,scan;public uint flags,time;public UIntPtr extra; }
        [DllImport("user32.dll",SetLastError=true)]static extern uint SendInput(uint count,INPUT[] inputs,int size);
        [DllImport("user32.dll")]static extern bool SetCursorPos(int x,int y);
        public static Dictionary<string,object> Capture() {var rect=Screen.PrimaryScreen.Bounds;using(var bitmap=new Bitmap(rect.Width,rect.Height))using(var graphics=Graphics.FromImage(bitmap)) {graphics.CopyFromScreen(rect.Location,Point.Empty,rect.Size);double ratio=Math.Min(1,1440.0/Math.Max(rect.Width,rect.Height));using(var scaled=new Bitmap(bitmap,new Size(Math.Max(1,(int)(rect.Width*ratio)),Math.Max(1,(int)(rect.Height*ratio)))))using(var output=new MemoryStream()) {var codec=ImageCodecInfo.GetImageEncoders().First(x=>x.MimeType=="image/jpeg");using(var parameters=new EncoderParameters(1)){parameters.Param[0]=new EncoderParameter(System.Drawing.Imaging.Encoder.Quality,65L);scaled.Save(output,codec,parameters);}return J.Obj("width",scaled.Width,"height",scaled.Height,"image_base64",Convert.ToBase64String(output.ToArray()));} } }
        static void Input(INPUT i) {if(SendInput(1,new[]{i},Marshal.SizeOf(typeof(INPUT)))!=1)throw new Exception("Windows 拒绝输入：目标窗口权限较高或屏幕已锁定。");}
        static void Mouse(uint flags) {Input(new INPUT{type=0,data=new INPUTUNION{mouse=new MOUSEINPUT{dwFlags=flags}}});}
        static void Key(ushort vk,ushort scan,uint flags) {Input(new INPUT{type=1,data=new INPUTUNION{key=new KEYBDINPUT{vk=vk,scan=scan,flags=flags}}});}
        static Point PointFor(object args,string x,string y) {if(J.Get(args,x)==null||J.Get(args,y)==null)throw new Exception("Missing coordinates");double a=J.Num(args,x,-1),b=J.Num(args,y,-1);if(double.IsNaN(a)||double.IsNaN(b)||a<0||a>1||b<0||b>1)throw new Exception("Coordinates must be 0..1");var r=Screen.PrimaryScreen.Bounds;return new Point(r.Left+Math.Min(r.Width-1,(int)(a*r.Width)),r.Top+Math.Min(r.Height-1,(int)(b*r.Height)));}
        public static object Execute(string tool,object args,CancellationToken ct) {ct.ThrowIfCancellationRequested();if(tool=="screen_capture")return Capture();if(tool=="screen_tap") {var p=PointFor(args,"x","y");SetCursorPos(p.X,p.Y);Mouse(2);try{}finally{Mouse(4);}return J.Obj("tapped",true);}
            if(tool=="screen_swipe") {var a=PointFor(args,"x","y");var b=PointFor(args,"x2","y2");SetCursorPos(a.X,a.Y);Mouse(2);try{for(int i=1;i<=20;i++){ct.ThrowIfCancellationRequested();SetCursorPos(a.X+(b.X-a.X)*i/20,a.Y+(b.Y-a.Y)*i/20);Thread.Sleep((int)(Math.Max(.1,Math.Min(2,J.Num(args,"duration",.3)))*50));}}finally{Mouse(4);}return J.Obj("swiped",true);}
            if(tool=="screen_type") {string text=J.Str(args,"text");if(text.Length>32768)throw new Exception("Text too long");foreach(char c in text){ct.ThrowIfCancellationRequested();Key(0,c,4);Key(0,c,6);}return J.Obj("typed",true);}
            if(tool=="screen_home") {Key(0x5b,0,0);try{Key(0x44,0,0);Key(0x44,0,2);}finally{Key(0x5b,0,2);}return J.Obj("desktop",true);}throw new Exception("Unknown screen tool"); }
    }

    internal sealed class TerminalSession : IDisposable {
        public readonly string Id=J.Id(),Owner;
        public DateTime Used=DateTime.UtcNow;
        public bool Ended;
        public int ExitCode=-1;
        Process process;readonly object gate=new object();byte[] output=new byte[0];long offset;
        public TerminalSession(string work,string owner) {Owner=owner;var start=new ProcessStartInfo("powershell.exe","-NoLogo -NoProfile -NonInteractive -NoExit -Command -") { UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=work,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8 };process=new Process{StartInfo=start,EnableRaisingEvents=true};process.Exited+=(s,e)=>{Ended=true;try{ExitCode=process.ExitCode;}catch{}};process.Start();Task.Run(()=>Pump(process.StandardOutput.BaseStream));Task.Run(()=>Pump(process.StandardError.BaseStream));Write("[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false; $OutputEncoding = [Console]::OutputEncoding\n");}
        async Task Pump(Stream stream) {var buffer=new byte[4096];try{int n;while((n=await stream.ReadAsync(buffer,0,buffer.Length).ConfigureAwait(false))>0){lock(gate){output=Wire.Join(output,buffer.Take(n).ToArray());if(output.Length>262144){int drop=output.Length-262144;offset+=drop;output=output.Skip(drop).ToArray();}}}}catch(ObjectDisposedException){}catch(IOException){} }
        public void Write(string text) {if(Ended)throw new Exception("终端已结束");if(text.Length>32768)throw new Exception("Terminal input too long");Used=DateTime.UtcNow;process.StandardInput.Write(text);process.StandardInput.Flush();}
        public object Read(long from) {Used=DateTime.UtcNow;lock(gate){return J.Obj("output",Encoding.UTF8.GetString(output.Skip((int)Math.Min(output.Length,Math.Max(0,from-offset))).ToArray()),"next_offset",offset+output.Length,"truncated",from<offset,"ended",Ended);}}
        public static void KillTree(Process child) {try{if(child.HasExited)return;using(var killer=Process.Start(new ProcessStartInfo("taskkill.exe","/PID "+child.Id+" /T /F"){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true})){killer.WaitForExit(4000);}if(!child.HasExited)child.Kill();}catch(InvalidOperationException){} }
        public void Dispose() {KillTree(process);process.Dispose();Ended=true;}
        public static async Task<object> Command(string command,string work,int seconds,CancellationToken ct) { if(string.IsNullOrWhiteSpace(command)||command.Length>32768)throw new Exception("Invalid command");string script="[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false; $OutputEncoding = [Console]::OutputEncoding; "+command;var p=new Process{StartInfo=new ProcessStartInfo("powershell.exe","-NoLogo -NoProfile -NonInteractive -EncodedCommand "+Convert.ToBase64String(Encoding.Unicode.GetBytes(script))) {UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=work,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8}};p.Start();var buffer=new StringBuilder();object sync=new object();bool overflow=false;Func<StreamReader,Task> pump=async reader=>{var b=new char[4096];int n;while((n=await reader.ReadAsync(b,0,b.Length).ConfigureAwait(false))>0){lock(sync){int remaining=65536-buffer.Length;buffer.Append(b,0,Math.Min(remaining,n));if(n>remaining){overflow=true;KillTree(p);}}}};var stdout=pump(p.StandardOutput);var stderr=pump(p.StandardError);bool timed=false;try{var watch=Stopwatch.StartNew();while(!p.HasExited){if(ct.IsCancellationRequested||watch.Elapsed.TotalSeconds>=seconds){timed=!ct.IsCancellationRequested;KillTree(p);break;}await Task.Delay(60).ConfigureAwait(false);}await Task.WhenAll(stdout,stderr).ConfigureAwait(false);return J.Obj("output",buffer.ToString(),"exit_code",p.HasExited?p.ExitCode:-1,"cancelled",ct.IsCancellationRequested,"error",timed?"Command timed out":overflow?"Output limit reached":ct.IsCancellationRequested?"Task stopped":"");}finally{if(!p.HasExited)KillTree(p);p.Dispose();} }
    }

    internal sealed class ToolHost : IDisposable {
        readonly Vault vault;readonly Dictionary<string,TerminalSession> terminals=new Dictionary<string,TerminalSession>();
        public Func<string> Workspace;
        public Action RequireAccess {get;set;}
        public ToolHost(Vault v) {vault=v;Workspace=()=>J.Str(v.State,"workspace");}
        public string Work {get{string p=Workspace();Directory.CreateDirectory(p);return p;}}
        public object Terminal(string action,object args,string owner) {if(action!="close"&&action!="interrupt"&&RequireAccess!=null)RequireAccess();lock(terminals){foreach(var old in terminals.Values.Where(stale=>(DateTime.UtcNow-stale.Used).TotalMinutes>20).ToArray()){old.Dispose();terminals.Remove(old.Id);}if(action=="open"){if(terminals.Count>=8)throw new Exception("Terminal limit reached");var created=new TerminalSession(Work,owner);terminals.Add(created.Id,created);return J.Obj("session",created.Id,"mode","persistent-command-shell");}string id=J.Str(args,"session");TerminalSession t;if(!terminals.TryGetValue(id,out t)||t.Owner!=owner)throw new Exception("Terminal not found");if(action=="read")return t.Read((long)J.Num(args,"offset"));if(action=="write"){t.Write(J.Str(args,"text"));return J.Obj("written",true);}if(action=="close"||action=="interrupt"){t.Dispose();terminals.Remove(id);return J.Obj("closed",true,"ended",true,"interrupted",action=="interrupt");}throw new Exception("Unknown terminal action");}}
        public void CloseOwner(string owner) {lock(terminals)foreach(var t in terminals.Values.Where(t=>t.Owner==owner).ToArray()){t.Dispose();terminals.Remove(t.Id);}}
        public async Task<object> Execute(string tool,object a,CancellationToken ct,bool remote=false) {ct.ThrowIfCancellationRequested();if(RequireAccess!=null)RequireAccess();if(tool.StartsWith("screen_")){if(!J.Bool(vault.State,"screenEnabled"))throw new Exception("请先在设置中允许屏幕控制");return WindowsScreen.Execute(tool,a,ct);}if(tool=="run_shell")return await TerminalSession.Command(J.Str(a,"command"),Work,(int)Math.Max(1,Math.Min(120,J.Num(a,"timeout_seconds",30))),ct).ConfigureAwait(false);if(!new[]{"read_file","write_file","list_directory"}.Contains(tool))throw new Exception("Unknown tool");string value=J.Str(a,"path");if(string.IsNullOrEmpty(value)||value.IndexOf('\0')>=0)throw new Exception("Invalid path");string file=Path.GetFullPath(Path.IsPathRooted(value)?value:Path.Combine(Work,value));if(tool=="list_directory"){var entries=Directory.GetFileSystemEntries(file).Select(Path.GetFileName).OrderBy(x=>x).ToArray();return J.Obj("path",file,"entries",entries.Take(200).ToArray(),"total",entries.Length);}if(tool=="read_file"){long offset=(long)J.Num(a,"offset");if(offset<0)throw new Exception("Invalid offset");using(var f=File.Open(file,FileMode.Open,FileAccess.Read,FileShare.Read)){f.Position=offset;var b=new byte[49152];int n=f.Read(b,0,b.Length);return J.Obj("text",Encoding.UTF8.GetString(b,0,n),"next_offset",offset+n,"path",file);}}string content=J.Str(a,"content");if(Encoding.UTF8.GetByteCount(content)>262144)throw new Exception("File content too large");if(File.Exists(file)){if((File.GetAttributes(file)&(FileAttributes.ReparsePoint|FileAttributes.Directory))!=0)throw new Exception("Regular files only");File.Copy(file,file+".asterhand-backup-"+J.Id(),false);}if(!Directory.Exists(Path.GetDirectoryName(file)))throw new Exception("Parent directory does not exist");J.Atomic(file,Wire.Utf8(content));return J.Obj("written",true,"path",file); }
        public void Dispose() {lock(terminals){foreach(var t in terminals.Values)t.Dispose();terminals.Clear();}}
    }
}
