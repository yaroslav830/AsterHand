#import <UserNotifications/UserNotifications.h>
UNUserNotificationCenter *PCNotificationCenter(void);
void PCRequestNotificationsIfNeeded(BOOL explicitRequest,void (^completion)(NSDictionary *status));
void PCSendNotificationTest(void (^completion)(NSString *result));
