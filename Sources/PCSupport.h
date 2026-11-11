#import <Foundation/Foundation.h>

NSString *PCWorkspace(void);
NSString *PCAPIKey(void);
BOOL PCSetAPIKey(NSString *key, NSError **error);
NSString *PCAPIKeyForProvider(NSString *provider);
BOOL PCSetAPIKeyForProvider(NSString *provider, NSString *key, NSError **error);
NSDictionary *PCChatGPTCredentials(void);
BOOL PCSetChatGPTCredentials(NSDictionary *credentials, NSError **error);
NSString *PCJSON(id object);
NSString *PCRedact(NSString *text);
NSError *PCError(NSString *message);
void PCHaptic(NSString *kind);
NSString *PCSelectedAssistantName(void);

