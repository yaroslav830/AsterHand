using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace AsterHand {
    internal static partial class NativeTests {
        static async Task PublicAuthCheck() {System.Net.ServicePointManager.SecurityProtocol=System.Net.SecurityProtocolType.Tls12;var meta=await Net.Json("https://auth.openai.com/.well-known/openid-configuration",null,CancellationToken.None,20);string jwks=J.Str(meta,"jwks_uri");var uri=new Uri(jwks);if(J.Str(meta,"issuer")!="https://auth.openai.com"||uri.Scheme!="https"||uri.Host!="auth.openai.com")throw new Exception("Unexpected OpenID provider");var keys=await Net.Json(jwks,null,CancellationToken.None,20);Console.WriteLine(J.Write(J.Obj("nativeHttps",true,"issuerVerified",true,"publicKeys",J.List(J.Get(keys,"keys")).Count,"accountSignedIn",false)));}
        static async Task HttpTests() {
            using(var tools=new ToolHost(Create("http")))using(var hub=new DeviceHub(Create("http-hub"),tools,0,false)) {
                var agent=new Agent(Create("http-agent"),tools,hub,"");
                var server=new TcpListener(IPAddress.Loopback,0);server.Start();int port=((IPEndPoint)server.LocalEndpoint).Port;
                try {
                    var serving=Task.Run(async()=>{using(var socket=await server.AcceptTcpClientAsync()){var stream=socket.GetStream();var header=new StringBuilder();while(!header.ToString().EndsWith("\r\n\r\n")){byte[] b=await DeviceHub.ReadExact(stream,1,CancellationToken.None);header.Append((char)b[0]);if(header.Length>32768)throw new Exception("fixture header too large");}string h=header.ToString();int length=int.Parse(h.Split(new[]{"\r\n"},StringSplitOptions.None).First(l=>l.StartsWith("Content-Length:",StringComparison.OrdinalIgnoreCase)).Split(':')[1]);var body=J.Read(Encoding.UTF8.GetString(await DeviceHub.ReadExact(stream,length,CancellationToken.None)));Check(h.StartsWith("POST /v1/chat/completions ")&&h.Contains("Bearer fixture-http-key"),"generic API uses configured HTTP route and bearer header");Check(J.Str(body,"model")=="model-from-server"&&J.List(J.Get(body,"messages")).Count==2,"generic API transmits selected model and converted messages");string json=J.Write(J.Obj("choices",new[]{J.Obj("finish_reason","stop","message",J.Obj("role","assistant","content","native-http-ok"))}));byte[] response=Wire.Utf8("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: "+Encoding.UTF8.GetByteCount(json)+"\r\n\r\n"+json);await stream.WriteAsync(response,0,response.Length);}});
                    var result=await agent.Request(J.Obj("provider","compatible","apiBase","http://127.0.0.1:"+port+"/v1","key","fixture-http-key","apiProtocol","chat"),J.Obj("model","model-from-server","input",new[]{J.Obj("role","user","content","fixture")},"instructions","fixture","tools",new object[0]),"responses",CancellationToken.None);
                    await serving;Check(J.Write(result).Contains("native-http-ok")&&J.Str(result,"status")=="completed","generic API completes real local HTTP roundtrip");
                }finally{server.Stop();}
                server=new TcpListener(IPAddress.Loopback,0);server.Start();port=((IPEndPoint)server.LocalEndpoint).Port;
                try{var serving=Task.Run(async()=>{using(var socket=await server.AcceptTcpClientAsync()){var stream=socket.GetStream();var buffer=new byte[4096];await stream.ReadAsync(buffer,0,buffer.Length);byte[] response=Encoding.ASCII.GetBytes("HTTP/1.1 302 Found\r\nLocation: https://redirect.invalid/steal\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");await stream.WriteAsync(response,0,response.Length);}});await RejectAsync(()=>agent.Request(J.Obj("provider","compatible","apiBase","http://127.0.0.1:"+port+"/v1","key","fixture-http-key"),null,"models",CancellationToken.None),"API redirects refused without forwarding credentials");await serving;}finally{server.Stop();}
            }
            var grouped=Agent.ChatMessages(J.Obj("input",new object[]{J.Obj("type","function_call","call_id","screen","name","screen_capture","arguments","{}"),J.Obj("type","function_call","call_id","file","name","read_file","arguments","{}"),J.Obj("type","function_call_output","call_id","screen","output",new[]{J.Obj("type","input_image","image_url","data:image/jpeg;base64,Zml4dHVyZQ==")}),J.Obj("type","function_call_output","call_id","file","output","fixture")}));Check(J.Str(grouped[2],"role")=="tool"&&J.Str(grouped[3],"role")=="tool"&&J.Str(grouped[4],"role")=="user","multiple tool results precede screenshot user messages");
            var history=J.List(new[]{J.Obj("type","function_call","call_id","interrupted","name","write_file","arguments","{}")});Agent.CompleteInterruptedCalls(history);Check(history.Count==2&&J.Str(history[1],"type")=="function_call_output","interrupted tool calls close cleanly before next turn");
        }
    }
}
