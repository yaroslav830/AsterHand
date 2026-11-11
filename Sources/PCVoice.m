#import "PCLocalization.h"
#import "PCButtonCompat.h"
#import "PCVoice.h"
#import "PCPages.h"
#import "PCHaptics.h"
#import "PCPlatform.h"
#import "PCMemoryBudget.h"
#import "PCVoiceIdle.h"
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <Intents/Intents.h>
#import <IntentsUI/IntentsUI.h>
#import <CallKit/CallKit.h>
#include <stdatomic.h>
#include <math.h>
#include <sys/stat.h>

NSString * const PCVoiceActionNotification=@"AsterHandVoiceAction";
static NSString * const ActivityPrefix=@"local.asterhand.shortcut.";
static NSString * const VoicePreferencesChanged=@"AsterHandVoicePreferencesChanged";
BOOL PCVoiceActionValid(NSString *action){return [@[@"voice",@"status",@"open"] containsObject:action];}
static NSString *VoiceLocale(void){NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:@"voiceLocale"];if([@[@"zh-CN",@"en-US"] containsObject:saved])return saved;return [NSLocale.preferredLanguages.firstObject hasPrefix:@"zh"]?@"zh-CN":@"en-US";}
static double VoiceIdleTimeout(void){NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;double saved=[defaults doubleForKey:@"voiceIdleTimeoutSeconds"],seconds=PCVoiceIdleConfiguredLimit(saved);if(![defaults objectForKey:@"voiceIdleTimeoutSeconds"]||saved!=seconds)[defaults setDouble:seconds forKey:@"voiceIdleTimeoutSeconds"];return seconds;}
NSUserActivity *PCVoiceShortcutActivity(NSString *action){
    if(!PCVoiceActionValid(action))return nil;
    NSUserActivity *activity=[[NSUserActivity alloc] initWithActivityType:[ActivityPrefix stringByAppendingString:action]];
    activity.title=PCLocalized(@{@"voice":@"与 AsterHand 连续对话",@"status":@"朗读 AsterHand 任务状态",@"open":@"打开 AsterHand"}[action]);
    activity.userInfo=@{@"action":action};activity.eligibleForSearch=YES;activity.eligibleForPrediction=YES;activity.eligibleForHandoff=NO;
    activity.persistentIdentifier=activity.activityType;
    activity.suggestedInvocationPhrase=PCLocalized(@{@"voice":@"和星手对话",@"status":@"星手任务进度",@"open":@"打开星手"}[action]);return activity;
}
NSDictionary *PCVoiceCapabilities(void){
    SFSpeechRecognizer *recognizer=[[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:VoiceLocale()]];
    return @{@"locale":VoiceLocale(),@"speech_authorization":@([SFSpeechRecognizer authorizationStatus]),@"microphone_authorization":@(AVAudioSession.sharedInstance.recordPermission),@"recognizer_available":@(recognizer.available),@"on_device_recognition":@(recognizer.supportsOnDeviceRecognition),@"siri_authorization":@([INPreferences siriAuthorizationStatus])};
}
BOOL PCVoiceFloatingLaunchValid(NSString *requestID){
    if(![[NSUUID alloc] initWithUUIDString:requestID?:@""])return NO;
    NSData *data=[NSData dataWithContentsOfFile:PCRealPath(@"/var/mobile/Library/PocketAgentControl/voice-command.json")];if(data.length>4096)return NO;
    NSDictionary *command=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    return [command isKindOfClass:NSDictionary.class]&&[command[@"action"] isEqual:@"start"]&&[command[@"id"] isEqual:requestID]&&fabs(NSDate.date.timeIntervalSince1970-[command[@"created"] doubleValue])<30;
}
@interface PCVoiceAudioSink : NSObject
@property(atomic,strong) SFSpeechAudioBufferRecognitionRequest *request;
@property(atomic) BOOL muted;
@end
@implementation PCVoiceAudioSink
@end
@interface PCVoiceSession () <AVSpeechSynthesizerDelegate,CXProviderDelegate> {
    _Atomic(double) _lastSound;
    BOOL _microphoneMuted,_speechMuted;
    PCVoiceIdleClock _idleClock;
}
@property(nonatomic,readwrite) BOOL active,listening;
@property(nonatomic,readwrite,copy) NSString *phase,*detail,*transcript,*spokenText;
@property(nonatomic,strong) AVAudioEngine *engine;
@property(nonatomic,strong) SFSpeechRecognizer *recognizer;
@property(nonatomic,strong) SFSpeechAudioBufferRecognitionRequest *request;
@property(nonatomic,strong) SFSpeechRecognitionTask *recognition;
@property(nonatomic,strong) AVSpeechSynthesizer *synth;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) NSTimer *idleTimer;
@property(nonatomic) BOOL idleWaitingForUser;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSTimeInterval started,lastText;
@property(nonatomic) BOOL tapInstalled,resumeAfterSpeech,waiting,restoreIdleTimer,idleTimerWasDisabled;
@property(nonatomic,strong) AVSpeechUtterance *utterance;
@property(nonatomic,copy) NSString *lastDiagnostic;
@property(nonatomic,readwrite,copy) NSString *controlSessionID;
@property(nonatomic,strong) PCVoiceAudioSink *audioSink;
@property(nonatomic) NSTimeInterval lastStatusWrite;
@property(nonatomic,strong) CXProvider *callProvider;
@property(nonatomic,strong) CXCallController *callController;
@property(nonatomic,strong) NSUUID *callID;
@property(nonatomic) BOOL callAudioActive;
@property(nonatomic) BOOL callStarted;
@property(nonatomic) BOOL confirmationBlocked;
@end
@implementation PCVoiceSession
- (instancetype)init {if((self=[super init])){_phase=@"未开始";_detail=@"说完自动发送，回复后继续聆听";_transcript=@"";_microphoneMuted=[NSUserDefaults.standardUserDefaults boolForKey:@"voiceMicrophoneMuted"];_speechMuted=[NSUserDefaults.standardUserDefaults objectForKey:@"voiceAutoRead"]&&![NSUserDefaults.standardUserDefaults boolForKey:@"voiceAutoRead"];_synth=[AVSpeechSynthesizer new];_synth.delegate=self;[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupted:) name:AVAudioSessionInterruptionNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(preferencesChanged:) name:VoicePreferencesChanged object:nil];}return self;}
- (BOOL)microphoneMuted {return _microphoneMuted;}
- (void)setMicrophoneMuted:(BOOL)muted {[self applyMicrophoneMute:muted notifySystem:YES];}
- (void)applyMicrophoneMute:(BOOL)muted notifySystem:(BOOL)notifySystem {
    if(_microphoneMuted==muted)return;_microphoneMuted=muted;[NSUserDefaults.standardUserDefaults setBool:muted forKey:@"voiceMicrophoneMuted"];self.audioSink.muted=muted;
    if(muted&&self.listening){[self endCapture];self.transcript=@"";[self releaseAudio];[self setPhaseText:@"麦克风已静音" detail:@"恢复麦克风后继续聆听"];}else if(!muted&&self.active&&!self.waiting&&!self.speaking&&!self.confirmationBlocked)[self listen];
    if(notifySystem&&self.callID&&self.callAudioActive){CXSetMutedCallAction *action=[[CXSetMutedCallAction alloc] initWithCallUUID:self.callID muted:muted];[self.callController requestTransaction:[[CXTransaction alloc] initWithAction:action] completion:^(NSError *error){if(error)NSLog(@"AsterHand voice system mute: %@ / %ld",error.domain,(long)error.code);}];}
    [self notify];
}
- (BOOL)speechMuted {return _speechMuted;}
- (void)setSpeechMuted:(BOOL)muted {
    if(_speechMuted==muted)return;_speechMuted=muted;[NSUserDefaults.standardUserDefaults setBool:!muted forKey:@"voiceAutoRead"];
    if(muted&&self.speaking){BOOL resume=self.resumeAfterSpeech;self.resumeAfterSpeech=NO;self.utterance=nil;[self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];[self releaseAudio];if(resume&&self.active)[self listen];else[self setPhaseText:self.active?@"等待确认":@"朗读已静音" detail:self.active?@"请在聊天页面选择操作":@""];}
    [self notify];
}
- (void)preferencesChanged:(NSNotification *)note {self.microphoneMuted=[NSUserDefaults.standardUserDefaults boolForKey:@"voiceMicrophoneMuted"];self.speechMuted=[NSUserDefaults.standardUserDefaults objectForKey:@"voiceAutoRead"]&&![NSUserDefaults.standardUserDefaults boolForKey:@"voiceAutoRead"];}
- (void)idleWaiting:(BOOL)waiting {
    self.idleWaitingForUser=waiting;PCVoiceIdleTick(&_idleClock,NSProcessInfo.processInfo.systemUptime,VoiceIdleTimeout(),self.active&&waiting,0);
}
- (void)receivedVoiceInput {PCVoiceIdleTick(&_idleClock,NSProcessInfo.processInfo.systemUptime,VoiceIdleTimeout(),self.active&&self.idleWaitingForUser,1);}
- (void)checkIdleTimeout {
    if(!self.active)return;
    BOOL waiting=self.idleWaitingForUser&&!self.waiting&&!self.speaking&&!self.confirmationBlocked;
    if(PCVoiceIdleTick(&_idleClock,NSProcessInfo.processInfo.systemUptime,VoiceIdleTimeout(),waiting,0)){
        NSInteger seconds=(NSInteger)VoiceIdleTimeout();[self stop];[self setPhaseText:@"语音已自动结束" detail:[NSString stringWithFormat:@"连续 %ld 秒没有听到你的回应，已结束语音；AI 任务不受影响。",(long)seconds]];
    }
}
- (BOOL)speaking{return self.synth.speaking;}
- (void)notify {
    NSString *key=[NSString stringWithFormat:@"%d/%d/%d/%d/%d/%@",self.active,self.listening,self.speaking,self.microphoneMuted,self.speechMuted,self.phase];NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if(![key isEqual:self.lastDiagnostic]||(self.active&&now-self.lastStatusWrite>.45)){self.lastDiagnostic=key;self.lastStatusWrite=now;NSString *(^clip)(NSString *)=^NSString *(NSString *text){return text.length>400?[text substringToIndex:400]:text?:@"";};NSDictionary *state=@{@"updated":@(now),@"active":@(self.active),@"listening":@(self.listening),@"speaking":@(self.speaking),@"microphone_muted":@(self.microphoneMuted),@"speech_muted":@(self.speechMuted),@"engine_running":@(self.engine.isRunning),@"input_tap_installed":@(self.tapInstalled),@"phase":self.phase?:@"",@"detail":clip(self.detail),@"floating":@(self.allowsBackground),@"session":self.controlSessionID?:@"",@"launch_request":self.launchRequestID?:@"",@"transcript":clip(self.transcript),@"reply":clip(self.spokenText)};NSString *path=PCRealPath(@"/var/mobile/Library/PocketAgentControl/voice-status.json");NSData *data=[NSJSONSerialization dataWithJSONObject:state options:0 error:nil];if(path&&[data writeToFile:path options:NSDataWritingAtomic error:nil])chmod(path.fileSystemRepresentation,0600);}
    if(self.changed)self.changed();
}
- (void)publishState {[self notify];}
- (void)setPhaseText:(NSString *)phase detail:(NSString *)detail {self.phase=phase;self.detail=detail?:@"";[self notify];}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];[self.timer invalidate];[self.idleTimer invalidate];[self.recognition cancel];[self.engine stop];if(self.tapInstalled)[self.engine.inputNode removeTapOnBus:0];}
- (void)endCapture {
    self.generation++;[self.timer invalidate];self.timer=nil;self.listening=NO;
    self.audioSink.request=nil;[self.request endAudio];[self.recognition cancel];self.recognition=nil;self.request=nil;
    // A floating conversation keeps a real microphone audio session alive.
    // Between turns the input is discarded, never saved or sent to the AI.
    if(!(self.active&&self.allowsBackground)){[self.engine stop];if(self.tapInstalled){[self.engine.inputNode removeTapOnBus:0];self.tapInstalled=NO;}self.engine=nil;self.audioSink=nil;}
}
- (void)releaseAudio {if(self.active&&self.allowsBackground)return;NSError *error=nil;[AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];}
- (void)restoreIdle {if(self.restoreIdleTimer){UIApplication.sharedApplication.idleTimerDisabled=self.idleTimerWasDisabled;self.restoreIdleTimer=NO;}}
- (void)stop {
    self.active=NO;self.waiting=NO;self.resumeAfterSpeech=NO;self.utterance=nil;[self.idleTimer invalidate];self.idleTimer=nil;[self idleWaiting:NO];[self endCapture];[self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    CXProvider *provider=self.callProvider;NSUUID *callID=self.callID;self.callProvider=nil;self.callID=nil;self.callController=nil;self.callAudioActive=NO;if(callID)[provider reportCallWithUUID:callID endedAtDate:NSDate.date reason:CXCallEndedReasonRemoteEnded];[provider invalidate];
    [self releaseAudio];[self restoreIdle];[self setPhaseText:@"语音已结束" detail:@"AI 任务可在聊天页面继续查看"];
}
- (void)fail:(NSString *)message {[self stop];[self setPhaseText:@"暂时无法使用语音" detail:message];PCHaptic(@"error");}
- (void)startAuthorizedAudio {BOOL waiting=self.waiting;if(waiting&&self.allowsBackground)[self listen];if(waiting)[self waitForAI];else[self listen];}
- (void)startFloatingCall {
    // CallKit supplies the visible system communication session needed to
    // start microphone input while another app stays in the foreground.
    CXProviderConfiguration *configuration=[[CXProviderConfiguration alloc] initWithLocalizedName:@"AsterHand"];configuration.supportsVideo=NO;configuration.maximumCallGroups=1;configuration.maximumCallsPerCallGroup=1;configuration.includesCallsInRecents=NO;configuration.supportedHandleTypes=[NSSet setWithObject:@(CXHandleTypeGeneric)];
    self.callProvider=[[CXProvider alloc] initWithConfiguration:configuration];[self.callProvider setDelegate:self queue:dispatch_get_main_queue()];self.callController=[CXCallController new];self.callID=NSUUID.UUID;self.callAudioActive=NO;self.callStarted=NO;
    NSUUID *callID=self.callID;NSUInteger generation=self.generation;CXStartCallAction *action=[[CXStartCallAction alloc] initWithCallUUID:callID handle:[[CXHandle alloc] initWithType:CXHandleTypeGeneric value:@"AsterHand AI"]];
    [self setPhaseText:@"连接语音" detail:@"正在启动系统语音会话"];__weak typeof(self) weakSelf=self;
    [self.callController requestTransaction:[[CXTransaction alloc] initWithAction:action] completion:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{PCVoiceSession *s=weakSelf;if(error&&s.active&&s.generation==generation&&[s.callID isEqual:callID])[s fail:[NSString stringWithFormat:@"系统语音会话无法启动：%@ (%@ / %ld)",error.localizedDescription,error.domain,(long)error.code]];});}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{PCVoiceSession *s=weakSelf;if(s.active&&s.generation==generation&&[s.callID isEqual:callID]&&!s.callAudioActive)[s fail:@"系统未激活语音会话，请稍后重试或在应用内开始语音。"];});
}
- (void)providerDidReset:(CXProvider *)provider {if(provider==self.callProvider&&self.active&&self.callStarted)[self fail:@"系统语音会话已结束，请重新开始语音。"];}
- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action {
    if(provider!=self.callProvider||!self.active||![action.callUUID isEqual:self.callID]){[action fail];return;}
    self.callStarted=YES;
    NSError *error=nil;if(![AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeVoiceChat options:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionAllowBluetooth error:&error]){[action fail];[self fail:error.localizedDescription];return;}
    [provider reportOutgoingCallWithUUID:self.callID startedConnectingAtDate:NSDate.date];[action fulfill];[provider reportOutgoingCallWithUUID:self.callID connectedAtDate:NSDate.date];
}
- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audio {if(provider!=self.callProvider||!self.active)return;self.callAudioActive=YES;[self startAuthorizedAudio];if(self.microphoneMuted){CXSetMutedCallAction *action=[[CXSetMutedCallAction alloc] initWithCallUUID:self.callID muted:YES];[self.callController requestTransaction:[[CXTransaction alloc] initWithAction:action] completion:^(NSError *error){}];}}
- (void)provider:(CXProvider *)provider performSetMutedCallAction:(CXSetMutedCallAction *)action {if(provider!=self.callProvider||![action.callUUID isEqual:self.callID]){[action fail];return;}[self applyMicrophoneMute:action.muted notifySystem:NO];[action fulfill];}
- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action {[action fulfill];if(provider==self.callProvider)[self stop];}
- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(AVAudioSession *)audio {if(provider==self.callProvider&&self.active)[self fail:@"系统已关闭语音音频，请重新开始。"];}
- (void)startWaiting:(BOOL)waiting {
    if(self.active)return;if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive&&!(self.allowsBackground&&AVAudioSession.sharedInstance.recordPermission==AVAudioSessionRecordPermissionGranted&&SFSpeechRecognizer.authorizationStatus==SFSpeechRecognizerAuthorizationStatusAuthorized)){[self setPhaseText:@"需要在应用中授权" detail:@"首次请在 AsterHand 中允许麦克风和语音识别，再从悬浮窗启动。"];return;}
    self.utterance=nil;self.resumeAfterSpeech=NO;self.confirmationBlocked=NO;[self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    self.active=YES;self.waiting=waiting;self.transcript=@"";self.spokenText=@"";self.generation++;NSUInteger generation=self.generation;
    _idleClock=(PCVoiceIdleClock){0};self.idleWaitingForUser=NO;__weak typeof(self) idleSelf=self;self.idleTimer=[NSTimer timerWithTimeInterval:.5 repeats:YES block:^(NSTimer *timer){PCVoiceSession *s=idleSelf;if(!s.active){[timer invalidate];return;}[s checkIdleTimeout];}];[NSRunLoop.mainRunLoop addTimer:self.idleTimer forMode:NSRunLoopCommonModes];
    self.controlSessionID=NSUUID.UUID.UUIDString.lowercaseString;
    if(self.allowsBackground&&!PCEnsureServiceMemoryBudget()){[self fail:@"无法启动悬浮语音的后台音频会话，请在应用内使用语音。"];return;}
    self.idleTimerWasDisabled=UIApplication.sharedApplication.idleTimerDisabled;self.restoreIdleTimer=YES;UIApplication.sharedApplication.idleTimerDisabled=YES;
    [self setPhaseText:@"准备语音" detail:@"检查麦克风与语音识别权限"];
    __weak typeof(self) weakSelf=self;
    void(^ready)(BOOL)=^(BOOL microphone){dispatch_async(dispatch_get_main_queue(),^{PCVoiceSession *s=weakSelf;if(!s.active||s.generation!=generation)return;if(!microphone){[s fail:@"麦克风权限未开启，请在系统设置中允许 AsterHand 使用麦克风。"];return;}
        void(^authorized)(SFSpeechRecognizerAuthorizationStatus)=^(SFSpeechRecognizerAuthorizationStatus status){dispatch_async(dispatch_get_main_queue(),^{PCVoiceSession *v=weakSelf;if(!v.active||v.generation!=generation)return;if(status!=SFSpeechRecognizerAuthorizationStatusAuthorized){[v fail:@"语音识别权限未开启，请在系统设置中允许语音识别。"];return;}if(v.allowsBackground)[v startFloatingCall];else[v startAuthorizedAudio];});};
        SFSpeechRecognizerAuthorizationStatus status=SFSpeechRecognizer.authorizationStatus;if(status==SFSpeechRecognizerAuthorizationStatusNotDetermined)[SFSpeechRecognizer requestAuthorization:authorized];else authorized(status);
    });};
    AVAudioSessionRecordPermission permission=AVAudioSession.sharedInstance.recordPermission;if(permission==AVAudioSessionRecordPermissionUndetermined)[AVAudioSession.sharedInstance requestRecordPermission:ready];else ready(permission==AVAudioSessionRecordPermissionGranted);
}
- (void)waitForAI {
    if(!self.active)return;self.waiting=YES;[self idleWaiting:NO];self.resumeAfterSpeech=NO;self.utterance=nil;[self endCapture];[self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];[self releaseAudio];[self setPhaseText:@"AI 正在处理" detail:@"回复完成后朗读，再继续聆听"];
}
- (void)listen {
    if(!self.active||(!self.allowsBackground&&UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)||(self.callID&&!self.callAudioActive))return;
    [self endCapture];self.waiting=NO;self.transcript=@"";self.started=NSProcessInfo.processInfo.systemUptime;self.lastText=self.started;atomic_store(&_lastSound,self.started);
    if(self.microphoneMuted){[self idleWaiting:YES];[self setPhaseText:@"麦克风已静音" detail:@"恢复麦克风后继续聆听"];return;}
    self.recognizer=[[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:VoiceLocale()]];
    if(!self.recognizer.available){[self fail:@"系统语音识别当前不可用，请检查网络或稍后重试。"];return;}
    NSError *error=nil;AVAudioSession *audio=AVAudioSession.sharedInstance;
    if(!self.callID&&(![audio setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeVoiceChat options:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionAllowBluetooth error:&error]||![audio setActive:YES error:&error])){[self fail:error.localizedDescription?:@"无法启动音频设备"];return;}
    if(!self.engine)self.engine=[AVAudioEngine new];AVAudioInputNode *input=self.engine.inputNode;AVAudioFormat *format=[input outputFormatForBus:0];if(format.sampleRate<=0||format.channelCount==0){[self fail:@"未找到可用麦克风"];return;}
    self.request=[SFSpeechAudioBufferRecognitionRequest new];self.request.shouldReportPartialResults=YES;self.request.taskHint=SFSpeechRecognitionTaskHintDictation;self.request.requiresOnDeviceRecognition=self.recognizer.supportsOnDeviceRecognition;
    SFSpeechAudioBufferRecognitionRequest *request=self.request;NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;
    if(!self.audioSink)self.audioSink=[PCVoiceAudioSink new];PCVoiceAudioSink *sink=self.audioSink;sink.muted=self.microphoneMuted;sink.request=request;
    @try {
        if(!self.tapInstalled){[input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer,AVAudioTime *time){
            if(sink.muted)return;SFSpeechAudioBufferRecognitionRequest *current=sink.request;if(!current)return;[current appendAudioPCMBuffer:buffer];PCVoiceSession *s=weakSelf;if(!s)return;float *samples=buffer.floatChannelData?buffer.floatChannelData[0]:NULL;double energy=0;if(samples&&buffer.frameLength){for(AVAudioFrameCount i=0;i<buffer.frameLength;i++)energy+=samples[i]*samples[i];if(energy/buffer.frameLength>.00006)atomic_store(&s->_lastSound,NSProcessInfo.processInfo.systemUptime);}
        }];self.tapInstalled=YES;}
        if(!self.engine.isRunning){[self.engine prepare];if(![self.engine startAndReturnError:&error]){[self fail:error.localizedDescription?:@"麦克风启动失败"];return;}}
        self.listening=YES;[self idleWaiting:YES];
        self.recognition=[self.recognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *result,NSError *failure){dispatch_async(dispatch_get_main_queue(),^{PCVoiceSession *s=weakSelf;if(!s.active||!s.listening||generation!=s.generation)return;NSString *text=result.bestTranscription.formattedString;if(text.length)[s receivedVoiceInput];if(text.length&&![text isEqual:s.transcript]){s.transcript=text;s.lastText=NSProcessInfo.processInfo.systemUptime;[s notify];}if(result.final&&s.transcript.length){[s submitUtterance];return;}if(failure){[s fail:failure.localizedDescription?:@"语音识别中断，请重试"];}});}];
    }@catch(NSException *exception){[self fail:exception.reason?:@"音频设备异常"];return;}
    self.timer=[NSTimer scheduledTimerWithTimeInterval:.2 repeats:YES block:^(NSTimer *timer){PCVoiceSession *s=weakSelf;if(!s.active||!s.listening){[timer invalidate];return;}NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;double pause=[NSUserDefaults.standardUserDefaults doubleForKey:@"voiceSilenceSeconds"];if(pause<1||pause>3)pause=1.5;if(s.transcript.length&&now-MAX(atomic_load(&s->_lastSound),s.lastText)>pause)[s submitUtterance];else if(now-s.started>50){if(s.transcript.length)[s submitUtterance];else[s listen];}}];
    [self setPhaseText:@"正在聆听" detail:self.request.requiresOnDeviceRecognition?@"本机识别 · 停顿后自动发送":@"Apple 系统识别 · 停顿后自动发送"];PCHaptic(@"select");
}
- (void)submitUtterance {
    if(!self.active||!self.listening||self.microphoneMuted)return;NSString *text=[self.transcript stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!text.length)return;
    [self waitForAI];self.transcript=text;BOOL sent=self.submitText?self.submitText(text):NO;
    if(!sent){[self fail:@"未发送：当前有草稿、任务或待确认操作，请返回聊天页面处理。"];return;}PCHaptic(@"impact");[self notify];
}
- (void)speak:(NSString *)text thenListen:(BOOL)listen {
    self.confirmationBlocked=self.active&&!listen;
    [self idleWaiting:NO];
    [self endCapture];self.waiting=NO;self.resumeAfterSpeech=listen&&self.active;self.utterance=nil;[self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    NSString *clean=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!clean.length){if(self.resumeAfterSpeech)[self listen];return;}
    self.spokenText=clean;
    if(self.speechMuted){self.resumeAfterSpeech=NO;[self releaseAudio];if(listen&&self.active)[self listen];else[self setPhaseText:self.active?@"等待确认":@"朗读已静音" detail:self.active?@"请在聊天页面选择操作":@""];return;}
    NSError *error=nil;AVAudioSession *audio=AVAudioSession.sharedInstance;if(!self.allowsBackground&&(![audio setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeSpokenAudio options:AVAudioSessionCategoryOptionDuckOthers error:&error]||![audio setActive:YES error:&error])){[self fail:error.localizedDescription?:@"无法播放语音"];return;}
    // Avoid reading enormous build logs aloud. The full reply remains in chat.
    if(clean.length>2400)clean=[[clean substringToIndex:2400] stringByAppendingString:@"。完整回复请在聊天页面查看。"];
    AVSpeechUtterance *utterance=[AVSpeechUtterance speechUtteranceWithString:clean];utterance.voice=[AVSpeechSynthesisVoice voiceWithLanguage:VoiceLocale()];utterance.rate=AVSpeechUtteranceDefaultSpeechRate;self.utterance=utterance;[self.synth speakUtterance:utterance];[self setPhaseText:@"正在朗读" detail:self.resumeAfterSpeech?@"朗读结束后自动继续聆听":@"可随时停止朗读"];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if(self.utterance!=utterance)return;self.utterance=nil;BOOL resume=self.resumeAfterSpeech;self.resumeAfterSpeech=NO;[self releaseAudio];
    if(resume&&self.active){NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;[self setPhaseText:@"准备聆听" detail:@"你可以继续说话"];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,450*NSEC_PER_MSEC),dispatch_get_main_queue(),^{PCVoiceSession *s=weakSelf;if(s.active&&s.generation==generation)[s listen];});}
    else [self setPhaseText:self.active?@"等待确认":@"朗读结束" detail:self.active?@"请在聊天页面选择操作":@""];
}
- (void)interruptAndListen {if(!self.active)return;self.resumeAfterSpeech=NO;self.utterance=nil;[self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];[self listen];}
- (void)blockForConfirmation:(NSString *)text {[self speak:text thenListen:NO];}
- (void)background:(NSNotification *)note {if(self.active&&self.allowsBackground){[self restoreIdle];[self notify];return;}if(self.active||self.speaking){[self stop];[self setPhaseText:@"语音已暂停" detail:@"切到后台已关闭麦克风，返回后可重新开始；AI 任务继续运行"];}}
- (void)interrupted:(NSNotification *)note {if(self.callID&&!self.callAudioActive)return;if([note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue]==AVAudioSessionInterruptionTypeBegan&&(self.active||self.speaking)){[self stop];[self setPhaseText:@"音频被中断" detail:@"通话或其他音频结束后，请重新开始语音"];}}
- (void)routeChanged:(NSNotification *)note {if([note.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue]==AVAudioSessionRouteChangeReasonOldDeviceUnavailable&&(self.active||self.speaking)){[self stop];[self setPhaseText:@"音频设备已断开" detail:@"检查耳机或麦克风后重新开始"];}}
@end

@interface PCVoiceController ()
@property(nonatomic,strong) UILabel *phaseLabel,*detailLabel;
@property(nonatomic,strong) UITextView *text;
@property(nonatomic,strong) UIButton *toggle,*submit,*interrupt,*muteMicrophone,*muteSpeech;
@end
@implementation PCVoiceController
- (UIButton *)button:(NSString *)title action:(SEL)action {UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];if(@available(iOS 15.0,*)){UIButtonConfiguration *style=UIButtonConfiguration.tintedButtonConfiguration;style.cornerStyle=UIButtonConfigurationCornerStyleCapsule;style.title=title;button.configuration=style;}else{PCStyleButton(button,PCButtonTinted);button.layer.cornerRadius=24;[button setTitle:title forState:UIControlStateNormal];}[button.heightAnchor constraintGreaterThanOrEqualToConstant:48].active=YES;[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return button;}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=PCLocalized(@"语音对话");self.view.backgroundColor=UIColor.systemBackgroundColor;self.view.tintColor=UIColor.labelColor;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Siri" style:UIBarButtonItemStylePlain target:self action:@selector(siri)];
    UIImageView *icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"waveform.circle.fill"]];icon.contentMode=UIViewContentModeScaleAspectFit;icon.tintColor=UIColor.labelColor;[icon.heightAnchor constraintEqualToConstant:72].active=YES;
    self.phaseLabel=[UILabel new];self.phaseLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];self.phaseLabel.textAlignment=NSTextAlignmentCenter;
    self.detailLabel=[UILabel new];self.detailLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];self.detailLabel.textColor=UIColor.secondaryLabelColor;self.detailLabel.numberOfLines=0;self.detailLabel.textAlignment=NSTextAlignmentCenter;
    self.text=[UITextView new];self.text.editable=NO;self.text.backgroundColor=UIColor.secondarySystemBackgroundColor;self.text.layer.cornerRadius=18;self.text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];self.text.textContainerInset=UIEdgeInsetsMake(16,12,16,12);[self.text.heightAnchor constraintEqualToConstant:MAX(120,MIN(220,CGRectGetHeight(UIScreen.mainScreen.bounds)*.22))].active=YES;
    self.toggle=[self button:PCLocalized(@"开始连续对话") action:@selector(toggleVoice)];self.submit=[self button:PCLocalized(@"发送这句话") action:@selector(submitVoice)];self.interrupt=[self button:PCLocalized(@"打断朗读，继续说话") action:@selector(interruptVoice)];UIButton *stop=[self button:PCLocalized(@"停止 AI 任务") action:@selector(stopTask)];
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[self.submit,stop]];row.spacing=10;row.distribution=UIStackViewDistributionFillEqually;
    self.muteMicrophone=[self button:PCLocalized(@"麦克风静音") action:@selector(muteMicrophoneVoice)];self.muteSpeech=[self button:PCLocalized(@"朗读静音") action:@selector(muteSpeechVoice)];UIStackView *muteRow=[[UIStackView alloc] initWithArrangedSubviews:@[self.muteMicrophone,self.muteSpeech]];muteRow.spacing=10;muteRow.distribution=UIStackViewDistributionFillEqually;
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[icon,self.phaseLabel,self.detailLabel,muteRow,self.text,self.toggle,self.interrupt,row]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];UILayoutGuide *g=self.view.safeAreaLayoutGuide,*content=scroll.contentLayoutGuide;[NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:g.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],[scroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],[stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],[stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]]];
    __weak typeof(self) weakSelf=self;self.session.changed=^{[weakSelf refresh];};[self refresh];
}
- (void)viewDidAppear:(BOOL)animated {[super viewDidAppear:animated];if(self.startOnAppearance){self.startOnAppearance=NO;[self.session startWaiting:self.AIIsRunning?self.AIIsRunning():NO];}}
- (void)viewWillDisappear:(BOOL)animated {[super viewWillDisappear:animated];if(!self.session.allowsBackground)[self.session stop];}
- (void)styleMute:(UIButton *)button microphone:(BOOL)microphone muted:(BOOL)muted {if(@available(iOS 15.0,*)){UIButtonConfiguration *style=button.configuration;style.title=microphone?(muted?PCLocalized(@"恢复麦克风"):PCLocalized(@"麦克风静音")):(muted?PCLocalized(@"恢复朗读"):PCLocalized(@"朗读静音"));style.image=[UIImage systemImageNamed:microphone?(muted?@"mic.slash.fill":@"mic.fill"):(muted?@"speaker.slash.fill":@"speaker.wave.2.fill")];style.imagePadding=5;style.baseForegroundColor=muted?UIColor.systemRedColor:UIColor.labelColor;button.configuration=style;}else{[button setTitle:microphone?(muted?PCLocalized(@"恢复麦克风"):PCLocalized(@"麦克风静音")):(muted?PCLocalized(@"恢复朗读"):PCLocalized(@"朗读静音")) forState:UIControlStateNormal];[button setImage:[UIImage systemImageNamed:microphone?(muted?@"mic.slash.fill":@"mic.fill"):(muted?@"speaker.slash.fill":@"speaker.wave.2.fill")] forState:UIControlStateNormal];button.tintColor=muted?UIColor.systemRedColor:UIColor.labelColor;[button setTitleColor:button.tintColor forState:UIControlStateNormal];}button.selected=muted;button.accessibilityValue=muted?PCLocalized(@"已静音"):PCLocalized(@"已开启");}
- (void)refresh {if(!self.isViewLoaded)return;self.phaseLabel.text=PCLocalized(self.session.phase);self.detailLabel.text=PCLocalized(self.session.detail);[self styleMute:self.muteMicrophone microphone:YES muted:self.session.microphoneMuted];[self styleMute:self.muteSpeech microphone:NO muted:self.session.speechMuted];[self.toggle setTitle:self.session.active?PCLocalized(@"结束语音对话"):self.session.speaking?PCLocalized(@"停止朗读"):PCLocalized(@"开始连续对话") forState:UIControlStateNormal];self.submit.enabled=self.session.listening&&self.session.transcript.length;self.interrupt.enabled=self.session.active&&self.session.speaking;self.text.text=[NSString stringWithFormat:@"%@%@%@",self.session.transcript.length?[PCLocalized(@"你：\n") stringByAppendingString:self.session.transcript]:@"",self.session.transcript.length&&self.session.spokenText.length?@"\n\n":@"",self.session.spokenText.length?[@"AI：\n" stringByAppendingString:self.session.spokenText]:self.session.transcript.length?@"":PCLocalized(@"说出你的问题或任务…")];}
- (void)muteMicrophoneVoice {self.session.microphoneMuted=!self.session.microphoneMuted;PCHaptic(@"select");}
- (void)muteSpeechVoice {self.session.speechMuted=!self.session.speechMuted;PCHaptic(@"select");}
- (void)toggleVoice {if(self.session.active||self.session.speaking)[self.session stop];else[self.session startWaiting:self.AIIsRunning?self.AIIsRunning():NO];}
- (void)submitVoice {[self.session submitUtterance];}
- (void)interruptVoice {[self.session interruptAndListen];}
- (void)stopTask {[self.session stop];if(self.stopAI)self.stopAI();}
- (void)siri {[self.navigationController pushViewController:[[PCVoiceSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
@end

@interface PCVoiceSettingsController () <INUIAddVoiceShortcutViewControllerDelegate>
@property(nonatomic,strong) NSArray *items;
@property(nonatomic,copy) NSString *message;
@end
@implementation PCVoiceSettingsController
- (void)viewDidLoad {[super viewDidLoad];self.title=PCLocalized(@"语音与 Siri");self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=60;self.view.tintColor=UIColor.labelColor;self.items=@[PCLocalized(@"开始连续语音对话"),PCLocalized(@"自动朗读回复"),PCLocalized(@"识别语言"),PCLocalized(@"停顿多久发送"),PCLocalized(@"无回应自动结束"),PCLocalized(@"添加「和星手对话」"),PCLocalized(@"添加「星手任务进度」"),PCLocalized(@"添加「打开星手」"),PCLocalized(@"系统权限设置")];NSMutableArray *suggestions=[NSMutableArray new];for(NSString *action in @[@"voice",@"status",@"open"])[suggestions addObject:[[INShortcut alloc] initWithUserActivity:PCVoiceShortcutActivity(action)]];[INVoiceShortcutCenter.sharedCenter setShortcutSuggestions:suggestions];}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.items.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.text=self.items[index.row];cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    if(index.row==0)cell.detailTextLabel.text=PCLocalized(@"说完发送 → AI 回复朗读 → 继续聆听");
    if(index.row==1){UISwitch *toggle=[UISwitch new];toggle.on=![NSUserDefaults.standardUserDefaults objectForKey:@"voiceAutoRead"]||[NSUserDefaults.standardUserDefaults boolForKey:@"voiceAutoRead"];[toggle addTarget:self action:@selector(readChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;cell.selectionStyle=UITableViewCellSelectionStyleNone;}
    if(index.row==2)cell.detailTextLabel.text=[VoiceLocale() hasPrefix:@"zh"]?PCLocalized(@"普通话"):@"English";
    if(index.row==3){double pause=[NSUserDefaults.standardUserDefaults doubleForKey:@"voiceSilenceSeconds"];cell.detailTextLabel.text=[NSString stringWithFormat:PCLocalized(@"%.1f 秒"),pause>=1?pause:1.5];}
    if(index.row==4)cell.detailTextLabel.text=[NSString stringWithFormat:PCLocalized(@"%.0f 秒"),VoiceIdleTimeout()];return cell;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{return self.message?:PCLocalized(@"Siri 快捷指令会打开 AsterHand，再开始语音或朗读任务状态。首次使用需要系统麦克风、语音识别授权。优先使用本机识别；系统不支持时由 Apple 处理语音。切到后台暂停收音，AI 任务不受影响。");}
- (void)readChanged:(UISwitch *)toggle {[NSUserDefaults.standardUserDefaults setBool:toggle.on forKey:@"voiceAutoRead"];[NSNotificationCenter.defaultCenter postNotificationName:VoicePreferencesChanged object:nil];PCHaptic(@"select");}
- (void)saveIdleTimeout:(double)seconds {[NSUserDefaults.standardUserDefaults setDouble:PCVoiceIdleLimit(seconds)>0?PCVoiceIdleLimit(seconds):5 forKey:@"voiceIdleTimeoutSeconds"];[NSNotificationCenter.defaultCenter postNotificationName:VoicePreferencesChanged object:nil];[self.tableView reloadData];[self.navigationController popToViewController:self animated:YES];}
- (void)idleTimeoutOptions {
    PCOptionsPage *page=[[PCOptionsPage alloc] initWithStyle:UITableViewStyleInsetGrouped];page.title=PCLocalized(@"无回应自动结束");page.explanation=PCLocalized(@"仅等待你说话时计时，识别到语音会重新计时；AI 处理、朗读或等待确认时暂停。麦克风静音期间仍计时。默认 5 秒，可自定义 1～3600 秒。");
    NSArray *values=@[@5,@10,@15],*titles=@[PCLocalized(@"5 秒"),PCLocalized(@"10 秒"),PCLocalized(@"15 秒"),PCLocalized(@"自定义")];NSMutableArray *options=[NSMutableArray new];double current=VoiceIdleTimeout();
    for(NSUInteger i=0;i<titles.count;i++)[options addObject:@{@"title":titles[i],@"selected":@(i<values.count?current==[values[i] doubleValue]:current>0&&![values containsObject:@(current)])}];page.options=options;
    __weak typeof(self) weakSelf=self;page.selectOption=^(NSInteger selected){if(selected<3){[weakSelf saveIdleTimeout:[values[selected] doubleValue]];return;}
        PCTextEntryPage *input=[PCTextEntryPage new];input.title=PCLocalized(@"自定义秒数");input.submitTitle=PCLocalized(@"保存");input.fieldPlaceholder=PCLocalized(@"1～3600 秒");input.initialText=[NSString stringWithFormat:@"%.0f",VoiceIdleTimeout()];input.numeric=YES;__weak PCTextEntryPage *weakInput=input;
        input.submit=^(NSString *text){BOOL digits=[[NSPredicate predicateWithFormat:@"SELF MATCHES %@",@"[0-9]{1,4}"] evaluateWithObject:text];NSInteger seconds=text.integerValue;if(!digits||seconds<1||seconds>3600){weakInput.navigationItem.prompt=PCLocalized(@"请输入 1～3600 秒");return;}[weakSelf saveIdleTimeout:seconds];};[weakSelf.navigationController pushViewController:input animated:YES];};[self.navigationController pushViewController:page animated:YES];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {[tableView deselectRowAtIndexPath:index animated:YES];if(index.row==0){[NSNotificationCenter.defaultCenter postNotificationName:PCVoiceActionNotification object:@"voice"];return;}if(index.row==1)return;
    if(index.row==2||index.row==3){PCOptionsPage *page=[[PCOptionsPage alloc] initWithStyle:UITableViewStyleInsetGrouped];page.title=index.row==2?PCLocalized(@"识别语言"):PCLocalized(@"停顿后发送");NSArray *values=index.row==2?@[@"zh-CN",@"en-US"]:@[@1.0,@1.5,@2.0,@3.0];NSArray *titles=index.row==2?@[PCLocalized(@"普通话"),@"English"]:@[PCLocalized(@"1 秒"),PCLocalized(@"1.5 秒"),PCLocalized(@"2 秒"),PCLocalized(@"3 秒")];NSMutableArray *options=[NSMutableArray new];for(NSString *title in titles)[options addObject:@{@"title":title}];page.options=options;__weak typeof(self) weakSelf=self;page.selectOption=^(NSInteger selected){[NSUserDefaults.standardUserDefaults setObject:values[selected] forKey:index.row==2?@"voiceLocale":@"voiceSilenceSeconds"];[weakSelf.tableView reloadData];[weakSelf.navigationController popToViewController:weakSelf animated:YES];};[self.navigationController pushViewController:page animated:YES];return;}
    if(index.row==4){[self idleTimeoutOptions];return;}
    if(index.row==8){[UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];return;}
    [self addShortcut:@[@"voice",@"status",@"open"][index.row-5]];
}
- (void)addShortcut:(NSString *)action {
    __weak typeof(self) weakSelf=self;void(^show)(INSiriAuthorizationStatus)=^(INSiriAuthorizationStatus status){dispatch_async(dispatch_get_main_queue(),^{PCVoiceSettingsController *s=weakSelf;if(!s.view.window)return;if(status!=INSiriAuthorizationStatusAuthorized){s.message=PCLocalized(@"Siri 权限未开启，可到系统权限设置中开启后再添加。");[s.tableView reloadData];return;}INShortcut *shortcut=[[INShortcut alloc] initWithUserActivity:PCVoiceShortcutActivity(action)];INUIAddVoiceShortcutViewController *add=[[INUIAddVoiceShortcutViewController alloc] initWithShortcut:shortcut];add.delegate=s;[s presentViewController:add animated:YES completion:nil];});};
    INSiriAuthorizationStatus status=INPreferences.siriAuthorizationStatus;if(status==INSiriAuthorizationStatusNotDetermined)[INPreferences requestSiriAuthorization:show];else show(status);
}
- (void)addVoiceShortcutViewController:(INUIAddVoiceShortcutViewController *)controller didFinishWithVoiceShortcut:(INVoiceShortcut *)shortcut error:(NSError *)error {self.message=error.localizedDescription?:(shortcut?PCLocalized(@"已添加。可以用你设置的名称呼叫 Siri。"):PCLocalized(@"快捷指令未添加，请重试。"));[controller dismissViewControllerAnimated:YES completion:^{[self.tableView reloadData];}];}
- (void)addVoiceShortcutViewControllerDidCancel:(INUIAddVoiceShortcutViewController *)controller {[controller dismissViewControllerAnimated:YES completion:nil];}
@end
