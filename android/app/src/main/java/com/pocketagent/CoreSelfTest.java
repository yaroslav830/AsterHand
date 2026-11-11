package com.pocketagent;
import android.content.*;
import android.os.*;
import org.json.*;
import java.util.concurrent.*;
/** Protected in-app diagnostics: no exported component, no API keys, and fixtures are labeled explicitly. */
public final class CoreSelfTest {
    private static final Handler main=new Handler(Looper.getMainLooper());
    public static JSONObject runBasic(Context context)throws Exception{
        if(Looper.myLooper()==Looper.getMainLooper())throw new Exception("请在诊断工作线程运行检查。");
        Context app=context.getApplicationContext();JSONObject out=new JSONObject().put("fixture",true).put("real_model_request",false).put("app_uid",android.os.Process.myUid()).put("projects",ProjectStoreSelfTest.run(app));
        VoiceController voice=VoiceController.get(app);if(voice.enabled())out.put("voice_mute_test","skipped_active_voice");else{boolean mic=voice.micMuted(),speech=voice.speechMuted();int checked=0;try{voice.setMicMuted(true);drain();if(!voice.micMuted()||voice.speechMuted()!=speech)throw new Exception("麦克风静音影响了朗读状态。");checked++;voice.setSpeechMuted(true);drain();if(!voice.micMuted()||!voice.speechMuted())throw new Exception("朗读静音状态未更新。");checked++;voice.setMicMuted(false);drain();if(voice.micMuted()||!voice.speechMuted())throw new Exception("麦克风恢复影响了朗读静音。");checked++;}finally{voice.setMicMuted(mic);voice.setSpeechMuted(speech);drain();}if(voice.micMuted()!=mic||voice.speechMuted()!=speech)throw new Exception("原有静音设置未能恢复。");out.put("voice_mute_checks",checked+1).put("voice_settings_restored",true).put("actual_recognition_tested",false);}
        out.put("resume_context",resumeContext(app)).put("followup_context",followupContext(app)).put("question_binding",questionBinding()).put("voice_capsule",voiceCapsule()).put("voice_idle",voiceIdle());
        out.put("ordinary_permission_probe",new PrivilegeManager(app).probe(PrivilegeManager.Mode.NORMAL));out.put("overlay_permission",android.provider.Settings.canDrawOverlays(app)).put("ordinary_screen_connected",ScreenAccess.enabled(app)).put("microphone_granted",app.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)==android.content.pm.PackageManager.PERMISSION_GRANTED).put("notifications_granted",Build.VERSION.SDK_INT<33||app.checkSelfPermission("android.permission.POST_NOTIFICATIONS")==android.content.pm.PackageManager.PERMISSION_GRANTED);return out;
    }
    private static JSONObject resumeContext(Context app)throws Exception{
        java.io.File scratch=new java.io.File(app.getCacheDir(),"resume-selftest-"+java.util.UUID.randomUUID());
        if(!scratch.mkdirs())throw new Exception("无法创建隔离测试目录。");
        try{
            ProjectStore store=new ProjectStore(new java.io.File(scratch,"app"),new java.io.File(scratch,"work"));
            JSONObject original=store.currentProject();String pid=original.getString("id"),cid=store.currentChat().getString("id");
            JSONObject other=store.createProject("另一个测试项目");String selected=other.getString("id");
            JSONObject target=AgentSession.resumeTarget(store,pid,cid);int checked=0;
            if(!target.getJSONObject("project").getString("id").equals(pid)||!target.getJSONObject("chat").getString("id").equals(cid))throw new AssertionError("Resume selected the wrong task");checked++;
            if(!store.currentProject().getString("id").equals(selected))throw new AssertionError("Resume lookup changed current selection");checked++;
            store.deleteChat(cid);boolean rejected=false;try{AgentSession.resumeTarget(store,pid,cid);}catch(Exception expected){rejected=true;}
            if(!rejected)throw new AssertionError("Deleted task silently fell back to another chat");checked++;
            rejected=false;try{AgentSession.resumeTarget(store,"","");}catch(Exception expected){rejected=true;}
            if(!rejected)throw new AssertionError("Missing context silently fell back to current chat");checked++;
            return new JSONObject().put("fixture",true).put("checks",checked).put("scratch_only",true).put("real_model_request",false);
        }finally{deleteFixture(scratch);}
    }
    private static JSONObject followupContext(Context app)throws Exception{
        java.io.File scratch=new java.io.File(app.getCacheDir(),"followup-selftest-"+java.util.UUID.randomUUID());
        if(!scratch.mkdirs())throw new Exception("无法创建隔离测试目录。");
        try{
            ProjectStore store=new ProjectStore(new java.io.File(scratch,"app"),new java.io.File(scratch,"work"));
            String activeProject=store.currentProject().getString("id"),activeChat=store.currentChat().getString("id");
            java.util.Queue<String> queue=new java.util.concurrent.ConcurrentLinkedQueue<>();int checks=0;
            AgentSession.queueFollowup(AgentSession.sendContext(store,activeProject,activeChat),activeProject,activeChat,"同一对话追加1",queue);
            if(queue.size()!=1||!"同一对话追加1".equals(queue.peek()))throw new AssertionError("Active chat followup not queued");checks++;
            String otherChat=store.createChat().getString("id");
            rejectFollowup(store,activeProject,activeChat,queue,activeProject,activeChat);checks++;
            rejectFollowup(store,activeProject,activeChat,queue);checks++;
            if(!store.currentChat().getString("id").equals(otherChat))throw new AssertionError("Rejected followup changed selected chat");checks++;
            store.selectChat(activeChat);AgentSession.queueFollowup(AgentSession.sendContext(store,activeProject,activeChat),activeProject,activeChat,"同一对话追加2",queue);
            if(queue.size()!=2)throw new AssertionError("Returning to active chat cannot append");checks++;
            String otherProject=store.createProject("独立项目 B").getString("id"),otherProjectChat=store.currentChat().getString("id");
            rejectFollowup(store,activeProject,activeChat,queue);checks++;
            if(!store.currentProject().getString("id").equals(otherProject)||!store.currentChat().getString("id").equals(otherProjectChat))throw new AssertionError("Rejected followup changed selected project");checks++;
            rejectFollowup(store,otherProject,activeChat,queue);checks++;
            rejectFollowup(store,activeProject,activeChat,queue,activeProject,activeChat);checks++;
            rejectFollowup(store,activeProject,activeChat,queue,"","");checks++;
            rejectFollowup(store,"",otherProjectChat,queue);checks++;
            if(AgentSession.resumeTarget(store,activeProject,activeChat).getJSONObject("chat").getJSONArray("history").length()!=0||store.currentChat().getJSONArray("history").length()!=0)throw new AssertionError("Routing appended messages directly to project history");checks++;
            store.selectChat(activeChat);
            rejectFollowup(store,activeProject,activeChat,queue,otherProject,otherProjectChat);checks++;
            rejectFollowup(store,activeProject,activeChat,queue,activeProject,otherChat);checks++;
            AgentSession.queueFollowup(AgentSession.sendContext(store,activeProject,activeChat),activeProject,activeChat,"同一对话追加3",queue);
            if(queue.size()!=3||!queue.toString().equals("[同一对话追加1, 同一对话追加2, 同一对话追加3]"))throw new AssertionError("Rejected text leaked into active task queue");checks++;
            store.deleteChat(activeChat);rejectFollowup(store,activeProject,activeChat,queue);checks++;
            if(!store.currentChat().getString("id").equals(otherChat))throw new AssertionError("Deleted context did not retain other chat");checks++;
            JSONArray legacyRows=store.projects();for(int i=0;i<legacyRows.length();i++){JSONObject project=legacyRows.getJSONObject(i);if(project.getString("id").equals(otherProject))project.remove("currentChatID");}
            java.io.File legacyApp=new java.io.File(scratch,"legacy-app");if(!legacyApp.mkdirs())throw new Exception("无法创建旧索引测试目录。");
            JSONObject legacyIndex=new JSONObject().put("projects",legacyRows).put("currentProjectID",activeProject).put("currentChatID",otherChat);
            try(java.io.FileOutputStream out=new java.io.FileOutputStream(new java.io.File(legacyApp,"projects.json"))){out.write(legacyIndex.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));}
            ProjectStore legacy=new ProjectStore(legacyApp,new java.io.File(scratch,"legacy-work"));legacy.selectProject(otherProject);
            JSONObject context=AgentSession.sendContext(legacy,otherProject,otherProjectChat);
            if(!context.getJSONObject("project").getString("id").equals(otherProject)||!context.getJSONObject("chat").getString("id").equals(otherProjectChat))throw new AssertionError("Legacy project missing currentChatID rejected the real current chat");checks++;
            java.util.Queue<String> legacyQueue=new java.util.concurrent.ConcurrentLinkedQueue<>();AgentSession.queueFollowup(context,otherProject,otherProjectChat,"旧项目的正确追加",legacyQueue);
            if(legacyQueue.size()!=1||!"旧项目的正确追加".equals(legacyQueue.peek()))throw new AssertionError("Legacy project followup cannot append");checks++;
            return new JSONObject().put("fixture",true).put("checks",checks).put("scratch_only",true).put("real_model_request",false).put("live_task_changed",false);
        }finally{deleteFixture(scratch);}
    }
    private static void rejectFollowup(ProjectStore store,String project,String chat,java.util.Queue<String> queue)throws Exception{rejectFollowup(store,project,chat,queue,null,null);}
    private static void rejectFollowup(ProjectStore store,String project,String chat,java.util.Queue<String> queue,String sourceProject,String sourceChat)throws Exception{
        java.util.List<String> before=new java.util.ArrayList<>(queue);boolean rejected=false;
        try{AgentSession.queueFollowup(AgentSession.sendContext(store,sourceProject,sourceChat),project,chat,"不得进入活动任务",queue);}catch(Exception expected){rejected=true;}
        if(!rejected||!new java.util.ArrayList<>(queue).equals(before))throw new AssertionError("Foreign or missing context reached active task queue");
    }
    private static void deleteFixture(java.io.File file){if(file.isDirectory()){java.io.File[] children=file.listFiles();if(children!=null)for(java.io.File child:children)deleteFixture(child);}file.delete();}
    private static JSONObject questionBinding()throws Exception{
        java.util.List<String> options=java.util.Arrays.asList("不允许","允许一次","始终允许");int checks=0;
        if(AgentTaskService.validateAnswer("task","new-question","task","old-question","permission",options,false,"",java.util.Arrays.asList("允许一次"))!=null)throw new AssertionError("Stale question authorized a new question");checks++;
        if(AgentTaskService.validateAnswer("task","question","old-task","question","permission",options,false,"",java.util.Arrays.asList("允许一次"))!=null)throw new AssertionError("Stale task authorized a new task");checks++;
        if(AgentTaskService.validateAnswer("task","question","task","question","permission",options,false,"允许一次",java.util.Collections.emptyList())!=null)throw new AssertionError("Free text authorized permission");checks++;
        if(AgentTaskService.validateAnswer("task","question","task","question","approval",options,false,"始终允许",java.util.Collections.emptyList())!=null)throw new AssertionError("Free text authorized an operation");checks++;
        if(AgentTaskService.validateAnswer("task","question","task","question","permission",options,false,"",java.util.Arrays.asList("unknown"))!=null)throw new AssertionError("Unknown option authorized permission");checks++;
        AgentTaskService.Answer valid=AgentTaskService.validateAnswer("task","question","task","question","permission",options,false,"ignored text",java.util.Arrays.asList("允许一次"));
        if(valid==null||!valid.text.isEmpty()||!valid.selections.equals(java.util.Arrays.asList("允许一次")))throw new AssertionError("Explicit valid choice rejected");checks++;
        valid=AgentTaskService.validateAnswer("task","question","task","question","question",options,false,"普通问题回答",java.util.Collections.emptyList());
        if(valid==null||!valid.text.equals("普通问题回答"))throw new AssertionError("Ordinary free-text answer rejected");checks++;
        return new JSONObject().put("fixture",true).put("checks",checks).put("actual_permission_granted",false).put("live_task_changed",false);
    }
    private static JSONObject voiceCapsule()throws Exception{
        JSONObject value=new JSONObject().put("active",true).put("listening",true).put("transcript","测试文字");int checks=0;
        String first=FloatingOverlayService.capsuleVoiceText(value,0),next=FloatingOverlayService.capsuleVoiceText(value,1);
        if(!first.startsWith("正在聆听")||!first.contains("测试文字")||first.equals(next))throw new AssertionError("Listening capsule did not expose an animated listening state");checks++;
        value.put("listening",false).put("status","正在识别");if(!FloatingOverlayService.capsuleVoiceText(value,0).equals("正在识别"))throw new AssertionError("Recognition capsule state");checks++;
        value.put("waiting",true);if(!FloatingOverlayService.capsuleVoiceText(value,0).equals("等待 AI 回复"))throw new AssertionError("Waiting capsule state");checks++;
        value.put("waiting",false).put("speaking",true).put("reply","模拟回复");if(!FloatingOverlayService.capsuleVoiceText(value,0).equals("正在朗读 · 模拟回复"))throw new AssertionError("Read-aloud capsule state");checks++;
        value.put("speaking",false).put("micMuted",true);if(!FloatingOverlayService.capsuleVoiceText(value,0).equals("麦克风已静音"))throw new AssertionError("Muted capsule state");checks++;
        value.put("active",false);if(!FloatingOverlayService.capsuleVoiceText(value,0).isEmpty())throw new AssertionError("Inactive voice obscures task capsule");checks++;
        return new JSONObject().put("fixture",true).put("checks",checks).put("microphone_started",false).put("actual_recognition_tested",false).put("overlay_windows_changed",false);
    }
    private static JSONObject voiceIdle()throws Exception{
        VoiceIdlePolicy policy=new VoiceIdlePolicy();int checked=0;policy.configure(0,0);policy.update(true,false,0);
        if(policy.expired(100000))throw new AssertionError("Disabled idle limit expires");checked++;
        policy.configure(10,0);if(policy.expired(9999)||policy.remaining(9999)!=1||!policy.expired(10000))throw new AssertionError("Idle boundary");checked++;
        policy.update(true,true,10000);if(policy.remaining(10000)!=10)throw new AssertionError("User response failed to reset idle");checked++;
        policy.update(false,false,15000);if(policy.expired(100000)||!policy.paused())throw new AssertionError("AI/read-aloud consumed idle");checked++;
        policy.update(true,false,100000);if(policy.remaining(100000)!=10||!policy.expired(110000))throw new AssertionError("Return to user failed to restart idle");checked++;
        boolean invalid=false;try{policy.configure(-1,0);}catch(IllegalArgumentException expected){invalid=true;}if(!invalid)throw new AssertionError("Invalid idle limit accepted");checked++;
        if(VoiceIdlePolicy.productTimeout(0)!=5||VoiceIdlePolicy.requireProductTimeout(1)!=1)throw new AssertionError("Product idle migration or custom minimum");checked++;
        invalid=false;try{VoiceIdlePolicy.requireProductTimeout(0);}catch(IllegalArgumentException expected){invalid=true;}if(!invalid)throw new AssertionError("Product exposed disabled idle limit");checked++;
        policy.configure(5,0);if(policy.expired(4999)||!policy.expired(5000))throw new AssertionError("Five-second idle boundary");checked++;
        return new JSONObject().put("fixture",true).put("checks",checked).put("clock_injected",true).put("microphone_started",false);
    }
    public static JSONObject startQuestionFixture(Context context)throws Exception{
        Context app=context.getApplicationContext();AgentTaskService.Session session=AgentTaskService.start(app,task->{task.progress("测试夹具 · 不调用模型","正在验证后台任务与问题选项");Thread.sleep(350);String selected=task.ask("本机测试夹具：请选择一个选项（不涉及任何授权）",new String[]{"测试选项 A","测试选项 B"});app.getSharedPreferences("selftest",0).edit().putString("questionFixtureId",task.id).putString("questionFixtureAnswer",selected).apply();task.finish("completed","本机测试夹具完成："+selected);});return new JSONObject().put("fixture",true).put("real_model_request",false).put("id",session.id);
    }
    public static JSONObject questionFixtureResult(Context context)throws Exception{android.content.SharedPreferences p=context.getSharedPreferences("selftest",0);return new JSONObject().put("fixture",true).put("id",p.getString("questionFixtureId","")).put("answer",p.getString("questionFixtureAnswer","")).put("task",AgentTaskService.snapshot(context));}
    private static void drain()throws Exception{CountDownLatch latch=new CountDownLatch(1);main.post(latch::countDown);if(!latch.await(3,TimeUnit.SECONDS))throw new Exception("主线程未及时处理诊断检查。");}
}
