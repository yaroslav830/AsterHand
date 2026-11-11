// Standalone UIKit hosting setup adapted from TrollSpeed (MIT, Lessica).
// See third_party/TrollSpeed/NOTICE.md and LICENSE.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <notify.h>
#import "PCRuntimePaths.h"
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <spawn.h>
#include <poll.h>
#include <sys/wait.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/file.h>
extern int memorystatus_control(uint32_t command,int32_t pid,uint32_t flags,void *buffer,size_t size);
#include <string.h>
extern int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
extern int proc_name(int pid, void *buffer, uint32_t buffersize);
#define PROC_ALL_PIDS 1

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef void *IOHIDServiceRef;
extern void GSInitialize(void);
extern void GSEventInitialize(Boolean);
extern void GSEventPushRunLoopMode(CFStringRef);
extern void BKSDisplayServicesStart(void);
extern void UIApplicationInitialize(void);
extern void UIApplicationInstantiateSingleton(Class);
extern void *BKSHIDEventRegisterEventCallback(void (*)(void *, void *, IOHIDServiceRef, IOHIDEventRef));
extern void PCOverlayCreateControls(void);
extern UIWindow *PCOverlayWindow(void);
extern UIInterfaceOrientation PCOverlayInterfaceOrientation(void);
extern BOOL PCOverlayControlsVisible(void);
extern uint64_t IOHIDEventGetSenderID(IOHIDEventRef event);
extern void PCOverlayRecordGesture(CGPoint point,UITouchPhase phase);
extern BOOL PCOverlayAnswerFocused(void);
extern CGFloat PCOverlayKeyboardHeight(void);
extern BOOL PCOverlayPointInKeyboard(CGPoint point);
extern UIWindow *PCOverlayInputAccessoryWindowAtPoint(CGPoint point);
extern void PCOverlayPrepareScreen(void);
extern void PCOverlayFinishScreen(void);
extern void PCOverlaySetAppearance(NSInteger style);
extern char **environ;
static NSDictionary *sAppearanceProbe;
NSDictionary *PCOverlayAppearanceDiagnostic(void){return sAppearanceProbe?:@{};}

// UIKit caches the initial system style in scene-less hosts. A short-lived,
// nonvisual process reads a fresh public UIScreen trait after a system change.
// Only this helper is spawned; SpringBoard is never modified or restarted.
void PCOverlayRequestAppearance(void){
    static BOOL pending;if(pending)return;pending=YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSString *path=[NSString stringWithUTF8String:jbroot(PC_JB_EXEC("/Applications/PocketCodex.app/pocketoverlay"))];
        NSInteger style=0;int spawnError=0,readCount=0,exitCode=0;int output[2];if(pipe(output)==0){
            posix_spawn_file_actions_t actions;posix_spawn_file_actions_init(&actions);posix_spawn_file_actions_adddup2(&actions,output[1],STDOUT_FILENO);posix_spawn_file_actions_addclose(&actions,output[0]);posix_spawn_file_actions_addclose(&actions,output[1]);
            char *args[]={(char *)path.fileSystemRepresentation,"--appearance-style",NULL};pid_t child=0;int result=posix_spawn(&child,args[0],&actions,NULL,args,environ);posix_spawn_file_actions_destroy(&actions);close(output[1]);
            spawnError=result;if(result==0){struct pollfd ready={output[0],POLLIN,0};if(poll(&ready,1,2000)>0){char value[8]={0};ssize_t count=read(output[0],value,sizeof(value)-1);readCount=(int)count;if(count==2&&value[1]=='\n'&&(value[0]=='1'||value[0]=='2'))style=value[0]-'0';}
                int status=0;BOOL ended=NO;for(int i=0;i<50;i++){pid_t endedPID=waitpid(child,&status,WNOHANG);if(endedPID==child||endedPID<0){ended=YES;break;}usleep(10000);}if(!ended){kill(child,SIGKILL);waitpid(child,&status,0);style=0;}exitCode=status;
            }close(output[0]);
        }
        dispatch_async(dispatch_get_main_queue(),^{pending=NO;sAppearanceProbe=@{@"style":@(style),@"spawn_error":@(spawnError),@"bytes":@(readCount),@"exit":@(exitCode),@"updated":@(NSDate.date.timeIntervalSince1970)};PCOverlaySetAppearance(style);});
    });
}

@interface PCOverlayAXEvent : NSObject
- (CGPoint)location;
@end

@interface NSObject (PCOverlayPrivate)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)internal onlyVisibleWindows:(BOOL)visible;
- (void)_installEventRunLoopSources:(CFRunLoopRef)loop;
- (void)setEventFetcherSink:(id)sink;
- (void)_accessibilityInit;
- (void)_enqueueHIDEvent:(IOHIDEventRef)event;
- (void)__completeAndRunAsPlugin;
- (unsigned int)_contextId;
- (void)registerWindowWithContextID:(unsigned int)context atLevel:(double)level;
+ (id)representationWithHIDEvent:(IOHIDEventRef)event hidStreamIdentifier:(NSString *)identifier;
- (BOOL)isTouchDown;
- (BOOL)isMove;
- (BOOL)isLift;
- (BOOL)isInRange;
- (BOOL)isInRangeLift;
- (BOOL)isCancel;
- (id)handInfo;
- (NSArray *)paths;
- (NSInteger)pathIdentity;
- (UIEvent *)_touchesEvent;
- (void)_clearTouches;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setGestureView:(UIView *)view;
- (void)_setLocationInWindow:(CGPoint)point resetPrevious:(BOOL)reset;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTimestamp:(NSTimeInterval)time;
- (void)setTapCount:(NSUInteger)count;
- (void)_setIsTapToClick:(BOOL)value;
- (void)_setIsFirstTouchForView:(BOOL)value;
- (void)_setHidEvent:(IOHIDEventRef)event;
@end
static NSHashTable *sInputWindows;
NSArray *PCOverlayAllWindows(void){NSMutableArray *windows=[UIApplication.sharedApplication.windows mutableCopy];if([UIWindow respondsToSelector:@selector(allWindowsIncludingInternalWindows:onlyVisibleWindows:)])for(UIWindow *window in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO])if(![windows containsObject:window])[windows addObject:window];for(UIWindow *window in sInputWindows.allObjects)if(![windows containsObject:window])[windows addObject:window];return windows;}

@interface PCOverlayApplication : UIApplication
@end

static BOOL InstallEventRunLoop(id dispatcher, Class applicationClass) {
    if (!dispatcher) { NSLog(@"AsterHand overlay: dispatcher not initialized"); return NO; }
    SEL selector = sel_registerName("_installEventRunLoopSources:");
    if ([dispatcher respondsToSelector:selector]) {
        [dispatcher _installEventRunLoopSources:CFRunLoopGetMain()];
        return YES;
    }
    // UIKit hides this selector on some iOS 15/16 builds. Locate the same
    // call inside UIApplication's _run, as used by TrollSpeed's HUD runtime.
    IMP run = class_getMethodImplementation(applicationClass, sel_registerName("_run"));
    if (!run) return NO;
    uint32_t *code = (uint32_t *)(void *)run;
    for (NSUInteger i = 0; i + 2 < 0x140; i++) {
        if (code[i] != 0xaa0003e2 || (code[i + 1] & 0xff000000) != 0xaa000000) continue;
        uint32_t branch = code[i + 2];
        if ((branch & 0xfc000000) != 0x94000000) continue;
        int64_t displacement = ((int32_t)(branch << 6) >> 6) * (int64_t)4;
        uint32_t *target = (uint32_t *)((uint8_t *)&code[i + 2] + displacement);
        if ((*target & 0xff000000) != 0xb4000000) continue;
        void (*install)(id, SEL, CFRunLoopRef) = (void (*)(id, SEL, CFRunLoopRef))(void *)target;
        install(dispatcher, selector, CFRunLoopGetMain());
        return YES;
    }
    // Newer UIKit builds can use an objc_direct two-argument entry.
    // Verify the argument setup, nil guard and store into the dispatcher's
    // _runLoop ivar before calling it. The older entry above takes a selector.
    Ivar runLoopIvar=class_getInstanceVariable([dispatcher class],"_runLoop");
    ptrdiff_t runLoopOffset=runLoopIvar?ivar_getOffset(runLoopIvar):-1;
    if(runLoopOffset>=0)for(NSUInteger i=0;i+2<0x140;i++){
        if(code[i]!=0xaa0003e1||(code[i+1]&~0x001f0000u)!=0xaa0003e0||(code[i+2]&0xfc000000)!=0x94000000)continue;
        int64_t displacement=((int32_t)(code[i+2]<<6)>>6)*(int64_t)4;uint32_t *target=(uint32_t *)((uint8_t *)&code[i+2]+displacement);
        if((target[0]&0xff00001f)!=0xb4000000)continue;
        BOOL storesRunLoop=NO;for(NSUInteger j=1;j<12;j++)if((target[j]&0xffc003ff)==0xf9000001&&((target[j]>>10)&0xfff)*8==runLoopOffset)storesRunLoop=YES;
        if(!storesRunLoop)continue;
        void (*install)(id,CFRunLoopRef)=(void (*)(id,CFRunLoopRef))(void *)target;install(dispatcher,CFRunLoopGetMain());
        NSLog(@"AsterHand overlay: installed validated direct event run loop");return YES;
    }
    return NO;
}

@implementation PCOverlayApplication
- (UIInterfaceOrientation)interfaceOrientation {return PCOverlayInterfaceOrientation();}
- (UIInterfaceOrientation)statusBarOrientation {return PCOverlayInterfaceOrientation();}
- (instancetype)init {
    if ((self = [super init])) {
        @try {
            id dispatcher = [self valueForKey:@"eventDispatcher"];
            if (!InstallEventRunLoop(dispatcher, self.class)) {
                NSLog(@"AsterHand overlay: event run loop is unavailable on this iOS build");
                exit(3);
            }
            id fetcher = [NSClassFromString(@"UIEventFetcher") new];
            [dispatcher setValue:fetcher forKey:@"eventFetcher"];
            if ([fetcher respondsToSelector:@selector(setEventFetcherSink:)]) [fetcher setEventFetcherSink:dispatcher];
            else [fetcher setValue:dispatcher forKey:@"eventFetcherSink"];
            [self setValue:fetcher forKey:@"eventFetcher"];
        } @catch (NSException *exception) { NSLog(@"AsterHand overlay event setup: %@", exception.reason); }
    }
    return self;
}
@end

@interface PCOverlayDelegate : NSObject <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) id host;
@property(nonatomic,strong) NSMutableDictionary *inputHosts;
@property(nonatomic,strong) NSHashTable *forcedInputWindows;
@property(nonatomic) BOOL hostingInput;
- (void)rehostWindow;
@end
@implementation PCOverlayDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    PCOverlayCreateControls();
    self.window = PCOverlayWindow();
    [self rehostWindow];
    self.inputHosts=[NSMutableDictionary new];[NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(hostInputWindows) userInfo:nil repeats:YES];
    self.forcedInputWindows=[NSHashTable weakObjectsHashTable];
    sInputWindows=[NSHashTable weakObjectsHashTable];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(inputWindowVisible:) name:UIWindowDidBecomeVisibleNotification object:nil];
    NSLog(@"AsterHand standalone overlay ready, uid=%d", getuid());
    return YES;
}
- (void)rehostWindow {
    if (!self.window) return;
    if(self.host)return; // One registration per context; repeated hosts can leave stale surfaces.
    self.host = [NSClassFromString(@"SBSAccessibilityWindowHostingController") new];
    if (![self.host respondsToSelector:@selector(registerWindowWithContextID:atLevel:)]) {
        NSLog(@"AsterHand overlay: window hosting unavailable");
        exit(2);
    }
    [self.host registerWindowWithContextID:[self.window _contextId] atLevel:self.window.windowLevel];
}
- (void)hostInputWindows {
    if(self.hostingInput)return;self.hostingInput=YES;
    @try {
        if(!PCOverlayAnswerFocused()){for(UIWindow *window in self.forcedInputWindows.allObjects)window.hidden=YES;[self.forcedInputWindows removeAllObjects];return;}
        for(UIWindow *window in PCOverlayAllWindows()){NSString *name=NSStringFromClass(window.class);if(window==self.window||(![name containsString:@"Keyboard"]&&![name containsString:@"TextEffects"]))continue;
            if(window.hidden&&[name containsString:@"RemoteKeyboard"]&&PCOverlayKeyboardHeight()>0){[self.forcedInputWindows addObject:window];window.hidden=NO;}
            if(window.hidden)continue;unsigned int context=[window _contextId];if(!context||self.inputHosts[@(context)])continue;id host=[NSClassFromString(@"SBSAccessibilityWindowHostingController") new];[host registerWindowWithContextID:context atLevel:self.window.windowLevel+1];self.inputHosts[@(context)]=host;
        }
    } @catch(NSException *exception){NSLog(@"AsterHand input host: %@",exception.name);}
    @finally {self.hostingInput=NO;}
}
- (void)inputWindowVisible:(NSNotification *)note {if([note.object isKindOfClass:UIWindow.class]){[sInputWindows addObject:note.object];[self hostInputWindows];}}
@end

void PCOverlayRehostWindow(void) {
    PCOverlayDelegate *delegate = (PCOverlayDelegate *)UIApplication.sharedApplication.delegate;
    [delegate rehostWindow];
}

static pid_t SpringBoardPID(void) {
    int size = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (size <= 0 || size > 4 * 1024 * 1024) return 0;
    NSMutableData *storage = [NSMutableData dataWithLength:(NSUInteger)size + 4096];
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, storage.mutableBytes, (int)storage.length);
    pid_t *pids = storage.mutableBytes;
    for (int i = 0; i < bytes / (int)sizeof(pid_t); i++) {
        char name[64] = {0};
        if (pids[i] > 1 && proc_name(pids[i], name, sizeof(name)) > 0 && strcmp(name, "SpringBoard") == 0) return pids[i];
    }
    return 0;
}

static void WatchWindowHost(void) {
    // The HUD process can outlive SpringBoard while its XPC window host cannot.
    // A fresh process also renews the event-fetcher/HID connections. launchd
    // restarts only this helper; never inject into or restart SpringBoard here.
    __block pid_t initial = SpringBoardPID();
    __block pid_t candidate = 0;
    __block NSUInteger stable = 0;
    [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
        pid_t current = SpringBoardPID();
        if (!current) { stable = 0; return; }
        if (!initial) { initial = current; return; }
        if (current == initial) { candidate = 0; stable = 0; return; }
        if (candidate != current) { candidate = current; stable = 1; return; }
        if (++stable >= 2) {
            NSLog(@"AsterHand overlay: SpringBoard changed %d -> %d; renewing standalone host", initial, current);
            _exit(0);
        }
    }];
}

static UITouch *sTouch;
static NSInteger sPointer;
void PCOverlayCancelTouch(void) {
    if (sTouch) {
        [sTouch setPhase:UITouchPhaseCancelled];
        [sTouch setTimestamp:NSProcessInfo.processInfo.systemUptime];
        UIEvent *event = [UIApplication.sharedApplication _touchesEvent];
        [event _clearTouches];
        [event _addTouch:sTouch forDelayedDelivery:NO];
        [UIApplication.sharedApplication sendEvent:event];
        [event _clearTouches];
    }
    sTouch = nil;
    sPointer = 0;
}
static void HandleTouch(IOHIDEventRef event) {
    UIWindow *window = PCOverlayWindow();
    if (!window || window.hidden || !PCOverlayControlsVisible()) { PCOverlayCancelTouch(); return; }
    static Class representationClass;
    if (!representationClass) {
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/AccessibilityUtilities.framework"] load];
        representationClass = NSClassFromString(@"AXEventRepresentation");
    }
    PCOverlayAXEvent *rep = [representationClass representationWithHIDEvent:event hidStreamIdentifier:@"UIApplicationEvents"];
    NSInteger pointer = [[[[rep handInfo] paths] firstObject] pathIdentity];
    if (pointer <= 0) return;
    CGPoint point = [rep location],physicalPoint=point;UIWindow *overlay=window;
    if(PCOverlayAnswerFocused()){UIWindow *accessory=PCOverlayInputAccessoryWindowAtPoint(point);if(accessory)window=accessory;else if(PCOverlayPointInKeyboard(point))for(UIWindow *candidate in [PCOverlayAllWindows() reverseObjectEnumerator]){NSString *name=NSStringFromClass(candidate.class);if(candidate!=window&&!candidate.hidden&&([name containsString:@"Keyboard"]||[name containsString:@"TextEffects"])) {window=candidate;break;}}}
    if(window!=overlay)point=[window convertPoint:physicalPoint fromWindow:overlay];
    UITouchPhase phase;
    if ([rep isTouchDown]) phase = UITouchPhaseBegan;
    else if ([rep isMove]) phase = UITouchPhaseMoved;
    else if ([rep isCancel]) phase = UITouchPhaseCancelled;
    else if ([rep isLift] || [rep isInRange] || [rep isInRangeLift]) phase = UITouchPhaseEnded;
    else return;
    if(IOHIDEventGetSenderID(event)==0x8000000817319371ULL)PCOverlayRecordGesture(physicalPoint,phase);
    // EventCallback feeds iOS 14's native queue exactly once. AX replay would
    // create a second stream and cancel UIButton taps while pans still work.
    if(![NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){15,0,0}])return;
    if (phase == UITouchPhaseBegan) {
        // A lost lift (for example while hiding the controls) must not block
        // every subsequent tap. A fresh down always starts a new gesture.
        PCOverlayCancelTouch();
        UIView *view = [window hitTest:point withEvent:nil];
        if (!view) return;
        sPointer = pointer;
        sTouch = [UITouch new];
        [sTouch setWindow:window];
        [sTouch setView:view];
        [sTouch _setLocationInWindow:point resetPrevious:YES];
        [sTouch setTapCount:1];
        if ([sTouch respondsToSelector:@selector(setGestureView:)]) [sTouch setGestureView:view];
        if ([sTouch respondsToSelector:@selector(_setIsTapToClick:)]) [sTouch _setIsTapToClick:NO];
        if ([sTouch respondsToSelector:@selector(_setIsFirstTouchForView:)]) [sTouch _setIsFirstTouchForView:YES];
    } else {
        if (!sTouch || sPointer != pointer) return;
        [sTouch _setLocationInWindow:point resetPrevious:NO];
    }
    [sTouch setTimestamp:NSProcessInfo.processInfo.systemUptime];
    [sTouch setPhase:phase];
    [sTouch _setHidEvent:event];
    UIEvent *uiEvent = [UIApplication.sharedApplication _touchesEvent];
    [uiEvent _clearTouches];
    [uiEvent _addTouch:sTouch forDelayedDelivery:NO];
    [UIApplication.sharedApplication sendEvent:uiEvent];
    if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) {
        [uiEvent _clearTouches];
        sTouch = nil; sPointer = 0;
    }
}

static void EventCallback(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event) {
    if (!event) return;
    CFRetain(event);
    dispatch_async(dispatch_get_main_queue(), ^{@try{
        // iOS 14's hosted UIKit surface consumes HID through its event queue.
        // It has no AX replay below; enqueue exactly once for native buttons/pans.
        if(![NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){15,0,0}]){
            UIApplication *app=UIApplication.sharedApplication;if([app respondsToSelector:@selector(_enqueueHIDEvent:)])[app _enqueueHIDEvent:event];
        }
        HandleTouch(event);
    }@catch(NSException *exception){NSLog(@"AsterHand overlay touch error: %@ %@",exception.name,exception.reason);sTouch=nil;sPointer=0;}@finally{CFRelease(event);}});
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if(argc==2&&strcmp(argv[1],"--appearance-style")==0){NSInteger style=UIScreen.mainScreen.traitCollection.userInterfaceStyle;printf("%ld\n",(long)style);return style==1||style==2?0:1;}
        if (getuid() != 0) { fprintf(stderr, "Overlay must run as root\n"); return 1; }
        // Keep one hosted surface even if a second launcher starts the helper.
        // The inode remains in place; the kernel releases the lock on exit.
        const char *lockPath=jbroot(PC_PRIVILEGED_DIRECTORY "/asterhand-overlay.lock");
        int instanceLock=open(lockPath,O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0600);struct stat lockStat;
        if(instanceLock<0||fstat(instanceLock,&lockStat)<0||!S_ISREG(lockStat.st_mode)||lockStat.st_uid!=0||lockStat.st_nlink!=1){fprintf(stderr,"Overlay instance lock unavailable\n");return 4;}
        if(flock(instanceLock,LOCK_EX|LOCK_NB)<0){int error=errno;close(instanceLock);return error==EWOULDBLOCK?0:4;}
        ftruncate(instanceLock,0);dprintf(instanceLock,"%d\n",getpid());
        // UIKit and its system keyboard exceed launchd's small daemon default
        // on iOS 17. Bound only this helper; keep ordinary jetsam priority.
        struct {int32_t active;uint32_t activeFlags;int32_t inactive;uint32_t inactiveFlags;} limits={0};
        int readLimit=memorystatus_control(8,getpid(),0,&limits,sizeof(limits));
        if(readLimit<0||limits.active<256||limits.inactive<256){
            int result=memorystatus_control(6,getpid(),256,NULL,0);NSLog(@"AsterHand overlay memory budget: previous=%d/%d MB, requested=256 MB, result=%d errno=%d",limits.active,limits.inactive,result,result<0?errno:0);
        }
        [UIScreen initialize];
        CFRunLoopGetCurrent();
        GSInitialize();
        BKSDisplayServicesStart();
        UIApplicationInitialize();
        UIApplicationInstantiateSingleton(PCOverlayApplication.class);
        static PCOverlayDelegate *delegate;
        delegate = [PCOverlayDelegate new];
        UIApplication.sharedApplication.delegate = delegate;
        [UIApplication.sharedApplication _accessibilityInit];
        BKSHIDEventRegisterEventCallback(EventCallback);
        int prepareToken;notify_register_dispatch("local.agentgo.overlay.prepare-screen",&prepareToken,dispatch_get_main_queue(),^(int token){PCOverlayPrepareScreen();});
        int finishToken;notify_register_dispatch("local.agentgo.overlay.finish-screen",&finishToken,dispatch_get_main_queue(),^(int token){PCOverlayFinishScreen();});
        int appearanceToken,modeToken;notify_register_dispatch("com.apple.darkmode.changed",&appearanceToken,dispatch_get_main_queue(),^(int token){PCOverlayRequestAppearance();});notify_register_dispatch("com.apple.uikitservices.userInterfaceStyleMode",&modeToken,dispatch_get_main_queue(),^(int token){PCOverlayRequestAppearance();});
        // iOS 14's native event queue is already installed by UIKit. Registering
        // its Purple port again aborts in GSRegisterPurpleNamedPerPIDPort.
        if([NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){15,0,0}]){
            GSEventInitialize(false);GSEventPushRunLoopMode(kCFRunLoopDefaultMode);
        }
        [UIApplication.sharedApplication __completeAndRunAsPlugin];
        WatchWindowHost();
        CFRunLoopRun();
    }
    return 0;
}
