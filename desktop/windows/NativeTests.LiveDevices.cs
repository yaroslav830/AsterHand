using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace AsterHand {
    internal static partial class NativeTests {
        // Operator first opens an empty local calculator and inspects its screen.
        // Reuses only the separately held QA session, without closing its owner.
        static async Task LiveScreenType(string directory,string reportPath,string expectedDevice) {
            var vault=new Vault(Path.Combine(Path.GetFullPath(directory),"profile"),null);
            var peer=vault.Peers.Single(p=>!J.Bool(p,"incoming",true)&&J.Str(p,"device_id")==expectedDevice);
            string id=J.Str(peer,"id");
            using(var tools=new ToolHost(vault))using(var hub=new DeviceHub(vault,tools,18769,false))using(var cancel=new CancellationTokenSource(30*1000)) {
                hub.UiActive=true;var info=await hub.Request(id,"info",J.Obj(),cancel.Token);
                if(J.Str(info,"device_id")!=expectedDevice)throw new Exception("QA phone identity changed");
                await hub.Request(id,"presence",J.Obj("actor","ai","active",true,"lease_seconds",30),cancel.Token);
                try {
                    await hub.Request(id,"execute",J.Obj("tool","screen_type","arguments",J.Obj("text","42"),"actor","ai"),cancel.Token);
                    await Task.Delay(1500,cancel.Token);
                    var shot=await hub.Request(id,"execute",J.Obj("tool","screen_capture","arguments",J.Obj(),"actor","ai"),cancel.Token);
                    File.WriteAllBytes(Path.Combine(Path.GetFullPath(directory),"type-after.jpg"),Convert.FromBase64String(J.Str(shot,"image_base64")));
                    J.Save(Path.GetFullPath(reportPath),J.Obj("dispatched",true,"text","42","credentialsLogged",false,"requiresVisualVerification",true));
                    Console.WriteLine("Native text input dispatched; inspect type-after.jpg before recording visual success.");
                } finally {hub.Request(id,"presence",J.Obj("actor","ai","active",false),CancellationToken.None).GetAwaiter().GetResult();}
            }
        }
        static async Task LiveLan(string directory,string reportPath,string expectedDevice,string directHost=null,bool screenHome=false,bool hold=false) {
            directory=Path.GetFullPath(directory);Directory.CreateDirectory(directory);
            var report=J.Obj("timeUtc",DateTime.UtcNow.ToString("o"),"checks",new List<object>(),"passed",false,"credentialsLogged",false);
            var checks=(List<object>)report["checks"];
            Action<bool,string> assert=(ok,label)=>{if(!ok)throw new Exception(label);checks.Add(label);Console.WriteLine("PASS: "+label);};
            string peerId="",terminalId="";
            var vault=new Vault(Path.Combine(directory,"profile"),null);
            vault.State["name"]="AsterHand Windows Native QA";vault.State["workspace"]=Path.Combine(directory,"work");vault.Save();
            using(var tools=new ToolHost(vault))using(var hub=new DeviceHub(vault,tools,18769,false))using(var limit=new CancellationTokenSource(TimeSpan.FromMinutes(hold?15:4))) {
                try {
                    hub.UiActive=true;
                    var found=directHost==null?await hub.Discover(limit.Token):new List<object>{await hub.DeviceAt(directHost,18769,limit.Token)};
                    report["connectionMethod"]=directHost==null?"LAN discovery":"Manual IP over VM NAT";
                    report["discoveredCount"]=found.Count;
                    var remote=found.FirstOrDefault(d=>J.Str(d,"device_id")==expectedDevice);
                    assert(remote!=null,directHost==null?"Native LAN discovery finds the authenticated target identity":"Native manual IP connection finds the expected target identity");
                    var request=await hub.Begin(remote,limit.Token);
                    peerId=J.Str(request,"id");
                    J.Save(Path.Combine(directory,"pending.json"),J.Obj("request",peerId,"senderDeviceId",J.Str(hub.Identity(),"device_id"),"receiverDeviceId",expectedDevice,"status",J.Str(request,"status")));
                    if(directHost!=null)J.Save(Path.Combine(Path.GetDirectoryName(Path.GetFullPath(reportPath)),"PENDING.JSN"),J.Read(File.ReadAllText(Path.Combine(directory,"pending.json"))));
                    Console.WriteLine("Waiting for explicitly authorized receiver approval; pending.json contains only request identifiers.");
                    while(J.Str(request,"status")=="pending"){await Task.Delay(1000,limit.Token);request=await hub.Poll(peerId,false,limit.Token);}
                    assert(J.Str(request,"status")=="accepted","Native encrypted pairing accepted by the selected phone");
                    var info=await hub.Request(peerId,"info",J.Obj(),limit.Token);
                    assert(J.Str(info,"device_id")==expectedDevice,"Native encrypted RPC confirms the same phone identity");
                    string platform=J.Str(info,"platform");report["platform"]=platform;
                    string marker="AsterHand native LAN file "+J.Id();
                    // Android file tools intentionally stay inside the current project.
                    // Its persistent terminal starts in the same workspace; use relative
                    // paths rather than asking for broader storage access.
                    string folder=(platform=="ios"?"/var/mobile/Media/":"")+"AsterHandQA-"+J.Id();
                    string file=folder+"/probe.txt";
                    report["ownedTestFolder"]=folder;
                    var opened=await hub.Request(peerId,"terminal.open",J.Obj(),limit.Token);terminalId=J.Str(opened,"session");
                    assert(terminalId.Length>0,"Native persistent terminal opens");
                    await hub.Request(peerId,"terminal.write",J.Obj("session",terminalId,"text","mkdir -p '"+folder+"' && printf 'ASTERHAND_FOLDER:%s\\n' \"$((17 + 25))\"\n"),limit.Token);
                    string folderOutput="";for(int n=0;n<30&&!folderOutput.Contains("ASTERHAND_FOLDER:42");n++){await Task.Delay(150,limit.Token);var value=await hub.Request(peerId,"terminal.read",J.Obj("session",terminalId,"offset",0),limit.Token);folderOutput=J.Str(value,"output");}
                    assert(folderOutput.Contains("ASTERHAND_FOLDER:42"),"Owned test folder created through the native terminal");
                    var written=await hub.Request(peerId,"execute",J.Obj("tool","write_file","arguments",J.Obj("path",file,"content",marker)),limit.Token);
                    if(J.Str(written,"error").Length>0)throw new Exception(J.Str(written,"error"));
                    var read=await hub.Request(peerId,"execute",J.Obj("tool","read_file","arguments",J.Obj("path",file,"offset",0)),limit.Token);
                    assert(J.Str(read,"text",J.Str(read,"content"))==marker,"Native file write and exact readback");
                    var listed=await hub.Request(peerId,"execute",J.Obj("tool","list_directory","arguments",J.Obj("path",folder)),limit.Token);
                    assert(J.Write(listed).Contains("probe.txt")&&J.Str(listed,"error").Length==0,"Native directory listing of owned test folder");
                    await hub.Request(peerId,"terminal.write",J.Obj("session",terminalId,"text","asterhand_qa_var=37\n"),limit.Token);
                    await hub.Request(peerId,"terminal.write",J.Obj("session",terminalId,"text","printf 'ASTERHAND_RESULT:%s\\n' \"$((asterhand_qa_var + 5))\"\n"),limit.Token);
                    string output="";for(int n=0;n<30&&!output.Contains("ASTERHAND_RESULT:42");n++){await Task.Delay(150,limit.Token);var value=await hub.Request(peerId,"terminal.read",J.Obj("session",terminalId,"offset",0),limit.Token);output=J.Str(value,"output");}
                    assert(output.Contains("ASTERHAND_RESULT:42"),"Native terminal executes and retains variables across writes");
                    if(screenHome) {
                        await hub.Request(peerId,"presence",J.Obj("actor","ai","active",true,"lease_seconds",30),limit.Token);
                        try {await hub.Request(peerId,"execute",J.Obj("tool","screen_home","arguments",J.Obj(),"actor","ai"),limit.Token);await Task.Delay(900,limit.Token);}
                        finally {hub.Request(peerId,"presence",J.Obj("actor","ai","active",false),CancellationToken.None).GetAwaiter().GetResult();}
                        report["screenHomeDispatched"]=true;
                    }
                    int frames=0,width=0,height=0;
                    using(var streamLimit=CancellationTokenSource.CreateLinkedTokenSource(limit.Token)) {
                        streamLimit.CancelAfter(TimeSpan.FromSeconds(10));
                        await hub.Request(peerId,"presence",J.Obj("active",true,"lease_seconds",30),limit.Token);
                        try {try{await hub.Stream(peerId,bytes=>{using(var memory=new MemoryStream(bytes))using(var image=Image.FromStream(memory)){width=image.Width;height=image.Height;}if(frames++==0){File.WriteAllBytes(Path.Combine(directory,"phone-first-frame.jpg"),bytes);if(directHost!=null)File.WriteAllBytes(Path.Combine(Path.GetDirectoryName(Path.GetFullPath(reportPath)),"SCREEN.JPG"),bytes);}if(frames>=3)streamLimit.Cancel();},streamLimit.Token);}catch(OperationCanceledException){}}
                        finally {hub.Request(peerId,"presence",J.Obj("active",false),CancellationToken.None).GetAwaiter().GetResult();}
                    }
                    report["frames"]=frames;report["frameWidth"]=width;report["frameHeight"]=height;
                    assert(frames>=3&&width>0&&height>0,"Native authenticated screen stream decodes real JPEG frames");
                    // Remove only the unique folder created by this check, using its owned terminal.
                    await hub.Request(peerId,"terminal.write",J.Obj("session",terminalId,"text","rm -f '"+file+"' && rmdir '"+folder+"' && test ! -e '"+folder+"' && printf 'ASTERHAND_CLEANUP:%s\\n' \"$((30 + 12))\"\n"),limit.Token);
                    string cleanup="";for(int n=0;n<30&&!cleanup.Contains("ASTERHAND_CLEANUP:42");n++){await Task.Delay(150,limit.Token);var value=await hub.Request(peerId,"terminal.read",J.Obj("session",terminalId,"offset",0),limit.Token);cleanup=J.Str(value,"output");}
                    assert(cleanup.Contains("ASTERHAND_CLEANUP:42"),"Owned test files removed and absence verified");
                    report["passed"]=true;
                    if(hold){J.Save(Path.GetFullPath(reportPath),report);J.Save(Path.Combine(directory,"ready.json"),J.Obj("ready",true));Console.WriteLine("Frontend QA session ready; waiting for owned finish marker.");try{while(!File.Exists(Path.Combine(directory,"finish")))await Task.Delay(500,limit.Token);}catch(OperationCanceledException){report["frontendHoldEnded"]="timeout after completed functional checks";}}
                }catch(Exception e){report["error"]=J.Error(e);throw;}
                finally {
                    if(terminalId.Length>0)try{hub.Request(peerId,"terminal.close",J.Obj("session",terminalId),CancellationToken.None).GetAwaiter().GetResult();}catch{}
                    if(peerId.Length>0)try{hub.Request(peerId,"session.close",J.Obj(),CancellationToken.None).GetAwaiter().GetResult();}catch{}
                    J.Save(Path.GetFullPath(reportPath),report);Console.WriteLine(J.Write(report));
                }
            }
        }
    }
}
