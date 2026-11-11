using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace AsterHand {
    internal static class Program {
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
        public static string Resources,Repository,DataPath;
        static Localizer startupLocalizer;
        static string StartupText(string text) {if(startupLocalizer==null)startupLocalizer=new Localizer(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Resources","localizations.json"),"system");return startupLocalizer.T(text);}
        [STAThread] public static int Main(string[] args) {try{object release=Microsoft.Win32.Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full","Release",0);if(Convert.ToInt32(release)<394802){MessageBox.Show(StartupText("请先安装 .NET Framework 4.6.2 或更高版本，再启动 AsterHand。"),"AsterHand");return 1;}SetProcessDPIAware();ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Resources=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Resources");Repository=FindRepository();DataPath=Argument(args,"--data-dir")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"AsterHand","Windows");string full=Path.GetFullPath(DataPath);bool acquired;using(var single=new Mutex(true,"Local\\AsterHand.Windows."+Wire.Hex(Wire.Hash(Wire.Utf8(full.ToLowerInvariant()))).Substring(0,24),out acquired)){if(!acquired){MessageBox.Show(StartupText("AsterHand 已在运行，请从任务栏托盘打开。"),"AsterHand");return 0;}string legacy=args.Contains("--isolated")?null:Path.Combine(Repository??AppDomain.CurrentDomain.BaseDirectory,".private","control","control.json");var vault=new Vault(full,legacy);int port;bool testPort=int.TryParse(Argument(args,"--port"),out port);using(var window=new MainForm(vault,Resources,testPort?port:18769,!args.Contains("--no-listen"))){Application.Run(window);}return 0;}}catch(Exception e){MessageBox.Show(StartupText(J.Error(e)),StartupText("AsterHand · 启动失败"),MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}}
        static string Argument(string[] args,string key) {int index=Array.IndexOf(args,key);return index>=0&&index+1<args.Length?args[index+1]:null;}
        static string FindRepository() {var p=new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);for(int i=0;p!=null&&i<6;i++,p=p.Parent)if(Directory.Exists(Path.Combine(p.FullName,"Sources"))&&File.Exists(Path.Combine(p.FullName,"version.json")))return p.FullName;return null;}
    }
}
