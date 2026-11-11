#import "PCHaptics.h"
#import <CoreHaptics/CoreHaptics.h>
#import <dlfcn.h>

static NSDictionary *lastEvent;
static NSUInteger eventCount;
static NSTimeInterval previous,previousVibrate,coreRetry;
static BOOL hostHint;
static CHHapticEngine *engine;
static id<CHHapticPatternPlayer> player;
static NSString *coreFailure=@"";
static NSObject *EventMonitor(void){static NSObject *monitor;static dispatch_once_t once;dispatch_once(&once,^{monitor=[NSObject new];});return monitor;}

NSString *PCHapticNormalizeStyle(NSString *style){
    NSString *s=[style isKindOfClass:NSString.class]?style.lowercaseString:@"system";
    if([s isEqual:@"firm"])return @"strong";
    if([s isEqual:@"selection"])return @"crisp";
    return [@[@"system",@"soft",@"crisp",@"strong"] containsObject:s]?s:@"system";
}
NSArray<NSDictionary *> *PCHapticStyles(void){return @[@{@"id":@"system",@"title":@"跟随操作",@"subtitle":@"选择、执行、完成与错误使用不同反馈"},@{@"id":@"soft",@"title":@"轻柔",@"subtitle":@"柔和的触感"},@{@"id":@"crisp",@"title":@"清脆",@"subtitle":@"短促、明确的触感"},@{@"id":@"strong",@"title":@"强烈",@"subtitle":@"更明显的触感"}];}
static NSString *Kind(NSString *kind){
    NSString *s=[kind isKindOfClass:NSString.class]?kind.lowercaseString:@"select";
    if([@[@"selection",@"toggle",@"select"] containsObject:s])return @"select";
    if([@[@"success",@"connect",@"complete",@"completed"] containsObject:s])return @"complete";
    if([@[@"warning",@"question",@"disconnect",@"delete"] containsObject:s])return @"warning";
    if([@[@"start",@"resume",@"send"] containsObject:s])return @"start";
    return [@[@"stop",@"pause",@"error"] containsObject:s]?s:@"tap";
}
static void Record(NSString *kind,NSString *style,NSString *backend,BOOL accepted,NSString *status){
    @synchronized(EventMonitor()){lastEvent=@{@"kind":kind,@"style":style,@"backend":backend,@"accepted":@(accepted),@"status":status?:@"",@"count":@(++eventCount),@"hardware_verified":@NO,@"core_error":coreFailure?:@"",@"updated":@(NSDate.date.timeIntervalSince1970)};}
}
NSDictionary *PCHapticLastEvent(void){@synchronized(EventMonitor()){return lastEvent?:@{};}}
void PCHapticSetStandaloneHost(BOOL standalone){hostHint=standalone;}
static BOOL Standalone(void){return hostHint||[NSProcessInfo.processInfo.processName.lowercaseString isEqual:@"pocketoverlay"]||[NSBundle.mainBundle.executablePath.lastPathComponent.lowercaseString isEqual:@"pocketoverlay"];}
static NSDictionary *Transient(double time,double intensity,double sharpness){return @{@"Event":@{@"Time":@(time),@"EventType":@"HapticTransient",@"EventParameters":@[@{@"ParameterID":@"HapticIntensity",@"ParameterValue":@(intensity)},@{@"ParameterID":@"HapticSharpness",@"ParameterValue":@(sharpness)}]}};}
static NSDictionary *Pattern(NSString *kind,NSString *style){
    double strength=.52,sharp=.55;
    if([style isEqual:@"soft"]){strength=.35;sharp=.12;}
    else if([style isEqual:@"crisp"]){strength=.65;sharp=.95;}
    else if([style isEqual:@"strong"]){strength=1;sharp=.70;}
    else if([kind isEqual:@"select"]){strength=.35;sharp=.65;}
    else if([kind isEqual:@"stop"]||[kind isEqual:@"error"]){strength=.9;sharp=.75;}
    else if([kind isEqual:@"start"]||[kind isEqual:@"pause"]){strength=.65;sharp=.55;}
    NSMutableArray *events=[NSMutableArray arrayWithObject:Transient(0,strength,sharp)];
    if([style isEqual:@"system"]){if([kind isEqual:@"complete"]||[kind isEqual:@"warning"])[events addObject:Transient(.09,strength,.8)];else if([kind isEqual:@"error"]){[events addObject:Transient(.08,strength,sharp)];[events addObject:Transient(.17,strength,sharp)];}}
    return @{@"Version":@1,@"Pattern":events};
}
static BOOL Core(NSString *kind,NSString *style){
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(now<coreRetry)return NO;
    static void *framework;static dispatch_once_t once;dispatch_once(&once,^{framework=dlopen("/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics",RTLD_LAZY|RTLD_LOCAL);});
    NSError *error=nil;Class engineClass=NSClassFromString(@"CHHapticEngine"),patternClass=NSClassFromString(@"CHHapticPattern");
    @try{
        if(!framework||!engineClass||!patternClass||![[(id)engineClass capabilitiesForHardware] supportsHaptics]){coreFailure=@"unsupported";coreRetry=now+10;return NO;}
        if(!engine){engine=[[(id)engineClass alloc] initAndReturnError:&error];if(engine){engine.playsHapticsOnly=YES;engine.isMutedForAudio=YES;engine.autoShutdownEnabled=YES;engine.resetHandler=^{dispatch_async(dispatch_get_main_queue(),^{player=nil;});};engine.stoppedHandler=^(CHHapticEngineStoppedReason reason){dispatch_async(dispatch_get_main_queue(),^{player=nil;coreFailure=[NSString stringWithFormat:@"stopped:%ld",(long)reason];});};}}
        if(!engine||![engine startAndReturnError:&error]){coreFailure=error?[NSString stringWithFormat:@"%@:%ld",error.domain,(long)error.code]:@"engine_unavailable";coreRetry=now+2;return NO;}
        CHHapticPattern *pattern=[[(id)patternClass alloc] initWithDictionary:Pattern(kind,style) error:&error];
        id<CHHapticPatternPlayer> next=pattern?[engine createPlayerWithPattern:pattern error:&error]:nil;
        if(!next){coreFailure=error?[NSString stringWithFormat:@"%@:%ld",error.domain,(long)error.code]:@"pattern_unavailable";coreRetry=now+2;return NO;}
        if(player)[player cancelAndReturnError:nil];
        if(![next startAtTime:0 error:&error]){coreFailure=error?[NSString stringWithFormat:@"%@:%ld",error.domain,(long)error.code]:@"playback_rejected";coreRetry=now+2;return NO;}
        player=next;coreFailure=@"";return YES;
    }@catch(NSException *exception){coreFailure=@"engine_exception";coreRetry=now+2;return NO;}
}
static BOOL Vibrate(void){
    // Public fallback only. One system vibration, never combined with an accepted Core/UIKit request.
    static void *framework;static void (*play)(UInt32);static dispatch_once_t once;
    dispatch_once(&once,^{framework=dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",RTLD_LAZY|RTLD_LOCAL);if(framework)play=(void(*)(UInt32))dlsym(framework,"AudioServicesPlaySystemSound");});
    if(!play)return NO;NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(previousVibrate&&now-previousVibrate<.65)return NO;
    previousVibrate=now;play(0x00000fff);return YES; // Public kSystemSoundID_Vibrate; no private sound IDs.
}
static void UIKitFeedback(NSString *kind,NSString *style){
    // Keep generators alive. Scene-less hosts use the explicit Core/AudioServices path instead.
    if([style isEqual:@"system"]&&[@[@"complete",@"warning",@"error"] containsObject:kind]){static UINotificationFeedbackGenerator *n;if(!n)n=[UINotificationFeedbackGenerator new];[n prepare];[n notificationOccurred:[kind isEqual:@"complete"]?UINotificationFeedbackTypeSuccess:[kind isEqual:@"error"]?UINotificationFeedbackTypeError:UINotificationFeedbackTypeWarning];}
    else if([style isEqual:@"system"]&&[kind isEqual:@"select"]){static UISelectionFeedbackGenerator *s;if(!s)s=[UISelectionFeedbackGenerator new];[s prepare];[s selectionChanged];}
    else{UIImpactFeedbackStyle impact=[style isEqual:@"soft"]?UIImpactFeedbackStyleSoft:[style isEqual:@"crisp"]?UIImpactFeedbackStyleRigid:[style isEqual:@"strong"]||[kind isEqual:@"stop"]?UIImpactFeedbackStyleHeavy:[@[@"start",@"pause"] containsObject:kind]?UIImpactFeedbackStyleMedium:UIImpactFeedbackStyleLight;static NSMutableDictionary *generators;if(!generators)generators=[NSMutableDictionary new];UIImpactFeedbackGenerator *g=generators[@(impact)];if(!g){g=[[UIImpactFeedbackGenerator alloc] initWithStyle:impact];generators[@(impact)]=g;}[g prepare];[g impactOccurred];}
}
void PCHapticWithStyle(NSString *kind,NSString *style){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{PCHapticWithStyle(kind,style);});return;}
    style=PCHapticNormalizeStyle(style);kind=Kind(kind);NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if(previous&&now-previous<.045){Record(kind,style,@"none",NO,@"throttled");return;}previous=now;
    if(player){[player cancelAndReturnError:nil];player=nil;}
    if(!Standalone()&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive){UIKitFeedback(kind,style);Record(kind,style,@"uikit",YES,@"requested");return;}
    if(Core(kind,style)){Record(kind,style,@"core_haptics",YES,@"requested");return;}
    BOOL requested=Vibrate();Record(kind,style,requested?@"system_vibrate":@"none",requested,requested?@"style_degraded":@"unavailable_or_throttled");
}
void PCHaptic(NSString *kind){NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;NSString *saved=[defaults stringForKey:@"hapticStyle"],*style=PCHapticNormalizeStyle(saved);if(![saved isEqual:style])[defaults setObject:style forKey:@"hapticStyle"];PCHapticWithStyle(kind,style);}
