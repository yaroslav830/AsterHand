package com.pocketagent;
import android.content.*;
/** Restores only the user's opt-in passive connection service, never a microphone or executable task. */
public final class AsterBootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context,Intent intent){String a=intent==null?"":intent.getAction();if(!Intent.ACTION_BOOT_COMPLETED.equals(a)&&!Intent.ACTION_MY_PACKAGE_REPLACED.equals(a))return;try{if(context.getSharedPreferences("MainActivity",0).getBoolean("background",true))AsterRuntime.configure(context);}catch(RuntimeException ignored){}}
}
