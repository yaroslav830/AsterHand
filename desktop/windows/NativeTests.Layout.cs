using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace AsterHand {
    internal static partial class NativeTests {
        [System.Runtime.InteropServices.DllImport("user32.dll")]static extern bool SetProcessDPIAware();
        static void Layout(string directory,bool aware=true) {root=Path.Combine(Path.GetFullPath(directory),J.Id());Directory.CreateDirectory(root);if(aware)SetProcessDPIAware();Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);using(var form=new MainForm(Create("profile"),Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Resources"),0,false)){
                form.ShowInTaskbar=false;form.StartPosition=FormStartPosition.Manual;form.Location=new Point(-20000,-20000);form.Show();
                foreach(var size in new[]{new Size(900,640),new Size(1160,800),new Size(1600,900)})foreach(string page in new[]{"chat","settings","chatgpt","devices"}){form.Size=size;if(page=="chatgpt")form.SelectProviderForTest("chatgpt");else form.SelectProviderForTest("compatible");form.NavigateForTest(page=="chatgpt"?"settings":page);Application.DoEvents();if(page=="chat"){form.AssertGeometryForTest();}if(page=="chatgpt")form.AssertProviderSwitchForTest();using(var bmp=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bmp,new Rectangle(Point.Empty,form.Size));bmp.Save(Path.Combine(root,page+"-"+size.Width+"x"+size.Height+".png"));}}
                form.LanguageSwitchForTest();form.FileTargetSwitchForTest();form.SelectProviderForTest("compatible");form.NavigateForTest("chat");if(!form.DraftIsolationForTest())throw new Exception("Draft leaked into a new chat");Console.WriteLine("PASS: new chat does not inherit the previous draft");form.ExitForTest();
            }J.Save(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,aware?"native-layout-aware.json":"native-layout-unaware.json"),J.Obj("dpiScale",Design.DpiScale,"geometryPassed",true,"floatingRemoved",true,"directory",root));Console.WriteLine("Rendered native layout fixtures: "+root);}
    }
    internal sealed partial class MainForm {
        internal void LanguageSwitchForTest(){
            Navigate("chat");draft.Text="Draft — 日本語 123";Navigate("settings");
            var tabs=DescendantsForTest(content).OfType<TabControl>().First();
            tabs.SelectedTab=tabs.TabPages.Cast<TabPage>().First(tab=>tab.Text==T("界面语言"));
            foreach(var next in new[]{"en","ja","es","fr","zh-CN","en"}){
                var language=DescendantsForTest(content).OfType<ComboBox>().First(c=>c.AccessibleName==T("界面语言"));
                language.SelectedItem=language.Items.Cast<Choice>().First(c=>c.Id==next);
                DescendantsForTest(tabs.SelectedTab).OfType<Button>().First(c=>c.Text==T("保存")).PerformClick();
                Application.DoEvents();tabs=DescendantsForTest(content).OfType<TabControl>().First();
                if(!Visible||loc.Language!=next||tabs.SelectedTab.Text!=T("界面语言")||navSettings.Text!=T("设置"))throw new Exception("Locale switch lost the settings page or window: "+next);
                var sameTabs=tabs;ChangeUiLanguage(next);
                if(sameTabs.IsDisposed)throw new Exception("Saving the same language rebuilt the window");
            }
            Navigate("chat");if(draft.Text!="Draft — 日本語 123")throw new Exception("Locale switch lost draft");
            foreach(var route in new[]{"chat","devices","terminal","settings"}){
                Navigate(route);
                var leaked=DescendantsForTest(content).Where(c=>(c is Label||c is Button||c is TabPage)&&!(route=="chat"&&c.Name=="PageTitle"))
                    .Select(c=>(c.Text??"").Replace(vault.DirectoryPath,"")).Where(s=>System.Text.RegularExpressions.Regex.IsMatch(s,@"[\u3400-\u9fff]")).Distinct().ToArray();
                if(leaked.Length>0)throw new Exception("Untranslated English UI on "+route+": "+string.Join(" | ",leaked));
            }
            Console.WriteLine("PASS: repeated native language switches retain settings tab, visibility and draft");
            Console.WriteLine("PASS: no Chinese labels in English chat, devices, terminal or settings");
        }
        internal void FileTargetSwitchForTest() {
            string prior=terminalTarget;var peer=J.Obj("id","layout-phone","name","QA Phone","incoming",false);object priorPeers=J.Get(vault.State,"peers");vault.State["peers"]=vault.Peers.Concat(new object[]{peer}).ToArray();
            try {terminalTarget="local";using(var tab=new TabPage()){BuildFiles(tab);var controls=DescendantsForTest(tab).ToArray();var target=controls.OfType<ComboBox>().First();var path=controls.OfType<TextBox>().First(c=>c.AccessibleName==T("文件路径"));var editor=controls.OfType<TextBox>().First(c=>c.AccessibleName==T("文件内容"));if(path.Text!=tools.Work)throw new Exception("Local file path is incorrect");target.SelectedIndex=target.Items.Count-1;if(path.Text!=".")throw new Exception("Remote file page leaked Windows path");editor.Text="previous phone file";target.SelectedIndex=0;if(editor.Text.Length!=0||path.Text!=tools.Work)throw new Exception("Switching file target retained the previous editor or path");}terminalTarget="layout-phone";using(var tab=new TabPage()){BuildFiles(tab);if(DescendantsForTest(tab).OfType<TextBox>().First(c=>c.AccessibleName==T("文件路径")).Text!=".")throw new Exception("Opening files from a remote device leaked local path");}Console.WriteLine("PASS: file target switching isolates paths and editor content");}
            finally{terminalTarget=prior;vault.State["peers"]=priorPeers;}
        }
        internal void NavigateForTest(string value) {Navigate(value);}
        internal void SelectProviderForTest(string value) {vault.State["provider"]=value;}
        static System.Collections.Generic.IEnumerable<Control> DescendantsForTest(Control root){foreach(Control child in root.Controls){yield return child;foreach(Control item in DescendantsForTest(child))yield return item;}}
        internal void AssertProviderSwitchForTest(){var picker=DescendantsForTest(content).OfType<ComboBox>().First(c=>c.AccessibleName==T("AI 服务"));foreach(int index in new[]{1,0,1,0}){picker.SelectedIndex=index;Application.DoEvents();}var button=DescendantsForTest(content).OfType<Button>().First(c=>c.Text==T("Continue with ChatGPT"));if(button.Width<Design.P(220)||button.Height<Design.P(36))throw new Exception("Dynamic provider fields were not DPI scaled");Console.WriteLine("PASS: repeated provider switching preserves button dimensions at "+Design.DpiScale);}
        internal bool DraftIsolationForTest() {var previous=chat;draft.Text="isolated draft fixture";NewChat();return draft.Text.Length==0&&J.Str(previous,"draft")=="isolated draft fixture";}
        internal void AssertGeometryForTest(){if(draft.Height<Design.P(60))throw new Exception("Composer input is clipped: "+draft.Height);if(timeline.HorizontalScroll.Visible)throw new Exception("Unexpected horizontal conversation scrollbar");var header=content.Controls.Cast<Control>().SelectMany(c=>c.Controls.Cast<Control>()).FirstOrDefault(c=>c.Name=="PageTitle");if(header==null||header.Height<TextRenderer.MeasureText("国Ag",header.Font).Height)throw new Exception("Page title clipped");if(GetType().Assembly.GetType("AsterHand.FloatingForm")!=null)throw new Exception("Floating window still shipped");Console.WriteLine("PASS: input, title, conversation bounds and no floating UI at "+(Design.DpiScale*100)+"%");}
        internal void ExitForTest() {exiting=true;Close();}
    }
}
