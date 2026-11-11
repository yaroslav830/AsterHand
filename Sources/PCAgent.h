#import <Foundation/Foundation.h>

@interface PCAgent : NSObject
@property(atomic, readonly) BOOL running;
@property(atomic, readonly) BOOL failed;
@property(atomic, readonly) BOOL paused;
@property(atomic, readonly) BOOL cancelled;
@property(nonatomic, copy) NSString *workspace;
/* Callbacks always arrive on the main queue. */
@property(nonatomic, copy) void (^event)(NSString *kind, NSString *text);
@property(nonatomic, copy) void (^approval)(NSString *name, NSDictionary *args, void (^reply)(BOOL));
@property(nonatomic, copy) void (^question)(NSString *text, NSArray *options, void (^reply)(NSString *));
@property(nonatomic, copy) void (^rootPermission)(NSString *text, NSDictionary *operation, void (^reply)(NSString *));
@property(nonatomic, copy) void (^finished)(void);
- (void)send:(NSString *)message;
- (void)send:(NSString *)message attachments:(NSArray *)attachments;
- (BOOL)enqueueMessage:(NSString *)message;
- (void)stop;
- (void)pause;
- (void)resume;
- (void)reset;
- (void)restoreHistory:(NSArray *)history;
- (NSArray *)historySnapshot;
@end
