#import <UIKit/UIKit.h>
#import "PCViewController.h"
#import "PCSelfTest.h"
#import "PCSupport.h"
#import "PCRemote.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <grp.h>
#include <objc/runtime.h>
#import "PCRoot.h"
#import "PCScreen.h"
#import "PCPlatform.h"
#import "PCControl.h"
#import "PCPairing.h"
#import "PCPersistentAgent.h"
#import "PCMemoryBudget.h"
#import "PCNotifications.h"
#import "PCDiscovery.h"
#import "PCTheme.h"
#import "PCNetworkPermission.h"
#import "PCVoice.h"
#import <UserNotifications/UserNotifications.h>

@interface PCAppDelegate : UIResponder <UIApplicationDelegate,UNUserNotificationCenterDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) PCViewController *controller;
@property(nonatomic, strong) NSTimer *remoteConsentTimer;
@end
@implementation PCAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[PCThemeWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    [self syncRootPreference];
    self.controller = [PCViewController new];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:self.controller];
    [self.window makeKeyAndVisible];
    PCNotificationCenter().delegate=self;
    self.remoteConsentTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(checkRemoteConsent) userInfo:nil repeats:YES];
    NSURL *launchURL=options[UIApplicationLaunchOptionsURLKey];if([launchURL isKindOfClass:NSURL.class]&&[launchURL.host.lowercaseString isEqual:@"remote-consent"]) [self openRemoteConsent];
    if([launchURL isKindOfClass:NSURL.class]&&[launchURL.host.lowercaseString isEqual:@"network-permission"])[(UINavigationController *)self.window.rootViewController pushViewController:[[PCNetworkPermissionController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:NO];
    if([launchURL isKindOfClass:NSURL.class]&&PCVoiceActionValid(launchURL.host.lowercaseString)&&[@[@"pocketagent",@"asterhand"] containsObject:launchURL.scheme.lowercaseString])[self.controller performVoiceAction:launchURL.host.lowercaseString];
    if([launchURL isKindOfClass:NSURL.class]&&[launchURL.host.lowercaseString isEqual:@"floating-voice"])for(NSURLQueryItem *item in [NSURLComponents componentsWithURL:launchURL resolvingAgainstBaseURL:NO].queryItems)if([item.name isEqual:@"request"])[self.controller performFloatingVoiceRequest:item.value];
    return YES;
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    if (![@[@"pocketagent",@"asterhand"] containsObject:url.scheme.lowercaseString]) return NO;
    if([url.host.lowercaseString isEqual:@"floating-voice"]){for(NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems)if([item.name isEqual:@"request"]&&PCVoiceFloatingLaunchValid(item.value)){[self.controller performFloatingVoiceRequest:item.value];return YES;}return NO;}
    if(PCVoiceActionValid(url.host.lowercaseString)){[self.controller performVoiceAction:url.host.lowercaseString];return YES;}
    if([url.host.lowercaseString isEqual:@"network-permission"]){UINavigationController *nav=(UINavigationController *)self.window.rootViewController;[nav dismissViewControllerAnimated:NO completion:nil];[nav pushViewController:[[PCNetworkPermissionController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];return YES;}
    if([url.host.lowercaseString isEqual:@"open"]){UINavigationController *nav=(UINavigationController *)self.window.rootViewController;[nav dismissViewControllerAnimated:NO completion:nil];[nav popToRootViewControllerAnimated:NO];return YES;}
    if(![url.host.lowercaseString isEqual:@"remote-consent"])return NO;
    [self openRemoteConsent];
    return YES;
}
- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)activity restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> *))restorationHandler {
    NSString *prefix=@"local.asterhand.shortcut.";if(![activity.activityType hasPrefix:prefix])return NO;
    NSString *action=[activity.activityType substringFromIndex:prefix.length];if(!PCVoiceActionValid(action))return NO;
    [self.controller performVoiceAction:action];return YES;
}
- (void)openRemoteConsent {
    dispatch_async(dispatch_get_main_queue(), ^{
        UINavigationController *nav = (UINavigationController *)self.window.rootViewController;
        if (![nav.topViewController isKindOfClass:PCRemoteController.class])
            [nav pushViewController:[PCRemoteController new] animated:NO];
    });
}
- (void)applicationDidBecomeActive:(UIApplication *)application { [self checkRemoteConsent]; PCSyncApplicationIcon(self.window); }
- (void)syncRootPreference {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        for (NSInteger attempt = 0; attempt < 3; attempt++) {
            BOOL enabled = [NSUserDefaults.standardUserDefaults boolForKey:@"rootEnabled"];
            NSDictionary *result = PCSendRootRequest(@{@"action": @"set_enabled", @"enabled": @(enabled)}, 3);
            if (!result[@"error"] && [result[@"enabled"] isEqual:@(enabled)]) return;
            sleep(1);
        }
    });
}
- (void)checkRemoteConsent {
    PCPairPromptIfNeeded(self.window.rootViewController);
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || ![PCRemote.shared hasPendingConsent]) return;
    [self openRemoteConsent];
}
- (void)applicationDidEnterBackground:(UIApplication *)application { [self.controller stopForBackground]; }
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completion {completion([notification.request.identifier isEqual:@"agentgo-notification-test"]?UNNotificationPresentationOptionBanner|UNNotificationPresentationOptionList|UNNotificationPresentationOptionSound:UNNotificationPresentationOptionNone);}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults registerDefaults:@{@"overlayEnabled":@YES,@"hapticStyle":@"system"}];
        if(argc==2&&strcmp(argv[1],"--voice-capabilities")==0){puts(PCJSON(PCVoiceCapabilities()).UTF8String);return 0;}
        if(argc==2&&strcmp(argv[1],"--display-geometry")==0){NSMutableDictionary *report=[NSMutableDictionary new];id configuration=nil,exclusion=nil,utilities=nil;@try{configuration=[UIScreen.mainScreen valueForKey:@"displayConfiguration"];exclusion=[UIScreen.mainScreen valueForKey:@"_exclusionArea"];utilities=[UIScreen.mainScreen valueForKey:@"_boundingPathUtilities"];id rect=[exclusion valueForKey:@"rect"];if([rect isKindOfClass:NSValue.class])report[@"exclusion_rect"]=NSStringFromCGRect([rect CGRectValue]);}@catch(NSException *ignored){}report[@"exclusion_class"]=exclusion?NSStringFromClass([exclusion class]):@"none";report[@"utilities_class"]=utilities?NSStringFromClass([utilities class]):@"none";
            if([exclusion isKindOfClass:UIBezierPath.class])report[@"exclusion_bounds"]=NSStringFromCGRect([exclusion bounds]);
            for(Class start in @[UIScreen.class,configuration?[configuration class]:NSObject.class,exclusion?[exclusion class]:NSObject.class,utilities?[utilities class]:NSObject.class])for(Class type=start;type&&type!=NSObject.class;type=class_getSuperclass(type)){unsigned int count=0;Method *methods=class_copyMethodList(type,&count);NSMutableArray *items=[NSMutableArray new];for(unsigned int i=0;i<count;i++){NSString *selector=NSStringFromSelector(method_getName(methods[i]));if(start==[exclusion class]||start==[utilities class]||[selector rangeOfString:@"corner|occlu|notch|periph|exclu|mask|cutout|shape|safe|path|bound" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch].location!=NSNotFound)[items addObject:@{@"name":selector,@"encoding":@(method_getTypeEncoding(methods[i]))}];}free(methods);report[NSStringFromClass(type)]=items;}puts(PCJSON(report).UTF8String);return 0;}
        if(argc==2&&strcmp(argv[1],"--network-permission-status")==0){NSDictionary *r=PCSendRootRequest(@{@"action":@"network_status"},6);puts(PCJSON(r).UTF8String);return r[@"error"]?1:0;}
        if(argc==3&&strcmp(argv[1],"--network-permission-grant")==0){NSDictionary *r=geteuid()==0?PCNetworkPermissionApply(@(argv[2])):@{@"error":@"命令行网络授权需要 Root；也可在应用的网络授权页面操作。"};puts(PCJSON(r).UTF8String);return [r[@"verified"] boolValue]?0:1;}
        if(argc==3&&strcmp(argv[1],"--pair-found")==0){NSDictionary *match=nil;for(NSDictionary *d in PCPairDiscover())if([d[@"device_id"] isEqual:@(argv[2])])match=d;NSDictionary *r=match?PCPairBegin(match):@{@"error":@"搜索未发现指定设备。"};puts(PCJSON(r).UTF8String);return r[@"error"]?1:0;}
        if(argc==4&&strcmp(argv[1],"--pair-host")==0){
            if(geteuid()!=0&&geteuid()!=501){puts("local mobile/root caller required");return 77;}
            if(geteuid()==0){gid_t group=501;if(setgroups(1,&group)||setgid(501)||setuid(501)){puts("could not use mobile identity");return 77;}setenv("HOME",PCRealPath(@"/var/mobile").fileSystemRepresentation,1);}
            NSError *error=nil;NSDictionary *remote=PCDiscoveryProbeHost(@(argv[2]),@(argv[3]),&error);NSMutableDictionary *result=remote?[PCPairBegin(remote) mutableCopy]:[@{@"error":error.localizedDescription?:@"未发出配对申请。"} mutableCopy];NSDictionary *receiver=result[@"receiver"];if([receiver isKindOfClass:NSDictionary.class])result[@"receiver"]=@{@"device_id":receiver[@"device_id"]?:@"",@"name":receiver[@"name"]?:@""};puts(PCJSON(result).UTF8String);return result[@"error"]?1:0;
        }
        if(argc==3&&strcmp(argv[1],"--pair-poll")==0){NSDictionary *r=PCPairPoll(@(argv[2]));puts(PCJSON(r).UTF8String);return r[@"error"]?1:0;}
        if((argc==2&&strcmp(argv[1],"--pair-pending")==0)||(argc==3&&strcmp(argv[1],"--pair-decide-once")==0)){
            if(geteuid()!=0&&geteuid()!=501){puts("local mobile/root caller required");return 77;}
            if(geteuid()==0){gid_t group=501;if(setgroups(1,&group)||setgid(501)||setuid(501)){puts("could not use mobile identity");return 77;}setenv("HOME",PCRealPath(@"/var/mobile").fileSystemRepresentation,1);}
            if(argc==2){puts(PCJSON(@{@"requests":PCPairPending()}).UTF8String);return 0;}
            NSString *identifier=@(argv[2]);if(identifier.length!=36||![[NSUUID alloc] initWithUUIDString:identifier]){puts("invalid pending request UUID");return 2;}NSDictionary *r=PCPairDecide(identifier,@"once");puts(PCJSON(r).UTF8String);return r[@"error"]?1:0;
        }
        if(argc==3&&strcmp(argv[1],"--pair-close")==0){PCControlRelease(@(argv[2]));puts("session closed");return 0;}
        if(argc==2&&strcmp(argv[1],"--discover")==0){NSDictionary *report=PCDiscoveryRun(nil);NSMutableDictionary *safe=[report mutableCopy];NSMutableArray *devices=[NSMutableArray new];for(NSDictionary *device in report[@"devices"])[devices addObject:@{@"name":device[@"name"],@"host":device[@"host"],@"device_id":device[@"device_id"],@"platform":device[@"platform"]?:@"unknown"}];safe[@"devices"]=devices;puts(PCJSON(safe).UTF8String);return devices.count?0:1;}
        if(argc==2&&(strcmp(argv[1],"--agent-daemon")==0||strcmp(argv[1],"--control-daemon")==0||strcmp(argv[1],"--root-daemon")==0))if(!PCEnsureServiceMemoryBudget())return 3;
        if(argc==2&&(strcmp(argv[1],"--notification-status")==0||strcmp(argv[1],"--notification-test")==0)){
            __block BOOL done=NO;BOOL test=strcmp(argv[1],"--notification-test")==0;
            [PCNotificationCenter() getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){printf("notification authorization=%ld alert=%ld center=%ld\n",(long)settings.authorizationStatus,(long)settings.alertSetting,(long)settings.notificationCenterSetting);if(!test){done=YES;return;}PCSendNotificationTest(^(NSString *result){puts(result.UTF8String);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC),dispatch_get_main_queue(),^{[PCNotificationCenter() getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *items){BOOL found=NO;for(UNNotification *item in items)if([item.request.identifier isEqual:@"agentgo-notification-test"])found=YES;printf("test_notification_delivered=%s\n",found?"true":"false");done=YES;}];});});}];
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:12];while(!done&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];return done?0:1;
        }
        if (argc == 2 && strcmp(argv[1], "--agent-daemon") == 0) return PCRunAgentDaemon();
        if (argc == 2 && strcmp(argv[1], "--control-daemon") == 0) return PCRunControlDaemon();
        if (argc == 4 && strcmp(argv[1], "--control-call") == 0) {
            NSDictionary *args=[NSJSONSerialization JSONObjectWithData:[@(argv[3]) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            NSDictionary *result=PCControlExecute(@(argv[2]),args?:@{},@"cli");puts(PCJSON(result).UTF8String);return result[@"error"]?1:0;
        }
        if (argc == 3 && strcmp(argv[1], "--control-import") == 0) {NSDictionary *r=PCControlImport(@(argv[2]));puts(PCJSON(r).UTF8String);return r[@"error"]?1:0;}
        if (argc == 3 && strcmp(argv[1], "--control-import-file") == 0) {NSString *invite=[NSString stringWithContentsOfFile:PCRealPath(@(argv[2])) encoding:NSUTF8StringEncoding error:nil];NSDictionary *r=PCControlImport(invite?:@"");puts(PCJSON(r).UTF8String);return r[@"error"]?1:0;}
        if (argc == 5 && strcmp(argv[1], "--control-remote") == 0) {
            NSDictionary *args=[NSJSONSerialization JSONObjectWithData:[@(argv[4]) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];NSMutableDictionary *r=[PCControlRequest(@(argv[2]),@(argv[3]),args?:@{},nil) mutableCopy];if(r[@"image_base64"]){r[@"image_bytes"]=@([r[@"image_base64"] length]);[r removeObjectForKey:@"image_base64"];}puts(PCJSON(r).UTF8String);return r[@"error"]?1:0;
        }
        if (argc == 2 && strcmp(argv[1], "--root-daemon") == 0) return PCRunRootDaemon();
        if (argc == 2 && strcmp(argv[1], "--remote-test") == 0) {
            BOOL passed = PCRemote.shared.running;
            puts(passed ? "launchd remote service is running" : "launchd remote service is not running");
            return passed ? 0 : 1;
        }
        if (argc == 2 && strcmp(argv[1], "--selftest") == 0) {
            NSDictionary *results = PCOfflineSelfTest();
            puts(PCJSON(results).UTF8String);
            BOOL passed = YES;
            for (id key in results) if ([results[key] isKindOfClass:NSNumber.class] && ![results[key] boolValue]) passed = NO;
            if (results[@"error"] || results[@"cleanup_error"]) passed = NO;
            return passed ? 0 : 1;
        }
        if (argc == 2 && strcmp(argv[1], "--screen-test") == 0) {
            NSDictionary *result = PCScreenRequest(@{@"action":@"capture"});
            if (result[@"error"]) { puts([result[@"error"] UTF8String]); return 1; }
            printf("screen_capture width=%ld height=%ld jpeg_base64_bytes=%lu\n",
                (long)[result[@"width"] integerValue], (long)[result[@"height"] integerValue],
                (unsigned long)[result[@"image_base64"] length]);
            return 0;
        }
        if (argc == 2 && strcmp(argv[1], "--screen-save-test") == 0) {
            if (![NSUserDefaults.standardUserDefaults boolForKey:@"aiScreenEnabled"]) { puts("AI screen control is disabled"); return 1; }
            NSDictionary *result = PCScreenRequest(@{@"action":@"capture"});
            NSString *encoded = [result[@"image_base64"] isKindOfClass:NSString.class] ? result[@"image_base64"] : nil;
            NSData *jpeg = encoded ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
            if (!jpeg.length) { puts([result[@"error"] ?: @"capture failed" UTF8String]); return 1; }
            NSString *path = PCRealPath(@"/var/mobile/Library/PocketCodexRemote/screen-test.jpg");
            if (![jpeg writeToFile:path options:NSDataWritingAtomic error:nil]) return 1;
            [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
            printf("saved %lu bytes\n", (unsigned long)jpeg.length);
            return 0;
        }
        if (argc == 4 && strcmp(argv[1], "--screen-tap-test") == 0) {
            if (![NSUserDefaults.standardUserDefaults boolForKey:@"aiScreenEnabled"]) { puts("AI screen control is disabled"); return 1; }
            NSDictionary *result = PCScreenRequest(@{@"action":@"tap", @"x":@(atof(argv[2])), @"y":@(atof(argv[3]))});
            puts(PCJSON(result).UTF8String);
            return result[@"tapped"] ? 0 : 1;
        }
        if (argc == 3 && strcmp(argv[1], "--screen-action-test") == 0) {
            if (![NSUserDefaults.standardUserDefaults boolForKey:@"aiScreenEnabled"]) { puts("AI screen control is disabled"); return 1; }
            NSData *data = [[NSString stringWithUTF8String:argv[2]] dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *request = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (![request isKindOfClass:NSDictionary.class] || ![@[@"home", @"swipe", @"type", @"tap"] containsObject:request[@"action"]]) return 2;
            NSDictionary *result = PCScreenRequest(request);
            puts(PCJSON(result).UTF8String);
            return result[@"error"] ? 1 : 0;
        }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(PCAppDelegate.class));
    }
}
