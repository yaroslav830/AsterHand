using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace AsterHand {
    internal static partial class NativeTests {
        // Explicit operator-invoked test of AsterHand's own saved account. Never log credentials.
        static async Task LiveChatGPT(string directory,string reportPath,bool exclusiveRefresh=false) {
            System.Net.ServicePointManager.SecurityProtocol=System.Net.SecurityProtocolType.Tls12;
            string settings=Path.Combine(Path.GetFullPath(directory),"settings.dat");
            if(!File.Exists(settings))throw new Exception("AsterHand settings do not exist.");
            var report=J.Obj("timeUtc",DateTime.UtcNow.ToString("o"),"testMode","native request using AsterHand saved account", "prompt","Reply with exactly ASTERHAND_LOGIN_OK. Do not use tools.","credentialsLogged",false,"passed",false);
            report["releaseSha256"]=Wire.Hex(Wire.Hash(File.ReadAllBytes(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"AsterHand.exe"))));
            try {
                var vault=new Vault(Path.GetDirectoryName(settings),null);
                using(var auth=new ChatGPTAuth(vault))using(var tools=new ToolHost(vault))using(var hub=new DeviceHub(vault,tools,0,false))using(var cancel=new CancellationTokenSource(TimeSpan.FromSeconds(90))) {
                    var profile=auth.Selected;
                    if(profile==null||!ChatGPTAuth.PlanEnabled(profile))throw new Exception("Sign in and authorize ChatGPT plan usage first.");
                    if(exclusiveRefresh&&System.Diagnostics.Process.GetProcesses().Any(process=>process.ProcessName.Equals("AsterHand",StringComparison.OrdinalIgnoreCase)||process.ProcessName.Equals("AsterHand-Windows",StringComparison.OrdinalIgnoreCase)))throw new Exception("Close native AsterHand before an exclusive refresh test.");
                    bool stale=J.Num(profile,"expires_at")<J.Now+300;
                    if(stale&&!exclusiveRefresh)throw new Exception("Reauthorize in AsterHand first; this check never rotates a running app's tokens.");
                    report["accountSignedIn"]=true;report["planPermissionGranted"]=true;report["tokenRefreshAttempted"]=stale;
                    var agent=new Agent(vault,tools,hub,""){ChatGPT=auth};
                    var options=J.Obj("provider","chatgpt","profileId",J.Str(profile,"id"));
                    var catalog=AiSettings.Models(await agent.Request(options,null,"models",cancel.Token),true);
                    if(catalog.Count==0)throw new Exception("The account returned no visible models.");
                    string configured=J.Str(J.Get(vault.State,"chatgptSettings"),"model");
                    string model=catalog.Any(m=>J.Str(m,"id")==configured)?configured:J.Str(catalog[0],"id");
                    report["modelCount"]=catalog.Count;report["model"]=model;
                    int deltas=0;agent.Event=(kind,deltaText)=>{if(kind=="流式回复")deltas++;};
                    var request=J.Obj("model",model,"input",new[]{J.Obj("role","user","content",J.Str(report,"prompt"))},"store",false,"stream",true,"max_output_tokens",1024);
                    var response=await agent.Request(options,request,"responses",cancel.Token);
                    string text=string.Concat(J.List(J.Get(response,"output")).Where(o=>J.Str(o,"type")=="message").SelectMany(o=>J.List(J.Get(o,"content"))).Select(c=>J.Str(c,"text")));
                    report["responseCompleted"]=J.Str(response,"status")=="completed";
                    report["expectedReplyMatched"]=text.Trim()=="ASTERHAND_LOGIN_OK";report["streamDeltaEvents"]=deltas;
                    if(!J.Bool(report,"responseCompleted")||!J.Bool(report,"expectedReplyMatched"))throw new Exception("The completed response did not match the test marker.");
                    report["passed"]=true;
                }
            }catch(Exception e){report["error"]=J.Error(e);throw;}
            finally {J.Save(Path.GetFullPath(reportPath),report);Console.WriteLine(J.Write(report));}
        }
    }
}
