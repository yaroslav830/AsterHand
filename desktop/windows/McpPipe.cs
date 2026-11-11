using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Net;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace AsterHand {
    internal sealed class McpPipe : IDisposable {
        const int Limit=16*1024*1024;
        readonly string name="AsterHand.MCP."+Guid.NewGuid().ToString("N");
        readonly string descriptor,document;
        readonly CancellationTokenSource stop=new CancellationTokenSource();
        readonly List<NamedPipeServerStream> pipes=new List<NamedPipeServerStream>();
        readonly Func<string,object,CancellationToken,Task<object>> dispatch;
        public McpPipe(string directory,Func<string,object,CancellationToken,Task<object>> handler) {
            dispatch=handler;descriptor=Path.Combine(directory,"mcp-bridge.json");document=J.Write(J.Obj("version",1,"platform","win32","address",@"\\.\pipe\"+name));
            var temporary=descriptor+"."+Guid.NewGuid().ToString("N");File.WriteAllText(temporary,document,new UTF8Encoding(false));if(File.Exists(descriptor))File.Replace(temporary,descriptor,null);else File.Move(temporary,descriptor);
            for(int i=0;i<4;i++)Task.Run((Func<Task>)Listen);
        }
        static async Task<byte[]> Read(Stream stream,int length,CancellationToken token){var bytes=new byte[length];for(int n=0;n<length;){int size=await stream.ReadAsync(bytes,n,length-n,token).ConfigureAwait(false);if(size==0)throw new EndOfStreamException();n+=size;}return bytes;}
        async Task Listen(){while(!stop.IsCancellationRequested){NamedPipeServerStream pipe=null;try{
            var user=WindowsIdentity.GetCurrent().User;var security=new PipeSecurity();security.SetAccessRuleProtection(true,false);security.AddAccessRule(new PipeAccessRule(user,PipeAccessRights.FullControl,AccessControlType.Allow));
            pipe=new NamedPipeServerStream(name,PipeDirection.InOut,4,PipeTransmissionMode.Byte,PipeOptions.Asynchronous,65536,65536,security);
            lock(pipes){if(stop.IsCancellationRequested){pipe.Dispose();return;}pipes.Add(pipe);}await pipe.WaitForConnectionAsync(stop.Token).ConfigureAwait(false);
            using(var request=CancellationTokenSource.CreateLinkedTokenSource(stop.Token)){
                request.CancelAfter(130000);var header=await Read(pipe,4,request.Token).ConfigureAwait(false);int length=IPAddress.NetworkToHostOrder(BitConverter.ToInt32(header,0));if(length<1||length>Limit)throw new IOException("Invalid MCP request size");
                var data=J.Read(Encoding.UTF8.GetString(await Read(pipe,length,request.Token).ConfigureAwait(false)));string route=J.Str(data,"route");if(route.Length==0||route.Length>80)throw new IOException("Invalid MCP route");
                var disconnected=pipe.ReadAsync(new byte[1],0,1,request.Token).ContinueWith(_=>{try{request.Cancel();}catch{}},TaskScheduler.Default);
                object response;try{response=J.Obj("result",await dispatch(route,J.Get(data,"body"),request.Token).ConfigureAwait(false));}catch(Exception error){response=J.Obj("error",J.Error(error));}
                var bytes=Encoding.UTF8.GetBytes(J.Write(response));if(bytes.Length>Limit)throw new IOException("MCP response too large");var prefix=BitConverter.GetBytes(IPAddress.HostToNetworkOrder(bytes.Length));await pipe.WriteAsync(prefix,0,4,request.Token).ConfigureAwait(false);await pipe.WriteAsync(bytes,0,bytes.Length,request.Token).ConfigureAwait(false);await pipe.FlushAsync(request.Token).ConfigureAwait(false);
            }
        }catch{if(!stop.IsCancellationRequested)Thread.Sleep(80);}finally{if(pipe!=null){lock(pipes)pipes.Remove(pipe);pipe.Dispose();}}}}
        public void Dispose(){stop.Cancel();lock(pipes)foreach(var pipe in pipes.ToArray())pipe.Dispose();try{if(File.Exists(descriptor)&&File.ReadAllText(descriptor)==document)File.Delete(descriptor);}catch{}}
    }
    internal sealed partial class MainForm {
        McpPipe mcpPipe;
        string mcpJob="";
        readonly List<object> mcpEvents=new List<object>();
        void StartMcpPipe(){try{mcpPipe=new McpPipe(vault.DirectoryPath,DispatchMcp);}catch(Exception error){System.Diagnostics.Trace.WriteLine("AsterHand MCP: "+J.Error(error));}}
        void TrackMcpJob(){mcpJob=J.Id();mcpEvents.Clear();}
        void TrackMcpEvent(string kind,string text){if(mcpEvents.Count>=120)mcpEvents.RemoveAt(0);mcpEvents.Add(J.Obj("kind",kind,"text",text));}
        object McpAiStatus(){return J.Obj("platform","win32","enabled",true,"agent",J.Obj("id",mcpJob,"running",job!=null,"events",mcpEvents.ToArray()));}
        Task<object> McpUi(Func<object> action,CancellationToken token){var done=new TaskCompletionSource<object>();if(IsDisposed||!IsHandleCreated)throw new InvalidOperationException("AsterHand window is unavailable");BeginInvoke(new Action(()=>{try{token.ThrowIfCancellationRequested();done.TrySetResult(action());}catch(Exception e){done.TrySetException(e);}}));return done.Task;}
        async Task<object> DispatchMcp(string route,object p,CancellationToken ct){
            if(route=="state")return hub.Info();if(route=="discover")return J.Obj("devices",await hub.Discover(ct).ConfigureAwait(false));
            if(route=="connect/ip")return await hub.Begin(await hub.DeviceAt(J.Str(p,"host"),(int)J.Num(p,"port"),ct).ConfigureAwait(false),ct).ConfigureAwait(false);
            if(route=="connect/code"){var matches=(await hub.Discover(ct).ConfigureAwait(false)).Where(x=>J.Str(x,"pair_code")==J.Str(p,"code")).ToArray();if(matches.Length!=1)throw new Exception("Pairing code did not identify exactly one receiver");return await hub.Begin(matches[0],ct).ConfigureAwait(false);}
            if(route=="pair/status")return await hub.Poll(J.Str(p,"id"),false,ct).ConfigureAwait(false);
            if(route=="pair/decision"){hub.Decide(J.Str(p,"id"),J.Str(p,"mode"));return hub.Info();}
            if(route=="trust"){hub.Trust(J.Str(p,"device_id"),J.Str(p,"mode"));return hub.Info();}if(route=="revoke"){hub.Revoke(J.Str(p,"id"));return hub.Info();}
            if(route=="mcp-guide"||route=="skill-guide")return J.Obj("platform","win32","command","python scripts/install_asterhand_mcp.py","repository",AppInfo.RepositoryUrl);
            if(route=="name"||route=="enable"||route=="background"||route=="pair-code")return await McpUi(()=>{if(route=="name"){var name=J.Str(p,"name").Trim();if(name.Length<1||name.Length>80)throw new Exception("Invalid device name");vault.State["name"]=name;}else if(route=="pair-code"){var code=J.Str(p,"code");if(code.Length>0&&(code.Length!=6||!code.All(c=>c>='0'&&c<='9')))throw new Exception("Invalid pairing code");vault.State["pair_code_mode"]=J.Bool(p,"fixed")?"fixed":"rotating";if(code.Length>0)vault.State["pair_code_fixed"]=code;}else{var enabled=J.Get(p,"enabled");if(!(enabled is bool))throw new Exception("Expected enabled boolean");vault.State[route=="enable"?"enabled":"background"]=enabled;}vault.Save();return hub.Info();},ct).ConfigureAwait(false);
            if(route=="codex/status")return await McpUi(McpAiStatus,ct).ConfigureAwait(false);
            if(route=="agent/stop")return await McpUi(()=>{if(job==null||J.Str(p,"job")!=mcpJob)throw new Exception("AI job identity changed");job.Cancel();return McpAiStatus();},ct).ConfigureAwait(false);
            if(route=="codex/message")return await McpUi(()=>{if(job!=null)throw new Exception("A desktop AI task is already running");string message=J.Str(p,"message"),receiver=J.Str(p,"target");if(message.Length==0||message.Length>32768)throw new Exception("Invalid AI task text");if(receiver!="local")hub.Peer(receiver);var options=AiSettings.Options(vault);if(J.Str(options,"model").Length==0||Agent.NeedsKey(options)&&J.Str(options,"key").Length==0||J.Str(options,"provider")=="chatgpt"&&!ChatGPTAuth.PlanEnabled(chatAuth.Selected))throw new Exception("Configure AI in AsterHand settings first");RunTask(new QueuedTask{Chat=chat,Project=project,Text=message,Target=receiver,Attachments=new List<object>(),Automatic=false});return McpAiStatus();},ct).ConfigureAwait(false);
            if(route!="call")throw new Exception("Unsupported native MCP operation");
            string targetId=J.Str(p,"target"),method=J.Str(p,"method");var args=J.Get(p,"args");if(!new[]{"info","execute","app","presence","session.close","terminal.open","terminal.read","terminal.write","terminal.interrupt","terminal.close"}.Contains(method))throw new Exception("Unsupported device method");
            if(targetId!="local"){var peer=hub.Peer(targetId);if(J.Bool(peer,"incoming"))throw new Exception("Select an outgoing paired device");return await hub.Request(targetId,method,args,ct).ConfigureAwait(false);}
            if(method=="info")return hub.Info();if(method=="presence"||method=="session.close")return J.Obj("ok",true);if(method=="app"&&J.Str(args,"action")=="capabilities")return J.Obj("platform","win32","desktop",true,"groups",new[]{"screen","shell","terminal","files"},"desktop_ai",true);
            if(method.StartsWith("terminal."))return tools.Terminal(method.Substring(9),args,"local-mcp");
            if(method=="execute")return await tools.Execute(J.Str(args,"tool"),J.Get(args,"arguments"),ct).ConfigureAwait(false);
            throw new Exception("This operation requires a compatible mobile receiver");
        }
    }
}

