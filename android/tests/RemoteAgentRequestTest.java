package com.pocketagent;
import org.json.JSONObject;

public final class RemoteAgentRequestTest {
    static int checks;
    static void ok(boolean value){checks++;if(!value)throw new AssertionError("check "+checks);}
    static void rejected(String method,JSONObject args)throws Exception{try{RemoteAgentRequest.normalize(method,args);throw new AssertionError("accepted "+method);}catch(IllegalArgumentException e){throw e;}catch(AssertionError e){throw e;}catch(Exception expected){checks++;}}
    public static void main(String[] args)throws Exception{
        RemoteAgentRequest capture=RemoteAgentRequest.normalize("screen_capture",new JSONObject());
        ok(capture.method.equals("execute"));ok(capture.args.getString("tool").equals("screen_capture"));ok(capture.args.getString("actor").equals("ai"));
        RemoteAgentRequest tap=RemoteAgentRequest.normalize("screen_tap",new JSONObject().put("x",0.5).put("y",0.25));
        ok(tap.args.getJSONObject("arguments").getDouble("x")==0.5);ok(tap.args.getString("actor").equals("ai"));
        JSONObject original=new JSONObject().put("tool","screen_home").put("arguments",new JSONObject()).put("actor","manual");
        RemoteAgentRequest canonical=RemoteAgentRequest.normalize("execute",original);ok(canonical.args.getString("actor").equals("ai"));ok(original.getString("actor").equals("manual"));
        RemoteAgentRequest terminal=RemoteAgentRequest.normalize("terminal.read",new JSONObject().put("offset",0));ok(terminal.method.equals("terminal.read"));
        rejected("screen_tap",new JSONObject().put("tool","screen_home").put("arguments",new JSONObject()));
        rejected("execute",new JSONObject().put("tool","remote_execute").put("arguments",new JSONObject()));
        rejected("presence",new JSONObject());rejected("delete_all",new JSONObject());rejected("screen_tap",new JSONObject().put("arguments","invalid"));
        System.out.println("Remote AI request normalization passed: "+checks+" (offline, no device access)");
    }
}
