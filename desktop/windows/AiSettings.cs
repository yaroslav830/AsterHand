using System;
using System.Collections.Generic;
using System.Linq;

namespace AsterHand {
    internal static class AiSettings {
        public static void Migrate(Vault vault) {lock(vault.Sync){if(J.Num(vault.State,"aiSchema")==2)return;string oldProvider=J.Str(vault.State,"provider","openai");var saved=J.Map(J.Get(vault.State,"providers"));var compatible=J.Get(saved,"compatible");var old=J.Get(saved,oldProvider)??vault.State;var api=J.Obj();foreach(string key in new[]{"apiBase","model","key","effort","apiProtocol"})if(J.Get(compatible??old,key)!=null)api[key]=J.Get(compatible??old,key);api["apiBase"]=J.Str(api,"apiBase",oldProvider=="deepseek"?"https://api.deepseek.com":"https://api.openai.com/v1");api["model"]=J.Str(api,"model");api["key"]=J.Str(api,"key");api["apiProtocol"]=J.Str(api,"apiProtocol","auto");api["effort"]=J.Str(api,"effort","auto");vault.State["genericApi"]=api;vault.State["provider"]=oldProvider=="chatgpt"?"chatgpt":"compatible";vault.State["aiSchema"]=2;vault.Save();}}
        public static Dictionary<string,object> Options(Vault vault) {lock(vault.Sync){bool chatgpt=J.Str(vault.State,"provider")=="chatgpt";var o=J.Read(J.Write(chatgpt?J.Get(vault.State,"chatgptSettings"):J.Get(vault.State,"genericApi"))??"{}");o["provider"]=chatgpt?"chatgpt":"compatible";if(chatgpt){o["profileId"]=J.Str(vault.State,"selectedChatgpt");o["apiBase"]="https://api.openai.com/v1";}return o;}}
        public static List<object> Models(object response,bool chatgpt) {var raw=J.List(J.Get(response,chatgpt?"models":"data"));if(raw.Count==0&&!chatgpt)raw=J.List(J.Get(response,"models"));return raw.Where(m=>!chatgpt||J.Str(m,"visibility")=="list").Select(m=>J.Obj("id",J.Str(m,chatgpt?"slug":"id",J.Str(m,"slug")),"name",J.Str(m,"display_name",J.Str(m,"id",J.Str(m,"slug"))))).Where(m=>J.Str(m,"id").Length>0).GroupBy(m=>J.Str(m,"id")).Select(g=>(object)g.First()).ToList();}
    }
}
