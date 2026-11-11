#import <Foundation/Foundation.h>

NSDictionary *PCParseCompletedSSE(NSData *data, NSError **error);

@interface PCAPI : NSObject <NSURLSessionDataDelegate>
@property(atomic) BOOL cancelled;
@property(nonatomic, copy) NSString *provider;
/* Called from the networking queue; the UI must dispatch to the main queue. */
@property(nonatomic, copy) void (^progress)(NSString *state);
@property(nonatomic, copy) void (^liveText)(NSString *text);
- (void)cancel;
/* Blocking; call on a worker queue, never on the main/UI thread. */
- (NSDictionary *)request:(NSString *)path body:(NSDictionary *)body error:(NSError **)error;
@end
