package com.pocketagent;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.os.*;
import android.util.AtomicFile;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Owns one user-initiated task independently of the Activity; never replays code after process death. */
public final class AgentTaskService extends Service {
    public interface Work {void run(Session session)throws Exception;}
    public interface Listener {void onChanged(JSONObject state);}
    public static final class Snapshot {
        public final String id,stage,reply,question,questionId,questionKind,error;
        public final List<String> options;
        public final boolean running,multi,attention;
        public final long updated;
        private Snapshot(String id,String stage,String reply,String question,String questionId,String questionKind,String error,List<String> options,boolean running,boolean multi,boolean attention,long updated){this.id=id;this.stage=stage;this.reply=reply;this.question=question;this.questionId=questionId;this.questionKind=questionKind;this.error=error;this.options=Collections.unmodifiableList(new ArrayList<>(options));this.running=running;this.multi=multi;this.attention=attention;this.updated=updated;}
        public JSONObject json(){JSONObject j=new JSONObject();try{j.put("id",id).put("stage",stage).put("reply",reply).put("question",question).put("questionId",questionId).put("questionKind",questionKind).put("error",error).put("options",new JSONArray(options)).put("running",running).put("multi",multi).put("attention",attention).put("updated",updated);}catch(Exception ignored){}return j;}
    }
    public static final class Answer {
        public final String text;public final List<String> selections;
        Answer(String text,List<String> selections){this.text=text;this.selections=Collections.unmodifiableList(new ArrayList<>(selections));}
    }
    public static final class Session {
        public final AtomicBoolean cancelled=new AtomicBoolean(false);
        public final String id=UUID.randomUUID().toString();
        private final Context app;
        private volatile String stage="正在准备",reply="",question="",questionId="",questionKind="",error="";
        private volatile List<String> options=Collections.emptyList();
        private volatile boolean running=true,multi=false;
        private volatile Thread worker;
        private volatile CountDownLatch answerLatch;
        private volatile Answer answer;
        private Session(Context app){this.app=app;}
        public AtomicBoolean cancelled(){return cancelled;}
        public void progress(String stage,String text){this.stage=limit(stage,200);if(text!=null&&!text.isEmpty())this.reply=limit(text,6000);publish(this,false);}
        public void finish(String status,String text){if(text!=null&&!text.isEmpty())this.reply=limit(text,6000);this.stage="completed".equals(status)?"任务完成":"stopped".equals(status)?"任务已停止":"failed".equals(status)?"任务失败":limit(status,200);publish(this,true);}
        public void progress(String value){stage=limit(value,200);publish(this,false);}
        public void reply(String value){reply=limit(value,6000);publish(this,false);}
        public void finish(String value){if(value!=null&&!value.isEmpty())reply(value);stage=cancelled.get()?"已停止":"任务完成";}
        public Answer ask(String value,List<String> choices,boolean multiple)throws Exception{return ask(value,choices,multiple,"question");}
        public Answer ask(String value,List<String> choices,boolean multiple,String kind)throws Exception{
            if(cancelled.get())throw new InterruptedException("任务已停止");
            synchronized(this){if(answerLatch!=null)throw new Exception("已有一个问题等待回答。");question=limit(value,4000);if(question.isEmpty())throw new Exception("问题不能为空。");ArrayList<String> safe=new ArrayList<>();if(choices!=null)for(String option:choices){if(safe.size()>=12)break;safe.add(limit(option,240));}options=safe;multi=multiple;questionId=UUID.randomUUID().toString();questionKind=kind!=null&&(kind.equals("permission")||kind.equals("approval"))?kind:"question";stage="等待你的回答";answer=null;answerLatch=new CountDownLatch(1);}
            publish(this,true);postQuestion(this);
            CountDownLatch waiting=answerLatch;long deadline=SystemClock.elapsedRealtime()+10*60*1000;
            try{while(!cancelled.get()&&SystemClock.elapsedRealtime()<deadline){if(waiting.await(250,TimeUnit.MILLISECONDS))break;}if(cancelled.get())throw new InterruptedException("任务已停止");Answer result=answer;if(result==null)throw new Exception("等待回答已超时，本次任务已暂停结束。");return result;}
            finally{synchronized(this){question="";questionId="";questionKind="";options=Collections.emptyList();multi=false;answerLatch=null;answer=null;}cancelQuestion(app);publish(this,true);}
        }
        public String ask(String value,String[] choices)throws Exception{return ask(value,choices,"question");}
        public String ask(String value,String[] choices,String kind)throws Exception{Answer a=ask(value,choices==null?Collections.emptyList():Arrays.asList(choices),false,kind);return !a.text.isEmpty()?a.text:a.selections.isEmpty()?"":a.selections.get(0);}
        private Snapshot view(){synchronized(this){return new Snapshot(id,stage,reply,question,questionId,questionKind,error,options,running,multi,!question.isEmpty(),System.currentTimeMillis());}}
    }
    private static final String CHANNEL="asterhand.tasks",QUESTIONS="asterhand.questions",STOP="com.pocketagent.STOP_TASK";
    private static final int NOTIFICATION=2101,QUESTION_NOTIFICATION=2102;
    private static final Handler main=new Handler(Looper.getMainLooper());
    private static final CopyOnWriteArrayList<java.lang.ref.WeakReference<Listener>> listeners=new CopyOnWriteArrayList<>();
    private static volatile Session current;
    private static volatile Snapshot latest=new Snapshot("","就绪","","","","","",Collections.emptyList(),false,false,false,0);
    private static volatile AgentTaskService service;
    private static volatile Work pendingWork;
    private static boolean publishQueued;
    private WakeLease wakeLease;
    private Session owned;
    private long lastNotification;

    public static synchronized Session start(Context context,Work work)throws Exception{
        if(work==null)throw new IllegalArgumentException("缺少任务");if(current!=null&&current.running)throw new Exception("已有任务正在运行，请先停止。");
        Context app=context.getApplicationContext();Session session=new Session(app);current=session;pendingWork=work;publish(session,true);
        try{Intent intent=new Intent(app,AgentTaskService.class);if(Build.VERSION.SDK_INT>=26)app.startForegroundService(intent);else app.startService(intent);}catch(Exception e){session.running=false;session.error="后台服务未能启动："+e.getMessage();session.stage="启动失败";pendingWork=null;publish(session,true);throw e;}
        return session;
    }
    public static Snapshot view(){Session s=current;return s!=null?s.view():latest;}
    public static JSONObject snapshot(){return view().json();}
    public static JSONObject snapshot(Context context){if(current==null&&latest.updated==0)loadLast(context.getApplicationContext());return snapshot();}
    public static void addListener(Listener listener){listeners.add(new java.lang.ref.WeakReference<>(listener));main.post(()->listener.onChanged(snapshot()));}
    public static void removeListener(Listener listener){for(java.lang.ref.WeakReference<Listener> ref:listeners){Listener l=ref.get();if(l==null||l==listener)listeners.remove(ref);}}
    public static void stop(){cancel();}
    public static void cancel(){Session s=current;if(s==null||!s.running)return;s.cancelled.set(true);s.stage="正在停止";Thread worker=s.worker;if(worker!=null)worker.interrupt();CountDownLatch waiting=s.answerLatch;if(waiting!=null)waiting.countDown();publish(s,true);}
    public static boolean answer(String text,List<String> choices){Session s=current;return s!=null&&answer(text,choices,s.id,s.questionId);}
    public static boolean answer(String text,List<String> choices,String taskId,String questionId){Session s=current;if(s==null||!s.running||s.answerLatch==null)return false;synchronized(s){if(s!=current||s.answerLatch==null||s.answer!=null)return false;Answer checked=validateAnswer(s.id,s.questionId,taskId,questionId,s.questionKind,s.options,s.multi,text,choices);if(checked==null)return false;s.answer=checked;s.answerLatch.countDown();return true;}}
    /** Pure validation shared with isolated fixtures; does not answer or authorize a live task. */
    static Answer validateAnswer(String expectedTask,String expectedQuestion,String taskId,String questionId,String kind,List<String> options,boolean multi,String text,List<String> choices){
        if(expectedTask==null||expectedQuestion==null||expectedQuestion.isEmpty()||!expectedTask.equals(taskId)||!expectedQuestion.equals(questionId))return null;
        ArrayList<String> valid=new ArrayList<>();if(choices!=null)for(String choice:choices){if(!options.contains(choice)||valid.contains(choice))continue;valid.add(choice);if(!multi)break;}
        String typed=limit(text,4000).trim();if(!"question".equals(kind)){if(valid.isEmpty())return null;typed="";}
        return typed.isEmpty()&&valid.isEmpty()?null:new Answer(typed,valid);
    }
    public static boolean answer(String text){return answer(text,Collections.emptyList());}
    public static boolean answer(String text,JSONArray selections){ArrayList<String> values=new ArrayList<>();if(selections!=null)for(int i=0;i<selections.length();i++)values.add(selections.optString(i));return answer(text,values);}
    public static boolean answer(String text,JSONArray selections,String taskId,String questionId){ArrayList<String> values=new ArrayList<>();if(selections!=null)for(int i=0;i<selections.length();i++)values.add(selections.optString(i));return answer(text,values,taskId,questionId);}
    public static boolean answer(JSONArray selections){return answer("",selections);}
    @Override public void onCreate(){super.onCreate();service=this;channels(this);}
    @Override public int onStartCommand(Intent intent,int flags,int startId){
        if(intent!=null&&STOP.equals(intent.getAction())){cancel();if(current==null||!current.running)stopSelf();return START_NOT_STICKY;}
        Session session=current;Work work=pendingWork;pendingWork=null;
        if(session==null||!session.running||work==null){stopSelf();return START_NOT_STICKY;}
        owned=session;Notification notification=taskNotification(this,session.view());
        try{if(Build.VERSION.SDK_INT>=34)startForeground(NOTIFICATION,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);else if(Build.VERSION.SDK_INT>=29)startForeground(NOTIFICATION,notification,0);else startForeground(NOTIFICATION,notification);
            PowerManager power=(PowerManager)getSystemService(POWER_SERVICE);wakeLease=new WakeLease(session,power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"AsterHand:AgentTask"));wakeLease.begin();
        }catch(Exception e){session.running=false;session.error="后台运行不可用："+e.getMessage();session.stage="任务未启动";publish(session,true);stopSelf();return START_NOT_STICKY;}
        final WakeLease heldLease=wakeLease;session.worker=new Thread(()->{try{if(session.cancelled.get())throw new InterruptedException("任务已停止");work.run(session);if(session.stage.equals("正在准备")||session.stage.startsWith("正在")||session.stage.equals("等待你的回答"))session.stage="任务完成";}catch(InterruptedException e){session.cancelled.set(true);}catch(Exception e){session.error=limit(e.getMessage()==null?e.getClass().getSimpleName():e.getMessage(),1000);session.stage="任务失败";}finally{session.running=false;if(session.cancelled.get())session.stage="任务已停止";session.question="";session.questionId="";session.questionKind="";session.options=Collections.emptyList();session.answerLatch=null;cancelQuestion(this);publish(session,true);main.post(()->{if(heldLease!=null)heldLease.close();if(current==session||current==null||!current.running){stopForeground(true);stopSelf(startId);}});}},"AsterHand-Agent");session.worker.start();return START_NOT_STICKY;
    }
    @Override public IBinder onBind(Intent intent){return null;}
    @Override public void onDestroy(){if(service==this)service=null;if(wakeLease!=null)wakeLease.close();Session s=owned;if(s!=null&&s.running){s.cancelled.set(true);s.running=false;s.stage="任务已中断";if(s.worker!=null)s.worker.interrupt();if(s.answerLatch!=null)s.answerLatch.countDown();publish(s,true);}super.onDestroy();}
    private final class WakeLease implements Runnable{
        private final Session session;private final PowerManager.WakeLock lock;private boolean closed;
        WakeLease(Session session,PowerManager.WakeLock lock){this.session=session;this.lock=lock;lock.setReferenceCounted(false);}
        void begin(){lock.acquire(30*60*1000L);main.postDelayed(this,15*60*1000L);}
        public void run(){if(closed)return;if(owned!=session||!session.running||session.cancelled.get()){close();return;}try{lock.acquire(30*60*1000L);main.postDelayed(this,15*60*1000L);}catch(RuntimeException unavailable){close();}}
        void close(){if(closed)return;closed=true;main.removeCallbacks(this);if(lock.isHeld())lock.release();}
    }
    @Override public void onTimeout(int startId,int fgsType){cancel();stopSelf();}
    private static void publish(Session session,boolean immediate){FloatingOverlayService.taskState(view().running);synchronized(AgentTaskService.class){latest=view();if(!immediate&&publishQueued)return;publishQueued=true;}Runnable action=()->{synchronized(AgentTaskService.class){publishQueued=false;}Snapshot state=view();persist(session.app,state);for(java.lang.ref.WeakReference<Listener> ref:listeners){Listener l=ref.get();if(l==null)listeners.remove(ref);else try{l.onChanged(state.json());}catch(RuntimeException ignored){}}AgentTaskService host=service;if(host!=null&&state.running&&(immediate||SystemClock.elapsedRealtime()-host.lastNotification>750)){host.lastNotification=SystemClock.elapsedRealtime();try{((NotificationManager)host.getSystemService(NOTIFICATION_SERVICE)).notify(NOTIFICATION,taskNotification(host,state));}catch(SecurityException ignored){}}};if(immediate)main.post(action);else main.postDelayed(action,120);}
    private static void persist(Context c,Snapshot state){AtomicFile file=new AtomicFile(new File(c.getFilesDir(),"agent-task-state.json"));FileOutputStream out=null;try{out=file.startWrite();out.write(state.json().toString().getBytes(StandardCharsets.UTF_8));file.finishWrite(out);}catch(Exception e){if(out!=null)file.failWrite(out);}}
    private static synchronized void loadLast(Context c){try{File f=new File(c.getFilesDir(),"agent-task-state.json");if(!f.exists()||f.length()>32*1024)return;try(InputStream in=new AtomicFile(f).openRead()){ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[2048];int n;while((n=in.read(b))!=-1){if(out.size()+n>32*1024)return;out.write(b,0,n);}JSONObject j=new JSONObject(new String(out.toByteArray(),StandardCharsets.UTF_8));boolean interrupted=j.optBoolean("running");latest=new Snapshot(j.optString("id"),interrupted?"上次任务已中断，未自动重试":j.optString("stage","就绪"),j.optString("reply"),"","","",j.optString("error"),Collections.emptyList(),false,false,false,j.optLong("updated"));if(interrupted)persist(c,latest);}}catch(Exception ignored){}}
    private static void channels(Context c){UILocalization.initialize(c);if(Build.VERSION.SDK_INT>=26){NotificationManager n=(NotificationManager)c.getSystemService(NOTIFICATION_SERVICE);n.createNotificationChannel(new NotificationChannel(CHANNEL,UILocalization.t("AI 后台任务"),NotificationManager.IMPORTANCE_LOW));n.createNotificationChannel(new NotificationChannel(QUESTIONS,UILocalization.t("AI 等待回答"),NotificationManager.IMPORTANCE_HIGH));}}
    private static PendingIntent open(Context c){return PendingIntent.getActivity(c,2101,new Intent(c,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);}
    private static Notification.Builder builder(Context c,String channel){return Build.VERSION.SDK_INT>=26?new Notification.Builder(c,channel):new Notification.Builder(c);}
    private static Notification taskNotification(Context c,Snapshot state){PendingIntent stop=PendingIntent.getService(c,2102,new Intent(c,AgentTaskService.class).setAction(STOP),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);return builder(c,CHANNEL).setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("AsterHand").setContentText(UILocalization.t(state.stage)).setContentIntent(open(c)).setOngoing(true).setOnlyAlertOnce(true).setVisibility(Notification.VISIBILITY_PRIVATE).addAction(new Notification.Action.Builder(android.R.drawable.ic_media_pause,UILocalization.t("停止"),stop).build()).build();}
    private static void postQuestion(Session s){main.post(()->{try{channels(s.app);Notification n=builder(s.app,QUESTIONS).setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(UILocalization.t("AsterHand 等待你的回答")).setContentText(s.question).setStyle(new Notification.BigTextStyle().bigText(s.question)).setContentIntent(open(s.app)).setAutoCancel(true).setPriority(Notification.PRIORITY_HIGH).setVisibility(Notification.VISIBILITY_PRIVATE).build();((NotificationManager)s.app.getSystemService(NOTIFICATION_SERVICE)).notify(QUESTION_NOTIFICATION,n);}catch(SecurityException ignored){}});}
    private static void cancelQuestion(Context c){((NotificationManager)c.getSystemService(NOTIFICATION_SERVICE)).cancel(QUESTION_NOTIFICATION);}
    private static String limit(String s,int max){if(s==null)return "";return s.length()>max?s.substring(0,max):s;}
}
