using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace AsterHand {
    internal static partial class NativeTests {
        static void BrandLayout(string directory) {
            root=Path.Combine(Path.GetFullPath(directory),"brand-"+J.Id());Directory.CreateDirectory(root);
            SetProcessDPIAware();Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            foreach(bool dark in new[]{false,true})using(var stream=new MemoryStream(Assets.Bytes(dark?"icon-dark.png":"icon.png")))using(var icon=new Bitmap(stream)) {
                Check(icon.Width==1024&&icon.Height==1024&&icon.GetPixel(0,0).A==0,"rounded artwork preserves transparent exterior corners");
                var tile=icon.GetPixel(100,512);Check(tile.A==255&&tile.R==(dark?18:255),"brand tile retains the correct opaque palette");
            }
            using(var form=new MainForm(Create("profile"),Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Resources"),0,false)) {
                form.ShowInTaskbar=false;form.StartPosition=FormStartPosition.Manual;form.Location=new Point(-20000,-20000);form.Show();
                foreach(bool dark in new[]{false,true,false,true}) {
                    form.BrandAppearanceForTest(dark);Application.DoEvents();
                    using(var image=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(image,new Rectangle(Point.Empty,form.Size));image.Save(Path.Combine(root,dark?"windows-dark.png":"windows-light.png"));}
                }
                form.ExitForTest();
            }
            J.Save(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"native-brand-theme-report.json"),J.Obj("passed",passed,"failed",0,"directory",root,"systemPreferenceHandlerUsesSameAppearancePath",true));
            Console.WriteLine("Rendered brand/theme fixtures: "+root);
        }
    }
    internal sealed partial class MainForm {
        internal void BrandAppearanceForTest(bool dark) {
            Navigate("chat");draft.Text="Brand theme draft 中文";string projectId=J.Str(project,"id"),chatId=J.Str(chat,"id");
            ApplySystemAppearance(dark);
            if(Design.Dark!=dark||draft.Text!="Brand theme draft 中文"||J.Str(project,"id")!=projectId||J.Str(chat,"id")!=chatId)throw new Exception("Theme change lost draft or active conversation");
            using(var icon=Icon.ToBitmap()){var pixel=icon.GetPixel(3,16);if(Math.Abs(pixel.R-(dark?18:255))>5)throw new Exception("Window icon did not follow appearance");}
            var brand=DescendantsForTest(side).OfType<SidebarBrand>().Single();
            using(var image=new Bitmap(brand.Width,brand.Height)){brand.DrawToBitmap(image,new Rectangle(Point.Empty,brand.Size));var pixel=image.GetPixel(Design.P(6),Design.P(30));if(Math.Abs(pixel.R-(dark?18:255))>5)throw new Exception("Sidebar brand did not follow appearance");}
            if(tray.Icon!=Icon)throw new Exception("Tray and window icons differ");
            Console.WriteLine("PASS: "+(dark?"dark":"light")+" window, tray, sidebar and draft persistence");
        }
    }
}
