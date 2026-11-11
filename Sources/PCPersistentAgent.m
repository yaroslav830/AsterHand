#import "PCPersistentAgent.h"
#import "PCPlatform.h"
#import "PCSupport.h"
#import "PCProjectStore.h"
#import "PCOverlay.h"
#import "PCMessageQueue.h"
#import "PCQuestion.h"
#import "PCRootPermission.h"
#import "PCScreen.h"
#import "PCLocalization.h"
#import <UserNotifications/UserNotifications.h>
#import <UIKit/UIKit.h>
#include <unistd.h>
#include <sys/stat.h>
#include <signal.h>
#import "PCNotifications.h"

NSString *PCAgentTaskDirectory(void) {return PCRealPath(@"/var/mobile/Library/AgentGoTasks");}
static NSDictionary *Read(NSString *name) {NSData *data=[NSData dataWithContentsOfFile:[PCAgentTaskDirectory() stringByAppendingPathComponent:name]];id value=data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil]:nil;return [value isKindOfClass:NSDictionary.class]?value:@{};}
static BOOL Write(NSString *name,NSDictionary *value) {[NSFileManager.defaultManager createDirectoryAtPath:PCAgentTaskDirectory() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];NSString *file=[PCAgentTaskDirectory() stringByAppendingPathComponent:name];if(!data||![data writeToFile:file options:NSDataWritingAtomic error:nil])return NO;chmod(file.fileSystemRepresentation,0600);return YES;}
NSDictionary *PCAgentTaskState(void) {return Read(@"state.json");}
void PCAgentSetForeground(BOOL active) {Write(@"foreground.json",@{@"active":@(active),@"updated":@(NSDate.date.timeIntervalSince1970)});}
static BOOL Reply(NSString *job,NSString *prompt,id value) {return job&&prompt?Write(@"reply.json",@{@"job":job,@"prompt":prompt,@"value":value?:NSNull.null}):NO;}
NSDictionary *PCAgentRemoteControl(NSDictionary *a){
    NSDictionary *state=PCAgentTaskState();NSString *action=a[@"action"];
    NSDictionary *queued=Read(@"request.json");BOOL pending=![state[@"running"] boolValue]&&![queued[@"cancelled"] boolValue]&&[queued[@"id"] isKindOfClass:NSString.class]&&![queued[@"id"] isEqual:state[@"id"]];
    if(pending){if([action isEqual:@"ai.status"])return @{@"id":queued[@"id"],@"running":@YES,@"queued":@YES,@"status":@"正在启动常驻任务…",@"context":@{@"project":queued[@"context"][@"project"]?:@"",@"chat":queued[@"context"][@"chat"]?:@""}};return @{@"error":@"新任务正在启动，请核对状态后再操作"};}
    if([action isEqual:@"ai.status"]){NSMutableDictionary *out=[NSMutableDictionary new];for(NSString *key in @[@"id",@"running",@"paused",@"failed",@"cancelled",@"status",@"latest_reply",@"question",@"revision"])if(state[key])out[key]=state[key];NSDictionary *context=state[@"context"];out[@"context"]=@{@"project":context[@"project"]?:@"",@"chat":context[@"chat"]?:@""};return out;}
    if(![a[@"job"] isEqual:state[@"id"]])return @{@"error":@"任务标识已变化"};
    if([@[@"ai.stop",@"ai.pause",@"ai.continue"] containsObject:action]){if(![state[@"running"] boolValue])return @{@"error":@"任务已经结束"};NSString *command=[action isEqual:@"ai.stop"]?@"stop":[action isEqual:@"ai.pause"]?@"pause":@"resume";BOOL ok=Write(@"command.json",@{@"job":state[@"id"],@"command":command,@"id":NSUUID.UUID.UUIDString.lowercaseString});return @{@"accepted":@(ok)};}
    BOOL ok=NO;if([action isEqual:@"ai.answer"]){NSString *text=a[@"text"];if(![text isKindOfClass:NSString.class]||!text.length||text.length>32768||!PCQuestionReplyMatches(state,a[@"job"],a[@"question"],a[@"chat"]))return @{@"error":@"问题或对话已变化"};if([state[@"question"][@"kind"] isEqual:@"root_permission"]&&!PCRootPermissionAnswerValid(text))return @{@"error":@"权限回答必须使用明确选项"};ok=Reply(a[@"job"],a[@"question"],text);}
    else if([action isEqual:@"ai.approve"]){if(![state[@"running"] boolValue]||![state[@"question"][@"id"] isEqual:a[@"question"]]||![state[@"question"][@"kind"] isEqual:@"approval"]||![state[@"context"][@"chat"] isEqual:a[@"chat"]]||![a[@"allow"] isKindOfClass:NSNumber.class]||![@[@YES,@NO] containsObject:a[@"allow"]])return @{@"error":@"待确认操作已变化"};ok=Reply(a[@"job"],a[@"question"],@([a[@"allow"] boolValue]));}
    else return @{@"error":@"任务操作不支持"};return @{@"accepted":@(ok)};
}
@implementation PCPersistentAgent {NSArray *_savedHistory;NSDictionary *_snapshot;NSString *_lastJob,*_prompt,*_answeredPrompt,*_answeredJob,*_rootPreferenceRevision;NSUInteger _revision;BOOL _finishedDelivered;NSTimer *_timer;}
- (instancetype)init {if((self=[super init])){_savedHistory=@[];_snapshot=PCAgentTaskState();_timer=[NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(poll) userInfo:nil repeats:YES];}return self;}
- (BOOL)running {return [_snapshot[@"running"] boolValue];}
- (BOOL)paused {return [_snapshot[@"paused"] boolValue];}
- (BOOL)failed {return [_snapshot[@"failed"] boolValue];}
- (BOOL)cancelled {return [_snapshot[@"cancelled"] boolValue];}
- (NSString *)currentTaskID {return _snapshot[@"id"];}
- (NSDictionary *)pendingQuestion {
    NSDictionary *p=[_snapshot[@"question"] isKindOfClass:NSDictionary.class]?_snapshot[@"question"]:nil;if(!PCQuestionReplyMatches(_snapshot,_snapshot[@"id"],p[@"id"],self.projectContext[@"chat"]))return nil;
    NSMutableDictionary *question=[p mutableCopy];question[@"job_id"]=_snapshot[@"id"];question[@"client_submitted"]=@([_answeredJob isEqual:_snapshot[@"id"]]&&[_answeredPrompt isEqual:p[@"id"]]);return question;
}
- (void)resetPromptDelivery {_prompt=nil;}
- (void)restoreHistory:(NSArray *)history {if(!self.running)_savedHistory=[history copy]?:@[];}
- (NSArray *)historySnapshot {BOOL belongs=[_snapshot[@"context"][@"chat"] isEqual:self.projectContext[@"chat"]];return belongs?(_snapshot[@"history"]?:_savedHistory):_savedHistory;}
- (void)reset {if(!self.running){_savedHistory=@[];_snapshot=@{};_lastJob=nil;}}
- (void)send:(NSString *)message {[self send:message attachments:@[]];}
- (void)send:(NSString *)message attachments:(NSArray *)attachments {
    if(self.pendingQuestion){[self answer:message];return;}if(self.running)return;
    NSDictionary *preferences=[self overlayPreferences];
    NSString *identifier=NSUUID.UUID.UUIDString.lowercaseString;NSDictionary *request=@{@"id":identifier,@"message":message?:@"",@"attachments":attachments?:@[],@"history":_savedHistory?:@[],@"preferences":preferences,@"workspace":self.workspace?:PCWorkspace(),@"context":self.projectContext?:@{},@"created":@(NSDate.date.timeIntervalSince1970)};
    _lastJob=identifier;_revision=0;_finishedDelivered=NO;_prompt=nil;_snapshot=@{@"id":identifier,@"running":@YES,@"history":_savedHistory?:@[],@"queued":@(NSDate.date.timeIntervalSince1970),@"status":@"正在启动常驻任务…"};Write(@"request.json",request);
}
- (NSDictionary *)overlayPreferences {
    NSMutableDictionary *preferences=[NSMutableDictionary new];NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    for(NSString *key in @[@"provider",@"model",@"workspace",@"rootEnabled",@"autoApproveTools",@"aiScreenEnabled",@"reasoningEffort",@"expandedOutput",@"apiBase.openai"])if([d objectForKey:key])preferences[key]=[d objectForKey:key];
    for(NSString *provider in @[@"openai",@"chatgpt",@"deepseek",@"anthropic"])for(NSString *prefix in @[@"model.",@"reasoningEffort.",@"expandedOutput."]) {NSString *key=[prefix stringByAppendingString:provider];if([d objectForKey:key])preferences[key]=[d objectForKey:key];}
    return preferences;
}
- (void)publishOverlayContext {
    if(!self.projectContext[@"chat"])return;
    Write(@"composer.json",@{@"preferences":[self overlayPreferences],@"history":[self historySnapshot]?:@[],@"workspace":self.workspace?:PCWorkspace(),@"context":self.projectContext});
}
- (void)command:(NSString *)command {if(_snapshot[@"id"])Write(@"command.json",@{@"job":_snapshot[@"id"],@"command":command,@"id":NSUUID.UUID.UUIDString.lowercaseString});}
- (void)stop {[self command:@"stop"];}
- (void)pause {[self command:@"pause"];}
- (void)resume {[self command:@"resume"];}
- (void)answer:(NSString *)text {NSDictionary *p=self.pendingQuestion;if(p)[self answer:text questionID:p[@"id"] jobID:p[@"job_id"]];}
- (BOOL)answer:(NSString *)text questionID:(NSString *)prompt jobID:(NSString *)job {
    if(![text isKindOfClass:NSString.class]||!text.length||text.length>32768||([_answeredJob isEqual:job]&&[_answeredPrompt isEqual:prompt]))return NO;
    NSDictionary *state=PCAgentTaskState();if(!PCQuestionReplyMatches(state,job,prompt,self.projectContext[@"chat"]))return NO;
    if ([state[@"question"][@"kind"] isEqual:@"root_permission"] && !PCRootPermissionAnswerValid(text)) return NO;
    if(!Reply(job,prompt,text))return NO;_answeredPrompt=[prompt copy];_answeredJob=[job copy];return YES;
}
- (void)poll {
    PCAgentSetForeground(UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground);
    if(self.running&&_snapshot[@"queued"]&&NSDate.date.timeIntervalSince1970-[_snapshot[@"queued"] doubleValue]>12){NSDictionary *service=Read(@"service.json");if(NSDate.date.timeIntervalSince1970-[service[@"updated"] doubleValue]>8){NSMutableDictionary *pending=[Read(@"request.json") mutableCopy];if([pending[@"id"] isEqual:_lastJob]){pending[@"cancelled"]=@YES;Write(@"request.json",pending);}_snapshot=@{@"id":_lastJob,@"running":@NO,@"failed":@YES,@"context":self.projectContext?:@{},@"history":_savedHistory?:@[]};if(self.event)self.event(@"错误",@"常驻 AI 服务未响应，请检查 RootHide 服务。");if(self.finished)self.finished();return;}}
    NSDictionary *state=PCAgentTaskState();NSString *identifier=state[@"id"];if(!identifier)return;
    if(self.projectContext[@"chat"]&&![state[@"context"][@"chat"] isEqual:self.projectContext[@"chat"]])return;
    // A queued request must not be replaced by the previous completed job.
    if(self.running&&_lastJob&&![_lastJob isEqual:identifier])return;
    if(_lastJob&&![_lastJob isEqual:identifier]&&![state[@"running"] boolValue])return;
    if(![_lastJob isEqual:identifier]){_lastJob=identifier;_revision=0;_finishedDelivered=NO;_prompt=nil;}
    _snapshot=state;NSUInteger revision=[state[@"revision"] unsignedIntegerValue];
    if ([state[@"root_preference_revision"] isKindOfClass:NSString.class] && ![_rootPreferenceRevision isEqual:state[@"root_preference_revision"]]) {
        _rootPreferenceRevision=state[@"root_preference_revision"];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
    if(revision!=_revision){_revision=revision;if(self.event){NSString *display=state[@"transcript"]?:@"";if([state[@"streaming_text"] length])display=[display stringByAppendingFormat:@"\n[%@]\n%@\n",state[@"assistant_name"]?:@"助手",state[@"streaming_text"]];self.event(@"记录同步",display);self.event(@"状态",state[@"status"]?:@"");}}
    NSDictionary *prompt=state[@"question"];if([prompt isKindOfClass:NSDictionary.class]&&![_prompt isEqual:prompt[@"id"]]&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive){_prompt=prompt[@"id"];
        PCHaptic(@"question");
        if([prompt[@"kind"] isEqual:@"approval"]&&self.approval){NSString *job=identifier,*pid=prompt[@"id"];self.approval(prompt[@"name"],prompt[@"arguments"],^(BOOL allow){Reply(job,pid,@(allow));});}
        else if(self.event)self.event(@"提问",prompt[@"text"]?:@"");
    }
    if(!self.running&&!_finishedDelivered){_finishedDelivered=YES;_savedHistory=state[@"history"]?:@[];if(self.finished)self.finished();[self publishOverlayContext];}
}
@end

@interface PCAgentWorker : NSObject <UNUserNotificationCenterDelegate>
@property(nonatomic,strong) PCAgent *agent;
@property(nonatomic,strong) NSMutableDictionary *state;
@property(nonatomic,strong) NSDictionary *request;
@property(nonatomic,copy) NSString *lastCommand;
@property(nonatomic,copy) void (^pendingReply)(id);
@property(nonatomic) BOOL credentialsAvailable;
@property(nonatomic,strong) NSMutableSet *receivedMessages;
@end
@implementation PCAgentWorker
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))complete {NSDictionary *foreground=Read(@"foreground.json");BOOL visible=[foreground[@"active"] boolValue]&&NSDate.date.timeIntervalSince1970-[foreground[@"updated"] doubleValue]<5;complete(visible?UNNotificationPresentationOptionNone:UNNotificationPresentationOptionBanner|UNNotificationPresentationOptionList|UNNotificationPresentationOptionSound);}
- (void)save {if(!self.state)return;self.state[@"updated"]=@(NSDate.date.timeIntervalSince1970);Write(@"state.json",self.state);}
- (void)append:(NSString *)kind text:(NSString *)text {
    if ([kind isEqual:@"Root 权限"] && [text hasPrefix:@"已始终允许"]) {
        self.state[@"root_preference_revision"]=NSUUID.UUID.UUIDString.lowercaseString;
        NSMutableDictionary *request=[self.request mutableCopy], *preferences=[request[@"preferences"] mutableCopy];
        preferences[@"rootEnabled"]=@YES; request[@"preferences"]=preferences; self.request=request;
        // Keep the overlay's next task from restoring the pre-grant preference snapshot.
        NSMutableDictionary *composer=[Read(@"composer.json") mutableCopy], *saved=[composer[@"preferences"] mutableCopy];
        if (saved) { saved[@"rootEnabled"]=@YES; composer[@"preferences"]=saved; Write(@"composer.json",composer); }
    }
    if([kind isEqual:PCSelectedAssistantName()])[self.state removeObjectForKey:@"streaming_text"];
    NSString *transcript=[self.state[@"transcript"]?:@"" stringByAppendingFormat:@"\n[%@]\n%@\n",kind,PCRedact(text?:@"")];if(transcript.length>120000)transcript=[transcript substringFromIndex:transcript.length-120000];self.state[@"transcript"]=transcript;self.state[@"revision"]=@([self.state[@"revision"] unsignedIntegerValue]+1);
    if(![@[@"状态",@"进度",@"工具请求",@"工具结果",@"用量",@"自动允许",@"错误",@"提示",@"提问",@"你",@"后台",@"Root 权限"] containsObject:kind])self.state[@"latest_reply"]=text?:@"";
    if([kind isEqual:@"工具请求"]&&[text hasPrefix:@"screen_"]){if(![self.state[@"screen_session"] boolValue])self.state[@"screen_started_at"]=@(NSDate.date.timeIntervalSince1970);self.state[@"screen_session"]=@YES;self.state[@"screen_action_until"]=@(NSDate.date.timeIntervalSince1970+8);}
    if([kind isEqual:@"工具结果"])self.state[@"screen_action_until"]=@0;
    self.state[@"history"]=[self.agent historySnapshot]?:@[];[self save];
}
- (void)question:(NSDictionary *)prompt reply:(void (^)(id))reply {
    NSMutableDictionary *question=[prompt mutableCopy];question[@"id"]=NSUUID.UUID.UUIDString.lowercaseString;self.state[@"question"]=question;self.pendingReply=reply;self.state[@"status"]=@"等待你回答";[self append:@"提问" text:question[@"text"]?:question[@"name"]];
    [self notifyIfBackground];
}
- (void)notifyIfBackground {
    NSDictionary *question=self.state[@"question"];if(!question||[self.state[@"notified_question"] isEqual:question[@"id"]])return;
    NSDictionary *foreground=Read(@"foreground.json");BOOL visible=[foreground[@"active"] boolValue]&&NSDate.date.timeIntervalSince1970-[foreground[@"updated"] doubleValue]<5;if(visible)return;
    double now=NSDate.date.timeIntervalSince1970;if(now-[self.state[@"notification_check_at"] doubleValue]<3)return;self.state[@"notification_check_at"]=@(now);NSString *job=self.state[@"id"];
    UNUserNotificationCenter *center=PCNotificationCenter();center.delegate=self;
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){dispatch_async(dispatch_get_main_queue(),^{if(![self.state[@"id"] isEqual:job]||![self.state[@"question"][@"id"] isEqual:question[@"id"]])return;
        self.state[@"notification_settings"]=@{@"authorization":@(settings.authorizationStatus),@"alert":@(settings.alertSetting),@"center":@(settings.notificationCenterSetting)};
        if(settings.authorizationStatus!=UNAuthorizationStatusAuthorized&&settings.authorizationStatus!=UNAuthorizationStatusProvisional){[self save];return;}
        self.state[@"notified_question"]=question[@"id"];UNMutableNotificationContent *content=[UNMutableNotificationContent new];content.title=PCLocalized(@"AsterHand 需要你回答");NSString *body=question[@"text"];content.body=body?([@[@"root_permission",@"approval"] containsObject:question[@"kind"]]?PCLocalized(body):body):PCLocalized(@"有一项操作等待确认");content.sound=UNNotificationSound.defaultSound;content.userInfo=@{@"job":job};UNNotificationRequest *notification=[UNNotificationRequest requestWithIdentifier:question[@"id"] content:content trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO]];
        [center addNotificationRequest:notification withCompletionHandler:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{if(![self.state[@"id"] isEqual:job])return;if(error)self.state[@"notification_error"]=error.localizedDescription;else self.state[@"notification_submitted"]=question[@"id"];[self save];});}];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{[center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications){BOOL delivered=NO;for(UNNotification *item in notifications)if([item.request.identifier isEqual:question[@"id"]])delivered=YES;dispatch_async(dispatch_get_main_queue(),^{if([self.state[@"id"] isEqual:job]){self.state[@"notification_delivered"]=@(delivered);[self save];}});}];});
    });}];
}

- (void)start:(NSDictionary *)request {
    self.receivedMessages=[NSMutableSet new];self.request=request;self.agent=[PCAgent new];self.agent.workspace=request[@"workspace"];NSMutableDictionary *preferences=[request[@"preferences"] mutableCopy]?:[NSMutableDictionary new];preferences[@"agentTaskID"]=request[@"id"];[NSUserDefaults.standardUserDefaults setVolatileDomain:preferences forName:NSArgumentDomain];[self.agent restoreHistory:request[@"history"]?:@[]];
    self.state=[@{@"id":request[@"id"],@"running":@YES,@"paused":@NO,@"failed":@NO,@"cancelled":@NO,@"revision":@1,@"history":request[@"history"]?:@[],@"context":request[@"context"]?:@{},@"transcript":request[@"context"][@"transcript"]?:@"",@"status":@"正在连接 AI…",@"assistant_name":PCSelectedAssistantName()} mutableCopy];
    self.credentialsAvailable=PCChatGPTCredentials()!=nil;
    __weak typeof(self) weakSelf=self;self.agent.event=^(NSString *kind,NSString *text){if([kind isEqual:@"流式回复"]){weakSelf.state[@"streaming_text"]=text;weakSelf.state[@"latest_reply"]=text;weakSelf.state[@"revision"]=@([weakSelf.state[@"revision"] unsignedIntegerValue]+1);[weakSelf save];}else if([kind isEqual:@"状态"]){weakSelf.state[@"status"]=text;weakSelf.state[@"revision"]=@([weakSelf.state[@"revision"] unsignedIntegerValue]+1);[weakSelf save];}else[weakSelf append:kind text:text];};
    self.agent.approval=^(NSString *name,NSDictionary *args,void(^reply)(BOOL)){[weakSelf question:@{@"kind":@"approval",@"name":name,@"arguments":args,@"text":[NSString stringWithFormat:@"允许执行 %@？",name],@"options":@[@"允许",@"拒绝"]} reply:^(id value){reply([value isKindOfClass:NSNumber.class]?[value boolValue]:[value isEqual:@"允许"]);}];};
    self.agent.question=^(NSString *text,NSArray *options,void(^reply)(NSString *)){[weakSelf question:@{@"kind":@"question",@"text":text,@"options":options?:@[]} reply:^(id value){reply([value isKindOfClass:NSString.class]?value:@"");}];};
    self.agent.rootPermission=^(NSString *text,NSDictionary *operation,void(^reply)(NSString *)){
        NSMutableDictionary *prompt=[operation mutableCopy]; prompt[@"kind"]=@"root_permission"; prompt[@"text"]=text; prompt[@"options"]=PCRootPermissionOptions();
        [weakSelf question:prompt reply:^(id value){reply(PCRootPermissionAnswerValid(value)?value:@"不允许");}];
    };
    self.agent.finished=^{PCAgentWorker *worker=weakSelf;worker.state[@"running"]=@NO;worker.state[@"failed"]=@(worker.agent.failed);worker.state[@"cancelled"]=@(worker.agent.cancelled);worker.state[@"history"]=[worker.agent historySnapshot];worker.state[@"status"]=worker.agent.failed?@"任务失败":worker.agent.cancelled?@"已停止":@"任务完成";[worker.state removeObjectForKey:@"question"];worker.pendingReply=nil;worker.state[@"revision"]=@([worker.state[@"revision"] unsignedIntegerValue]+1);[worker save];
        if([worker.state[@"screen_session"] boolValue])PCScreenRequest(@{@"action":@"clipboard_restore",@"clipboard_owner":worker.request[@"id"]});
        NSMutableDictionary *composer=[Read(@"composer.json") mutableCopy];if([composer[@"context"][@"chat"] isEqual:worker.request[@"context"][@"chat"]]){composer[@"history"]=worker.state[@"history"]?:@[];NSMutableDictionary *updated=[composer[@"context"] mutableCopy];updated[@"transcript"]=worker.state[@"transcript"]?:@"";composer[@"context"]=updated;Write(@"composer.json",composer);}
        NSDictionary *context=worker.request[@"context"];if([context[@"storage"] isKindOfClass:NSString.class]&&context[@"project"]&&context[@"chat"]){PCProjectStore *store=[[PCProjectStore alloc] initWithStoragePath:context[@"storage"]];if([store selectProject:context[@"project"]]&&[store selectChat:context[@"chat"]])[store saveHistory:[worker.agent historySnapshot] transcript:worker.state[@"transcript"]];}
    };
    [self append:@"你" text:request[@"message"]];[self.agent send:request[@"message"] attachments:request[@"attachments"]?:@[]];[self save];
}
- (void)receiveMessages {
    for(NSDictionary *message in PCMessagePending(PCAgentTaskDirectory())){
        NSString *error=nil,*identifier=message[@"id"],*text=message[@"text"],*job=message[@"job"];
        NSDictionary *old=PCMessageReceipt(PCAgentTaskDirectory(),identifier);if(old){PCMessageAcknowledge(PCAgentTaskDirectory(),message,old[@"status"],old[@"detail"]);continue;}
        if(![text isKindOfClass:NSString.class]||!text.length||text.length>4000||![job isKindOfClass:NSString.class])error=@"消息格式无效";
        else if(fabs(NSDate.date.timeIntervalSince1970-[message[@"created"] doubleValue])>120)error=@"消息已过期，请重新发送";
        else if(job.length){
            if(![job isEqual:self.state[@"id"]])error=@"任务已切换，请重新发送";
            else if([self.receivedMessages containsObject:identifier]){}
            else if([self.agent enqueueMessage:text])[self.receivedMessages addObject:identifier];
            else error=@"本轮任务已结束，请重新发送以继续";
        }else if([identifier isEqual:self.state[@"id"]])error=@"该消息已启动过，请检查结果后继续";
        else if(self.agent.running)error=@"已有任务运行，请重新发送到当前任务";
        else{
            NSMutableDictionary *request=[Read(@"composer.json") mutableCopy];NSDictionary *context=message[@"context"];
            if(![context[@"chat"] isEqual:request[@"context"][@"chat"]]||![context[@"project"] isEqual:request[@"context"][@"project"]])error=@"对话已切换，请在应用中确认后重试";
            else if(![request[@"preferences"] isKindOfClass:NSDictionary.class])error=@"请先打开应用并配置 AI";
            else{request[@"id"]=identifier;request[@"message"]=text;request[@"attachments"]=@[];request[@"created"]=@(NSDate.date.timeIntervalSince1970);Write(@"request.json",request);[self start:request];}
        }
        PCMessageAcknowledge(PCAgentTaskDirectory(),message,error?@"error":@"accepted",error?:@"消息已加入当前对话");
    }
}
- (void)tick {
    Write(@"service.json",@{@"pid":@(getpid()),@"updated":@(NSDate.date.timeIntervalSince1970),@"chatgpt_credentials":@(self.credentialsAvailable)});
    NSDictionary *request=Read(@"request.json");if(!self.agent.running&&![request[@"cancelled"] boolValue]&&[request[@"id"] isKindOfClass:NSString.class]&&![request[@"id"] isEqual:self.state[@"id"]]){[self start:request];return;}
    [self receiveMessages];if(!self.agent.running)return;[self notifyIfBackground];NSDictionary *command=Read(@"command.json");if([command[@"job"] isEqual:self.state[@"id"]]&&![command[@"id"] isEqual:self.lastCommand]){self.lastCommand=command[@"id"];if([command[@"command"] isEqual:@"stop"]){[self.agent stop];if(self.pendingReply){self.pendingReply(@NO);self.pendingReply=nil;}}else if([command[@"command"] isEqual:@"pause"])[self.agent pause];else if([command[@"command"] isEqual:@"resume"])[self.agent resume];}
    self.state[@"paused"]=@(self.agent.paused);NSDictionary *reply=Read(@"reply.json");if(self.pendingReply&&[reply[@"job"] isEqual:self.state[@"id"]]&&[reply[@"prompt"] isEqual:self.state[@"question"][@"id"]]){
        BOOL root=[self.state[@"question"][@"kind"] isEqual:@"root_permission"];
        if (!root || PCRootPermissionAnswerValid(reply[@"value"])) {void(^complete)(id)=self.pendingReply;self.pendingReply=nil;[self.state removeObjectForKey:@"question"];if([reply[@"value"] isKindOfClass:NSString.class])[self append:@"你" text:reply[@"value"]];complete(reply[@"value"]);}
    }
    [self save];
}
@end
int PCRunAgentDaemon(void) {
    signal(SIGPIPE,SIG_IGN);PCAgentWorker *worker=[PCAgentWorker new];worker.state=[PCAgentTaskState() mutableCopy];
    if([worker.state[@"running"] boolValue]){worker.state[@"running"]=@NO;worker.state[@"failed"]=@YES;[worker.state removeObjectForKey:@"question"];worker.state[@"status"]=@"服务重启，任务已中断；请检查结果后继续";NSMutableArray *history=[worker.state[@"history"] mutableCopy]?:[NSMutableArray new];NSMutableSet *completed=[NSMutableSet new];for(NSDictionary *item in history)if([item[@"type"] isEqual:@"function_call_output"]&&item[@"call_id"])[completed addObject:item[@"call_id"]];for(NSDictionary *item in [history copy])if([item[@"type"] isEqual:@"function_call"]&&item[@"call_id"]&&![completed containsObject:item[@"call_id"]])[history addObject:@{@"type":@"function_call_output",@"call_id":item[@"call_id"],@"output":@"{\"error\":\"Service restarted; operation outcome unknown. Inspect effects before retrying.\"}"}];worker.state[@"history"]=history;worker.state[@"revision"]=@([worker.state[@"revision"] unsignedIntegerValue]+1);[worker save];}
    static dispatch_source_t timer;timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());dispatch_source_set_timer(timer,DISPATCH_TIME_NOW,NSEC_PER_SEC/2,NSEC_PER_MSEC*50);dispatch_source_set_event_handler(timer,^{@autoreleasepool{[worker tick];}});dispatch_resume(timer);dispatch_main();return 0;
}
