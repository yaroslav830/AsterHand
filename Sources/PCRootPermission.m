#import "PCRootPermission.h"
#include <math.h>

NSArray *PCRootPermissionOptions(void) { return @[@"不允许", @"允许一次", @"始终允许"]; }
BOOL PCRootPermissionAnswerValid(id answer) {
    return [answer isKindOfClass:NSString.class] && [PCRootPermissionOptions() containsObject:answer];
}
static BOOL Text(id value, NSUInteger limit, BOOL empty) {
    return [value isKindOfClass:NSString.class] && (empty || [value length]) && [value length] <= limit && [value rangeOfString:@"\0"].location == NSNotFound;
}
BOOL PCRootOperationValid(NSString *name, NSDictionary *args) {
    if (![name isKindOfClass:NSString.class] || ![args isKindOfClass:NSDictionary.class]) return NO;
    if ([name isEqual:@"run_shell"]) return args.count == 2 && Text(args[@"command"], 32768, NO) && [args[@"timeout_seconds"] isKindOfClass:NSNumber.class] && [args[@"timeout_seconds"] doubleValue] >= 1 && [args[@"timeout_seconds"] doubleValue] <= 120;
    if ([name isEqual:@"read_file"]) return args.count == 2 && Text(args[@"path"], 4096, NO) && [args[@"offset"] isKindOfClass:NSNumber.class] && [args[@"offset"] doubleValue] >= 0 && isfinite([args[@"offset"] doubleValue]);
    if ([name isEqual:@"write_file"]) return args.count == 2 && Text(args[@"path"], 4096, NO) && Text(args[@"content"], 256 * 1024, YES);
    return [name isEqual:@"list_directory"] && args.count == 1 && Text(args[@"path"], 4096, NO);
}
BOOL PCRootOnceClaim(NSDictionary *request, NSMutableDictionary *used, NSTimeInterval now) {
    NSString *nonce = request[@"grant"], *job = request[@"job"], *prompt = request[@"prompt"];
    if (!Text(nonce, 64, NO) || ![[NSUUID alloc] initWithUUIDString:nonce] || !Text(job, 128, NO) || !Text(prompt, 128, NO) || ![[NSUUID alloc] initWithUUIDString:prompt]) return NO;
    NSNumber *created = request[@"created"];
    if (![created isKindOfClass:NSNumber.class] || !isfinite(created.doubleValue) || created.doubleValue > now + 5 || now - created.doubleValue > 30) return NO;
    for (NSString *key in [used.allKeys copy]) if (now - [used[key] doubleValue] > 40) [used removeObjectForKey:key];
    if (used[nonce] || used.count >= 256) return NO;
    used[nonce] = @(now); // Consume before execution, including failed or cancelled operations.
    return YES;
}
