#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NSDictionary *PCControlState(void);
NSDictionary *PCControlReadStateFile(NSString *path, NSError **error);
BOOL PCControlAvailable(void);
NSDictionary *PCControlUpdate(NSDictionary *(^change)(NSMutableDictionary *state));
NSArray *PCControlAddresses(void);
NSString *PCControlInvitation(NSString *host);
NSDictionary *PCControlImport(NSString *invitation);
NSDictionary *PCControlRequest(NSString *peer, NSString *method, NSDictionary *args, BOOL (^cancel)(void));
NSDictionary *PCControlExecute(NSString *method, NSDictionary *args, NSString *owner);
NSDictionary *PCControlSeal(NSString *pair, NSString *secret, NSDictionary *payload, NSString *direction);
NSDictionary *PCControlOpen(NSDictionary *packet, NSString *secret, NSString *direction);
NSData *PCControlSealFrame(NSDictionary *frame, NSString *secret, NSString *nonce);
NSDictionary *PCControlOpenFrame(NSData *data, NSString *secret, NSString *nonce);
int PCRunControlDaemon(void);
@interface PCControlStream : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, copy) void (^frame)(NSDictionary *frame);
@property(nonatomic, copy) void (^failed)(NSString *message);
- (void)start:(NSString *)peer;
- (void)stop;
@end
@interface PCDevicesController : UITableViewController
@end
