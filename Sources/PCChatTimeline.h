#import <UIKit/UIKit.h>
@interface PCChatTimeline : UITableView
@property(nonatomic, copy) void (^followChanged)(BOOL);
@property(nonatomic, copy) void (^showDetails)(NSString *, NSString *);
@property(nonatomic) BOOL automaticFollow;
@property(nonatomic,copy) BOOL (^answerQuestion)(NSString *job,NSString *prompt,NSString *text);
- (void)showPendingQuestion:(NSDictionary *)question;
- (void)refreshUILanguage;
- (void)showTranscript:(NSString *)transcript;
- (void)jumpToLatest;
@end
@interface PCSidebarTransition : NSObject <UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning>
@end
