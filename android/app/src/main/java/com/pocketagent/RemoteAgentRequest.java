package com.pocketagent;

import org.json.JSONObject;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/** Normalizes AI tool aliases before the authenticated remote RPC boundary. */
final class RemoteAgentRequest {
    private static final Set<String> TOOLS=new HashSet<>(Arrays.asList("run_shell","read_file","write_file","list_directory","screen_capture","screen_tap","screen_swipe","screen_type","screen_home"));
    private static final Set<String> METHODS=new HashSet<>(Arrays.asList("info","execute","terminal.open","terminal.read","terminal.write","terminal.close","terminal.interrupt"));
    final String method;
    final JSONObject args;
    private RemoteAgentRequest(String method,JSONObject args){this.method=method;this.args=args;}
    static RemoteAgentRequest normalize(String method,JSONObject input)throws Exception{
        if(method==null||method.trim().isEmpty())method="execute";
        JSONObject args=input==null?new JSONObject():new JSONObject(input.toString());
        if(TOOLS.contains(method)){
            String supplied=args.optString("tool","");
            if(!supplied.isEmpty()&&!supplied.equals(method))throw new Exception("远程工具名称不一致。");
            JSONObject inner=args.optJSONObject("arguments");
            if(inner==null){if(args.has("arguments")||args.has("tool"))throw new Exception("远程工具参数格式无效。");inner=args;}
            args=new JSONObject().put("tool",method).put("arguments",inner);method="execute";
        }
        if(!METHODS.contains(method))throw new Exception("不允许此远程控制方法。");
        if(method.equals("execute")){
            String tool=args.optString("tool","");if(!TOOLS.contains(tool)||args.optJSONObject("arguments")==null)throw new Exception("请指定允许的远程工具及参数。");
            // Actor is assigned by the app, not by the model.
            if(tool.startsWith("screen_"))args.put("actor","ai");else args.remove("actor");
        }
        return new RemoteAgentRequest(method,args);
    }
}
