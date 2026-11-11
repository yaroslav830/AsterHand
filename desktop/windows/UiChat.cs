using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace AsterHand {
    internal sealed partial class MainForm {
        void ShowChat() {
            ClearContent();Title(J.Str(chat,"name"),J.Str(project,"name")+"  /  "+T("项目与会话保存在本机"),true);UpdateNavigation();
            var body=new Panel{Dock=DockStyle.Fill,BackColor=Paper};content.Controls.Add(body);body.BringToFront();
            var top=new Panel{Dock=DockStyle.Top,Height=42,BackColor=Paper};var projectTag=L(T("项目")+"  "+J.Str(project,"name"),9);projectTag.Location=new Point(0,6);projectTag.MaximumSize=new Size(300,24);top.Controls.Add(projectTag);
            var actions=Flow();actions.AutoSize=false;actions.Dock=DockStyle.Right;actions.Width=240;actions.Height=40;
            var export=(ActionButton)B("导出会话",ExportChat,false,108);export.Height=32;var fresh=(ActionButton)B("新建会话",NewChat,false,108);fresh.Height=32;actions.Controls.Add(export);actions.Controls.Add(fresh);top.Controls.Add(actions);
            var composer=new SurfacePanel{Dock=DockStyle.Bottom,Height=226,Radius=DesignTokens.ComposerRadius,Padding=new Padding(18,14,18,12)};
            var context=Flow();context.AutoSize=false;context.Dock=DockStyle.Top;context.Height=40;
            context.Controls.Add(L("执行目标",9));target=Design.Combo(176);target.DropDownStyle=ComboBoxStyle.DropDownList;target.Margin=new Padding(5,4,12,4);target.AccessibleName=T("执行目标");target.Items.Add(new Choice("local",T("本机")));
            foreach(var p in vault.Peers.Where(p=>J.Str(p,"host").Length>0&&!J.Bool(p,"incoming",true)))target.Items.Add(new Choice(J.Str(p,"id"),J.Str(p,"name")));target.SelectedIndex=0;context.Controls.Add(target);
            var options=AiSettings.Options(vault);string model=J.Str(options,"model");modelLabel=L(model.Length>0?(J.Str(vault.State,"provider")=="chatgpt"?"ChatGPT":"API")+"  /  "+model:"请先设置 AI 服务",9);modelLabel.AutoSize=false;modelLabel.Width=280;modelLabel.Height=25;modelLabel.AutoEllipsis=true;modelLabel.Cursor=Cursors.Hand;modelLabel.Click+=(s,e)=>Navigate("settings");context.Controls.Add(modelLabel);
            var editor=new Panel{Dock=DockStyle.Fill,Padding=new Padding(2,8,2,4),BackColor=Design.Surface};
            draft=new TextBox{Multiline=true,Dock=DockStyle.Fill,BorderStyle=BorderStyle.None,Font=new Font(Font.FontFamily,11),ForeColor=Ink,ScrollBars=ScrollBars.Vertical,BackColor=Design.Surface,Text=J.Str(chat,"draft"),AccessibleName=T("输入任务")};
            var placeholder=new Label{Text=T("描述任务，或添加文件开始…"),ForeColor=Design.Muted,AutoSize=false,Dock=DockStyle.Fill,BackColor=Design.Surface,Font=draft.Font,Padding=new Padding(0,1,0,0)};editor.Controls.Add(draft);editor.Controls.Add(placeholder);placeholder.Click+=(s,e)=>{placeholder.Visible=false;draft.Focus();};
            Action cue=()=>placeholder.Visible=draft.TextLength==0&&!draft.Focused;draft.Enter+=(s,e)=>cue();draft.Leave+=(s,e)=>cue();draft.TextChanged+=(s,e)=>{if(chat!=null)chat["draft"]=draft.Text;cue();};cue();draft.KeyDown+=(s,e)=>{if(e.Control&&e.KeyCode==Keys.Enter){e.SuppressKeyPress=true;Guard(SendTask);}};
            var bottom=Flow();bottom.AutoSize=false;bottom.Dock=DockStyle.Bottom;bottom.Height=44;
            var attach=(ActionButton)B("",AddAttachments,false,40);attach.Glyph="file";attach.AccessibleName=T("附件");hints.SetToolTip(attach,T("添加附件"));
            var voice=(ActionButton)B("",StartVoice,false,40);voice.Glyph="voice";voice.AccessibleName=T("语音");hints.SetToolTip(voice,T("语音输入"));
            var read=(ActionButton)B("朗读",ReadReply,false,62);hints.SetToolTip(read,T("朗读"));bottom.Controls.AddRange(new Control[]{attach,voice,read});
            automatic=new CheckBox{Text=T("本次自动允许"),AutoSize=true,ForeColor=Muted,Margin=new Padding(10,15,10,0),AccessibleName=T("自动允许本次任务的工具操作")};hints.SetToolTip(automatic,T("自动允许本次任务的工具操作"));bottom.Controls.Add(automatic);
            send=B(job!=null?"加入队列":"发送",SendTask,true,96);((ActionButton)send).Glyph="send";stopButton=B("停止",()=>{if(job!=null)job.Cancel();queue.Clear();},false,76);stopButton.Enabled=job!=null;bottom.Controls.Add(send);bottom.Controls.Add(stopButton);
            attachmentsBar=new FlowLayoutPanel{Dock=DockStyle.Top,Height=0,AutoScroll=true,WrapContents=false,BackColor=Design.Surface};
            composer.Controls.Add(editor);composer.Controls.Add(bottom);composer.Controls.Add(attachmentsBar);composer.Controls.Add(context);editor.BringToFront();
            taskStatus=new Label{Dock=DockStyle.Bottom,Height=30,Text=T(job==null?"Ctrl + Enter 发送 · 操作前会请求确认":"任务进行中"),ForeColor=Muted,Font=new Font(Font.FontFamily,8),TextAlign=ContentAlignment.MiddleLeft,AutoEllipsis=true};
            timeline=new ConversationView{Dock=DockStyle.Fill,Translate=T,OpenPage=Navigate,Suggest=text=>{draft.Text=text;draft.Focus();}};
            body.Controls.Add(timeline);body.Controls.Add(taskStatus);body.Controls.Add(composer);body.Controls.Add(top);timeline.BringToFront();
            bool arranging=false;
            Action resize=()=>{if(arranging||body.ClientSize.Width<100)return;arranging=true;try{int width=Math.Max(1,composer.ClientSize.Width-composer.Padding.Horizontal),used=0,rows=1,rowHeight=Design.P(44);foreach(Control c in bottom.Controls){if(!c.Visible)continue;int cell=c.Width+c.Margin.Horizontal;if(used>0&&used+cell>width){rows++;used=0;}used+=cell;rowHeight=Math.Max(rowHeight,c.Height+c.Margin.Vertical);}bottom.Height=rows*rowHeight;context.Height=Math.Max(Design.P(40),target.Height+target.Margin.Vertical);composer.Height=composer.Padding.Vertical+context.Height+attachmentsBar.Height+Design.P(82)+bottom.Height;modelLabel.Width=Math.Max(Design.P(80),context.ClientSize.Width-target.Right-Design.P(24));context.WrapContents=false;}finally{arranging=false;}};
            body.SizeChanged+=(s,e)=>resize();composer.Layout+=(s,e)=>resize();bottom.SizeChanged+=(s,e)=>resize();Design.ApplyDpi(body);resize();RenderTimeline();RenderAttachments();Design.ApplyDpi(content);
        }
        void RenderTimeline(){if(timeline==null||timeline.IsDisposed)return;timeline.ShowMessages(J.List(J.Get(chat,"messages")));}
        void RenderAttachments(){if(attachmentsBar==null||attachmentsBar.IsDisposed)return;foreach(Control c in attachmentsBar.Controls.Cast<Control>().ToArray())c.Dispose();attachmentsBar.Controls.Clear();attachmentsBar.Height=attachments.Count==0?0:Design.P(36);foreach(var a in attachments.ToArray()){var value=a;var b=B(J.Str(a,"name")+"  ×",()=>{attachments.Remove(value);RenderAttachments();},false,180);b.Height=29;attachmentsBar.Controls.Add(b);Design.ApplyDpi(b);}if(attachmentsBar.Parent!=null)attachmentsBar.Parent.PerformLayout();}
    }
}
