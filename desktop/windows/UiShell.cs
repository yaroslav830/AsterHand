using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using System.Runtime.InteropServices;

namespace AsterHand {
    internal sealed partial class MainForm {
        readonly ToolTip hints=new ToolTip{AutoPopDelay=8000,InitialDelay=450,ReshowDelay=150};
        ActionButton navChat,navDevices,navTerminal,navSettings;Label sidebarState;
        int selectedSettingsTab;
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr window,uint message,IntPtr wparam,IntPtr lparam);
        [DllImport("user32.dll")] static extern bool RedrawWindow(IntPtr window,IntPtr update,IntPtr region,uint flags);
        Button B(string text,Action action,bool primary=false,int width=110) {
            var b=new ActionButton{Text=T(text),Width=width,Height=40,Primary=primary,BackColor=Design.Surface,ForeColor=Ink,
                Margin=new Padding(4),AccessibleName=T(text),AutoEllipsis=true,Font=new Font(Font.FontFamily,9F)};
            b.Click+=(s,e)=>Guard(action);return b;
        }
        Label L(string text,int size=10,bool bold=false) {return new Label{Text=T(text),AutoSize=true,Font=new Font(Font.FontFamily,size,bold?FontStyle.Bold:FontStyle.Regular),ForeColor=size<10?Muted:Ink,Margin=new Padding(4,8,4,7),MaximumSize=new Size(780,0)};}
        TextBox Field(string value,bool password=false) {return new TextBox{Text=value,Width=350,Height=30,UseSystemPasswordChar=password,BorderStyle=BorderStyle.FixedSingle,ForeColor=Ink,BackColor=Design.Surface,Margin=new Padding(4,6,4,14),Font=new Font(Font.FontFamily,10)};}
        FlowLayoutPanel Flow(bool vertical=false) {return new FlowLayoutPanel{AutoSize=true,FlowDirection=vertical?FlowDirection.TopDown:FlowDirection.LeftToRight,WrapContents=!vertical,Margin=new Padding(0),Padding=new Padding(0),BackColor=Color.Transparent};}
        ActionButton Navigation(string label,string glyph,string route) {var b=(ActionButton)B(label,()=>Navigate(route),false,208);b.Height=46;b.Margin=new Padding(0,0,0,7);b.Navigation=true;b.Glyph=glyph;return b;}
        void BuildShell() {
            IntPtr handle=IsHandleCreated&&Visible?Handle:IntPtr.Zero;
            if(handle!=IntPtr.Zero)SendMessage(handle,0x000B,IntPtr.Zero,IntPtr.Zero);
            SuspendLayout();
            try{BuildShellContents();}
            finally {
                rebuilding=false;
                try{ResumeLayout(true);}
                finally{if(handle!=IntPtr.Zero){SendMessage(handle,0x000B,new IntPtr(1),IntPtr.Zero);RedrawWindow(handle,IntPtr.Zero,IntPtr.Zero,0x0185);}}
            }
        }
        void ChangeUiLanguage(string next){SaveDraft();string previous=loc.Language;vault.State["language"]=next;vault.Save();loc.Set(next);if(previous==loc.Language)return;if(tray!=null&&tray.ContextMenuStrip!=null){tray.ContextMenuStrip.Items[0].Text=T("打开 AsterHand");tray.ContextMenuStrip.Items[1].Text=T("退出");}BuildShell();}
        void BuildShellContents() {
            rebuilding=true;foreach(Control c in Controls.Cast<Control>().ToArray())c.Dispose();Controls.Clear();
            side=new Panel{Dock=DockStyle.Left,Width=254,BackColor=Design.Sidebar,Padding=new Padding(22,8,22,16)};
            content=new Panel{Dock=DockStyle.Fill,Padding=new Padding(32,20,32,22),BackColor=Paper};Controls.Add(content);Controls.Add(side);
            var brand=new SidebarBrand{Dock=DockStyle.Top,Subtitle=T("本机工作空间")};
            var bottom=new Panel{Dock=DockStyle.Bottom,Height=128};
            navSettings=Navigation("设置","settings","settings");navSettings.Dock=DockStyle.Top;bottom.Controls.Add(navSettings);
            var local=new Label{Text=J.Str(vault.State,"name"),ForeColor=Design.Ink,AutoEllipsis=true,Location=new Point(7,70),Size=new Size(192,22),Font=new Font(Font.FontFamily,9,FontStyle.Bold)};
            sidebarState=new Label{ForeColor=Design.Muted,Location=new Point(7,95),Size=new Size(194,19),Font=new Font(Font.FontFamily,8),AutoEllipsis=true};bottom.Controls.Add(local);bottom.Controls.Add(sidebarState);
            var nav=Flow(true);nav.AutoSize=false;nav.Dock=DockStyle.Top;nav.Height=170;nav.BackColor=side.BackColor;
            navChat=Navigation("AI 会话","chat","chat");navDevices=Navigation("连接设备","devices","devices");navTerminal=Navigation("终端与文件","terminal","terminal");nav.Controls.AddRange(new Control[]{navChat,navDevices,navTerminal});
            var projects=new Panel{Dock=DockStyle.Fill,Padding=new Padding(0,8,0,0),BackColor=side.BackColor};
            var heading=new Panel{Dock=DockStyle.Top,Height=44,BackColor=side.BackColor};var title=new Label{Text=T("项目与会话"),AutoSize=true,ForeColor=Design.Muted,Location=new Point(6,12),Font=new Font(Font.FontFamily,8,FontStyle.Bold)};heading.Controls.Add(title);
            var add=(ActionButton)B("+",NewProject,false,30);add.Navigation=false;add.Text="";add.Glyph="plus";add.BackColor=Design.Sidebar;add.ForeColor=Design.SidebarText;add.Height=30;add.Location=new Point(178,4);add.AccessibleName=T("新建项目");hints.SetToolTip(add,T("新建项目"));heading.Controls.Add(add);
            var create=(ActionButton)B("新建会话",NewChat,true,208);create.Dock=DockStyle.Top;create.Height=40;create.Glyph="plus";
            var searchBox=new Panel{Dock=DockStyle.Top,Height=46,BackColor=side.BackColor,Padding=new Padding(8,11,7,7)};
            search=new TextBox{BorderStyle=BorderStyle.None,BackColor=Design.Soft,ForeColor=Design.Ink,Dock=DockStyle.Fill,Font=new Font(Font.FontFamily,9),AccessibleName=T("搜索会话")};
            searchBox.BackColor=search.BackColor;searchBox.Controls.Add(search);var searchCue=new Label{Text=T("搜索会话"),ForeColor=Design.Muted,BackColor=search.BackColor,Dock=DockStyle.Fill,Font=search.Font};searchBox.Controls.Add(searchCue);searchCue.Click+=(s,e)=>{searchCue.Visible=false;search.Focus();};Action showSearchCue=()=>searchCue.Visible=search.TextLength==0&&!search.Focused;search.Enter+=(s,e)=>showSearchCue();search.Leave+=(s,e)=>showSearchCue();search.TextChanged+=(s,e)=>showSearchCue();hints.SetToolTip(search,T("搜索会话"));search.TextChanged+=(s,e)=>FillTree();
            var treeHost=new Panel{Dock=DockStyle.Fill,Padding=new Padding(0,10,0,0),BackColor=side.BackColor};
            tree=new TreeView{Dock=DockStyle.Fill,BorderStyle=BorderStyle.None,BackColor=side.BackColor,ForeColor=Design.SidebarText,
                ShowLines=false,ShowRootLines=false,ShowPlusMinus=false,HideSelection=false,FullRowSelect=true,ItemHeight=34,Indent=15,DrawMode=TreeViewDrawMode.OwnerDrawText};
            tree.DrawNode+=(s,e)=>{bool selected=e.Node==tree.SelectedNode;var r=new Rectangle(0,e.Bounds.Top,tree.ClientSize.Width,e.Bounds.Height);using(var background=new SolidBrush(tree.BackColor))e.Graphics.FillRectangle(background,r);
                if(selected)Design.Fill(e.Graphics,new RectangleF(0,r.Y+2,r.Width-2,r.Height-4),Design.Selected,7);
                bool root=e.Node.Parent==null;using(var f=new Font(Font.FontFamily,root?9:8.75f,root?FontStyle.Bold:FontStyle.Regular))TextRenderer.DrawText(e.Graphics,e.Node.Text,f,new Rectangle(e.Bounds.X+5,r.Y,Math.Max(1,r.Width-e.Bounds.X-9),r.Height),selected?Design.Ink:root?Design.Ink:Design.SidebarText,TextFormatFlags.EndEllipsis|TextFormatFlags.VerticalCenter);};
            tree.AfterSelect+=(s,e)=>{if(rebuilding||e.Node.Tag==null)return;SelectConversation((object[])e.Node.Tag);};
            tree.MouseDown+=(s,e)=>{if(e.Button==MouseButtons.Right){var node=tree.GetNodeAt(e.Location);if(node!=null)tree.SelectedNode=node;}};
            var menu=new ContextMenuStrip();menu.Opening+=(s,e)=>BuildProjectMenu(menu);tree.ContextMenuStrip=menu;
            treeHost.Controls.Add(tree);projects.Controls.Add(treeHost);projects.Controls.Add(searchBox);projects.Controls.Add(create);projects.Controls.Add(heading);treeHost.BringToFront();
            side.Controls.Add(projects);side.Controls.Add(bottom);side.Controls.Add(nav);side.Controls.Add(brand);projects.BringToFront();
            Design.ApplyTheme(this);Design.ApplyDpi(side);Design.ApplyDpi(content);FillTree();rebuilding=false;Navigate(page);
        }
        void SelectConversation(object[] tag) {SaveDraft();draft=null;project=J.Map(tag[0]);if(tag[1]!=null)chat=J.Map(tag[1]);else{var list=J.List(J.Get(project,"chats"));chat=list.Count>0?J.Map(list[0]):store.NewChat(project);}attachments.Clear();attachments.AddRange(J.List(J.Get(chat,"attachments")));page="chat";ShowChat();Design.ApplyDpi(content);UpdateNavigation();}
        void UpdateNavigation() {foreach(var item in new[]{new object[]{navChat,"chat"},new object[]{navDevices,"devices"},new object[]{navTerminal,"terminal"},new object[]{navSettings,"settings"}}){var b=item[0] as ActionButton;if(b==null||b.IsDisposed)continue;b.Selected=page==(string)item[1];b.Invalidate();}if(sidebarState!=null&&!sidebarState.IsDisposed)sidebarState.Text=T(job==null?"本机工作空间":"任务进行中")+"  ·  "+vault.Peers.Count+" "+T("已配对");}
        void Title(string heading,string subtitle,bool rawHeading=false) {
            var panel=new Panel{Dock=DockStyle.Top,Height=100,BackColor=Paper};var overline=L("AsterHand / "+T("本机工作空间"),8);overline.ForeColor=Muted;
            var title=L(heading,23,true);title.Name="PageTitle";if(rawHeading)title.Text=heading;title.AutoSize=false;title.AutoEllipsis=true;
            var sub=L(subtitle,9);sub.AutoSize=false;sub.AutoEllipsis=true;
            panel.Controls.AddRange(new Control[]{overline,title,sub});content.Controls.Add(panel);
            Action layout=()=>{int w=Math.Max(80,panel.ClientSize.Width-Design.P(8));overline.Location=new Point(0,0);int y=overline.PreferredHeight+Design.P(8);int h=TextRenderer.MeasureText("国Ag",title.Font).Height+Design.P(4);title.SetBounds(0,y,w,h);y+=h+Design.P(5);sub.SetBounds(0,y,w,sub.PreferredHeight+Design.P(2));panel.Height=y+sub.Height+Design.P(12);};
            panel.SizeChanged+=(s,e)=>{if(title.Width!=panel.Width-Design.P(8))layout();};bool inLayout=false;panel.Layout+=(s,e)=>{if(inLayout)return;inLayout=true;try{layout();}finally{inLayout=false;}};panel.HandleCreated+=(s,e)=>layout();layout();
        }
        void BuildProjectMenu(ContextMenuStrip menu) {
            menu.Items.Clear();if(tree.SelectedNode==null)return;var tag=tree.SelectedNode.Tag as object[];if(tag==null)return;bool isProject=tag[1]==null;
            menu.Items.Add(T(isProject?"重命名项目":"重命名会话"),null,(s,e)=>Guard(()=>{if(isProject)RenameProject();else RenameCurrent();}));
            if(isProject){menu.Items.Add(T("选择项目目录"),null,(s,e)=>Guard(ChooseProjectDirectory));menu.Items.Add(T("删除项目"),null,(s,e)=>Guard(DeleteProject));}
            else {menu.Items.Add(T("导出会话"),null,(s,e)=>Guard(ExportChat));menu.Items.Add(T("删除会话"),null,(s,e)=>Guard(DeleteChat));}
        }
        void RenameProject(){if(job!=null)throw new Exception("请先停止当前 AI 任务");string name=Prompt("重命名项目","项目名称",J.Str(project,"name"));if(string.IsNullOrWhiteSpace(name))return;project["name"]=name.Trim();store.Save();FillTree();Navigate("chat");}
        void ChooseProjectDirectory(){if(job!=null)throw new Exception("请先停止当前 AI 任务");using(var dialog=new FolderBrowserDialog{SelectedPath=J.Str(project,"workspace",J.Str(vault.State,"workspace")),Description=T("选择项目目录")})if(dialog.ShowDialog(this)==DialogResult.OK){project["workspace"]=dialog.SelectedPath;store.Save();}}
        void DeleteProject(){if(job!=null)throw new Exception("请先停止当前 AI 任务");if(MessageBox.Show(this,T("删除项目及其会话记录？工作目录中的文件会保留。"),"AsterHand",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;SaveDraft();draft=null;attachments.Clear();store.Projects.Remove(project);if(store.Projects.Count==0)project=store.Create("AsterHand","");else project=J.Map(store.Projects[0]);var chats=J.List(J.Get(project,"chats"));chat=chats.Count==0?store.NewChat(project):J.Map(chats[0]);store.Save();FillTree();Navigate("chat");}
        void ExportChat(){using(var dialog=new SaveFileDialog{Filter="JSON (*.json)|*.json",FileName="AsterHand-chat.json",Title=T("导出会话")})if(dialog.ShowDialog(this)==DialogResult.OK){SaveDraft();J.Save(dialog.FileName,J.Obj("version",1,"project",J.Str(project,"name"),"chat",chat));}}
    }
}
