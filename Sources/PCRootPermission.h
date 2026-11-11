#import <Foundation/Foundation.h>

NSArray *PCRootPermissionOptions(void);
BOOL PCRootOperationValid(NSString *name, NSDictionary *args);
BOOL PCRootPermissionAnswerValid(id answer);
BOOL PCRootOnceClaim(NSDictionary *request, NSMutableDictionary *used, NSTimeInterval now);
