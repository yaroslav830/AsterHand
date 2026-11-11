using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace AsterHand {
    internal static class RemoteScreen {
        internal static bool Point(Size client,Size image,Point position,out PointF point) {
            point=PointF.Empty;if(client.Width<=0||client.Height<=0||image.Width<=0||image.Height<=0)return false;
            double ratio=Math.Min(client.Width/(double)image.Width,client.Height/(double)image.Height);
            double width=image.Width*ratio,height=image.Height*ratio;
            double x=(position.X-(client.Width-width)/2)/width,y=(position.Y-(client.Height-height)/2)/height;
            if(x<0||x>1||y<0||y>1)return false;
            point=new PointF((float)x,(float)y);return true;
        }
    }
    internal sealed partial class MainForm {
        void OpenScreen(object peer) {
            var form=new Form{Icon=Icon,Text=J.Str(peer,"name")+" · AsterHand",Size=new Size(520,830),MinimumSize=new Size(320,400),StartPosition=FormStartPosition.CenterParent,AutoScaleMode=AutoScaleMode.None,Font=Font};
            var picture=new PictureBox{Dock=DockStyle.Fill,BackColor=Color.FromArgb(20,24,29),SizeMode=PictureBoxSizeMode.Zoom};
            var footer=Flow();footer.Dock=DockStyle.Bottom;footer.Height=106;footer.AutoSize=false;
            var status=L("正在连接屏幕…",9);status.Width=440;footer.Controls.Add(status);
            var text=Field("");text.Width=220;text.AccessibleName=T("远程输入");footer.Controls.Add(text);
            string id=J.Str(peer,"id");var cancel=new CancellationTokenSource();var token=cancel.Token;Task streaming=null;
            footer.Controls.Add(B("发送文字",()=>Async(async()=>{await hub.Request(id,"execute",J.Obj("tool","screen_type","arguments",J.Obj("text",text.Text)),token);if(!text.IsDisposed)text.Clear();}),false,94));
            footer.Controls.Add(B("主屏幕",()=>Async(async()=>{await hub.Request(id,"execute",J.Obj("tool","screen_home","arguments",J.Obj()),token);}),false,90));
            form.Controls.Add(picture);form.Controls.Add(footer);
            Point start=Point.Empty;bool pressed=false;var elapsed=new Stopwatch();
            picture.MouseDown+=(s,e)=>{if(e.Button!=MouseButtons.Left||picture.Image==null)return;PointF point;if(!RemoteScreen.Point(picture.ClientSize,picture.Image.Size,e.Location,out point))return;start=e.Location;pressed=true;elapsed.Restart();picture.Capture=true;};
            picture.MouseUp+=(s,e)=>{if(e.Button!=MouseButtons.Left||!pressed)return;pressed=false;picture.Capture=false;elapsed.Stop();if(picture.Image==null)return;PointF a,b;if(!RemoteScreen.Point(picture.ClientSize,picture.Image.Size,start,out a)||!RemoteScreen.Point(picture.ClientSize,picture.Image.Size,e.Location,out b))return;
                bool swipe=Math.Abs(e.X-start.X)+Math.Abs(e.Y-start.Y)>Design.P(8);
                object args=swipe?J.Obj("x",a.X,"y",a.Y,"x2",b.X,"y2",b.Y,"duration",Math.Max(.15,Math.Min(1.5,elapsed.Elapsed.TotalSeconds))):J.Obj("x",b.X,"y",b.Y);
                Async(async()=>{await hub.Request(id,"execute",J.Obj("tool",swipe?"screen_swipe":"screen_tap","arguments",args),token);});};
            form.FormClosed+=(s,e)=>{cancel.Cancel();if(picture.Image!=null){picture.Image.Dispose();picture.Image=null;}if(streaming==null)cancel.Dispose();else streaming.ContinueWith(done=>cancel.Dispose());};
            Design.ApplyDpi(form);form.Show(this);
            streaming=StreamViewer(id,form,picture,status,token);Async(async()=>await streaming);
        }
        async Task StreamViewer(string id,Form form,PictureBox picture,Label status,CancellationToken token) {
            int scheduled=0,frames=0;
            try{await hub.Stream(id,bytes=>{if(form.IsDisposed||Interlocked.Exchange(ref scheduled,1)!=0)return;Ui(()=>{try{if(form.IsDisposed)return;using(var stream=new MemoryStream(bytes))using(var image=Image.FromStream(stream)){var old=picture.Image;picture.Image=new Bitmap(image);if(old!=null)old.Dispose();}status.Text=T("实时屏幕")+" · "+(++frames)+" "+T("帧");}finally{Interlocked.Exchange(ref scheduled,0);}});},token);}
            catch(OperationCanceledException){}
            catch(Exception e){if(!form.IsDisposed)status.Text=J.Error(e);}
        }
    }
}
