#import "PCNotifications.h"
#import "PCPersistentAgent.h"
#import "PCLocalization.h"
#include <sys/stat.h>
@interface UNUserNotificationCenter (AsterHandIdentity)
- (instancetype)initWithBundleIdentifier:(NSString *)identifier;
@end
UNUserNotificationCenter *PCNotificationCenter(void){static UNUserNotificationCenter *center;static dispatch_once_t once;dispatch_once(&once,^{if([NSProcessInfo.processInfo.arguments containsObject:@"--agent-daemon"]||[NSProcessInfo.processInfo.arguments containsObject:@"--notification-test"]||[NSProcessInfo.processInfo.arguments containsObject:@"--notification-status"])center=[[UNUserNotificationCenter alloc] initWithBundleIdentifier:@"local.pocketcodex"];else center=UNUserNotificationCenter.currentNotificationCenter;});return center;}
static NSString *PermissionPath(void){return [PCAgentTaskDirectory() stringByAppendingPathComponent:@"notification-permission.json"];}
static NSDictionary *PermissionState(void){NSData *data=[NSData dataWithContentsOfFile:PermissionPath()];id state=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;return [state isKindOfClass:NSDictionary.class]?state:@{};}
static void SavePermission(NSDictionary *state){[NSFileManager.defaultManager createDirectoryAtPath:PCAgentTaskDirectory() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];NSData *data=[NSJSONSerialization dataWithJSONObject:state options:0 error:nil];if([data writeToFile:PermissionPath() options:NSDataWritingAtomic error:nil])chmod(PermissionPath().fileSystemRepresentation,0600);}
void PCRequestNotificationsIfNeeded(BOOL explicitRequest,void (^completion)(NSDictionary *)){
    [PCNotificationCenter() getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){dispatch_async(dispatch_get_main_queue(),^{
        NSMutableDictionary *state=[PermissionState() mutableCopy];state[@"authorization"]=@(settings.authorizationStatus);state[@"alert"]=@(settings.alertSetting);state[@"center"]=@(settings.notificationCenterSetting);state[@"updated"]=@(NSDate.date.timeIntervalSince1970);
        BOOL asked=[state[@"requested"] boolValue];
        BOOL request=settings.authorizationStatus==UNAuthorizationStatusNotDetermined&&(explicitRequest||!asked);
        if(!request){SavePermission(state);if(completion)completion(state);return;}
        state[@"requested"]=@YES;SavePermission(state);
        [PCNotificationCenter() requestAuthorizationWithOptions:UNAuthorizationOptionAlert|UNAuthorizationOptionSound|UNAuthorizationOptionBadge completionHandler:^(BOOL granted,NSError *error){dispatch_async(dispatch_get_main_queue(),^{NSMutableDictionary *result=[PermissionState() mutableCopy];result[@"granted"]=@(granted);if(error)result[@"error"]=error.localizedDescription;[PCNotificationCenter() getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *updated){dispatch_async(dispatch_get_main_queue(),^{result[@"authorization"]=@(updated.authorizationStatus);result[@"alert"]=@(updated.alertSetting);result[@"center"]=@(updated.notificationCenterSetting);SavePermission(result);if(completion)completion(result);});}];});}];
    });}];
}
void PCSendNotificationTest(void (^completion)(NSString *)){
    [PCNotificationCenter() getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){
        if(settings.authorizationStatus!=UNAuthorizationStatusAuthorized&&settings.authorizationStatus!=UNAuthorizationStatusProvisional){if(completion)completion(@"系统尚未授权通知，请先申请权限或打开系统设置。");return;}
        UNMutableNotificationContent *content=[UNMutableNotificationContent new];content.title=PCLocalized(@"AsterHand 通知测试");content.body=PCLocalized(@"通知通道已发出测试。");content.sound=UNNotificationSound.defaultSound;
        UNNotificationRequest *request=[UNNotificationRequest requestWithIdentifier:@"agentgo-notification-test" content:content trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:3 repeats:NO]];
        [PCNotificationCenter() addNotificationRequest:request withCompletionHandler:^(NSError *error){if(completion)completion(error?error.localizedDescription:@"测试已安排，3 秒后请查看通知。");}];
    }];
}
