#import "PCAgent.h"
NSString *PCAgentTaskDirectory(void);
NSDictionary *PCAgentTaskState(void);
NSDictionary *PCAgentRemoteControl(NSDictionary *arguments);
void PCAgentSetForeground(BOOL active);
int PCRunAgentDaemon(void);
@interface PCPersistentAgent : PCAgent
@property(nonatomic,copy) NSDictionary *projectContext;
@property(nonatomic,readonly) NSDictionary *pendingQuestion;
@property(nonatomic,readonly,copy) NSString *currentTaskID;
- (void)publishOverlayContext;
- (void)answer:(NSString *)text;
- (BOOL)answer:(NSString *)text questionID:(NSString *)prompt jobID:(NSString *)job;
- (void)resetPromptDelivery;
@end
