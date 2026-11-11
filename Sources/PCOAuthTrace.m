#import "PCOAuthTrace.h"
#import "PCPlatform.h"

static NSMutableArray *PCLoginEvents;
static NSObject *TraceLock(void) {static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=[NSObject new];});return lock;}
void PCOAuthTraceBegin(void) {@synchronized(TraceLock()){PCLoginEvents=[NSMutableArray new];}PCOAuthTrace(@"attempt_started");}
void PCOAuthTrace(NSString *stage) {
    @synchronized(TraceLock()){
        if(!PCLoginEvents||![stage isKindOfClass:NSString.class]||stage.length>200)return;
        NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_0123456789-"];
        if([stage rangeOfCharacterFromSet:allowed.invertedSet].location!=NSNotFound)return;
        [PCLoginEvents addObject:@{@"stage":stage,@"time":@(NSDate.date.timeIntervalSince1970)}];
        if(PCLoginEvents.count>80)[PCLoginEvents removeObjectsInRange:NSMakeRange(0,PCLoginEvents.count-80)];
        NSString *directory=PCRealPath(@"/var/mobile/Library/Logs/AsterHand");
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
        NSString *path=[directory stringByAppendingPathComponent:@"login-status.json"];
        NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"events":PCLoginEvents} options:0 error:nil];
        if([data writeToFile:path options:NSDataWritingAtomic error:nil])[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
    }
}
