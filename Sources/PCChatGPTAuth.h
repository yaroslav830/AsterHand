#import <Foundation/Foundation.h>

void PCChatGPTSignIn(void (^completion)(NSDictionary *credentials, NSError *error));
void PCChatGPTSignInNewAccount(void (^completion)(NSDictionary *credentials, NSError *error));
NSDictionary *PCChatGPTAuthorizationSelfTest(void);
NSString *PCChatGPTPrepareDesktopAuthorizationURL(NSError **error);
void PCChatGPTCompleteDesktopSignIn(NSString *callbackURL, void (^completion)(NSDictionary *credentials, NSError *error));
BOOL PCRefreshChatGPTCredentials(NSError **error);
void PCChatGPTSignOut(void (^completion)(NSString *status));
