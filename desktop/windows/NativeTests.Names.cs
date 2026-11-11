using System;
using System.IO;
using System.Linq;

namespace AsterHand {
    internal static partial class NativeTests {
        static void DefaultNames() {
            string[] languages={"zh-CN","en","ja","es","fr"};
            string[] projects={"新项目","New project","新しいプロジェクト","Nuevo proyecto","Nouveau projet"};
            string[] chats={"新会话","New chat","新規チャット","Nuevo chat","Nouvelle discussion"};
            for(int i=0;i<languages.Length;i++) {
                var loc=new Localizer(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Resources","localizations.json"),languages[i]);
                var store=new ProjectStore(Path.Combine(root,"names-"+languages[i]),loc.T);
                var project=store.Create("","");var chat=store.NewChat(project);
                Check(J.Str(project,"name")==projects[i]&&J.Str(chat,"name")==chats[i],"localized new project/chat "+languages[i]);
                Check(J.Bool(chat,"autoTitle"),"automatic chat title intent "+languages[i]);
                loc.Set(languages[(i+1)%languages.Length]);var next=store.NewChat(project);
                Check(J.Str(next,"name")==chats[(i+1)%languages.Length]&&J.Str(chat,"name")==chats[i],"language change preserves existing names "+languages[i]);
                var custom=store.Create("用户项目 / Custom","");Check(J.Str(custom,"name")=="用户项目 / Custom","custom project name preserved "+languages[i]);
                var reload=new ProjectStore(store.Root,loc.T);Check(J.Str(J.List(J.Get(reload.Projects[1],"chats")).First(),"name")==chats[i],"localized name persisted "+languages[i]);
            }
            var english=new Localizer(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Resources","localizations.json"),"en");
            var previousContext=System.Threading.SynchronizationContext.Current;
            try {using(var welcome=new WelcomeView(english.T,text=>{},page=>{})) {
                var labels=welcome.Controls.OfType<System.Windows.Forms.Label>().Select(c=>c.Text).ToArray();
                Check(labels.Contains("Your personal AI workspace")&&labels.Contains("Turn ideas into action.")&&labels.Contains("Start with a task. Bring projects, devices, and files together."),"English welcome hero uses translated display text");
            }} finally {System.Threading.SynchronizationContext.SetSynchronizationContext(previousContext);}
            Check(english.T("项目与会话")=="Projects and chats","English project navigation label");
            Check(MessageCard.DisplayBody("状态","思考中…",english.T)=="Thinking…"&&MessageCard.DisplayBody("错误","任务失败",english.T)=="Task failed","app-owned timeline status and errors are localized");
            foreach(string kind in new[]{"你","助手","工具结果"})Check(MessageCard.DisplayBody(kind,"设置 / 用户内容 <literal>",english.T)=="设置 / 用户内容 <literal>","timeline preserves user model and tool content "+kind);
            Check(english.T("正在请求 model-x · fast（本次第 2 / 40 轮）…")=="Requesting model-x · fast (round 2 / 40)…","formatted native status translates while preserving model and round values");
        }
    }
}
