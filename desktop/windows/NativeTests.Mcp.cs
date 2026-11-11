using System;
using System.IO;
using System.Windows.Forms;

namespace AsterHand {
    internal static partial class NativeTests {
        static void McpDemo(string directory,bool controller){
            string profile=Path.GetFullPath(directory),repo=Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"..",".."));
            string allowed=Path.Combine(repo,".private","mcp-release-demo")+Path.DirectorySeparatorChar;
            if(!profile.StartsWith(allowed,StringComparison.OrdinalIgnoreCase)||Directory.Exists(profile))throw new InvalidOperationException("Choose a new isolated demo profile");
            var v=new Vault(profile,controller?Path.Combine(repo,".private","control","control.json"):null);
            v.State["name"]=controller?"AsterHand QA controller":"AsterHand QA Windows";v.State["language"]="en";v.State["screenEnabled"]=true;v.State["workspace"]=Path.Combine(profile,"workspace");Directory.CreateDirectory((string)v.State["workspace"]);v.Save();
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            using(var form=new MainForm(v,Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Resources"),0,true)){form.WindowState=FormWindowState.Maximized;Application.Run(form);}
        }
    }
}
