package com.pocketagent;

import android.content.Context;
import org.json.JSONObject;
import java.io.File;
import java.util.concurrent.atomic.AtomicBoolean;

final class AgentTools {
    private final Context context;
    private final File root;
    private final PrivilegeManager manager;
    private final PrivilegeManager.Mode mode;
    AgentTools(Context context,boolean useRoot){this(context,useRoot,null);}
    AgentTools(Context context,boolean useRoot,String workspace){this(context,useRoot?PrivilegeManager.Mode.ROOT:PrivilegeManager.Mode.NORMAL,workspace);}
    AgentTools(Context context,PrivilegeManager.Mode mode,String workspace){
        this.context=context.getApplicationContext()==null?context:context.getApplicationContext();this.manager=new PrivilegeManager(this.context);this.mode=mode;
        File base=workspace==null||workspace.isEmpty()?context.getExternalFilesDir("workspace"):new File(workspace);if(base==null)base=new File(context.getFilesDir(),"workspace");base.mkdirs();root=base.getAbsoluteFile();
    }
    String workspace(){return root.getAbsolutePath();}
    JSONObject execute(String name,JSONObject args)throws Exception{return execute(name,args,new AtomicBoolean(false));}
    JSONObject execute(String name,JSONObject args,AtomicBoolean cancelled)throws Exception{
        try{manager.beginOperation(mode,name,args);return executeGranted(name,args,cancelled);}finally{PrivilegeManager.consumeOperationGrant();}
    }
    private JSONObject executeGranted(String name,JSONObject args,AtomicBoolean cancelled)throws Exception{
        if(cancelled.get())throw new Exception("操作已停止。");
        if(name.equals("run_shell")){
            String command=args.optString("command");
            if(mode!=PrivilegeManager.Mode.ROOT&&directElevation(command))throw new Exception("此命令直接请求系统高权限。请先通过 request_permission 申请 Root，而不是在普通或 ADB 命令中调用 su/sudo。");
            return manager.run(mode,command,root.getCanonicalPath(),args.optInt("timeout",120),cancelled);
        }
        boolean screen=name.startsWith("screen_");
        if(screen)FloatingOverlayService.setAutomationHidden(true);
        try{
            JSONObject result;
            if(screen&&mode==PrivilegeManager.Mode.NORMAL)result=ScreenAccess.execute(name,args,cancelled).put("mode","NORMAL").put("uid",android.os.Process.myUid()).put("mechanism","accessibility");
            else if(name.equals("screen_type")&&ScreenAccess.enabled(context))result=ScreenAccess.execute(name,args,cancelled).put("mode","NORMAL").put("selected_mode",mode.name()).put("uid",android.os.Process.myUid()).put("mechanism","accessibility");
            else result=manager.executeTool(mode,root.getCanonicalPath(),name,args,cancelled);
            if(screen&&!result.has("error"))FloatingOverlayService.showGesture(name,args);
            return result;
        }finally{if(screen)FloatingOverlayService.setAutomationHidden(false);}
    }
    // A cooperative-agent guardrail, not a sandbox for arbitrary hostile shell code.
    static boolean directElevation(String command){
        boolean start=true,escaped=false;char quote=0;StringBuilder word=new StringBuilder();
        for(int i=0;i<=command.length();i++){
            char c=i==command.length()?'\n':command.charAt(i);
            if(escaped){word.append(c);escaped=false;continue;}if(c=='\\'&&quote!='\''){escaped=true;continue;}
            if(quote!=0){if(c==quote)quote=0;else word.append(c);continue;}if(c=='\''||c=='"'){quote=c;continue;}
            if(c=='#'&&word.length()==0){while(i<command.length()&&command.charAt(i)!='\n')i++;start=true;continue;}
            boolean separator=c=='\n'||c==';'||c=='|'||c=='&'||c=='(';
            if(Character.isWhitespace(c)||separator){
                if(word.length()>0){String token=word.toString();word.setLength(0);if(start){String executable=token.substring(token.lastIndexOf('/')+1);if(executable.equals("su")||executable.equals("sudo")||executable.equals("tsu"))return true;if(!token.matches("[A-Za-z_][A-Za-z0-9_]*=.*")&&!executable.equals("command")&&!executable.equals("exec")&&!executable.equals("env")&&!executable.equals("nohup")&&!executable.equals("setsid"))start=false;}}
                if(separator)start=true;
            }else word.append(c);
        }
        return false;
    }
}
