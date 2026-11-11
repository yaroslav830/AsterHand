package com.pocketagent;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import org.json.*;
import java.util.*;

/** Debug-only native QA. No exported component and no approvals for pre-existing devices. */
public final class RemoteSelfTest {
    private static final String STORE="remote-selftest";
    private static void debug(Context app)throws Exception{if((app.getApplicationInfo().flags&ApplicationInfo.FLAG_DEBUGGABLE)==0)throw new Exception("此诊断仅用于调试安装包。");}
    private static SharedPreferences prefs(Context app){return app.getSharedPreferences(STORE,Context.MODE_PRIVATE);}
    private static JSONObject fixture(Context app)throws Exception{debug(app);String raw=prefs(app).getString("fixture","");if(raw.isEmpty())throw new Exception("没有活动的远程测试夹具。");JSONObject f=new JSONObject(raw);if(System.currentTimeMillis()-f.getLong("created")>10*60*1000)throw new Exception("远程测试夹具已过期，请先清理。");return f;}
    private static String ids(JSONArray rows,String field)throws Exception{ArrayList<String> values=new ArrayList<>();for(int i=0;i<rows.length();i++){JSONObject p=rows.optJSONObject(i);if(p!=null)values.add(p.optString(field));}Collections.sort(values);return new JSONArray(values).toString();}
    public static JSONObject prepare(Context context,String expectedFixtureDeviceId,String exactQAName)throws Exception{
        Context app=context.getApplicationContext();debug(app);if(AgentTaskService.snapshot(app).optBoolean("running"))throw new Exception("AI 任务正在运行，暂不执行远程测试。");if(!prefs(app).getString("fixture","").isEmpty())throw new Exception("请先清理上一轮测试夹具。");
        if(expectedFixtureDeviceId==null||!expectedFixtureDeviceId.matches("[a-f0-9]{64}")||exactQAName==null||!exactQAName.matches("AsterHand QA fixture [A-Za-z0-9-]{1,40}"))throw new Exception("测试设备标识或名称无效。");RemoteControlHub hub=RemoteControlHub.get(app);JSONObject before=hub.info();if(before.has("error")&&!before.optString("error").isEmpty())throw new Exception(before.optString("error"));if(expectedFixtureDeviceId.equals(before.optString("device_id")))throw new Exception("不能把本机作为测试远端。");
        JSONArray peers=before.getJSONArray("peers"),trust=before.getJSONArray("trust");for(int i=0;i<peers.length();i++)if(peers.getJSONObject(i).optString("device_id").equals(expectedFixtureDeviceId))throw new Exception("测试标识与现有配对相同，拒绝修改。");for(int i=0;i<trust.length();i++)if(trust.getJSONObject(i).optString("device_id").equals(expectedFixtureDeviceId))throw new Exception("测试标识与现有授权相同，拒绝修改。");
        JSONObject f=new JSONObject().put("created",System.currentTimeMillis()).put("expected_device",expectedFixtureDeviceId).put("name",exactQAName).put("own_device",before.getString("device_id")).put("enabled",before.optBoolean("enabled")).put("background",before.optBoolean("background")).put("peer_ids",ids(peers,"id")).put("trust_ids",ids(trust,"device_id"));prefs(app).edit().putString("fixture",f.toString()).commit();hub.setBackground(true);hub.start();
        return new JSONObject().put("fixture",true).put("device_id",before.getString("device_id")).put("public_key",before.getString("public_key")).put("port",18769).put("original_peer_count",peers.length()).put("original_trust_count",trust.length()).put("real_model_request",false);
    }
    public static JSONObject approveOnce(Context context,String requestId)throws Exception{
        Context app=context.getApplicationContext();JSONObject f=fixture(app);RemoteControlHub hub=RemoteControlHub.get(app);JSONArray pending=hub.pending();JSONObject selected=null;for(int i=0;i<pending.length();i++){JSONObject p=pending.getJSONObject(i);if(p.optString("id").equals(requestId)&&p.optString("device_id").equals(f.getString("expected_device"))&&p.optString("name").equals(f.getString("name")))selected=p;}if(selected==null)throw new Exception("没有匹配本轮临时测试身份的申请。");
        hub.decide(requestId,"once");f.put("incoming_pair",requestId);prefs(app).edit().putString("fixture",f.toString()).commit();return new JSONObject().put("fixture",true).put("id",requestId).put("mode","once");
    }
    public static JSONObject startOutgoing(Context context,String host,int port)throws Exception{
        Context app=context.getApplicationContext();JSONObject f=fixture(app);RemoteControlHub hub=RemoteControlHub.get(app);JSONObject result=hub.begin(host,port,f.getString("expected_device"));if(!result.optString("device_id").equals(f.getString("expected_device")))throw new Exception("申请目标不是本轮临时测试身份；没有批准此连接。");f.put("outgoing_pair",result.getString("id"));prefs(app).edit().putString("fixture",f.toString()).commit();return result.put("fixture",true);
    }
    public static JSONObject pollOutgoing(Context context)throws Exception{Context app=context.getApplicationContext();JSONObject f=fixture(app);return RemoteControlHub.get(app).poll(f.getString("outgoing_pair")).put("fixture",true);}
    public static JSONObject outboundMarker(Context context)throws Exception{
        Context app=context.getApplicationContext();JSONObject f=fixture(app);RemoteControlHub hub=RemoteControlHub.get(app);String pair=f.getString("outgoing_pair");JSONObject remote=hub.request(pair,"info",new JSONObject());if(!remote.optString("device_id").equals(f.getString("expected_device"))||!remote.optString("name").equals(f.getString("name")))throw new Exception("远端不是本轮临时测试服务。");String command=remote.optString("platform").equals("win32")?"Write-Output ASTERHAND_ANDROID_OUTBOUND_QA":"printf 'ASTERHAND_ANDROID_OUTBOUND_QA\\n'";JSONObject result=hub.request(pair,"execute",new JSONObject().put("tool","run_shell").put("arguments",new JSONObject().put("command",command).put("timeout_seconds",5)));if(result.optInt("exit_code",-1)!=0||!result.optString("output").contains("ASTERHAND_ANDROID_OUTBOUND_QA"))throw new Exception("双向控制测试未收到标记。");return new JSONObject().put("fixture",true).put("bidirectional_marker",true).put("exit_code",0);
    }
    public static JSONObject cleanup(Context context)throws Exception{
        Context app=context.getApplicationContext();debug(app);String raw=prefs(app).getString("fixture","");if(raw.isEmpty())return new JSONObject().put("fixture",true).put("nothing_to_clean",true);JSONObject f=new JSONObject(raw);RemoteControlHub hub=RemoteControlHub.get(app);String device=f.getString("expected_device");
        if(f.has("outgoing_pair"))try{hub.request(f.getString("outgoing_pair"),"session.close",new JSONObject());}catch(Exception ignored){}
        hub.forgetDevice(device);hub.setEnabled(f.optBoolean("enabled"));hub.setBackground(f.optBoolean("background"));JSONObject after=hub.info();boolean identity=after.getString("device_id").equals(f.getString("own_device")),peers=ids(after.getJSONArray("peers"),"id").equals(f.getString("peer_ids")),trust=ids(after.getJSONArray("trust"),"device_id").equals(f.getString("trust_ids"));if(!identity||!peers||!trust)throw new Exception("本轮测试期间其他连接状态发生改变；测试夹具已撤销，请保留检查记录。");prefs(app).edit().remove("fixture").commit();return new JSONObject().put("fixture",true).put("temporary_pairings_removed",true).put("identity_preserved",identity).put("existing_peer_ids_preserved",peers).put("existing_trust_ids_preserved",trust).put("settings_restored",true);
    }
}
