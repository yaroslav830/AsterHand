using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

namespace AsterHand {
    internal static class Design {
        static float? dpi;
        static readonly System.Collections.Generic.HashSet<Control> scaled=new System.Collections.Generic.HashSet<Control>();
        static readonly System.Collections.Generic.HashSet<Control> themed=new System.Collections.Generic.HashSet<Control>();
        [System.Runtime.InteropServices.DllImport("uxtheme.dll",CharSet=System.Runtime.InteropServices.CharSet.Unicode)]static extern int SetWindowTheme(IntPtr window,string app,string id);
        [System.Runtime.InteropServices.DllImport("dwmapi.dll")]static extern int DwmSetWindowAttribute(IntPtr window,int attribute,ref int value,int size);
        static void NativeTheme(Control control){try{SetWindowTheme(control.Handle,Dark?"DarkMode_Explorer":"Explorer",null);if(control is Form){int value=Dark?1:0;DwmSetWindowAttribute(control.Handle,20,ref value,4);}}catch(EntryPointNotFoundException){}catch(DllNotFoundException){}}
        internal static void ApplyTheme(Control root){if(root==null||root.IsDisposed)return;if(root is ComboBox){root.BackColor=Surface;root.ForeColor=Ink;((ComboBox)root).FlatStyle=FlatStyle.Flat;}else if(root is TextBoxBase||root is ListView){if(root.BackColor==SystemColors.Window){root.BackColor=Surface;root.ForeColor=Ink;}}else if(root is Form||root is TabPage){if(root.BackColor==SystemColors.Control){root.BackColor=Canvas;root.ForeColor=Ink;}}
            if(themed.Add(root)){root.Disposed+=(s,e)=>themed.Remove(root);var combo=root as ComboBox;if(combo!=null&&combo.DrawMode==DrawMode.Normal){combo.DrawMode=DrawMode.OwnerDrawFixed;combo.DrawItem+=(s,e)=>{if(e.Bounds.Width<1)return;bool selected=(e.State&DrawItemState.Selected)!=0&&combo.DroppedDown;var fill=selected?Selected:Surface;using(var brush=new SolidBrush(fill))e.Graphics.FillRectangle(brush,e.Bounds);var text=e.Index>=0&&e.Index<combo.Items.Count?combo.GetItemText(combo.Items[e.Index]):combo.Text;TextRenderer.DrawText(e.Graphics,text,combo.Font,e.Bounds,combo.Enabled?Ink:Muted,TextFormatFlags.Left|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);if((e.State&DrawItemState.Focus)!=0)e.DrawFocusRectangle();};}if(root.IsHandleCreated)NativeTheme(root);root.HandleCreated+=(s,e)=>NativeTheme(root);}foreach(Control child in root.Controls)ApplyTheme(child);}
        internal static float DpiScale {get{if(!dpi.HasValue)using(var g=Graphics.FromHwnd(IntPtr.Zero))dpi=Math.Max(1,g.DpiX/96f);return dpi.Value;}}
        internal static int P(int value){return (int)Math.Round(value*DpiScale);}
        internal static bool IsDpiReady(Control control){return scaled.Contains(control);}
        internal static void ApplyDpi(Control root){if(root==null||root.IsDisposed)return;ApplyTheme(root);if(!scaled.Contains(root)){if(Math.Abs(DpiScale-1)>0.01f)root.Scale(new SizeF(DpiScale,DpiScale));Mark(root);RefreshLayouts(root);}else foreach(Control child in root.Controls)ApplyDpi(child);}
        static void RefreshLayouts(Control root){root.PerformLayout();var conversation=root as ConversationView;if(conversation!=null)conversation.Arrange();foreach(Control child in root.Controls)RefreshLayouts(child);}
        internal static void MarkReady(Control root){Mark(root);}
        static void Mark(Control root){if(!scaled.Add(root))return;root.Disposed+=(s,e)=>scaled.Remove(root);foreach(Control child in root.Controls)Mark(child);}
        static bool dark=SystemDarkTheme();
        internal static bool Dark { get{return dark;} }
        internal static void RefreshWindowTheme(Control root){if(root.IsHandleCreated)NativeTheme(root);}
        internal static bool SetSystemAppearance(bool next){if(next==Dark)return false;dark=next;return true;}
        internal static bool SystemDarkTheme(){try{return Convert.ToInt32(Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize","AppsUseLightTheme",1))==0;}catch{return false;}}
        static Color Tone(string role){return Dark?DesignTokens.Dark(role):DesignTokens.Light(role);}
        internal static Color Ink {get{return Tone("text");}} internal static Color Muted {get{return Tone("muted");}}
        internal static Color Accent {get{return Tone("accent");}} internal static Color Canvas {get{return Tone("canvas");}}
        internal static Color Border {get{return Tone("border");}} internal static Color Sidebar {get{return Tone("sidebar");}}
        internal static Color SidebarText {get{return Tone("text");}} internal static Color Soft {get{return Tone("soft");}}
        internal static Color Surface {get{return Tone("surface");}} internal static Color Selected {get{return Tone("selected");}}
        internal static Color OnAccent {get{return Tone("onAccent");}} internal static Color Success {get{return Tone("success");}}
        internal static Color Danger {get{return Tone("danger");}} internal static Color DangerSoft {get{return Tone("dangerSoft");}}
        internal static Color Background(Control control) {while(control!=null){if(control.BackColor.A==255)return control.BackColor;control=control.Parent;}return Canvas;}
        internal static GraphicsPath Round(RectangleF r,float radius) {float d=Math.Min(radius*2,Math.Min(r.Width,r.Height));var p=new GraphicsPath();if(d<1){p.AddRectangle(r);return p;}p.AddArc(r.X,r.Y,d,d,180,90);p.AddArc(r.Right-d,r.Y,d,d,270,90);p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.X,r.Bottom-d,d,d,90,90);p.CloseFigure();return p;}
        internal static void Fill(Graphics g,RectangleF rect,Color color,int radius) {using(var p=Round(rect,radius))using(var b=new SolidBrush(color))g.FillPath(b,p);}
        internal static void Stroke(Graphics g,RectangleF rect,Color color,int radius) {using(var p=Round(rect,radius))using(var pen=new Pen(color))g.DrawPath(pen,p);}
        internal static void Icon(Graphics g,string icon,Rectangle r,Color color) {
            var state=g.Save();g.TranslateTransform(r.X,r.Y);g.ScaleTransform(r.Width/24f,r.Height/24f);float x=0,y=0,w=24,h=24;using(var pen=new Pen(color,1.7f)){pen.StartCap=pen.EndCap=LineCap.Round;pen.LineJoin=LineJoin.Round;
                if(icon=="chat"){g.DrawRounded(pen,new RectangleF(x+2,y+3,w-4,h-7),4);g.DrawLines(pen,new[]{new PointF(x+6,y+h-4),new PointF(x+5,y+h-1),new PointF(x+11,y+h-4)});g.DrawLine(pen,x+7,y+9,x+w-7,y+9);}
                else if(icon=="devices"){g.DrawRounded(pen,new RectangleF(x+1,y+3,w-7,h-8),3);g.DrawRounded(pen,new RectangleF(x+w-10,y+9,8,h-9),2);g.DrawLine(pen,x+7,y+h-3,x+12,y+h-3);}
                else if(icon=="terminal"){g.DrawRounded(pen,new RectangleF(x+1,y+3,w-2,h-6),3);g.DrawLines(pen,new[]{new PointF(x+6,y+8),new PointF(x+10,y+12),new PointF(x+6,y+16)});g.DrawLine(pen,x+13,y+16,x+18,y+16);}
                else if(icon=="settings"){g.DrawEllipse(pen,x+5,y+5,w-10,h-10);g.DrawEllipse(pen,x+10,y+10,w-20,h-20);for(int i=0;i<8;i++){double a=i*Math.PI/4;g.DrawLine(pen,x+w/2+(float)Math.Cos(a)*9,y+h/2+(float)Math.Sin(a)*9,x+w/2+(float)Math.Cos(a)*12,y+h/2+(float)Math.Sin(a)*12);}}
                else if(icon=="plus"){g.DrawLine(pen,x+w/2,y+5,x+w/2,y+h-5);g.DrawLine(pen,x+5,y+h/2,x+w-5,y+h/2);}
                else if(icon=="search"){g.DrawEllipse(pen,x+3,y+3,w-10,h-10);g.DrawLine(pen,x+w-9,y+h-9,x+w-3,y+h-3);}
                else if(icon=="file"){g.DrawRounded(pen,new RectangleF(x+4,y+2,w-8,h-4),2);g.DrawLine(pen,x+8,y+9,x+w-8,y+9);g.DrawLine(pen,x+8,y+14,x+w-8,y+14);}
                else if(icon=="voice"){g.DrawRounded(pen,new RectangleF(x+8,y+2,w-16,h-10),4);g.DrawArc(pen,x+4,y+7,w-8,h-11,0,180);g.DrawLine(pen,x+w/2,y+h-5,x+w/2,y+h-1);g.DrawLine(pen,x+8,y+h-1,x+w-8,y+h-1);}
                else if(icon=="send"){g.DrawLines(pen,new[]{new PointF(x+3,y+h/2),new PointF(x+w-3,y+3),new PointF(x+w-8,y+h-3),new PointF(x+w/2,y+h/2),new PointF(x+3,y+h/2)});g.DrawLine(pen,x+w/2,y+h/2,x+w-3,y+3);}
                else if(icon=="stop"){g.DrawRounded(pen,new RectangleF(x+6,y+6,w-12,h-12),2);}
                else if(icon=="folder"){g.DrawLines(pen,new[]{new PointF(x+2,y+7),new PointF(x+2,y+4),new PointF(x+10,y+4),new PointF(x+13,y+7),new PointF(x+w-2,y+7),new PointF(x+w-2,y+h-3),new PointF(x+2,y+h-3),new PointF(x+2,y+7),new PointF(x+w-2,y+7)});}
                else if(icon=="arrow"){g.DrawLine(pen,x+4,y+h/2,x+w-4,y+h/2);g.DrawLine(pen,x+w-9,y+7,x+w-4,y+h/2);g.DrawLine(pen,x+w-9,y+h-7,x+w-4,y+h/2);}
                else {g.DrawLine(pen,x+w/2,y+3,x+w/2,y+h-3);g.DrawLine(pen,x+3,y+h/2,x+w-3,y+h/2);g.DrawLine(pen,x+6,y+6,x+w-6,y+h-6);g.DrawLine(pen,x+w-6,y+6,x+6,y+h-6);}
            }g.Restore(state);
        }
        static void DrawRounded(this Graphics g,Pen pen,RectangleF r,int radius) {using(var p=Round(r,radius))g.DrawPath(pen,p);}
        internal static TabControl Tabs() {return new RefinedTabs{Dock=DockStyle.Fill};}
        internal static ComboBox Combo(int width=350) {return new ComboBox{Width=width,FlatStyle=FlatStyle.Flat,BackColor=Surface,ForeColor=Ink,Margin=new Padding(4,6,4,12)};}
    }

    internal class ActionButton : Button {
        internal bool Primary,Navigation,Selected;internal string Glyph="",Subtext="";
        bool hovering,pressed;
        public ActionButton() {FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);Cursor=Cursors.Hand;Height=40;BackColor=Design.Surface;ForeColor=Design.Ink;}
        protected override void OnMouseEnter(EventArgs e){hovering=true;Invalidate();base.OnMouseEnter(e);}
        protected override void OnMouseLeave(EventArgs e){hovering=false;pressed=false;Invalidate();base.OnMouseLeave(e);}
        protected override void OnMouseDown(MouseEventArgs e){pressed=true;Invalidate();base.OnMouseDown(e);}
        protected override void OnMouseUp(MouseEventArgs e){pressed=false;Invalidate();base.OnMouseUp(e);}
        protected override void OnEnabledChanged(EventArgs e){Invalidate();base.OnEnabledChanged(e);}
        protected override void OnPaint(PaintEventArgs e) {
            var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;g.Clear(Design.Background(Parent));
            Color fill=Navigation?(Selected?Design.Selected:hovering?Design.Soft:Design.Sidebar):Primary?Design.Accent:pressed||hovering?Design.Soft:BackColor;
            Color ink=!Enabled?Design.Muted:Navigation?Design.SidebarText:Primary?Design.OnAccent:ForeColor;
            if(!Enabled&&!Navigation)fill=Design.Soft;Design.Fill(g,new RectangleF(1,1,Width-3,Height-3),fill,Design.P(DesignTokens.ControlRadius));
            if(!Navigation&&!Primary)Design.Stroke(g,new RectangleF(1,1,Width-3,Height-3),Design.Border,Design.P(DesignTokens.ControlRadius));
            int left=Design.P(Navigation?46:Glyph.Length>0?36:10);var textRect=new Rectangle(left,0,Math.Max(1,Width-left-Design.P(10)),Height);
            if(Glyph.Length>0)Design.Icon(g,Glyph,new Rectangle(Text.Length==0?(Width-Design.P(22))/2:Design.P(Navigation?14:11),(Height-Design.P(22))/2,Design.P(22),Design.P(22)),ink);
            var flags=TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine|TextFormatFlags.EndEllipsis|(Navigation||Glyph.Length>0?TextFormatFlags.Left:TextFormatFlags.HorizontalCenter);
            TextRenderer.DrawText(g,Text,Font,textRect,ink,flags);if(Focused&&ShowFocusCues)ControlPaint.DrawFocusRectangle(g,new Rectangle(5,5,Width-11,Height-11),ink,fill);
        }
    }
    internal class SurfacePanel : Panel {
        internal int Radius=DesignTokens.CardRadius;internal Color Surface=Design.Surface;
        internal bool Bordered=true;
        public SurfacePanel(){BackColor=Design.Surface;SetStyle(ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);}
        protected override void OnPaintBackground(PaintEventArgs e){e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;e.Graphics.Clear(Design.Background(Parent));Design.Fill(e.Graphics,new RectangleF(1,1,Width-3,Height-3),Surface,Design.P(Radius));if(Bordered)Design.Stroke(e.Graphics,new RectangleF(1,1,Width-3,Height-3),Design.Border,Design.P(Radius));}
    }
    internal sealed class SurfaceFlow : FlowLayoutPanel {
        public SurfaceFlow(){BackColor=Design.Surface;SetStyle(ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);}
        protected override void OnPaintBackground(PaintEventArgs e){e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;e.Graphics.Clear(Design.Background(Parent));Design.Fill(e.Graphics,new RectangleF(1,1,Width-3,Height-3),Design.Surface,Design.P(DesignTokens.CardRadius));Design.Stroke(e.Graphics,new RectangleF(1,1,Width-3,Height-3),Design.Border,Design.P(DesignTokens.CardRadius));}
    }
    internal sealed class RefinedTabs : TabControl {
        public RefinedTabs(){DrawMode=TabDrawMode.OwnerDrawFixed;SizeMode=TabSizeMode.Fixed;ItemSize=new Size(110,42);Padding=new Point(12,5);}
        protected override void OnDrawItem(DrawItemEventArgs e){bool active=e.Index==SelectedIndex;var r=GetTabRect(e.Index);using(var b=new SolidBrush(Design.Canvas))e.Graphics.FillRectangle(b,r);TextRenderer.DrawText(e.Graphics,TabPages[e.Index].Text,Font,r,active?Design.Accent:Design.Muted,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);if(active)using(var pen=new Pen(Design.Accent,3))e.Graphics.DrawLine(pen,r.Left+18,r.Bottom-3,r.Right-18,r.Bottom-3);}
    }
    internal sealed class BrandPicture : PictureBox {
        public BrandPicture(){BackColor=Color.Transparent;SizeMode=PictureBoxSizeMode.Zoom;using(var stream=new System.IO.MemoryStream(Assets.Bytes(Design.Dark?"icon-dark.png":"icon.png")))using(var image=Image.FromStream(stream))Image=new Bitmap(image);}
        protected override void Dispose(bool disposing){if(disposing&&Image!=null){Image.Dispose();Image=null;}base.Dispose(disposing);}
    }
    internal sealed class SidebarBrand : Control {
        readonly Image logo;
        public string Subtitle { get; set; }
        public SidebarBrand(){Height=84;BackColor=Design.Sidebar;SetStyle(ControlStyles.OptimizedDoubleBuffer,true);using(var stream=new System.IO.MemoryStream(Assets.Bytes(Design.Dark?"icon-dark.png":"icon.png")))using(var image=Image.FromStream(stream))logo=new Bitmap(image);}
        protected override void OnPaint(PaintEventArgs e){e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;var r=new Rectangle(Design.P(2),Design.P(12),Design.P(36),Design.P(36));e.Graphics.InterpolationMode=InterpolationMode.HighQualityBicubic;e.Graphics.DrawImage(logo,r);using(var font=new Font("Segoe UI",18,FontStyle.Bold))TextRenderer.DrawText(e.Graphics,"AsterHand",font,new Rectangle(Design.P(49),Design.P(9),Math.Max(1,Width-Design.P(51)),Design.P(38)),Design.Ink,TextFormatFlags.Left|TextFormatFlags.VerticalCenter|TextFormatFlags.NoPadding);using(var font=new Font("Segoe UI",8))TextRenderer.DrawText(e.Graphics,Subtitle??"",font,new Rectangle(Design.P(50),Design.P(49),Math.Max(1,Width-Design.P(51)),Design.P(20)),Design.Muted,TextFormatFlags.NoPadding|TextFormatFlags.EndEllipsis);}
        protected override void Dispose(bool disposing){if(disposing&&logo!=null)logo.Dispose();base.Dispose(disposing);}

    }
    internal sealed class TaskTile : ActionButton {
        internal string Hint="";
        public TaskTile(){Height=82;}
        protected override void OnPaint(PaintEventArgs e){var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;g.Clear(Design.Background(Parent));Design.Fill(g,new RectangleF(1,1,Width-3,Height-3),Design.Surface,Design.P(DesignTokens.CardRadius));Design.Stroke(g,new RectangleF(1,1,Width-3,Height-3),Design.Border,Design.P(DesignTokens.CardRadius));Design.Fill(g,new RectangleF(Design.P(14),Design.P(22),Design.P(34),Design.P(34)),Design.Soft,Design.P(10));Design.Icon(g,Glyph,new Rectangle(Design.P(20),Design.P(28),Design.P(22),Design.P(22)),Design.Accent);using(var title=new Font(Font.FontFamily,10,FontStyle.Bold))TextRenderer.DrawText(g,Text,title,new Rectangle(Design.P(62),Design.P(17),Width-Design.P(76),Design.P(25)),Design.Ink,TextFormatFlags.EndEllipsis|TextFormatFlags.VerticalCenter);TextRenderer.DrawText(g,Hint,Font,new Rectangle(Design.P(62),Design.P(44),Width-Design.P(76),Design.P(21)),Design.Muted,TextFormatFlags.EndEllipsis);if(Focused&&ShowFocusCues)ControlPaint.DrawFocusRectangle(g,new Rectangle(5,5,Width-11,Height-11));}
    }
}
