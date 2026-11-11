using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace AsterHand {
    internal static class J {
        public static Dictionary<string, object> Obj(params object[] pairs) { var d = new Dictionary<string, object>(); for (int i=0;i<pairs.Length;i+=2) d[(string)pairs[i]]=pairs[i+1]; return d; }
        public static string Write(object o) { return new JavaScriptSerializer { MaxJsonLength=16*1024*1024, RecursionLimit=100 }.Serialize(o); }
        public static object Parse(string s) { return new JavaScriptSerializer { MaxJsonLength=16*1024*1024, RecursionLimit=100 }.DeserializeObject(s); }
        public static Dictionary<string, object> Map(object o) { return o as Dictionary<string, object> ?? new Dictionary<string, object>(); }
        public static Dictionary<string, object> Read(string s) { return Map(Parse(s)); }
        public static object Get(object d, string key) { object v; return Map(d).TryGetValue(key,out v)?v:null; }
        public static string Str(object d,string key,string fallback="") { object v=Get(d,key); return v==null?fallback:Convert.ToString(v,CultureInfo.InvariantCulture); }
        public static bool Bool(object d,string key,bool fallback=false) { object v=Get(d,key); return v is bool?(bool)v:fallback; }
        public static double Num(object d,string key,double fallback=0) { double n; return double.TryParse(Str(d,key),NumberStyles.Float,CultureInfo.InvariantCulture,out n)?n:fallback; }
        public static List<object> List(object o) { var a=o as IEnumerable; return a==null||o is string||o is IDictionary?new List<object>():a.Cast<object>().ToList(); }
        public static double Now { get { return (DateTime.UtcNow-new DateTime(1970,1,1)).TotalSeconds; } }
        public static string Id() { return Guid.NewGuid().ToString(); }
        public static void Atomic(string file,byte[] bytes) { Directory.CreateDirectory(Path.GetDirectoryName(file)); string temp=file+"."+Id()+".tmp"; try { using(var f=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)) { f.Write(bytes,0,bytes.Length); f.Flush(true); } if(File.Exists(file)) File.Replace(temp,file,file+".bak"); else File.Move(temp,file); } finally { if(File.Exists(temp)) File.Delete(temp); } }
        public static void Save(string file,object value) { Atomic(file,Encoding.UTF8.GetBytes(Write(value))); }
        public static Dictionary<string,object> Load(string file) { return Read(File.ReadAllText(file,Encoding.UTF8)); }
        public static string Error(Exception e) { while(e is AggregateException && e.InnerException!=null)e=e.InnerException; return e is OperationCanceledException?"已停止":e.Message; }
    }

    internal static class Wire {
        public const int Limit=2*1024*1024;
        public static byte[] Random(int n) { var b=new byte[n]; using(var r=RandomNumberGenerator.Create())r.GetBytes(b); return b; }
        public static string Hex(byte[] b) { return BitConverter.ToString(b).Replace("-","").ToLowerInvariant(); }
        public static byte[] Unhex(string s) { if(s==null||s.Length%2!=0)throw new Exception("Invalid hex"); return Enumerable.Range(0,s.Length/2).Select(i=>Convert.ToByte(s.Substring(i*2,2),16)).ToArray(); }
        public static byte[] Hash(byte[] b) { using(var h=SHA256.Create())return h.ComputeHash(b); }
        public static byte[] Join(params byte[][] all) { return all.SelectMany(b=>b).ToArray(); }
        public static byte[] Utf8(string s) { return Encoding.UTF8.GetBytes(s); }
        public static byte[] Hmac(byte[] k,byte[] data) { using(var h=new HMACSHA256(k))return h.ComputeHash(data); }
        public static string B64Url(byte[] b) { return Convert.ToBase64String(b).TrimEnd('=').Replace('+','-').Replace('/','_'); }
        public static byte[] Decode(string s) { s=s.Replace('-','+').Replace('_','/'); return Convert.FromBase64String(s.PadRight((s.Length+3)/4*4,'=')); }
        public static bool Equal(byte[] a,byte[] b) { if(a.Length!=b.Length)return false;int n=0;for(int i=0;i<a.Length;i++)n|=a[i]^b[i];return n==0; }
        static byte[] Key(string secret,string purpose) { if(secret==null||secret.Length!=64)throw new Exception("Invalid pairing key");return Hmac(Unhex(secret),Utf8("AgentGo/v1/"+purpose)); }
        static byte[] Crypt(byte[] b,byte[] key,byte[] iv,bool encrypt) { using(var a=Aes.Create()) { a.Key=key;a.IV=iv;a.Mode=CipherMode.CBC;a.Padding=PaddingMode.PKCS7;using(var t=encrypt?a.CreateEncryptor():a.CreateDecryptor())return t.TransformFinalBlock(b,0,b.Length); } }
        public static Dictionary<string,object> Seal(string pair,string secret,object payload,string direction) { var iv=Random(16);string ivs=Convert.ToBase64String(iv),data=Convert.ToBase64String(Crypt(Utf8(J.Write(payload)),Key(secret,"encryption/"+direction),iv,true)); return J.Obj("v",1,"pair",pair,"iv",ivs,"data",data,"mac",Convert.ToBase64String(Hmac(Key(secret,"authentication/"+direction),Utf8("v1\n"+direction+"\n"+pair+"\n"+ivs+"\n"+data)))); }
        public static Dictionary<string,object> Open(object packet,string secret,string direction) { Guid id;string pair=J.Str(packet,"pair"),data=J.Str(packet,"data"),ivs=J.Str(packet,"iv");if(J.Num(packet,"v")!=1||!Guid.TryParseExact(pair,"D",out id)||data.Length>Limit)throw new Exception("Invalid packet");byte[] iv=Decode(ivs),mac=Decode(J.Str(packet,"mac")),expected=Hmac(Key(secret,"authentication/"+direction),Utf8("v1\n"+direction+"\n"+pair+"\n"+ivs+"\n"+data));if(iv.Length!=16||!Equal(mac,expected))throw new Exception("Pairing authentication failed");var p=J.Read(Encoding.UTF8.GetString(Crypt(Decode(data),Key(secret,"encryption/"+direction),iv,false)));if(J.Str(p,"id").Length==0||J.Str(p,"id").Length>80||!p.ContainsKey("ts")||double.IsNaN(J.Num(p,"ts"))||double.IsInfinity(J.Num(p,"ts"))||Math.Abs(J.Now-J.Num(p,"ts"))>90)throw new Exception("Expired packet");return p; }
        public static byte[] Frame(string secret,string nonce,uint seq,byte[] jpeg,int width,int height) { byte[] head=new byte[16]; Put(head,0,seq);Put(head,4,(uint)width);Put(head,8,(uint)height);Put(head,12,seq);var iv=Random(16);string dir="stream/"+nonce;byte[] body=Join(iv,Crypt(Join(head,jpeg),Key(secret,"encryption/"+dir),iv,true));return Join(body,Hmac(Key(secret,"authentication/"+dir),body)); }
        public static byte[] OpenFrame(string secret,string nonce,byte[] data,ref uint sequence) { if(data.Length<80||data.Length>Limit)throw new Exception("Invalid frame");string dir="stream/"+nonce;var body=data.Take(data.Length-32).ToArray();if(!Equal(data.Skip(body.Length).ToArray(),Hmac(Key(secret,"authentication/"+dir),body)))throw new Exception("Video authentication failed");var plain=Crypt(body.Skip(16).ToArray(),Key(secret,"encryption/"+dir),body.Take(16).ToArray(),false);uint n=Get(plain,0);if(plain.Length<18||n<=sequence)throw new Exception("Video replay");sequence=n;return plain.Skip(16).ToArray(); }
        public static void Put(byte[] b,int i,uint n) { b[i]=(byte)(n>>24);b[i+1]=(byte)(n>>16);b[i+2]=(byte)(n>>8);b[i+3]=(byte)n; }
        public static uint Get(byte[] b,int i) { return ((uint)b[i]<<24)|((uint)b[i+1]<<16)|((uint)b[i+2]<<8)|b[i+3]; }
        public static Dictionary<string,object> NewIdentity() { using(var key=CngKey.Create(CngAlgorithm.ECDiffieHellmanP256,null,new CngKeyCreationParameters {ExportPolicy=CngExportPolicies.AllowPlaintextExport})) { var blob=key.Export(CngKeyBlobFormat.EccPrivateBlob);return J.Obj("public_key",Convert.ToBase64String(Join(new byte[]{4},blob.Skip(8).Take(64).ToArray())),"private_key",Convert.ToBase64String(blob.Skip(72).Take(32).ToArray())); } }
        public static string PairKey(object identity,object remote,string id) { Guid g;byte[] pub=Decode(J.Str(remote,"public_key"));if(!Guid.TryParseExact(id,"D",out g)||pub.Length!=65||pub[0]!=4||J.Str(remote,"device_id")!=Hex(Hash(pub)))throw new Exception("Invalid device identity");var localPub=Decode(J.Str(identity,"public_key"));var d=Decode(J.Str(identity,"private_key"));if(d.Length>32)throw new Exception("Invalid private key");d=Join(new byte[32-d.Length],d);var blob=Join(BitConverter.GetBytes(0x324b4345),BitConverter.GetBytes(32),localPub.Skip(1).ToArray(),d);var peer=Join(BitConverter.GetBytes(0x314b4345),BitConverter.GetBytes(32),pub.Skip(1).ToArray());using(var own=CngKey.Import(blob,CngKeyBlobFormat.EccPrivateBlob))using(var other=CngKey.Import(peer,CngKeyBlobFormat.EccPublicBlob))using(var ec=new ECDiffieHellmanCng(own))using(var re=new ECDiffieHellmanCng(other)) { ec.KeyDerivationFunction=ECDiffieHellmanKeyDerivationFunction.Hash;ec.HashAlgorithm=CngAlgorithm.Sha256;ec.SecretPrepend=Utf8("AgentGo/pairing/v2\0");ec.SecretAppend=Utf8(id);return Hex(ec.DeriveKeyMaterial(re.PublicKey)); } }
    }

    internal sealed class Vault {
        public readonly string DirectoryPath;
        public readonly object Sync=new object();
        public Dictionary<string,object> State;
        string FilePath { get { return Path.Combine(DirectoryPath,"settings.dat"); } }
        public Vault(string path,string legacy) { DirectoryPath=path;Directory.CreateDirectory(path); if(File.Exists(FilePath)) State=J.Read(Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(FilePath),null,DataProtectionScope.CurrentUser)));else { State=J.Obj("name",Environment.MachineName,"enabled",false,"background",true,"peers",new object[0],"trust",J.Obj(),"language","system","provider","openai","apiBase","https://api.openai.com/v1","model","","workspace",Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"AsterHand")); if(!string.IsNullOrEmpty(legacy)&&File.Exists(legacy)) { var old=J.Load(legacy);foreach(string key in new[]{"identity","peers","trust","name","enabled","background","pair_code_mode","pair_code_fixed"})if(old.ContainsKey(key))State[key]=old[key];State["legacyImported"]=true; } if(!State.ContainsKey("identity"))State["identity"]=Wire.NewIdentity();Save(); } if(!State.ContainsKey("identity"))throw new Exception("Device identity is missing; restore settings.dat.bak."); }
        public void Save() { lock(Sync)J.Atomic(FilePath,ProtectedData.Protect(Wire.Utf8(J.Write(State)),null,DataProtectionScope.CurrentUser)); }
        public List<object> Peers { get { lock(Sync)return J.List(J.Get(State,"peers")); } }
        public void SetPeers(IEnumerable<object> peers) { lock(Sync) {State["peers"]=peers.ToArray();Save();} }
    }

    internal sealed class ProjectStore {
        public readonly string Root;
        readonly Func<string,string> localize;
        public List<object> Projects;
        public ProjectStore(string root,Func<string,string> translate=null) {localize=translate??(s=>s);Root=root;Directory.CreateDirectory(root);string file=Path.Combine(root,"projects.json");Projects=File.Exists(file)?J.List(J.Parse(File.ReadAllText(file,Encoding.UTF8))):new List<object>();if(Projects.Count==0)Create("AsterHand","");}
        public void Save() {J.Save(Path.Combine(Root,"projects.json"),Projects);}
        public Dictionary<string,object> Create(string name,string workspace) {var p=J.Obj("id",J.Id(),"name",string.IsNullOrWhiteSpace(name)?localize("新项目"):name,"workspace",workspace,"chats",new object[0]);Projects.Add(p);Save();return p;}
        public Dictionary<string,object> NewChat(object project) {var c=J.Obj("id",J.Id(),"name",localize("新会话"),"autoTitle",true,"messages",new object[0],"history",new object[0],"draft","","created",J.Now);var chats=J.List(J.Get(project,"chats"));chats.Add(c);J.Map(project)["chats"]=chats;Save();return c;}
        public object Attach(string file) { var info=new FileInfo(file);if(info.Length>8*1024*1024)throw new Exception("附件不能超过 8 MiB");string id=J.Id(),ext=Path.GetExtension(file).ToLowerInvariant();string dst=Path.Combine(Root,"attachments",id+ext);Directory.CreateDirectory(Path.GetDirectoryName(dst));File.Copy(file,dst,false);return J.Obj("id",id,"name",info.Name,"path",dst,"size",info.Length,"image",new[]{".png",".jpg",".jpeg",".gif",".webp"}.Contains(ext)); }
    }

    internal sealed class Localizer {
        Dictionary<string,object> messages=J.Obj();public string Language="zh-CN";
        static readonly Regex Slots=new Regex(@"%(?:\d+\$)?[-+0 #]*(?:\d+)?(?:\.\d+)?(?:ll|l)?[@diuf]|\{[a-zA-Z0-9_]+\}");
        readonly List<KeyValuePair<Regex,string>> templates=new List<KeyValuePair<Regex,string>>();
        public Localizer(string resource,string preference) {if(Assets.Exists(resource))messages=J.Map(J.Get(J.Read(Assets.Text(resource)),"messages"));foreach(string key in messages.Keys.OrderByDescending(k=>k.Length)){var slots=Slots.Matches(key);if(slots.Count==0||key.Length>2048)continue;var pattern=new StringBuilder("^");int offset=0;foreach(Match slot in slots){pattern.Append(Regex.Escape(key.Substring(offset,slot.Index-offset))).Append("([\\s\\S]+?)");offset=slot.Index+slot.Length;}pattern.Append(Regex.Escape(key.Substring(offset))).Append("$");templates.Add(new KeyValuePair<Regex,string>(new Regex(pattern.ToString(),RegexOptions.CultureInvariant,TimeSpan.FromMilliseconds(25)),key));}Set(preference);}
        public void Set(string preference) {string p=preference=="system"?CultureInfo.CurrentUICulture.Name:preference;Language=p.StartsWith("zh",StringComparison.OrdinalIgnoreCase)?"zh-CN":new[]{"ja","es","fr"}.FirstOrDefault(x=>p.StartsWith(x,StringComparison.OrdinalIgnoreCase))??"en";}
        public string T(string key) {if(string.IsNullOrEmpty(key)||Language=="zh-CN")return key;string result=J.Str(J.Get(messages,key),Language,J.Str(J.Get(messages,key),"en"));if(result.Length>0)return result;
            if(key.Length<=8192)foreach(var template in templates){Match match;try{match=template.Key.Match(key);}catch(RegexMatchTimeoutException){continue;}if(!match.Success)continue;string format=J.Str(J.Get(messages,template.Value),Language,J.Str(J.Get(messages,template.Value),"en"));var slots=Slots.Matches(format);if(slots.Count+1!=match.Groups.Count)continue;var output=new StringBuilder(format);for(int i=slots.Count-1;i>=0;i--)output.Remove(slots[i].Index,slots[i].Length).Insert(slots[i].Index,match.Groups[i+1].Value);return output.ToString();}return key;}
    }

    internal static class Net {
        public static HttpClient Client(int seconds=125) {var h=new HttpClientHandler { AllowAutoRedirect=false, UseCookies=false, AutomaticDecompression=DecompressionMethods.GZip|DecompressionMethods.Deflate };var c=new HttpClient(h){Timeout=TimeSpan.FromSeconds(seconds),MaxResponseContentBufferSize=16*1024*1024};c.DefaultRequestHeaders.UserAgent.ParseAdd("AsterHand/1.0.1 (Windows)");return c;}
        public static Uri Api(string baseUrl,string route) {Uri b,u;if(!Uri.TryCreate(baseUrl.Trim(),UriKind.Absolute,out b)||b.UserInfo.Length>0||b.Query.Length>0||b.Fragment.Length>0||b.Scheme!="https"&&!(b.Scheme=="http"&&b.IsLoopback)||!Uri.TryCreate(b.AbsoluteUri.TrimEnd('/')+"/"+route,UriKind.Absolute,out u))throw new Exception("API 地址必须使用 HTTPS（本机服务允许 HTTP），且不能含账户、查询参数或片段。");return u;}
        public static async Task<string> ReadText(HttpContent content,int limit,CancellationToken ct) {using(var stream=await content.ReadAsStreamAsync().ConfigureAwait(false))using(var output=new MemoryStream()){byte[] buffer=new byte[8192];int n;while((n=await stream.ReadAsync(buffer,0,buffer.Length,ct).ConfigureAwait(false))>0){if(output.Length+n>limit)throw new Exception("响应超过大小限制。");output.Write(buffer,0,n);}return Encoding.UTF8.GetString(output.ToArray());}}
        public static async Task<Dictionary<string,object>> Json(string url,object body,CancellationToken ct,int timeout=12) {using(var client=Client(timeout))using(var req=new HttpRequestMessage(body==null?HttpMethod.Get:HttpMethod.Post,url)) { if(body!=null)req.Content=new StringContent(J.Write(body),Encoding.UTF8,"application/json");using(var response=await client.SendAsync(req,ct).ConfigureAwait(false)){string text=await response.Content.ReadAsStringAsync().ConfigureAwait(false);if(!response.IsSuccessStatusCode)throw new Exception("HTTP "+(int)response.StatusCode);return J.Read(text);} } }
    }
}
