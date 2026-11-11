#import <UIKit/UIKit.h>

@interface PCChatGPTBrowserController : UIViewController
@property(nonatomic,copy) void (^localCallback)(NSURL *url);
@property(nonatomic,copy) dispatch_block_t newRegistrationHandler;
- (instancetype)initWithURL:(NSURL *)url callbackURL:(NSURL *)callbackURL cancelHandler:(dispatch_block_t)cancelHandler;
@end
