#import <Foundation/Foundation.h>

@interface PCTools : NSObject
@property(atomic) BOOL cancelled;
@property(nonatomic, copy) BOOL (^cancellationCheck)(void);
@property(nonatomic, copy) NSString *workspace;
@property(nonatomic) BOOL rootEnabled;
@property(nonatomic, strong) NSNumber *screenPermission;
- (NSDictionary *)execute:(NSString *)name arguments:(NSDictionary *)args;
- (NSDictionary *)diagnostics;
@end
