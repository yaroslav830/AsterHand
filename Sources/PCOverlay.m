#import "PCLocalization.h"
#import "PCOverlay.h"
#import <UIKit/UIKit.h>
#import "PCPlatform.h"
#include <sys/stat.h>
#include <notify.h>
#include <unistd.h>

void PCOverlayPrepareForAIScreen(void) {
    NSString *identifier=NSUUID.UUID.UUIDString;NSString *directory=PCOverlayDirectory();
    NSDictionary *request=@{@"id":identifier,@"created":@(NSDate.date.timeIntervalSince1970)};
    NSString *path=[directory stringByAppendingPathComponent:@"screen-prepare.json"];
    if(![[NSJSONSerialization dataWithJSONObject:request options:0 error:nil] writeToFile:path options:NSDataWritingAtomic error:nil])return;chmod(path.fileSystemRepresentation,0600);
    notify_post("local.agentgo.overlay.prepare-screen");
    for(NSUInteger n=0;n<60;n++){@autoreleasepool{NSData *data=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"screen-prepared.json"]];NSDictionary *ack=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;if([ack[@"id"] isEqual:identifier])return;}usleep(10000);}
}
void PCOverlayFinishAIScreen(NSTimeInterval delay) {
    NSString *directory=PCOverlayDirectory();NSData *data=[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"screen-prepare.json"]];NSDictionary *prepare=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;if(!prepare[@"id"])return;
    NSString *path=[directory stringByAppendingPathComponent:@"screen-finish.json"];NSDictionary *value=@{@"id":prepare[@"id"],@"until":@(NSDate.date.timeIntervalSince1970+MAX(.15,MIN(3,delay)))};
    if([[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] writeToFile:path options:NSDataWritingAtomic error:nil]){chmod(path.fileSystemRepresentation,0600);notify_post("local.agentgo.overlay.finish-screen");}
}

NSString *PCOverlayDirectory(void) { return PCRealPath(@"/var/mobile/Library/PocketAgentControl"); }

void PCOverlayPublish(BOOL enabled, BOOL running, BOOL paused) {
    NSString *directory = PCOverlayDirectory();
    if (!directory) return;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return;
    NSMutableDictionary *effects=[NSMutableDictionary new];NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;for(NSString *key in @[@"effectAI",@"effectRemoteInput",@"effectRemoteConnected",@"effectScreenEdge"])effects[key]=@(![defaults objectForKey:key]||[defaults boolForKey:key]);
    NSString *overridePath=[directory stringByAppendingPathComponent:@"visibility-override.json"];NSData *overrideData=[NSData dataWithContentsOfFile:overridePath];NSDictionary *override=overrideData?[NSJSONSerialization JSONObjectWithData:overrideData options:0 error:nil]:nil;
    NSString *request=[defaults stringForKey:@"overlayVisibilityRequest"]?:@"initial";
    BOOL adopt=[override[@"base_request"] isEqual:request]||[override[@"request"] isEqual:request];
    if(adopt&&[override[@"request"] isKindOfClass:NSString.class]){enabled=[override[@"enabled"] boolValue];request=override[@"request"];[defaults setBool:enabled forKey:@"overlayEnabled"];[defaults setObject:request forKey:@"overlayVisibilityRequest"];}
    double width=[defaults objectForKey:@"edgeWidth"]?[defaults doubleForKey:@"edgeWidth"]:14;
    double opacity=[defaults objectForKey:@"edgeOpacity"]?[defaults doubleForKey:@"edgeOpacity"]:.7;
    UIWindow *window=UIApplication.sharedApplication.keyWindow;UIEdgeInsets safe=window?window.safeAreaInsets:UIEdgeInsetsZero;
    NSDictionary *display=@{@"safe_top":@(safe.top),@"safe_bottom":@(safe.bottom),@"width":@(UIScreen.mainScreen.bounds.size.width),@"height":@(UIScreen.mainScreen.bounds.size.height)};
    NSDictionary *state = @{@"ui_language":PCResolvedUILanguage(), @"enabled": @(enabled), @"running": @(running), @"paused": @(paused),@"effects":effects,@"display":display,@"haptic_style":[defaults stringForKey:@"hapticStyle"]?:@"system",@"capsule_locked":@([defaults boolForKey:@"capsuleLocked"]),@"edge_width":@(isfinite(width)?MAX(4,MIN(28,width)):14),@"edge_opacity":@(isfinite(opacity)?MAX(.2,MIN(1,opacity)):.7),@"visibility_request":request, @"updated": @(NSDate.date.timeIntervalSince1970)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    NSString *path = [directory stringByAppendingPathComponent:@"state.json"];
    if ([data writeToFile:path options:NSDataWritingAtomic error:nil]) {chmod(path.fileSystemRepresentation, 0600);if(adopt)[NSFileManager.defaultManager removeItemAtPath:overridePath error:nil];}
}

NSString *PCOverlayTakeCommand(void) {
    NSString *path = [PCOverlayDirectory() stringByAppendingPathComponent:@"command.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    NSDictionary *item = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSString *command = [item[@"command"] isKindOfClass:NSString.class] ? item[@"command"] : nil;
    NSTimeInterval created = [item[@"created"] doubleValue];
    return fabs(NSDate.date.timeIntervalSince1970 - created) < 10 && [@[@"pause", @"resume", @"stop"] containsObject:command] ? command : nil;
}
