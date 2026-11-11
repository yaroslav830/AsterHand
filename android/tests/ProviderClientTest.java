package com.pocketagent;

import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.concurrent.atomic.AtomicBoolean;

/** Local protocol fixtures. These do not contact a provider or prove account access. */
public final class ProviderClientTest {
    static int checks=0;
    static void ok(boolean value,String label){checks++;if(!value)throw new AssertionError(label);}
    interface Checked{void run()throws Exception;}
    static void fails(Checked c,String label)throws Exception{boolean failed=false;try{c.run();}catch(Exception expected){failed=true;}ok(failed,label);}
    static String event(JSONObject o){return "data: "+o.toString()+"\r\n\r\n";}
    static JSONObject parse(String provider,String data,ProviderClient.Listener listener)throws Exception{return ProviderClient.parseStream(provider,new ByteArrayInputStream(data.getBytes(StandardCharsets.UTF_8)),listener,new AtomicBoolean());}
    static JSONObject item(String type,String key,String value)throws Exception{return new JSONObject().put("type",type).put(key,value);}
    static final class Seen implements ProviderClient.Listener {StringBuilder text=new StringBuilder();ArrayList<String> stages=new ArrayList<>();JSONObject usage;public void onStage(String s){stages.add(s);}public void onText(String s){text.append(s);}public void onUsage(JSONObject u){usage=u;}}
    public static void main(String[] argv)throws Exception{
        ok(ProviderClient.adapter("openai","https://api.openai.com/v1/").equals("openai"),"Official OpenAI keeps Responses");
        ok(ProviderClient.adapter("openai","https://api.deepseek.com/v1").equals("deepseek"),"Custom OpenAI-compatible endpoint uses Chat Completions");
        ok(ProviderClient.adapter("chatgpt","https://example.invalid").equals("chatgpt"),"ChatGPT keeps its authenticated protocol");
        Seen seen=new Seen();JSONObject completed=new JSONObject().put("status","completed").put("output",new JSONArray()).put("usage",new JSONObject().put("input_tokens",8).put("output_tokens",2));
        String prefix=event(item("response.reasoning_text.delta","delta","PRIVATE_REASONING"))+event(item("response.output_text.delta","delta","你"))+event(item("response.output_text.delta","delta","好"));
        JSONObject result=parse("openai",prefix+event(new JSONObject().put("type","response.completed").put("response",completed)),seen);
        ok(ProviderClient.outputText(result).equals("你好"),"Responses CRLF output assembled");ok(seen.text.toString().equals("你好"),"Only visible deltas reach UI");ok(seen.stages.contains("正在思考"),"Fixed reasoning status");ok(seen.usage.optInt("output_tokens")==2,"Responses usage");
        fails(()->parse("openai",prefix,new Seen()),"Truncated stream rejected");fails(()->parse("openai",event(new JSONObject().put("type","response.completed").put("response",completed)),new Seen()),"Empty complete rejected");
        String failed=prefix+event(new JSONObject().put("type","response.failed").put("response",new JSONObject().put("error",new JSONObject().put("message","fixture failure"))));fails(()->parse("openai",failed,new Seen()),"Failure after delta remains failure");
        AtomicBoolean cancelled=new AtomicBoolean(true);fails(()->ProviderClient.parseStream("openai",new ByteArrayInputStream(prefix.getBytes(StandardCharsets.UTF_8)),seen,cancelled),"Cancelled stream rejected");

        JSONObject tool=new JSONObject().put("type","function_call").put("call_id","call-one").put("name","read_file").put("arguments","{}");
        JSONObject toolFinal=new JSONObject().put("status","completed").put("output",new JSONArray().put(tool));
        result=parse("openai",event(new JSONObject().put("type","response.completed").put("response",toolFinal)),new Seen());ok(result.getJSONArray("output").getJSONObject(0).getString("name").equals("read_file"),"Tool-only response accepted");

        JSONObject first=new JSONObject().put("choices",new JSONArray().put(new JSONObject().put("delta",new JSONObject().put("reasoning_content","PRIVATE_REASONING").put("tool_calls",new JSONArray().put(new JSONObject().put("index",0).put("id","call-d").put("function",new JSONObject().put("name","read_file").put("arguments","{\"path\":")))))));
        JSONObject last=new JSONObject().put("choices",new JSONArray().put(new JSONObject().put("delta",new JSONObject().put("tool_calls",new JSONArray().put(new JSONObject().put("index",0).put("function",new JSONObject().put("arguments","\"a.txt\"}"))))).put("finish_reason","tool_calls"))).put("usage",new JSONObject().put("prompt_tokens",7).put("completion_tokens",3));
        Seen deep=new Seen();result=parse("deepseek",event(first)+event(last)+"data: [DONE]\r\n\r\n",deep);ok(deep.text.length()==0,"DeepSeek reasoning not displayed");ok(result.getJSONArray("output").length()==2,"Private history plus tool retained");ok(result.getJSONArray("output").getJSONObject(1).getString("arguments").equals("{\"path\":\"a.txt\"}"),"DeepSeek split tool arguments assembled");
        JSONArray history=result.getJSONArray("output");history.put(new JSONObject().put("type","function_call_output").put("call_id","call-d").put("output","test"));
        JSONObject body=new JSONObject().put("model","chosen-model").put("input",history).put("max_output_tokens",1234).put("tools",new JSONArray().put(new JSONObject().put("type","function").put("name","read_file").put("parameters",new JSONObject().put("type","object"))));
        JSONObject wire=ProviderClient.wireRequest("deepseek",body);ok(wire.getJSONArray("messages").getJSONObject(0).getString("reasoning_content").equals("PRIVATE_REASONING"),"DeepSeek provider-private roundtrip");ok(wire.getJSONArray("messages").getJSONObject(0).getJSONArray("tool_calls").length()==1,"Tool merged into assistant turn");ok(wire.getInt("max_tokens")==1234,"DeepSeek token limit mapped");
        ok(!ProviderClient.wireRequest("openai",body).toString().contains("PRIVATE_REASONING"),"Provider-private metadata not sent to another provider");
        JSONObject chat=ProviderClient.wireRequest("chatgpt",body);ok(!chat.has("max_output_tokens"),"ChatGPT unsupported limit removed");ok(chat.getJSONArray("tools").getJSONObject(0).getString("type").equals("namespace"),"ChatGPT namespace retained");fails(()->parse("deepseek",event(first)+event(last),new Seen()),"DeepSeek missing DONE rejected");

        String claude=event(new JSONObject().put("type","message_start").put("message",new JSONObject().put("usage",new JSONObject().put("input_tokens",9))))+event(new JSONObject().put("type","content_block_start").put("index",0).put("content_block",item("text","text","")))+event(new JSONObject().put("type","content_block_delta").put("index",0).put("delta",item("text_delta","text","完成")))+event(new JSONObject().put("type","content_block_start").put("index",1).put("content_block",new JSONObject().put("type","tool_use").put("id","call-c").put("name","list_directory").put("input",new JSONObject())))+event(new JSONObject().put("type","content_block_delta").put("index",1).put("delta",item("input_json_delta","partial_json","{\"path\":\".\"}")))+event(new JSONObject().put("type","message_delta").put("delta",new JSONObject().put("stop_reason","tool_use")).put("usage",new JSONObject().put("output_tokens",4)))+event(new JSONObject().put("type","message_stop"));
        Seen anth=new Seen();result=parse("anthropic",claude,anth);ok(result.getJSONArray("output").length()==2,"Claude text does not overwrite tool");ok(result.getJSONArray("output").getJSONObject(1).getString("name").equals("list_directory"),"Claude tool retained");ok(anth.text.toString().equals("完成"),"Claude text streamed");ok(result.getJSONObject("usage").getInt("input_tokens")==9&&result.getJSONObject("usage").getInt("output_tokens")==4,"Claude usage merged");

        JSONArray parts=new JSONArray().put(item("input_text","text","看图")).put(item("input_image","image_url","data:image/png;base64,AA==")).put(new JSONObject().put("type","input_file").put("filename","notes.txt").put("file_data","data:text/plain;base64,aGk="));
        JSONObject media=new JSONObject().put("model","chosen").put("input",new JSONArray().put(new JSONObject().put("role","user").put("content",parts)));
        wire=ProviderClient.wireRequest("anthropic",media);JSONArray content=wire.getJSONArray("messages").getJSONObject(0).getJSONArray("content");ok(content.getJSONObject(1).getJSONObject("source").getString("media_type").equals("image/png"),"Claude image preserved");ok(content.getJSONObject(2).getJSONObject("source").getString("data").equals("hi"),"Claude text document decoded");ok(content.getJSONObject(2).getJSONObject("source").getString("type").equals("text"),"Claude plain document source");
        content=ProviderClient.wireRequest("deepseek",media).getJSONArray("messages").getJSONObject(0).getJSONArray("content");ok(content.getJSONObject(1).getJSONObject("image_url").getString("url").startsWith("data:image/png"),"DeepSeek image preserved");ok(content.getJSONObject(2).getString("type").equals("text")&&content.getJSONObject(2).getString("text").contains("hi"),"DeepSeek text attachment converted without loss");
        JSONObject imageFile=new JSONObject().put("model","chosen").put("input",new JSONArray().put(new JSONObject().put("role","user").put("content",new JSONArray().put(new JSONObject().put("type","input_file").put("filename","screen.png").put("file_data","data:image/png;base64,AA==")))));
        JSONObject imagePart=ProviderClient.wireRequest("deepseek",imageFile).getJSONArray("messages").getJSONObject(0).getJSONArray("content").getJSONObject(0);ok(imagePart.has("file_data")&&!imagePart.has("file"),"DeepSeek file image shape");
        JSONObject pdf=new JSONObject().put("model","chosen").put("input",new JSONArray().put(new JSONObject().put("role","user").put("content",new JSONArray().put(new JSONObject().put("type","input_file").put("filename","book.pdf").put("file_data","data:application/pdf;base64,JVBERi0=")))));
        fails(()->ProviderClient.wireRequest("deepseek",pdf),"Unsupported PDF fails before network instead of losing content");
        JSONObject signed=new JSONObject().put("type","thinking").put("thinking","PRIVATE_REASONING").put("signature","opaque-fixture-signature");JSONObject signedMessage=new JSONObject().put("type","message").put("role","assistant").put("content",new JSONArray().put(item("output_text","text","ok"))).put(ProviderClient.CLAUDE_CONTEXT,new JSONArray().put(signed));
        JSONObject thinkingBody=new JSONObject().put("model","chosen").put("input",new JSONArray().put(signedMessage)).put("reasoning",new JSONObject().put("effort","high"));
        JSONObject thinkingWire=ProviderClient.wireRequest("anthropic",thinkingBody);ok(thinkingWire.getJSONObject("output_config").getString("effort").equals("high"),"Claude reasoning effort applied");ok(thinkingWire.getJSONArray("messages").getJSONObject(0).getJSONArray("content").getJSONObject(0).getString("signature").equals("opaque-fixture-signature"),"Claude signed context preserved");ok(!ProviderClient.wireRequest("openai",thinkingBody).toString().contains("opaque-fixture-signature"),"Claude private context never crosses provider");
        fails(()->ProviderClient.base("openai","http://example.invalid"),"HTTPS required");fails(()->ProviderClient.base("openai","https://user:secret@example.invalid"),"URL credentials rejected");fails(()->ProviderClient.base("openai","https://example.invalid?key=secret"),"URL query rejected");ok(ProviderClient.base("chatgpt","https://other.invalid").equals("https://api.openai.com/v1"),"ChatGPT token destination pinned");
        System.out.println("Provider protocol fixtures passed: "+checks+" (no live provider requests)");
    }
}
