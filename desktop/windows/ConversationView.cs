using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace AsterHand {
    internal sealed class ConversationView : Panel {
        bool arranging;readonly List<MessageCard> cards=new List<MessageCard>();WelcomeView welcome;MessageCard preview;
        internal Func<string,string> Translate;internal Action<string> Suggest;internal Action<string> OpenPage;
        public ConversationView(){AutoScroll=true;BackColor=Design.Canvas;DoubleBuffered=true;AccessibleName="Conversation";}
        internal void ShowMessages(IEnumerable<object> values) {
            SuspendLayout();foreach(Control c in Controls.Cast<Control>().ToArray())c.Dispose();Controls.Clear();cards.Clear();preview=null;
            var messages=values.ToList();if(messages.Count==0){welcome=new WelcomeView(Translate,Suggest,OpenPage);Controls.Add(welcome);Design.MarkReady(welcome);}else{welcome=null;foreach(var message in messages){var c=new MessageCard(J.Str(message,"kind"),J.Str(message,"text"),J.Str(message,"time"),Translate);cards.Add(c);Controls.Add(c);Design.MarkReady(c);}}
            ResumeLayout();Arrange();if(cards.Count>0)ScrollControlIntoView(cards.Last());
        }
        internal void SetPreview(string role,string text) {if(preview==null){preview=new MessageCard(role,text,Translate("正在生成回复…"),Translate);cards.Add(preview);Controls.Add(preview);Design.MarkReady(preview);}else preview.SetBody(text);Arrange();ScrollControlIntoView(preview);}
        protected override void OnSizeChanged(EventArgs e){base.OnSizeChanged(e);Arrange();}
        internal void Arrange(){if(arranging||ClientSize.Width<50)return;arranging=true;try{SuspendLayout();int available=Math.Max(200,ClientSize.Width-Design.P(24)),y=Design.P(18);int scroll=AutoScrollPosition.Y;
            if(welcome!=null){welcome.Bounds=new Rectangle(Design.P(8),scroll+Design.P(10),available-Design.P(8),Math.Max(Design.P(330),ClientSize.Height-Design.P(24)));AutoScrollMinSize=new Size(0,welcome.Height+Design.P(20));}
            else {foreach(var c in cards){int width=Math.Min(c.User?Design.P(650):Design.P(850),available-Design.P(12));c.Width=width;c.Measure();c.Location=new Point(c.User?available-width:Design.P(4),y+scroll);y+=c.Height+Design.P(16);}AutoScrollMinSize=new Size(0,y+Design.P(12));}
            ResumeLayout();}finally{arranging=false;}}
    }
    internal sealed class MessageCard : SurfacePanel {
        readonly Label caption;readonly TextBox body;readonly bool detail;bool expanded;readonly string role;readonly Func<string,string> translate;
        internal bool User {get;private set;}
        internal static string DisplayBody(string kind,string text,Func<string,string> t) {return new[]{"状态","错误","进度","用量","提示","后台","已停止","自动允许"}.Contains(kind)?t(text):text;}
        internal MessageCard(string kind,string text,string time,Func<string,string> t) {translate=t;role=kind;User=kind=="你";detail=kind=="工具请求"||kind=="工具结果";Surface=User?Design.Soft:kind=="错误"?Design.DangerSoft:detail?Design.Surface:Design.Canvas;Bordered=User||detail||kind=="错误";BackColor=Surface;Padding=new Padding(18);Radius=DesignTokens.CardRadius;
            caption=new Label{ForeColor=User?Design.Accent:Design.Muted,AutoEllipsis=true,Font=new Font("Microsoft YaHei UI",8.5f,FontStyle.Bold),BackColor=Surface};
            caption.Text=t(kind)+"  ·  "+time+(detail?"    + "+t("展开详情"):"");caption.Cursor=detail?Cursors.Hand:Cursors.Default;
            body=new TextBox{Multiline=true,ReadOnly=true,BorderStyle=BorderStyle.None,WordWrap=true,Text=DisplayBody(kind,text,t),BackColor=Surface,ForeColor=Design.Ink,Font=new Font(detail?"Consolas":"Microsoft YaHei UI",detail?9:10.5f),AccessibleName=t(kind),ScrollBars=ScrollBars.None};
            Controls.Add(body);Controls.Add(caption);caption.Click+=(s,e)=>{if(!detail)return;expanded=!expanded;caption.Text=t(kind)+"    "+t(expanded?"收起详情":"展开详情");var p=Parent as ConversationView;if(p!=null)p.Arrange();};
            var menu=new ContextMenuStrip();menu.Items.Add(t("复制"),null,(s,e)=>Clipboard.SetText(body.Text));body.ContextMenuStrip=menu;Measure();}
        internal void SetBody(string text){body.Text=text;Measure();}
        internal void Measure(){int w=Math.Max(Design.P(160),Width-Design.P(40));caption.SetBounds(Design.P(20),Design.P(15),w,caption.PreferredHeight+Design.P(3));bool visible=!detail||expanded;body.Visible=visible;if(visible){int measured=TextRenderer.MeasureText(body.Text.Length==0?" ":body.Text,body.Font,new Size(w,100000),TextFormatFlags.WordBreak|TextFormatFlags.TextBoxControl|TextFormatFlags.NoPadding).Height+Design.P(10);int h=Math.Min(Design.P(620),Math.Max(Design.P(28),measured));body.ScrollBars=measured>Design.P(620)?ScrollBars.Vertical:ScrollBars.None;body.SetBounds(Design.P(20),caption.Bottom+Design.P(10),w,h);Height=body.Bottom+Design.P(18);}else{caption.Text=translate(role)+"  ·  "+body.Text.Replace('\n',' ').Replace('\r',' ').Substring(0,Math.Min(72,body.Text.Length))+"    +";Height=Design.P(58);}}
    }
    internal sealed class WelcomeView : Panel {
        readonly Label kicker,title,description;readonly TaskTile[] actions;
        public WelcomeView(Func<string,string> t,Action<string> suggest,Action<string> open) {BackColor=Design.Canvas;
            kicker=new Label{Text=t("你的个人 AI 工作空间"),ForeColor=Design.Accent,AutoSize=true,Font=new Font("Microsoft YaHei UI",9,FontStyle.Bold)};
            title=new Label{Text=t("把想法，变成行动。"),ForeColor=Design.Ink,AutoSize=false,Font=new Font("Microsoft YaHei UI",25,FontStyle.Bold)};
            description=new Label{Text=t("从一个任务开始。项目、设备与文件，在此协同。"),ForeColor=Design.Muted,AutoSize=false,Font=new Font("Microsoft YaHei UI",10)};
            actions=new[]{new TaskTile{Text=t("编写与修复代码"),Hint=t("检查项目，定位问题"),Glyph="terminal"},new TaskTile{Text=t("整理文件"),Hint=t("阅读、编辑与管理文件"),Glyph="file"},new TaskTile{Text=t("连接设备"),Hint=t("与手机安全协作"),Glyph="devices"},new TaskTile{Text=t("设置 AI 服务"),Hint=t("ChatGPT 或通用 API"),Glyph="spark"}};
            actions[0].Click+=(s,e)=>suggest(t("帮我检查当前项目的代码，先说明你发现的问题。"));actions[1].Click+=(s,e)=>suggest(t("列出当前工作目录的文件，并帮我了解目录结构。"));actions[2].Click+=(s,e)=>open("devices");actions[3].Click+=(s,e)=>open("settings");Controls.AddRange(new Control[]{kicker,title,description});Controls.AddRange(actions);}
        protected override void OnSizeChanged(EventArgs e){base.OnSizeChanged(e);int pad=Design.P(12),width=Math.Min(Design.P(760),Math.Max(100,Width-pad)),x=Math.Max(Design.P(6),(Width-width)/2);bool compact=Height<=Design.P(420);int top=compact?Design.P(10):Design.P(42);kicker.SetBounds(x+Design.P(3),top,width-Design.P(6),kicker.PreferredHeight+Design.P(4));int titleTop=kicker.Bottom+Design.P(10),titleHeight=TextRenderer.MeasureText("国Ag",title.Font).Height+Design.P(8);title.SetBounds(x,titleTop,width,titleHeight);int descTop=title.Bottom+Design.P(8);description.SetBounds(x+Design.P(3),descTop,width-Design.P(6),Design.P(40));int gap=Design.P(12),w=Math.Max(Design.P(180),(width-gap)/2),gridTop=description.Bottom+Design.P(18),height=Design.P(compact?76:82);for(int i=0;i<actions.Length;i++)actions[i].SetBounds(x+(i%2)*(w+gap),gridTop+(i/2)*(height+gap),w,height);}
    }
}
