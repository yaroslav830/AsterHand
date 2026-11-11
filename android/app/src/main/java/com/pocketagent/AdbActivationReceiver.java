package com.pocketagent;

import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.Build;
import android.util.Base64;
import org.json.JSONObject;
import java.nio.charset.StandardCharsets;

/** Authorized USB-ADB activation only; manifest signature permission DUMP is mandatory. */
public final class AdbActivationReceiver extends BroadcastReceiver {
    public static final String ACTION="com.pocketagent.ACTIVATE_ADB";
    private static final Object activationLock=new Object();
    @Override public void onReceive(Context context,Intent intent){
        if(!isOrderedBroadcast()||intent==null||!ACTION.equals(intent.getAction()))return;
        String nonce=intent.getStringExtra("nonce"),operation=intent.getStringExtra("operation");
        if(nonce==null||!nonce.matches("[a-f0-9]{32}")||!("activate".equals(operation)||"stop".equals(operation))){setResultCode(-1);setResultData("ASTERHAND_ADB_ERROR:invalid_request");return;}
        try{
            String permission=context.getPackageManager().getReceiverInfo(new ComponentName(context,AdbActivationReceiver.class),0).permission;
            if(!"android.permission.DUMP".equals(permission))throw new SecurityException("Missing sender permission gate");
            if(Build.VERSION.SDK_INT>=34){int sender=getSentFromUid();if(sender!=-1&&sender!=0&&sender!=2000)throw new SecurityException("Unexpected sender");}
        }catch(Exception denied){setResultCode(-1);setResultData("ASTERHAND_ADB_ERROR:sender_not_authorized");return;}
        PendingResult pending=goAsync();Context app=context.getApplicationContext()==null?context:context.getApplicationContext();
        new Thread(()->{
            synchronized(activationLock){
                try{
                    PrivilegeManager manager=new PrivilegeManager(app);JSONObject config=manager.bridgeConfiguration();boolean stopped=stopExisting(config);
                    if(operation.equals("stop")){pending.setResultCode(1);pending.setResultData("ASTERHAND_ADB_STOPPED:"+nonce+":"+(stopped?"stopped":"not_running"));}
                    else{
                        config=manager.relocateBridgePort();config.put("apk",app.getApplicationInfo().sourceDir);
                        String encoded=Base64.encodeToString(config.toString().getBytes(StandardCharsets.UTF_8),Base64.URL_SAFE|Base64.NO_WRAP|Base64.NO_PADDING);
                        pending.setResultCode(1);pending.setResultData("ASTERHAND_ADB_V1:"+nonce+":"+encoded);
                    }
                }catch(Exception failure){pending.setResultCode(-1);pending.setResultData("ASTERHAND_ADB_ERROR:activation_failed");}
                finally{pending.finish();}
            }
        },"AsterHand-ADB-activation").start();
    }
    private static boolean stopExisting(JSONObject config)throws Exception{
        try(BridgeTransport.Client channel=BridgeTransport.connect(config)){
            channel.socket.setSoTimeout(5000);channel.send(new JSONObject().put("kind","shutdown"));JSONObject result=channel.readResult();
            if(result.optInt("uid")!=2000||!result.optBoolean("stopped"))throw new SecurityException("Bridge shutdown not acknowledged");return true;
        }catch(java.net.ConnectException absent){return false;}
    }
}
