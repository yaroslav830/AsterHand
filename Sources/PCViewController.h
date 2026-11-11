#import <UIKit/UIKit.h>
@interface PCViewController : UIViewController
- (void)stopForBackground;
- (void)performVoiceAction:(NSString *)action;
- (void)performFloatingVoiceRequest:(NSString *)requestID;
@end
