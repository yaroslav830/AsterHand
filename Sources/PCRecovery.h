#import <UIKit/UIKit.h>
BOOL PCServicesEnabled(void);
NSString *PCServicesRequest(NSString *action,NSError **error);
NSDictionary *PCServicesResult(NSString *nonce);

/* Confirmation stays in the app; the independent fixed launchd job does recovery. */
@interface PCRecoveryController : UIViewController
@property(nonatomic,copy) void (^beforeRestart)(void);
@end
