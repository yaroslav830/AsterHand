package com.pocketagent;

import org.json.JSONArray;
import org.json.JSONObject;
import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.CancellationException;
import java.util.concurrent.atomic.AtomicBoolean;

/** Provider adapters share Responses-shaped history; network credentials stay in Vault. */
final class ProviderClient {
    static final String[] PROVIDERS={"通用 API","DeepSeek","Claude API","ChatGPT 登录"};
    static final String DEEPSEEK_CONTEXT="_asterhand_deepseek_reasoning";
    static final String CLAUDE_CONTEXT="_asterhand_claude_thinking";
    interface Listener {
        void onStage(String stage);
        void onText(String delta);
        void onUsage(JSONObject usage);
    }
    static String id(int index){return new String[]{"openai","deepseek","anthropic","chatgpt"}[Math.max(0,Math.min(3,index))];}
    static String host(String provider){if(provider.equals("deepseek"))return "https://api.deepseek.com";if(provider.equals("anthropic"))return "https://api.anthropic.com/v1";return "https://api.openai.com/v1";}
    static String apiKeyName(String provider){return "key."+provider;}
    static String adapter(String provider,String baseURL){return provider.equals("openai")&&baseURL!=null&&!baseURL.trim().isEmpty()&&!baseURL.trim().replaceAll("/+$","").equalsIgnoreCase(host("openai"))?"deepseek":provider;}
    static boolean supportsReasoning(String provider){return true;}
    static String base(String provider,String configured)throws Exception {
        if(!provider.equals("openai")&&!provider.equals("deepseek")&&!provider.equals("anthropic")&&!provider.equals("chatgpt"))throw new Exception("未知 AI 服务商。");
        String value=provider.equals("chatgpt")?host(provider):(configured==null||configured.trim().isEmpty()?host(provider):configured.trim());
        URI uri=new URI(value);
        if(!"https".equalsIgnoreCase(uri.getScheme())||uri.getHost()==null||uri.getRawUserInfo()!=null||uri.getRawQuery()!=null||uri.getRawFragment()!=null)throw new Exception("API 地址需要是 HTTPS，且不能包含账户、查询参数或片段。");
        while(value.endsWith("/"))value=value.substring(0,value.length()-1);
        return value;
    }
    private static void stage(Listener l,String s){if(l!=null)try{l.onStage(s);}catch(RuntimeException ignored){}}
    private static void text(Listener l,String s){if(l!=null&&!s.isEmpty())try{l.onText(s);}catch(RuntimeException ignored){}}
    private static void usage(Listener l,JSONObject u){if(l!=null&&u!=null)try{l.onUsage(u);}catch(RuntimeException ignored){}}
    private static void check(AtomicBoolean cancelled){if(cancelled!=null&&cancelled.get())throw new CancellationException("任务已停止");}
    private static byte[] bytes(InputStream stream,int limit)throws Exception {
        if(stream==null)return new byte[0];
        try(InputStream in=stream;ByteArrayOutputStream out=new ByteArrayOutputStream()){
            byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){if(out.size()+n>limit)throw new Exception("服务端响应超过大小限制。");out.write(b,0,n);}return out.toByteArray();
        }
    }
    private static HttpURLConnection connection(String address,String method,String token,String provider)throws Exception{
        HttpURLConnection c=(HttpURLConnection)new URL(address).openConnection();c.setRequestMethod(method);c.setConnectTimeout(20000);c.setReadTimeout(120000);c.setInstanceFollowRedirects(false);c.setRequestProperty("Accept","application/json");
        if(provider.equals("anthropic")){c.setRequestProperty("x-api-key",token);c.setRequestProperty("anthropic-version","2023-06-01");}else c.setRequestProperty("Authorization","Bearer "+token);
        return c;
    }
    static JSONArray models(String provider,String token)throws Exception{return models(provider,token,null);}
    static JSONArray models(String provider,String token,String baseURL)throws Exception{
        if(token==null||token.trim().isEmpty())throw new Exception("请先配置 API Key 或登录 ChatGPT。");
        String address=base(provider,baseURL)+"/models"+(provider.equals("anthropic")?"?limit=100":"");
        HttpURLConnection c=connection(address,"GET",token,provider);
        try{
            int code=c.getResponseCode();String data=new String(bytes(code>=400?c.getErrorStream():c.getInputStream(),8*1024*1024),StandardCharsets.UTF_8);
            if(code<200||code>=300)throw new Exception("模型列表 HTTP "+code+"："+message(data,token));
            JSONObject root=new JSONObject(data);JSONArray all=root.optJSONArray("models");if(all==null)all=root.optJSONArray("data");JSONArray result=new JSONArray();
            if(all!=null)for(int i=0;i<all.length();i++){
                Object item=all.opt(i);String value="";
                if(item instanceof JSONObject){JSONObject model=(JSONObject)item;if(provider.equals("chatgpt")&&model.has("visibility")&&!model.optString("visibility").equals("list"))continue;value=provider.equals("chatgpt")?model.optString("slug",model.optString("id")):model.optString("id");}
                else if(item instanceof String)value=(String)item;
                if(!value.trim().isEmpty())result.put(value);
            }
            return result;
        }finally{c.disconnect();}
    }
    static JSONObject request(String provider,String token,JSONObject body)throws Exception{return request(provider,token,body,null,null,null);}
    static JSONObject request(String provider,String token,JSONObject body,Listener listener,AtomicBoolean cancelled)throws Exception{return request(provider,token,body,null,listener,cancelled);}
    static JSONObject request(String provider,String token,JSONObject body,String baseURL,Listener listener,AtomicBoolean cancelled)throws Exception{
        check(cancelled);if(token==null||token.trim().isEmpty())throw new Exception("请先配置 API Key 或登录 ChatGPT。");
        // Custom OpenAI-compatible services generally expose Chat Completions;
        // the official OpenAI and ChatGPT integrations retain Responses.
        String adapter=adapter(provider,baseURL);
        String route=adapter.equals("anthropic")?"/messages":adapter.equals("deepseek")?"/chat/completions":"/responses";
        JSONObject wire=wireRequest(adapter,body);wire.put("stream",true);
        HttpURLConnection c=connection(base(provider,baseURL)+route,"POST",token,provider);c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json");c.setRequestProperty("Accept","text/event-stream");
        AtomicBoolean finished=new AtomicBoolean(false);
        Thread cancellation=new Thread(()->{while(!finished.get()){if(cancelled!=null&&cancelled.get()){c.disconnect();break;}try{Thread.sleep(100);}catch(InterruptedException e){break;}}},"AsterHand-network-cancel");cancellation.setDaemon(true);cancellation.start();
        try{
            stage(listener,"正在连接");byte[] payload=wire.toString().getBytes(StandardCharsets.UTF_8);if(payload.length>32*1024*1024)throw new Exception("会话及附件超过 32 MiB，请减少附件或新建对话。");
            c.setFixedLengthStreamingMode(payload.length);try(OutputStream out=c.getOutputStream()){check(cancelled);out.write(payload);}
            int code=c.getResponseCode();check(cancelled);
            if(code<200||code>=300){String error=new String(bytes(c.getErrorStream(),1024*1024),StandardCharsets.UTF_8);throw new Exception("HTTP "+code+"："+message(error,token));}
            stage(listener,"已连接 · 等待模型");
            JSONObject result;
            if(c.getContentType()!=null&&c.getContentType().toLowerCase(java.util.Locale.ROOT).contains("application/json")){
                JSONObject raw=new JSONObject(new String(bytes(c.getInputStream(),16*1024*1024),StandardCharsets.UTF_8));result=adapter.equals("anthropic")?normalizeClaude(raw):adapter.equals("deepseek")?normalizeDeepSeek(raw):raw;
                text(listener,outputText(result));usage(listener,result.optJSONObject("usage"));
            }else result=parseStream(adapter,c.getInputStream(),listener,cancelled);
            check(cancelled);validateCompleted(result);stage(listener,"回复完成");return result;
        }catch(Exception e){check(cancelled);String safe=e.getMessage()==null?"AI 请求失败。":e.getMessage();if(token!=null&&!token.isEmpty())safe=safe.replace(token,"[已隐藏]");throw new Exception(safe,e);}finally{finished.set(true);cancellation.interrupt();c.disconnect();}
    }
    /** No raw HTML/error pages, bearer keys, OAuth codes or arbitrary URLs in the UI. */
    private static String message(String data,String secret){
        String result="请求失败，请检查网络、模型权限和账号额度。";
        try{JSONObject j=new JSONObject(data),error=j.optJSONObject("error");String value=error==null?j.optString("message"):error.optString("message",error.optString("type"));if(!value.trim().isEmpty())result=value;}catch(Exception ignored){}
        if(secret!=null&&!secret.isEmpty())result=result.replace(secret,"[已隐藏]");
        result=result.replaceAll("(?i)Bearer\\s+[^\\s\\\"']+","Bearer [已隐藏]").replaceAll("(?i)(access_token|refresh_token|id_token|code_verifier)[\\\"' :=>]+[^\\s,}]+","$1 [已隐藏]");
        return result.length()>800?result.substring(0,800):result;
    }
    static String outputText(JSONObject response){String direct=response.optString("output_text","");if(!direct.isEmpty())return direct;StringBuilder result=new StringBuilder();JSONArray output=response.optJSONArray("output");if(output!=null)for(int i=0;i<output.length();i++){JSONObject item=output.optJSONObject(i);if(item==null||!item.optString("type").equals("message"))continue;JSONArray content=item.optJSONArray("content");if(content!=null)for(int j=0;j<content.length();j++){JSONObject p=content.optJSONObject(j);if(p!=null&&(p.optString("type").equals("output_text")||p.optString("type").equals("refusal")))result.append(p.optString("text",p.optString("refusal")));}}return result.toString();}
    private static void validateCompleted(JSONObject response)throws Exception{
        String state=response.optString("status","completed");
        if(!state.equals("completed")){JSONObject details=response.optJSONObject("incomplete_details");throw new Exception("模型响应未完成："+(details==null?state:details.optString("reason",state)));}
        if(response.has("error")&&!response.isNull("error"))throw new Exception(message(response.toString(),null));
        JSONArray output=response.optJSONArray("output");boolean tool=false;if(output!=null)for(int i=0;i<output.length();i++){JSONObject v=output.optJSONObject(i);if(v!=null&&v.optString("type").equals("function_call"))tool=true;}
        if(outputText(response).trim().isEmpty()&&!tool)throw new Exception("模型结束了响应，但没有返回可显示的文字或工具调用。请检查所选模型与账号权限。");
    }
    private interface EventSink{void event(JSONObject event,boolean done)throws Exception;}
    private static void events(InputStream input,AtomicBoolean cancelled,EventSink sink)throws Exception{
        try(BufferedReader reader=new BufferedReader(new InputStreamReader(input,StandardCharsets.UTF_8))){String line;StringBuilder data=new StringBuilder();int consumed=0;while((line=reader.readLine())!=null){check(cancelled);consumed+=line.length();if(consumed>16*1024*1024||line.length()>1024*1024)throw new Exception("模型输出超过大小限制。");
            if(line.isEmpty()){dispatch(data,sink);data.setLength(0);}else if(line.startsWith("data:")){if(data.length()>0)data.append('\n');String value=line.substring(5);if(value.startsWith(" "))value=value.substring(1);data.append(value);}
        }if(data.length()>0)dispatch(data,sink);}
    }
    private static void dispatch(StringBuilder data,EventSink sink)throws Exception{String value=data.toString();if(value.isEmpty())return;if(value.equals("[DONE]")){sink.event(null,true);return;}try{sink.event(new JSONObject(value),false);}catch(org.json.JSONException e){throw new Exception("模型流返回了无效事件，已停止处理。",e);}}
    static JSONObject parseStream(String provider,InputStream input,Listener listener,AtomicBoolean cancelled)throws Exception{
        if(provider.equals("anthropic"))return claudeStream(input,listener,cancelled);if(provider.equals("deepseek"))return deepSeekStream(input,listener,cancelled);
        final JSONObject[] complete={null};final String[] failure={null};StringBuilder visible=new StringBuilder();Map<Integer,JSONObject> items=new java.util.TreeMap<>();
        events(input,cancelled,(event,done)->{
            if(done||event==null)return;String type=event.optString("type");
            if(type.equals("error")||type.equals("response.failed")){JSONObject detail=event.optJSONObject("response");failure[0]=message(detail==null?event.toString():detail.toString(),null);}
            else if(type.equals("response.incomplete")){JSONObject r=event.optJSONObject("response");JSONObject d=r==null?null:r.optJSONObject("incomplete_details");failure[0]="响应未完成："+(d==null?"unknown":d.optString("reason","unknown"));}
            else if(type.equals("response.completed")){complete[0]=event.optJSONObject("response");if(complete[0]!=null)usage(listener,complete[0].optJSONObject("usage"));}
            else if(type.equals("response.output_text.delta")||type.equals("response.refusal.delta")){String delta=event.optString("delta");visible.append(delta);stage(listener,"正在回复");text(listener,delta);}
            else if(type.startsWith("response.reasoning"))stage(listener,"正在思考");
            else if(type.equals("response.output_item.added")||type.equals("response.output_item.done")){JSONObject item=event.optJSONObject("item");if(item!=null){items.put(event.optInt("output_index",items.size()),item);if(item.optString("type").equals("function_call"))stage(listener,"正在准备操作");}}
            else if(type.equals("response.function_call_arguments.delta")){JSONObject item=items.get(event.optInt("output_index"));if(item!=null)item.put("arguments",item.optString("arguments")+event.optString("delta"));stage(listener,"正在准备操作");}
            else if(type.equals("response.function_call_arguments.done")){JSONObject item=items.get(event.optInt("output_index"));if(item!=null)item.put("arguments",event.optString("arguments"));}
        });
        if(failure[0]!=null)throw new Exception(failure[0]);if(complete[0]==null)throw new Exception("连接在完整回复前中断，任务尚未完成。可检查网络后重试。");
        JSONObject response=complete[0];JSONArray output=response.optJSONArray("output");if(output==null||output.length()==0){output=new JSONArray();if(visible.length()>0)output.put(messageItem(visible.toString()));for(JSONObject item:items.values())if(item.optString("type").equals("function_call"))output.put(item);response.put("output",output);}
        if(visible.length()>0&&!response.has("output_text"))response.put("output_text",visible.toString());validateCompleted(response);return response;
    }
    private static JSONObject deepSeekStream(InputStream input,Listener listener,AtomicBoolean cancelled)throws Exception{
        StringBuilder visible=new StringBuilder(),reasoning=new StringBuilder();Map<Integer,JSONObject> tools=new java.util.TreeMap<>();final JSONObject[] used={null};final String[] finish={null};final boolean[] ended={false};
        events(input,cancelled,(event,done)->{if(done){ended[0]=true;return;}if(event==null)return;if(event.has("error"))throw new Exception(message(event.toString(),null));if(event.optJSONObject("usage")!=null){used[0]=event.optJSONObject("usage");usage(listener,normalizeUsage(used[0]));}
            JSONArray choices=event.optJSONArray("choices");if(choices==null||choices.length()==0)return;JSONObject first=choices.optJSONObject(0);if(first==null)return;if(!first.isNull("finish_reason")&&first.has("finish_reason"))finish[0]=first.optString("finish_reason");JSONObject delta=first.optJSONObject("delta");if(delta==null)return;
            if(!delta.isNull("content")){String s=delta.optString("content","");visible.append(s);if(!s.isEmpty()){stage(listener,"正在回复");text(listener,s);}}
            if(!delta.isNull("reasoning_content")){String s=delta.optString("reasoning_content","");reasoning.append(s);if(!s.isEmpty())stage(listener,"正在思考");}
            JSONArray calls=delta.optJSONArray("tool_calls");if(calls!=null)for(int i=0;i<calls.length();i++){JSONObject part=calls.optJSONObject(i);if(part==null)continue;int index=part.optInt("index",i);JSONObject current=tools.get(index);if(current==null){current=new JSONObject().put("id","").put("type","function").put("function",new JSONObject().put("name","").put("arguments",""));tools.put(index,current);}if(part.has("id"))current.put("id",part.optString("id"));JSONObject f=part.optJSONObject("function"),target=current.getJSONObject("function");if(f!=null){if(f.has("name"))target.put("name",target.optString("name")+f.optString("name"));if(f.has("arguments"))target.put("arguments",target.optString("arguments")+f.optString("arguments"));}stage(listener,"正在准备操作");}
        });
        if(!ended[0]||finish[0]==null)throw new Exception("DeepSeek 连接在完整回复前中断。");if(!finish[0].equals("stop")&&!finish[0].equals("tool_calls"))throw new Exception("DeepSeek 响应未完成："+finish[0]);
        JSONArray callArray=new JSONArray();for(JSONObject tool:tools.values())callArray.put(tool);JSONObject response=new JSONObject().put("choices",new JSONArray().put(new JSONObject().put("finish_reason",finish[0]).put("message",new JSONObject().put("content",visible.toString()).put("reasoning_content",reasoning.toString()).put("tool_calls",callArray))));if(used[0]!=null)response.put("usage",used[0]);return normalizeDeepSeek(response);
    }
    private static JSONObject claudeStream(InputStream input,Listener listener,AtomicBoolean cancelled)throws Exception{
        Map<Integer,JSONObject> blocks=new java.util.TreeMap<>();Map<Integer,StringBuilder> args=new LinkedHashMap<>();final JSONObject used=new JSONObject();final boolean[] ended={false};final String[] finish={""};
        events(input,cancelled,(event,done)->{if(done||event==null)return;String type=event.optString("type");if(type.equals("error"))throw new Exception(message(event.toString(),null));
            if(type.equals("message_start")){JSONObject message=event.optJSONObject("message"),u=message==null?null:message.optJSONObject("usage");merge(used,u);}
            else if(type.equals("content_block_start")){JSONObject block=event.optJSONObject("content_block");int index=event.optInt("index");if(block!=null){blocks.put(index,block);if(block.optString("type").equals("tool_use")){args.put(index,new StringBuilder());stage(listener,"正在准备操作");}}}
            else if(type.equals("content_block_delta")){int index=event.optInt("index");JSONObject d=event.optJSONObject("delta"),block=blocks.get(index);if(d==null)return;String kind=d.optString("type");if(kind.equals("text_delta")){String delta=d.optString("text");if(block!=null)block.put("text",block.optString("text")+delta);stage(listener,"正在回复");text(listener,delta);}else if(kind.equals("input_json_delta")){StringBuilder a=args.get(index);if(a!=null)a.append(d.optString("partial_json"));stage(listener,"正在准备操作");}else if(kind.equals("thinking_delta")){if(block!=null)block.put("thinking",block.optString("thinking")+d.optString("thinking"));stage(listener,"正在思考");}else if(kind.equals("signature_delta")&&block!=null)block.put("signature",block.optString("signature")+d.optString("signature"));}
            else if(type.equals("message_delta")){JSONObject delta=event.optJSONObject("delta");if(delta!=null)finish[0]=delta.optString("stop_reason");merge(used,event.optJSONObject("usage"));usage(listener,normalizeUsage(used));}
            else if(type.equals("message_stop"))ended[0]=true;
        });
        if(!ended[0])throw new Exception("Claude 连接在完整回复前中断。");if(!finish[0].equals("end_turn")&&!finish[0].equals("tool_use")&&!finish[0].equals("stop_sequence"))throw new Exception("Claude 响应未完成："+finish[0]);
        JSONArray content=new JSONArray();for(Map.Entry<Integer,JSONObject> entry:blocks.entrySet()){JSONObject block=entry.getValue();StringBuilder a=args.get(entry.getKey());if(a!=null&&a.length()>0)block.put("input",new JSONObject(a.toString()));content.put(block);}return normalizeClaude(new JSONObject().put("content",content).put("usage",used).put("stop_reason",finish[0]));
    }
    private static void merge(JSONObject into,JSONObject values)throws Exception{if(values!=null){Iterator<String> keys=values.keys();while(keys.hasNext()){String k=keys.next();into.put(k,values.get(k));}}}
    private static JSONObject normalizeUsage(JSONObject value)throws Exception{return new JSONObject().put("input_tokens",value.optLong("input_tokens",value.optLong("prompt_tokens"))).put("output_tokens",value.optLong("output_tokens",value.optLong("completion_tokens")));}
    private static JSONObject messageItem(String content)throws Exception{return new JSONObject().put("type","message").put("role","assistant").put("content",new JSONArray().put(new JSONObject().put("type","output_text").put("text",content)));}
    private static JSONArray flatTools(JSONArray source)throws Exception{JSONArray result=new JSONArray();if(source!=null)for(int i=0;i<source.length();i++){JSONObject tool=source.optJSONObject(i);if(tool==null)continue;if(tool.optString("type").equals("namespace")){JSONArray nested=flatTools(tool.optJSONArray("tools"));for(int n=0;n<nested.length();n++)result.put(nested.get(n));}else if(tool.optString("type").equals("function"))result.put(tool);}return result;}
    static JSONObject wireRequest(String provider,JSONObject body)throws Exception{
        if(provider.equals("anthropic"))return claudeRequest(body);if(provider.equals("deepseek"))return deepSeekRequest(body);
        JSONObject result=(JSONObject)clean(body);result.put("store",false);result.put("stream",true);if(provider.equals("openai")&&!result.has("include"))result.put("include",new JSONArray().put("reasoning.encrypted_content"));if(provider.equals("chatgpt")){result.remove("max_output_tokens");JSONArray tools=result.optJSONArray("tools");if(tools!=null&&tools.length()>0&&!tools.getJSONObject(0).optString("type").equals("namespace"))result.put("tools",new JSONArray().put(new JSONObject().put("type","namespace").put("name","pocketagent").put("description","Local Android device tools; execute only under the user-selected permission tier and approval policy.").put("tools",tools)));}return result;
    }
    private static Object clean(Object value)throws Exception{if(value instanceof JSONObject){JSONObject result=new JSONObject(),source=(JSONObject)value;Iterator<String> keys=source.keys();while(keys.hasNext()){String k=keys.next();if(!k.startsWith("_asterhand_"))result.put(k,clean(source.get(k)));}return result;}if(value instanceof JSONArray){JSONArray result=new JSONArray(),source=(JSONArray)value;for(int i=0;i<source.length();i++)result.put(clean(source.get(i)));return result;}return value;}
    private static JSONArray contentParts(Object content,boolean claude)throws Exception{
        JSONArray result=new JSONArray();if(content instanceof String){if(!((String)content).isEmpty())result.put(new JSONObject().put("type","text").put("text",content));return result;}if(!(content instanceof JSONArray))return result;
        JSONArray source=(JSONArray)content;for(int i=0;i<source.length();i++){JSONObject part=source.optJSONObject(i);if(part==null)continue;String type=part.optString("type");
            if(type.equals("input_text")||type.equals("output_text")||type.equals("text")||type.equals("refusal")){String text=part.optString("text",part.optString("refusal"));if(!text.isEmpty())result.put(new JSONObject().put("type","text").put("text",text));}
            else if(type.equals("input_image")||type.equals("image_url")){Object raw=part.opt("image_url");String address=raw instanceof JSONObject?((JSONObject)raw).optString("url"):raw instanceof String?(String)raw:"";if(address.isEmpty())throw new Exception("图片附件缺少内容。");if(claude)result.put(new JSONObject().put("type","image").put("source",claudeSource(address,true)));else result.put(new JSONObject().put("type","image_url").put("image_url",new JSONObject().put("url",address)));}
            else if(type.equals("input_file")){String data=part.optString("file_data"),name=part.optString("filename","attachment");if(data.isEmpty())throw new Exception("此服务商需要文件内容，无法使用其他服务商的 file_id。");if(claude)result.put(new JSONObject().put("type","document").put("source",claudeSource(data,false)).put("title",name));else if(data.startsWith("data:image/"))result.put(new JSONObject().put("type","file").put("file_data",data).put("filename",name));else{String plain=fileText(data);result.put(new JSONObject().put("type","text").put("text","[文件："+name+"]\n"+plain));}}
            else throw new Exception("此附件格式尚不受当前服务商支持："+type);
        }return result;
    }
    private static JSONObject claudeSource(String address,boolean image)throws Exception{
        if(address.startsWith("https://"))return new JSONObject().put("type","url").put("url",address);
        int comma=address.indexOf(',');if(!address.startsWith("data:")||comma<0||!address.substring(0,comma).endsWith(";base64"))throw new Exception("附件必须是 HTTPS URL 或 base64 数据。");String media=address.substring(5,comma-7);
        if(image&&!media.matches("image/(png|jpeg|gif|webp)"))throw new Exception("Claude 不支持此图片类型。");
        if(!image&&!media.equals("application/pdf"))return new JSONObject().put("type","text").put("media_type","text/plain").put("data",fileText(address));
        return new JSONObject().put("type","base64").put("media_type",media).put("data",address.substring(comma+1));
    }
    private static String fileText(String address)throws Exception{
        int comma=address.indexOf(',');if(!address.startsWith("data:")||comma<0||!address.substring(0,comma).endsWith(";base64"))throw new Exception("文件缺少 base64 内容。");String media=address.substring(5,comma-7);
        if(media.equals("application/pdf"))throw new Exception("当前 DeepSeek 附件通道支持图片和纯文本；PDF 请切换到支持 PDF 的服务商。");
        byte[] data=decodeBase64(address.substring(comma+1));String text;
        try{text=StandardCharsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT).onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(data)).toString();}catch(Exception e){throw new Exception("此服务商需要 PDF 或 UTF-8 纯文本附件，不能直接读取该二进制文件。");}
        if(text.indexOf('\0')>=0)throw new Exception("此文件不是可直接发送的纯文本附件。");return text;
    }
    private static byte[] decodeBase64(String value)throws Exception{
        ByteArrayOutputStream out=new ByteArrayOutputStream();int bits=0,count=0;boolean padded=false;
        for(int i=0;i<value.length();i++){char c=value.charAt(i);if(c=='='){padded=true;continue;}if(Character.isWhitespace(c))continue;if(padded)throw new Exception("文件 base64 数据无效。");int digit="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".indexOf(c);if(digit<0)throw new Exception("文件 base64 数据无效。");bits=(bits<<6)|digit;count+=6;if(count>=8){count-=8;out.write((bits>>count)&255);}if(out.size()>8*1024*1024)throw new Exception("附件超过 8 MiB。");}return out.toByteArray();
    }
    private static JSONObject deepSeekRequest(JSONObject body)throws Exception{
        JSONObject result=new JSONObject().put("model",body.optString("model")).put("max_tokens",body.optInt("max_output_tokens",8192)).put("stream",true);JSONArray messages=new JSONArray();String instructions=body.optString("instructions");if(!instructions.isEmpty())messages.put(new JSONObject().put("role","system").put("content",instructions));JSONArray source=body.optJSONArray("input");
        if(source!=null)for(int i=0;i<source.length();i++){JSONObject item=source.optJSONObject(i);if(item==null)continue;String type=item.optString("type"),role=item.optString("role");
            if(type.equals("function_call_output")){Object output=item.opt("output");messages.put(new JSONObject().put("role","tool").put("tool_call_id",item.optString("call_id")).put("content",output instanceof JSONArray?contentParts(output,false):String.valueOf(output)));}
            else if(type.equals("function_call")){JSONObject last=messages.length()>0?messages.optJSONObject(messages.length()-1):null;if(last==null||!last.optString("role").equals("assistant")){last=new JSONObject().put("role","assistant").put("content",JSONObject.NULL);messages.put(last);}JSONArray calls=last.optJSONArray("tool_calls");if(calls==null){calls=new JSONArray();last.put("tool_calls",calls);}calls.put(new JSONObject().put("type","function").put("id",item.optString("call_id")).put("function",new JSONObject().put("name",item.optString("name")).put("arguments",item.optString("arguments","{}"))));if(item.has(DEEPSEEK_CONTEXT))last.put("reasoning_content",item.optString(DEEPSEEK_CONTEXT));}
            else if(role.equals("user")||role.equals("assistant")||role.equals("system")){JSONArray content=contentParts(item.opt("content"),false);JSONObject message=new JSONObject().put("role",role);if(role.equals("assistant")){StringBuilder text=new StringBuilder();for(int j=0;j<content.length();j++){JSONObject p=content.optJSONObject(j);if(p!=null&&p.optString("type").equals("text"))text.append(p.optString("text"));}message.put("content",text.toString());if(item.has(DEEPSEEK_CONTEXT))message.put("reasoning_content",item.optString(DEEPSEEK_CONTEXT));}else message.put("content",content);messages.put(message);}
        }
        result.put("messages",messages);JSONArray tools=flatTools(body.optJSONArray("tools")),converted=new JSONArray();for(int i=0;i<tools.length();i++){JSONObject t=tools.getJSONObject(i),f=new JSONObject().put("name",t.optString("name")).put("description",t.optString("description")).put("parameters",t.optJSONObject("parameters"));converted.put(new JSONObject().put("type","function").put("function",f));}if(converted.length()>0)result.put("tools",converted);
        JSONObject reasoning=body.optJSONObject("reasoning");if(reasoning!=null&&!reasoning.optString("effort").isEmpty())result.put("reasoning_effort",reasoning.optString("effort"));return result;
    }
    private static JSONObject normalizeDeepSeek(JSONObject response)throws Exception{
        JSONObject choice=response.optJSONArray("choices")==null?null:response.optJSONArray("choices").optJSONObject(0),message=choice==null?null:choice.optJSONObject("message");if(message==null)throw new Exception("DeepSeek 响应中没有消息。");String finish=choice.optString("finish_reason","stop");if(!finish.equals("stop")&&!finish.equals("tool_calls"))throw new Exception("DeepSeek 响应未完成："+finish);
        JSONArray output=new JSONArray();String visible=message.isNull("content")?"":message.optString("content");JSONObject assistant=messageItem(visible);if(message.has("reasoning_content")&&!message.isNull("reasoning_content"))assistant.put(DEEPSEEK_CONTEXT,message.optString("reasoning_content"));if(!visible.isEmpty()||assistant.has(DEEPSEEK_CONTEXT))output.put(assistant);
        JSONArray tools=message.optJSONArray("tool_calls");if(tools!=null)for(int i=0;i<tools.length();i++){JSONObject tool=tools.optJSONObject(i),f=tool==null?null:tool.optJSONObject("function");if(f==null)continue;output.put(new JSONObject().put("type","function_call").put("call_id",tool.optString("id")).put("name",f.optString("name")).put("arguments",f.optString("arguments","{}")));}
        JSONObject result=new JSONObject().put("status","completed").put("output",output);if(response.optJSONObject("usage")!=null)result.put("usage",normalizeUsage(response.optJSONObject("usage")));validateCompleted(result);return result;
    }
    private static JSONObject claudeRequest(JSONObject body)throws Exception{
        JSONObject result=new JSONObject().put("model",body.optString("model")).put("max_tokens",body.optInt("max_output_tokens",8192)).put("stream",true);if(body.has("instructions"))result.put("system",body.optString("instructions"));JSONArray input=body.optJSONArray("input"),messages=new JSONArray();String previous="";
        if(input!=null)for(int i=0;i<input.length();i++){JSONObject item=input.optJSONObject(i);if(item==null)continue;String type=item.optString("type"),role="";JSONArray content=new JSONArray();
            if(type.equals("function_call")){role="assistant";JSONObject args=new JSONObject(item.optString("arguments","{}"));content.put(new JSONObject().put("type","tool_use").put("id",item.optString("call_id")).put("name",item.optString("name")).put("input",args));}
            else if(type.equals("function_call_output")){role="user";Object value=item.opt("output");JSONObject block=new JSONObject().put("type","tool_result").put("tool_use_id",item.optString("call_id")).put("content",value instanceof JSONArray?contentParts(value,true):String.valueOf(value));content.put(block);}
            else if(item.optString("role").equals("user")||item.optString("role").equals("assistant")){role=item.optString("role");content=contentParts(item.opt("content"),true);if(role.equals("assistant")&&item.optJSONArray(CLAUDE_CONTEXT)!=null){JSONArray joined=new JSONArray(),thinking=item.getJSONArray(CLAUDE_CONTEXT);for(int n=0;n<thinking.length();n++)joined.put(thinking.get(n));for(int n=0;n<content.length();n++)joined.put(content.get(n));content=joined;}}
            if(role.isEmpty()||content.length()==0)continue;if(role.equals(previous)){JSONArray last=messages.getJSONObject(messages.length()-1).getJSONArray("content");for(int j=0;j<content.length();j++)last.put(content.get(j));}else{messages.put(new JSONObject().put("role",role).put("content",content));previous=role;}
        }
        result.put("messages",messages);JSONArray tools=flatTools(body.optJSONArray("tools")),converted=new JSONArray();for(int i=0;i<tools.length();i++){JSONObject t=tools.getJSONObject(i);converted.put(new JSONObject().put("name",t.optString("name")).put("description",t.optString("description")).put("input_schema",t.optJSONObject("parameters")));}if(converted.length()>0)result.put("tools",converted);
        JSONObject reasoning=body.optJSONObject("reasoning");String effort=reasoning==null?"":reasoning.optString("effort");if(effort.equals("none"))result.put("thinking",new JSONObject().put("type","disabled"));else if(!effort.isEmpty())result.put("output_config",new JSONObject().put("effort",effort));return result;
    }
    private static JSONObject normalizeClaude(JSONObject response)throws Exception{
        String finish=response.optString("stop_reason","end_turn");if(!finish.equals("end_turn")&&!finish.equals("tool_use")&&!finish.equals("stop_sequence"))throw new Exception("Claude 响应未完成："+finish);JSONArray output=new JSONArray(),context=new JSONArray(),content=response.optJSONArray("content");StringBuilder visible=new StringBuilder();
        if(content!=null)for(int i=0;i<content.length();i++){JSONObject block=content.optJSONObject(i);if(block==null)continue;if(block.optString("type").equals("thinking")||block.optString("type").equals("redacted_thinking"))context.put(new JSONObject(block.toString()));else if(block.optString("type").equals("text"))visible.append(block.optString("text"));else if(block.optString("type").equals("tool_use")){JSONObject args=block.optJSONObject("input");output.put(new JSONObject().put("type","function_call").put("call_id",block.optString("id")).put("name",block.optString("name")).put("arguments",args==null?"{}":args.toString()));}}
        if(visible.length()>0||context.length()>0){JSONObject message=messageItem(visible.toString());if(context.length()>0)message.put(CLAUDE_CONTEXT,context);JSONArray ordered=new JSONArray().put(message);for(int i=0;i<output.length();i++)ordered.put(output.get(i));output=ordered;}JSONObject result=new JSONObject().put("status","completed").put("output",output);if(response.optJSONObject("usage")!=null)result.put("usage",normalizeUsage(response.optJSONObject("usage")));validateCompleted(result);return result;
    }
}
