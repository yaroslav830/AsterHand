#import <Foundation/Foundation.h>

int PCRunRootDaemon(void);
NSDictionary *PCSendRootRequest(NSDictionary *request, NSTimeInterval timeout);
NSDictionary *PCSendRootRequestWithCancellation(NSDictionary *request, NSTimeInterval timeout, BOOL (^cancelled)(void));
