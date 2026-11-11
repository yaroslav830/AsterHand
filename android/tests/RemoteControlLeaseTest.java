package com.pocketagent;

import java.util.*;
import java.util.concurrent.TimeUnit;

/** Production lease registry with a deterministic monotonic clock; no device APIs. */
public final class RemoteControlLeaseTest {
    private static int checks;
    private static void check(boolean value,String label){if(!value)throw new AssertionError(label);checks++;}
    private static long second(long value){return TimeUnit.SECONDS.toNanos(value);}
    public static void main(String[] args)throws Exception{
        check(RemoteControlHub.leaseMilliseconds(null)==6000,"default six-second action lease");
        check(RemoteControlHub.leaseMilliseconds(-10)==6000,"minimum six seconds");
        check(RemoteControlHub.leaseMilliseconds(240)==120000,"maximum 120 seconds");
        check(RemoteControlHub.leaseMilliseconds(45.5)==45500,"fractional bounded duration");
        for(Object bad:new Object[]{"120",Double.NaN,Double.POSITIVE_INFINITY}){boolean refused=false;try{RemoteControlHub.leaseMilliseconds(bad);}catch(Exception expected){refused=true;}check(refused,"non-number or non-finite refused");}
        Set<String> allowed=new HashSet<>(Arrays.asList("one","two"));
        RemoteControlHub.LeaseAuthority authority=allowed::contains;
        RemoteControlHub.ActorLeases ai=new RemoteControlHub.ActorLeases(),manual=new RemoteControlHub.ActorLeases();
        ai.begin("one",6000,0);check(ai.any(0,authority),"AI lease is active");
        check(!manual.any(0,authority),"AI does not create manual control");
        manual.begin("one",2000,0);check(manual.any(0,authority)&&ai.any(0,authority),"two independent indicators can coexist");
        ai.end("one");check(!ai.any(0,authority)&&manual.any(0,authority),"AI end leaves manual control independent");
        ai.begin("one",6000,0);ai.begin("two",6000,0);ai.end("one");check(ai.any(0,authority),"ending one owner does not end another");
        allowed.remove("two");check(!ai.any(0,authority),"revocation immediately prunes owner lease");
        allowed.add("two");check(!ai.any(0,authority),"regrant does not resurrect a revoked lease");
        ai.begin("one",6000,0);check(ai.any(second(5),authority),"lease alive before deadline");
        check(!ai.any(second(6),authority),"lease expires at exact monotonic deadline");
        ai.begin("one",120000,0);ai.begin("one",6000,second(1));check(ai.any(second(119),authority),"screen action does not shorten an explicit lease");
        check(!ai.any(second(120),authority),"renewal remains bounded");
        ai.begin("one",6000,0);check(!ai.any(0,owner->false),"screen permission removal prunes active state");
        check(!ai.any(0,authority),"reenabling permission does not resurrect old state");
        ai.begin("one",6000,0);ai.clear();check(!ai.any(0,authority),"receiver stop clears all leases");
        boolean refused=false;try{ai.begin("",6000,0);}catch(IllegalArgumentException expected){refused=true;}check(refused,"empty owner refused");
        System.out.println("Remote actor lease fixtures passed: "+checks+" (no screen/device actions)");
    }
}
