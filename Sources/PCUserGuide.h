#import <UIKit/UIKit.h>

BOOL PCUserGuideCompleted(void);

@interface PCUserGuideController : UIViewController
@property(nonatomic) BOOL onboarding;
@property(nonatomic, copy) NSDictionary *topic;
// Only an explicit finish or skip records completion. Reading help grants no permissions.
@property(nonatomic, copy) void (^finished)(BOOL connectAI);
@end
