#import <UIKit/UIKit.h>
NSDictionary *PCPairIdentity(void);
BOOL PCPairIdentityValid(NSDictionary *identity);
NSDictionary *PCPairHandle(NSDictionary *body, NSString *address);
NSArray *PCPairPending(void);
NSDictionary *PCPairDecide(NSString *request, NSString *mode);
NSDictionary *PCPairSetTrust(NSString *device, NSString *mode);
NSArray *PCPairDiscover(void);
NSDictionary *PCPairBegin(NSDictionary *remote);
NSDictionary *PCPairPoll(NSString *request);
void PCControlRelease(NSString *peer);
void PCPairPromptIfNeeded(UIViewController *presenter);
@interface PCRemoteConnectionsController : UITableViewController
@end
@interface PCPairApprovalController : UIViewController
@property(nonatomic,strong) NSDictionary *request;
@end
