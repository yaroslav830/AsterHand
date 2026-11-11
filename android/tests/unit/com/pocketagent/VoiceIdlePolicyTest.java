package com.pocketagent;

/** Host-JVM boundary tests: no Android runtime, microphone, clock sleeps or provider calls. */
public final class VoiceIdlePolicyTest {
    private static int checks;
    private static void check(boolean value,String message){if(!value)throw new AssertionError(message);checks++;}
    public static void main(String[] args){
        VoiceIdlePolicy p=new VoiceIdlePolicy();p.configure(0,0);p.update(true,false,0);
        check(!p.expired(1000000)&&p.remaining(1000000)==0,"disabled retains existing continuous behavior");
        p.configure(10,100);check(p.remaining(100)==10,"new timeout starts a full window");
        check(!p.expired(10099)&&p.remaining(10099)==1,"millisecond boundary before timeout");
        check(p.expired(10100)&&p.remaining(10100)==0,"expires at exact monotonic boundary");
        p.update(true,true,10100);check(!p.expired(10100)&&p.remaining(10100)==10,"real user text resets window");
        p.update(false,false,15000);check(p.paused()&&!p.expired(900000)&&p.remaining(900000)==0,"AI work pauses rather than consuming time");
        p.update(true,false,900000);check(!p.paused()&&p.remaining(900000)==10,"returning to user starts a fresh window");
        p.update(false,false,905000);p.update(true,false,920000);check(!p.expired(929999)&&p.expired(930000),"read-aloud suspension starts another full window");
        p.configure(60,1000000);check(p.remaining(1000000)==60,"changing timeout restarts current reply window");
        p.update(true,false,1001000);check(p.remaining(1001000)==59,"waiting without input includes microphone mute");
        boolean invalid=false;try{p.configure(-1,0);}catch(IllegalArgumentException expected){invalid=true;}check(invalid&&p.timeout()==60,"invalid short timeout preserves configuration");
        invalid=false;try{p.configure(3601,0);}catch(IllegalArgumentException expected){invalid=true;}check(invalid&&p.timeout()==60,"invalid long timeout preserves configuration");
        check(VoiceIdlePolicy.productTimeout(0)==5&&VoiceIdlePolicy.productTimeout(-1)==5,"product migrates disabled or invalid legacy preference to five seconds");
        check(VoiceIdlePolicy.requireProductTimeout(1)==1&&VoiceIdlePolicy.requireProductTimeout(3600)==3600,"product accepts custom boundary seconds");
        invalid=false;try{VoiceIdlePolicy.requireProductTimeout(0);}catch(IllegalArgumentException expected){invalid=true;}check(invalid,"product does not expose disabled timeout");
        p.configure(5,0);check(!p.expired(4999)&&p.expired(5000),"product five-second exact boundary");
        System.out.println("{\"fixture\":true,\"checks\":"+checks+",\"microphone_started\":false,\"provider_called\":false,\"success\":true}");
    }
}
