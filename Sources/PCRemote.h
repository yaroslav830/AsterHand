#import <UIKit/UIKit.h>

@interface PCRemote : NSObject
+ (instancetype)shared;
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) BOOL autoApproveEnabled;
@property(nonatomic, readonly) NSString *descriptionText;
- (BOOL)start:(NSError **)error;
- (void)setAutoApproveEnabled:(BOOL)enabled;
- (void)trustHost:(NSString *)host;
- (BOOL)hasPendingConsent;
@end

@interface PCRemoteController : UIViewController
@end
