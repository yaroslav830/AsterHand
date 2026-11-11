package com.pocketagent.test;
import android.app.*;
import android.content.*;
import android.os.*;
import android.view.*;
import android.webkit.*;
import com.pocketagent.CoreSelfTest;
import com.pocketagent.PrivilegeSelfTest;
import org.json.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;

/** Test APK is signed with the target's own development certificate and never exported as a device executor. */
public final class AsterInstrumentation extends Instrumentation {
    private Bundle args;
    @Override public void onCreate(Bundle arguments){args=arguments==null?new Bundle():arguments;super.onCreate(arguments);start();}
    @Override public void onStart(){Bundle result=new Bundle();JSONObject report=new JSONObject();int status=Activity.RESULT_OK;try{
        Context app=getTargetContext();int uid=android.os.Process.myUid();boolean appUID=uid==app.getApplicationInfo().uid&&uid>=10000;if(!appUID)throw new Exception("Test must execute in the target application's ordinary UID.");
        report.put("fixture",true).put("real_model_request",false).put("target_uid",uid).put("ordinary_app_uid_verified",true).put("api",Build.VERSION.SDK_INT);
        KeyguardManager keyguard=(KeyguardManager)app.getSystemService(Context.KEYGUARD_SERVICE);boolean locked=keyguard.isDeviceLocked();report.put("keyguard_locked",locked).put("lock_screen_modified",false);
        File projects=new File(app.getFilesDir(),"projects.json"),vault=new File(app.getApplicationInfo().dataDir,"shared_prefs/vault.xml");byte[] beforeProjects=bytes(projects),beforeVault=bytes(vault);
        String suite=args.getString("suite","core");if(suite.equals("privilege")){JSONObject privilege=PrivilegeSelfTest.run(app,"true".equals(args.getString("bridge-unavailable"))?new String[]{"--bridge-unavailable"}:new String[0]);report.put("privilege",privilege);if(!privilege.optBoolean("success"))throw new Exception("Privilege diagnostic suite failed: "+privilege.optString("error"));}else if(suite.equals("core"))report.put("basic",CoreSelfTest.runBasic(app));else throw new Exception("Unknown diagnostic suite");report.put("suite",suite);if(!Arrays.equals(beforeProjects,bytes(projects))||!Arrays.equals(beforeVault,bytes(vault)))throw new Exception("Core diagnostics changed the existing project index or credential store.");report.put("existing_projects_preserved",true).put("existing_vault_preserved",true);
        if("true".equals(args.getString("ui"))){report.put("own_ui_dom",ownUi(app));report.put("physical_touch_or_keyboard_verified",false);}else report.put("own_ui_dom","not_requested");
        if(locked&&!keyguard.isDeviceLocked())throw new Exception("Keyguard state changed unexpectedly during diagnostics.");
        report.put("success",true);result.putString("report",report.toString());result.putString("stream",report.toString()+"\n");
    }catch(Throwable e){status=Activity.RESULT_CANCELED;try{report.put("success",false).put("error_type",e.getClass().getSimpleName()).put("error",String.valueOf(e.getMessage()));}catch(Exception ignored){}result.putString("report",report.toString());result.putString("stream",report.toString()+"\n");}finish(status,result);}
    private JSONObject ownUi(Context app)throws Exception{
        Intent intent=new Intent().setClassName(app.getPackageName(),"com.pocketagent.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);Activity activity=startActivitySync(intent);waitForIdleSync();
        long deadline=SystemClock.elapsedRealtime()+15000;JSONObject parsed=null;
        while(SystemClock.elapsedRealtime()<deadline){CountDownLatch latch=new CountDownLatch(1);String[] json={null};runOnMainSync(()->{WebView web=findWebView(activity.getWindow().getDecorView());if(web==null||web.getUrl()==null||!web.getUrl().startsWith("https://appassets.androidplatform.net/asterhand/")){latch.countDown();return;}web.evaluateJavascript("JSON.stringify({title:document.title,ready:document.readyState,buttons:document.querySelectorAll('button').length,inputs:document.querySelectorAll('input,textarea').length,width:innerWidth,scrollWidth:document.documentElement.scrollWidth,visibleTouchVerified:false})",value->{json[0]=value;latch.countDown();});});
            if(latch.await(3,TimeUnit.SECONDS)&&json[0]!=null&&!json[0].equals("null")){String decoded=new JSONArray("["+json[0]+"]").getString(0);parsed=new JSONObject(decoded);if(parsed.optInt("buttons")>0&&parsed.optString("ready").equals("complete"))break;}Thread.sleep(150);
        }
        if(parsed==null||parsed.optInt("buttons")==0)throw new Exception("The target's own UI DOM did not initialize before timeout.");
        if(parsed.optInt("scrollWidth")>parsed.optInt("width")+2)throw new Exception("The target's own UI has horizontal overflow.");return parsed;
    }
    private static WebView findWebView(View view){if(view instanceof WebView)return (WebView)view;if(view instanceof ViewGroup){ViewGroup group=(ViewGroup)view;for(int i=0;i<group.getChildCount();i++){WebView found=findWebView(group.getChildAt(i));if(found!=null)return found;}}return null;}
    private static byte[] bytes(File file)throws Exception{if(!file.exists())return null;if(file.length()>16*1024*1024)throw new Exception("Protected data snapshot exceeds diagnostic limit.");try(InputStream in=new FileInputStream(file);ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){if(out.size()+n>16*1024*1024)throw new Exception("Protected data snapshot exceeds diagnostic limit.");out.write(b,0,n);}return out.toByteArray();}}
}
