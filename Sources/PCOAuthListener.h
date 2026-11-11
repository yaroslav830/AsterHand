#import <Foundation/Foundation.h>
NSDictionary *PCOAuthWaitForCallback(int listener,NSURL *redirect,NSString *state,NSTimeInterval timeout,NSError **error);
BOOL PCOAuthDeliverCallbackURL(NSURL *url,NSURL *redirect,NSString *state,NSError **error);
NSDictionary *PCOAuthListenerSelfTest(void);
