#import "PCLocalization.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "PCRuntimePaths.h"
#import "PCMessageQueue.h"
#import "PCOverlayLayout.h"
#import "PCEdgeGeometry.h"
#import "PCHaptics.h"
#import "PCSystemScreenGeometry.h"
#import "PCScreenEdgeMask.h"
#include <sys/stat.h>
#include <unistd.h>
#include <float.h>
#include <dlfcn.h>
#include <notify.h>
#include <sys/utsname.h>
#import <objc/message.h>
@interface NSObject (AsterHandKeyboardRuntime)
+ (id)sharedInstance;
- (void)setAutomaticMinimizationEnabled:(BOOL)value;
- (void)showKeyboard;
- (void)hideKeyboard;
- (void)updateLayoutToCurrentInterfaceOrientation;
- (void)_setRotatableViewOrientation:(UIInterfaceOrientation)orientation updateStatusBar:(BOOL)update duration:(double)duration force:(BOOL)force;
@end
@interface NSObject (AsterHandOrientationRuntime)
- (long long)activeInterfaceOrientation;
- (void)setHandler:(id)handler;
@end
@interface PCAsterOverlayController : UIViewController
@end
static UIInterfaceOrientation gOrientation=UIInterfaceOrientationPortrait;
@implementation PCAsterOverlayController
- (BOOL)shouldAutorotate {return NO;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {return UIInterfaceOrientationMaskPortrait;}
@end
@interface NSObject (AsterHandVoiceWake)
+ (id)targetWithPid:(pid_t)pid;
+ (id)attributeWithReason:(uint64_t)reason flags:(uint64_t)flags;
- (id)initWithExplanation:(NSString *)explanation target:(id)target attributes:(NSArray *)attributes;
- (BOOL)acquireWithError:(NSError **)error;
- (void)invalidate;
- (BOOL)valid;
@end

// Controls hosted by a separate ARM64 UIKit process.
static id gController;
static UIWindow *gWindow;
static UIView *gContentView;
static UIView *gFullInfoView;
static id gOrientationObserver;
static UIButton *gBubble, *gPauseButton, *gStopButton;
static UIView *gPanel;
static UIVisualEffectView *gPanelMaterial;
static UIView *gVoiceCard;
static UIView *gPanelViewport,*gPanelContent,*gPanelScrollThumb;
static UIPanGestureRecognizer *gPanelScrollPan;
static CGFloat gPanelScrollOffset,gPanelContentHeight,gPanelScrollStart;
static int gPanelSide;
static BOOL gDraggingBubble,gEnsureAnswerVisible;
static CGRect gDragBubbleStart;
static UIButton *gCapsule;
static CALayer *gCapsuleVoiceDot;
static BOOL gCapsuleDismissed,gPreviousCapsuleAI;
static BOOL gCapsuleNeeded;
static NSString *gHapticStyle;
static PCEdgeProfile gEdgeProfile;
static NSDictionary *gSystemGeometry;
static id gSystemBoundary;
static PCScreenEdgeMask *gSystemEdgeMask;
static BOOL gIgnoreTopCutout;
static NSString *gCapsuleSession,*gCapsuleFinalText,*gLastCapsuleText;
static BOOL gCapsuleLocked,gPreviousLocalRunning;
static NSTimeInterval gCapsuleTailUntil;
static BOOL gComposing;
static NSString *gComposeJob,*gComposePausedJob,*gSendingID,*gSendingText,*gMessageFeedback,*gQuestionDraft,*gComposeDraft;
static NSDictionary *gComposeContext;
static CGFloat gEdgeWidth=14,gEdgeOpacity=.7;
static UILabel *gStatus,*gPreview;
static UITextField *gAnswer;
static UIButton *gReply;
static NSMutableArray *gOptions;
static NSDictionary *gPending,*gJob;
static BOOL gAIActive,gManualActive,gConnected,gAutoSuppressed;
static NSString *gVisibilityRequest,*gAutoSession;
static NSString *gQuestionID;
static CGFloat gKeyboardHeight,gLastKeyboardHeight;
static CGRect gKeyboardScreenFrame;
static BOOL gKeyboardRequested;
static NSDictionary *gKeyboardRuntime;
static double gKeyboardHideMilliseconds;
static NSInteger gAppearance=-1;
static NSInteger gSystemAppearance;
static BOOL gPreviousAppVisible,gQuestionAutoPanel;
static NSMutableArray *gBubbleRings;
static NSMutableArray<NSNumber *> *gRingOrder;
static NSTimeInterval gRingStarted[3],gVNCStarted;
static BOOL gEffects[]={YES,YES,YES,YES};
static CALayer *gEdge;
static CGFloat gDisplayCornerRadius;
static CAShapeLayer *gTrail;
static UIBezierPath *gTrailPath;
static BOOL gRunning, gPaused;
static BOOL gVisible;
// BackBoard hit testing happens in the render server, before UIView hitTest.
// Decorative layers must never claim a touch, including through a layer mask.
static void LayerInput(CALayer *layer,BOOL enabled) {
    for(NSString *name in @[@"setAllowsHitTesting:",@"setHitTestsAsOpaque:"]){
        SEL selector=NSSelectorFromString(name);
        if([layer respondsToSelector:selector])((void(*)(id,SEL,BOOL))objc_msgSend)(layer,selector,enabled);
    }
}
static id LayerAcceptsInput(CALayer *layer){SEL selector=NSSelectorFromString(@"allowsHitTesting");return [layer respondsToSelector:selector]?@(((BOOL(*)(id,SEL))objc_msgSend)(layer,selector)):(id)NSNull.null;}
static NSTimeInterval gAIScreenPassUntil;
static NSString *gAIScreenPrepareID;
static NSDictionary *gVoiceState;
static BOOL gVoiceActive,gPreviousVoiceActive;
static NSString *gCapsuleVoiceSession,*gCapsuleVoicePhase;
static id gVoiceWakeAssertion;
static NSString *gVoiceWakeStage;
static NSString *gVoiceWakeError;
static NSDictionary *gVoiceWakeAPI;
static NSInteger gVoiceLaunchResult=-1;
static NSUInteger gVoiceWakeGeneration;
extern void PCOverlayCancelTouch(void);
extern void PCOverlayRehostWindow(void);
extern NSArray *PCOverlayAllWindows(void);
static void PositionPanel(void);
static void ResetCapsulePosition(void);
static void ApplyPanelScroll(void);
static void UpdateEdgeStyle(CGFloat width,CGFloat opacity);
static void Feedback(void);
static void Diagnostic(NSString *stage);
static void Refresh(id self,SEL selector);
static void EndComposition(void);
static void ApplyTheme(void);
static NSInteger SystemStyle(void){return gSystemAppearance?:UIScreen.mainScreen.traitCollection.userInterfaceStyle;}
static CGRect ContentBounds(void){return gContentView?gContentView.bounds:gWindow.bounds;}
static BOOL Landscape(void){return UIInterfaceOrientationIsLandscape(gOrientation);}
static CGFloat ContentSideInset(void){return Landscape()?MAX(16,gDisplayCornerRadius):0;}
static CGFloat ContentTopInset(void){return Landscape()?16:gDisplayCornerRadius>0?60:24;}
extern void PCOverlayRequestAppearance(void);
extern NSDictionary *PCOverlayAppearanceDiagnostic(void);
void PCOverlaySetAppearance(NSInteger style){if(style!=UIUserInterfaceStyleLight&&style!=UIUserInterfaceStyleDark)return;gSystemAppearance=style;gWindow.overrideUserInterfaceStyle=style;ApplyTheme();}
static void DismissKeyboard(id self,SEL selector){double start=NSProcessInfo.processInfo.systemUptime;gKeyboardRequested=NO;[UIView performWithoutAnimation:^{for(UIWindow *window in PCOverlayAllWindows()){NSString *name=NSStringFromClass(window.class);if(window!=gWindow&&([name containsString:@"Keyboard"]||[name containsString:@"TextEffects"]))window.hidden=YES;}gKeyboardHeight=0;PositionPanel();}];[gAnswer resignFirstResponder];gKeyboardHideMilliseconds=(NSProcessInfo.processInfo.systemUptime-start)*1000;Diagnostic(@"keyboard_hidden");dispatch_async(dispatch_get_main_queue(),^{if(gKeyboardRequested)return;id keyboard=[NSClassFromString(@"UIKeyboardImpl") sharedInstance];if([keyboard respondsToSelector:@selector(hideKeyboard)])[keyboard hideKeyboard];});}

static NSString *S(const char *value) { return [NSString stringWithUTF8String:value]; }
static UIImage *BrandIcon(BOOL dark) {
    UIImage *image=[UIImage imageNamed:dark?@"AsterHandBrandDark":@"AsterHandBrand"];
    if(!image)image=[UIImage imageNamed:dark?@"AgentGoIconDark1024":@"AgentGoIcon1024"];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static NSString *ControlPath(NSString *name) {
    const char *root = jbroot("/var/mobile/Library/PocketAgentControl");
    return root ? [[NSString stringWithUTF8String:root] stringByAppendingPathComponent:name] : nil;
}

static void Diagnostic(NSString *stage) {
    NSMutableArray *windows=[NSMutableArray new];for(UIWindow *window in PCOverlayAllWindows())[windows addObject:@{S("class"):NSStringFromClass(window.class),S("hidden"):@(window.hidden),S("key"):@(window.isKeyWindow),S("frame"):NSStringFromCGRect(window.frame)}];
    NSDictionary *status = @{S("stage"):stage, S("updated"):@(NSDate.date.timeIntervalSince1970),S("appearance_probe"):PCOverlayAppearanceDiagnostic(),S("appearance"):@(gAppearance),S("system_appearance"):@(SystemStyle()),S("window_appearance"):@(gWindow.traitCollection.userInterfaceStyle),
        S("scenes"):@(UIApplication.sharedApplication.connectedScenes.count),S("visible"):@(gVisible),S("display_corner_radius"):@(gDisplayCornerRadius),S("keyboard_height"):@(gKeyboardHeight),S("keyboard_requested"):@(gKeyboardRequested),S("answer_focused"):@(gAnswer.isFirstResponder),S("keyboard_hide_ms"):@(gKeyboardHideMilliseconds),S("capsule_hidden"):@(gCapsule.hidden),S("capsule_text"):gCapsule.currentTitle?:S(""),S("capsule_locked"):@(gCapsuleLocked),S("capsule_tail_until"):@(gCapsuleTailUntil),S("panel_visible"):@(!gPanel.hidden),S("panel_frame"):NSStringFromCGRect(gPanel.frame),S("bubble_frame"):NSStringFromCGRect(gBubble.frame),S("dragging_bubble"):@(gDraggingBubble),S("panel_side"):gPanelSide==1?S("above"):gPanelSide==-1?S("below"):S("closed"),S("panel_gap"):@12,S("panel_content_height"):@(gPanelContentHeight),S("panel_scroll_offset"):@(gPanelScrollOffset),S("composing"):@(gComposing),S("message_feedback"):gMessageFeedback?:S(""),S("capsule_frame"):NSStringFromCGRect(gCapsule.frame),S("edge_width"):@(gEdgeWidth),S("edge_opacity"):@(gEdgeOpacity),S("windows"):windows};
    NSString *path = ControlPath(S("overlay-status.json"));
    NSMutableDictionary *details=[status mutableCopy];details[@"haptic_style"]=gHapticStyle?:@"system";details[@"capsule_toggle_enabled"]=@(gCapsuleNeeded);details[@"capsule_toggle_title"]=[(UIButton *)[gPanel viewWithTag:404] currentTitle]?:@"";details[@"edge_hidden"]=@(gEdge.hidden);details[@"edge_profile"]=@{@"kind":@(gEdgeProfile.kind),@"corner":@(gEdgeProfile.corner),@"notch_width":@(gEdgeProfile.notchWidth),@"notch_depth":@(gEdgeProfile.notchDepth)};
    details[@"voice_wake"]=@{@"stage":gVoiceWakeStage?:@"idle",@"held":@(gVoiceWakeAssertion!=nil),@"error":gVoiceWakeError?:@"",@"api":gVoiceWakeAPI?:@{}};
    details[@"haptic_feedback"]=PCHapticLastEvent()?:@{};
    details[@"capsule_voice"]=@{@"active":@(gVoiceActive),@"phase":gCapsuleVoicePhase?:@"",@"listening":@([gVoiceState[@"listening"] boolValue]&&![gVoiceState[@"microphone_muted"] boolValue]),@"pulsing":@([gCapsuleVoiceDot animationForKey:@"voice-listening"]!=nil),@"decorative_input":LayerAcceptsInput(gCapsuleVoiceDot)};
    details[@"orientation"]=@(gOrientation);details[@"content_bounds"]=NSStringFromCGRect(ContentBounds());details[@"orientation_observer"]=@(gOrientationObserver!=nil);
    details[@"keyboard_runtime"]=gKeyboardRuntime?:@{};
    details[@"keyboard_screen_frame"]=NSStringFromCGRect(gKeyboardScreenFrame);
    details[@"decorative_input"]=@{@"edge":LayerAcceptsInput(gEdge),@"trail":LayerAcceptsInput(gTrail),@"opaque_window":@(gWindow.opaque)};
    NSMutableDictionary *system=[gSystemGeometry mutableCopy];[system removeObjectForKey:@"exclusion"];system[@"source"]=gSystemEdgeMask?@"system-bitmap":@"system-parameters";system[@"ignore_top_cutout"]=@(gIgnoreTopCutout);if(gSystemEdgeMask)system[@"pixel_size"]=NSStringFromCGSize(gSystemEdgeMask.pixelSize);details[@"system_geometry"]=system?:@{};
    NSData *data = [NSJSONSerialization dataWithJSONObject:details options:0 error:nil];
    if (path && [data writeToFile:path options:NSDataWritingAtomic error:nil]) { chmod(path.fileSystemRepresentation, 0600); chown(path.fileSystemRepresentation, 501, 501); }
}

static BOOL PointInside(UIWindow *window, SEL selector, CGPoint point, UIEvent *event) {
    if (window.hidden || !gVisible||gAIScreenPassUntil>NSDate.date.timeIntervalSince1970) return NO;
    if(gFullInfoView||gWindow.rootViewController.presentedViewController)return YES;
    point=[gContentView convertPoint:point fromView:window];
    return (!gBubble.hidden && CGRectContainsPoint(gBubble.frame, point)) ||
        (!gPanel.hidden && CGRectContainsPoint(gPanel.frame, point)) ||
        (!gCapsule.hidden && CGRectContainsPoint(gCapsule.frame,point));
}

static const void *PCFullInfoDescriptionKey=&PCFullInfoDescriptionKey;
static const void *PCFullInfoEnabledKey=&PCFullInfoEnabledKey;
static void CloseFullInfo(id owner,SEL selector){[gFullInfoView removeFromSuperview];gFullInfoView=nil;Diagnostic(@"full_info_closed");}
static void FullInfo(id owner,SEL selector,UILongPressGestureRecognizer *gesture){
    if(gesture.state!=UIGestureRecognizerStateBegan||gFullInfoView||gWindow.rootViewController.presentedViewController)return;
    UIView *view=gesture.view;
    if(view==gPanelViewport){view=nil;CGPoint point=[gesture locationInView:gPanelContent];for(UIView *candidate in [gPanelContent.subviews reverseObjectEnumerator])if(!candidate.hidden&&objc_getAssociatedObject(candidate,PCFullInfoEnabledKey)&&CGRectContainsPoint(candidate.bounds,[candidate convertPoint:point fromView:gPanelContent])){view=candidate;break;}}
    NSString *text=[view isKindOfClass:UIButton.class]?((UIButton *)view).currentTitle:[view isKindOfClass:UILabel.class]?((UILabel *)view).text:nil;
    if(!text.length)text=view.accessibilityLabel;if(!text.length)return;
    NSString *description=objc_getAssociatedObject(view,PCFullInfoDescriptionKey);if(view==gReply&&gComposing)description=@"向当前任务或所选对话发送消息。";NSString *message=description.length?[NSString stringWithFormat:@"%@\n\n%@",text,PCLocalized(description)]:text;
    // A scene-less hosted window cannot reliably present UIKit's alert window.
    // Keep the temporary detail sheet in the already hosted content surface.
    gFullInfoView=[[UIView alloc] initWithFrame:ContentBounds()];gFullInfoView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;gFullInfoView.backgroundColor=[UIColor colorWithWhite:0 alpha:.38];
    BOOL dark=SystemStyle()==UIUserInterfaceStyleDark;UIColor *surface=[UIColor colorWithWhite:dark?.12:.98 alpha:1],*foreground=[UIColor colorWithWhite:dark?.94:.08 alpha:1];
    CGFloat width=MIN(340,CGRectGetWidth(gFullInfoView.bounds)-40),height=MIN(380,CGRectGetHeight(gFullInfoView.bounds)-100);
    UIView *card=[[UIView alloc] initWithFrame:CGRectMake((CGRectGetWidth(gFullInfoView.bounds)-width)/2,(CGRectGetHeight(gFullInfoView.bounds)-height)/2,width,height)];card.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;card.backgroundColor=surface;card.layer.cornerRadius=18;card.clipsToBounds=YES;[gFullInfoView addSubview:card];
    UILabel *heading=[[UILabel alloc] initWithFrame:CGRectMake(16,16,width-32,28)];heading.text=PCLocalized(@"完整信息");heading.textAlignment=NSTextAlignmentCenter;heading.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];heading.textColor=foreground;[card addSubview:heading];
    UITextView *body=[[UITextView alloc] initWithFrame:CGRectMake(12,52,width-24,height-112)];body.text=message;body.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];body.textColor=foreground;body.backgroundColor=UIColor.clearColor;body.editable=NO;body.selectable=YES;body.alwaysBounceVertical=YES;body.accessibilityLabel=message;[card addSubview:body];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];close.frame=CGRectMake(0,height-48,width,48);[close setTitle:PCLocalized(@"关闭") forState:UIControlStateNormal];[close addTarget:gController action:@selector(closeFullInfo) forControlEvents:UIControlEventTouchUpInside];[card addSubview:close];
    [gContentView addSubview:gFullInfoView];Feedback();Diagnostic(@"full_info_shown");
}
static void AddFullInfo(UIView *view,NSString *description){
    view.userInteractionEnabled=YES;objc_setAssociatedObject(view,PCFullInfoDescriptionKey,description,OBJC_ASSOCIATION_COPY_NONATOMIC);objc_setAssociatedObject(view,PCFullInfoEnabledKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.accessibilityHint=PCLocalized(@"长按查看完整信息和说明");
}
static NSString *FullInfoDescription(SEL action){
    NSString *name=NSStringFromSelector(action);
    return @{@"pauseOrResume":@"暂停或继续当前任务。长按不会执行任务操作。",@"stopTask":@"停止当前任务。已完成的操作不会撤销。",@"openApp":@"在应用中查看完整任务、对话和设置。",@"showCapsule":@"查看或隐藏状态胶囊。",@"composeMessage":@"向当前任务或所选对话发送消息。",@"hideOverlay":@"隐藏悬浮窗，可在应用中重新显示。",@"voiceToggle":@"开始或结束连续语音对话。",@"voiceSecondary":@"发送当前识别文字；正在朗读时可打断朗读。",@"voiceMuteMicrophone":@"只切换麦克风静音，不结束语音会话。",@"voiceMuteSpeech":@"只切换朗读静音，文字回复仍保留。",@"sendAnswer":@"提交当前问题的回答。长按不会提交答案。",@"pickAnswer:":@"提交当前问题的回答。长按不会提交答案。",@"dismissKeyboard":@"收起系统键盘。"}[name];
}
static UIButton *Button(NSString *title, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [button addTarget:gController action:action forControlEvents:UIControlEventTouchUpInside];
    if(action!=@selector(togglePanel))AddFullInfo(button,FullInfoDescription(action));
    return button;
}

static void StyleMenuButton(UIButton *button,NSString *symbol){
    button.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightMedium];button.titleLabel.numberOfLines=1;button.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;
    button.tintColor=[UIColor colorWithWhite:.94 alpha:1];[button setTitleColor:button.tintColor forState:UIControlStateNormal];[button setTitleColor:[UIColor colorWithWhite:.45 alpha:1] forState:UIControlStateDisabled];
    button.backgroundColor=[UIColor colorWithWhite:1 alpha:.07];button.layer.cornerRadius=11;button.contentEdgeInsets=UIEdgeInsetsMake(6,8,6,8);
    if(@available(iOS 15.0,*)){
    UIButtonConfiguration *configuration=UIButtonConfiguration.plainButtonConfiguration;configuration.title=button.currentTitle;configuration.titleLineBreakMode=NSLineBreakByTruncatingTail;configuration.image=symbol?[UIImage systemImageNamed:symbol]:nil;configuration.imagePadding=6;configuration.contentInsets=NSDirectionalEdgeInsetsMake(5,7,5,7);configuration.titleTextAttributesTransformer=^NSDictionary *(NSDictionary *incoming){NSMutableDictionary *attributes=[incoming mutableCopy];attributes[NSFontAttributeName]=[UIFont systemFontOfSize:14 weight:UIFontWeightMedium];return attributes;};button.configuration=configuration;
    }else{[button setImage:symbol?[UIImage systemImageNamed:symbol]:nil forState:UIControlStateNormal];button.imageEdgeInsets=UIEdgeInsetsMake(0,-3,0,3);button.titleEdgeInsets=UIEdgeInsetsMake(0,3,0,-3);}

}
static void ApplyTheme(void){
    if(!gWindow||!gPanel)return;
    NSInteger style=SystemStyle();if(style!=UIUserInterfaceStyleLight&&style!=UIUserInterfaceStyleDark)style=gWindow.traitCollection.userInterfaceStyle;if(style==UIUserInterfaceStyleUnspecified)style=UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    if(style==gAppearance)return;gAppearance=style;BOOL dark=style==UIUserInterfaceStyleDark;
    UIColor *text=[UIColor colorWithWhite:dark?.94:.08 alpha:1],*secondary=[UIColor colorWithWhite:dark?.72:.35 alpha:1],*surface=[UIColor colorWithWhite:dark?.12:.97 alpha:.97],*button=[UIColor colorWithWhite:dark?1:0 alpha:dark?.07:.055];
    [UIView performWithoutAnimation:^{
        gBubble.backgroundColor=UIColor.clearColor;[gBubble setImage:BrandIcon(dark) forState:UIControlStateNormal];gBubble.tintColor=text;[gBubble setTitleColor:text forState:UIControlStateNormal];gBubble.layer.shadowOpacity=dark?.3:.16;
        gPanel.backgroundColor=[UIColor colorWithWhite:dark?.08:1 alpha:dark?.78:.86];gPanelMaterial.effect=[UIBlurEffect effectWithStyle:dark?UIBlurEffectStyleSystemChromeMaterialDark:UIBlurEffectStyleSystemChromeMaterialLight];gPanel.layer.shadowOpacity=dark?.25:.13;gStatus.textColor=text;gPreview.textColor=secondary;gVoiceCard.backgroundColor=[text colorWithAlphaComponent:dark?.035:.04];
        gAnswer.backgroundColor=[UIColor colorWithWhite:dark?.2:.9 alpha:1];gAnswer.textColor=text;gAnswer.tintColor=text;gAnswer.keyboardAppearance=dark?UIKeyboardAppearanceDark:UIKeyboardAppearanceLight;
        gAnswer.attributedPlaceholder=[[NSAttributedString alloc] initWithString:gComposing?PCLocalized(S("给 AI 发消息")):PCLocalized(S("输入回答")) attributes:@{NSForegroundColorAttributeName:secondary}];
        for(UIView *view in gPanelContent.subviews)if([view isKindOfClass:UIButton.class]){UIButton *control=(UIButton *)view;control.tintColor=text;[control setTitleColor:text forState:UIControlStateNormal];[control setTitleColor:secondary forState:UIControlStateDisabled];control.backgroundColor=button;}
        for(NSNumber *tag in @[@407,@408,@409,@411])[(UIButton *)[gPanelContent viewWithTag:tag.integerValue] setBackgroundColor:UIColor.clearColor];
        for(NSNumber *tag in @[@401,@402]){UIButton *control=(UIButton *)[gPanelContent viewWithTag:tag.integerValue];control.backgroundColor=UIColor.clearColor;control.tintColor=secondary;[control setTitleColor:secondary forState:UIControlStateNormal];}
        gStopButton.backgroundColor=[UIColor.systemRedColor colorWithAlphaComponent:.12];gStopButton.tintColor=UIColor.systemRedColor;[gStopButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
        gReply.backgroundColor=text;gReply.tintColor=surface;[gReply setTitleColor:surface forState:UIControlStateNormal];
        gPanelScrollThumb.backgroundColor=[text colorWithAlphaComponent:.35];gCapsule.backgroundColor=surface;gCapsule.layer.borderColor=[secondary colorWithAlphaComponent:.25].CGColor;gCapsule.tintColor=text;[gCapsule setTitleColor:text forState:UIControlStateNormal];
    }];Diagnostic(S("appearance_changed"));
}
static NSString *TaskPath(NSString *name) {const char *root=jbroot("/var/mobile/Library/AgentGoTasks");return root?[[NSString stringWithUTF8String:root] stringByAppendingPathComponent:name]:nil;}
static NSDictionary *ReadTask(NSString *name){NSData *data=[NSData dataWithContentsOfFile:TaskPath(name)];id value=data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil]:nil;return [value isKindOfClass:NSDictionary.class]?value:@{};}
static NSString *VoiceCommandValue(NSString *action,NSNumber *muted){
    NSString *identifier=NSUUID.UUID.UUIDString.lowercaseString;NSMutableDictionary *value=[@{@"id":identifier,@"action":action,@"wake_ready":@(![action isEqual:@"start"]),@"session":gVoiceState[@"session"]?:@"",@"created":@(NSDate.date.timeIntervalSince1970)} mutableCopy];if(muted)value[@"muted"]=muted;NSString *path=ControlPath(@"voice-command.json");NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];if(![data writeToFile:path options:NSDataWritingAtomic error:nil])return nil;chmod(path.fileSystemRepresentation,0600);chown(path.fileSystemRepresentation,501,501);if(![action isEqual:@"start"])notify_post("local.asterhand.voice-command");return identifier;
}
static NSString *VoiceCommand(NSString *action){return VoiceCommandValue(action,nil);}
static void ReleaseVoiceWake(void){if(gVoiceWakeAssertion){[gVoiceWakeAssertion invalidate];gVoiceWakeAssertion=nil;}}
static void WakeVoiceApp(NSString *requestID){
    // A Darwin notification cannot run a suspended UIKit process. Hold only
    // our app for ten seconds while its real microphone session starts. No
    // scene activation is requested.
    NSUInteger generation=++gVoiceWakeGeneration;ReleaseVoiceWake();
    dlopen("/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices",RTLD_NOW);
    Class type=NSClassFromString(@"RBSAssertion"),targetType=NSClassFromString(@"RBSTarget"),attributeType=NSClassFromString(@"RBSLegacyAttribute");
    BOOL(*getPID)(CFStringRef,pid_t *)=dlsym(RTLD_DEFAULT,"SBSProcessIDForDisplayIdentifier");pid_t pid=0;BOOL found=getPID?getPID(CFSTR("local.pocketcodex"),&pid):NO;
    gVoiceWakeError=nil;
    gVoiceWakeAPI=@{@"launch_result":@(gVoiceLaunchResult),@"pid":@(pid),@"pid_found":@(found),@"lookup":@(getPID!=NULL),@"assertion":@([type instancesRespondToSelector:@selector(initWithExplanation:target:attributes:)]),@"acquire":@([type instancesRespondToSelector:@selector(acquireWithError:)]),@"target":@([targetType respondsToSelector:@selector(targetWithPid:)]),@"attribute":@([attributeType respondsToSelector:@selector(attributeWithReason:flags:)])};
    if(!getPID||pid<=0||![type instancesRespondToSelector:@selector(initWithExplanation:target:attributes:)]||![type instancesRespondToSelector:@selector(acquireWithError:)]||![targetType respondsToSelector:@selector(targetWithPid:)]||![attributeType respondsToSelector:@selector(attributeWithReason:flags:)]){gVoiceWakeStage=@"unavailable";Diagnostic(@"voice_wake_unavailable");return;}
    @try {
        // Briefly allow our audio engine to start without activating its UI.
        // Legacy flags 1|2 prevent suspension/throttling; finishTask=4
        // remains explicitly time bounded.
        gVoiceWakeStage=@"acquiring";
        id target=[targetType targetWithPid:pid],attribute=[attributeType attributeWithReason:4 flags:3];
        gVoiceWakeAssertion=[[type alloc] initWithExplanation:@"AsterHand floating voice start" target:target attributes:@[attribute]];
        NSError *error=nil;BOOL acquired=[gVoiceWakeAssertion acquireWithError:&error];gVoiceWakeStage=acquired?@"acquired":@"denied";gVoiceWakeError=error.description;
        if(acquired){
            NSString *path=ControlPath(@"voice-command.json");NSData *raw=[NSData dataWithContentsOfFile:path];id parsed=raw.length<4096?[NSJSONSerialization JSONObjectWithData:raw?:[NSData data] options:NSJSONReadingMutableContainers error:nil]:nil;
            NSMutableDictionary *command=[parsed isKindOfClass:NSDictionary.class]?[parsed mutableCopy]:nil;
            if([command[@"id"] isEqual:requestID]&&[command[@"action"] isEqual:@"start"]&&fabs(NSDate.date.timeIntervalSince1970-[command[@"created"] doubleValue])<15){command[@"wake_ready"]=@YES;NSData *data=[NSJSONSerialization dataWithJSONObject:command options:0 error:nil];if([data writeToFile:path options:NSDataWritingAtomic error:nil]){chmod(path.fileSystemRepresentation,0600);chown(path.fileSystemRepresentation,501,501);notify_post("local.asterhand.voice-command");}}
        }else ReleaseVoiceWake();Diagnostic(@"voice_wake_result");
    } @catch(NSException *exception){gVoiceWakeStage=@"failed";ReleaseVoiceWake();}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(generation!=gVoiceWakeGeneration)return;ReleaseVoiceWake();gVoiceWakeStage=@"released";Diagnostic(@"voice_wake_released");});
}
static void VoiceToggle(id self,SEL selector){
    Feedback();if(gVoiceActive){VoiceCommand(@"stop");++gVoiceWakeGeneration;ReleaseVoiceWake();return;}
    NSString *requestID=VoiceCommand(@"start");if(!requestID)return;
    // Launch/resume only the registered app in the background. Do not open a
    // URL or activate its scene when the user is working in another app.
    int(*launch)(CFStringRef,Boolean)=dlsym(RTLD_DEFAULT,"SBSLaunchApplicationWithIdentifier");gVoiceLaunchResult=launch?launch(CFSTR("local.pocketcodex"),true):-1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{WakeVoiceApp(requestID);});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{notify_post("local.asterhand.voice-command");});
}
static void VoiceSecondary(id self,SEL selector){if(!gVoiceActive)return;Feedback();VoiceCommand([gVoiceState[@"speaking"] boolValue]?@"interrupt":@"submit");}
static void VoiceMuteMicrophone(id self,SEL selector){if(!gVoiceActive)return;Feedback();VoiceCommandValue(@"microphone_mute",@(![gVoiceState[@"microphone_muted"] boolValue]));}
static void VoiceMuteSpeech(id self,SEL selector){if(!gVoiceActive)return;Feedback();VoiceCommandValue(@"speech_mute",@(![gVoiceState[@"speech_muted"] boolValue]));}
static void RefreshVoice(void){
    NSData *data=[NSData dataWithContentsOfFile:ControlPath(@"voice-status.json")];id value=data.length<16384?[NSJSONSerialization JSONObjectWithData:data?:[NSData data] options:0 error:nil]:nil;gVoiceState=[value isKindOfClass:NSDictionary.class]?value:@{};
    gVoiceActive=[gVoiceState[@"active"] boolValue]&&NSDate.date.timeIntervalSince1970-[gVoiceState[@"updated"] doubleValue]<5;
    UIButton *toggle=(UIButton *)[gPanel viewWithTag:407],*secondary=(UIButton *)[gPanel viewWithTag:408];[toggle setTitle:gVoiceActive?PCLocalized(@"结束语音"):PCLocalized(@"语音对话") forState:UIControlStateNormal];[toggle setImage:[UIImage systemImageNamed:gVoiceActive?@"phone.down.fill":@"waveform"] forState:UIControlStateNormal];BOOL speaking=[gVoiceState[@"speaking"] boolValue];[secondary setTitle:speaking?PCLocalized(@"打断朗读"):PCLocalized(@"发送这句") forState:UIControlStateNormal];secondary.enabled=gVoiceActive&&(speaking||([gVoiceState[@"listening"] boolValue]&&[gVoiceState[@"transcript"] length]));secondary.alpha=secondary.enabled?1:.65;
    [((UIButton *)[gPanel viewWithTag:406]) setTitle:gVoiceActive?PCLocalized(@"结束并隐藏"):PCLocalized(@"隐藏悬浮窗") forState:UIControlStateNormal];
    for(NSNumber *tag in @[@409,@411]){BOOL microphone=tag.integerValue==409,muted=[gVoiceState[microphone?@"microphone_muted":@"speech_muted"] boolValue];UIButton *button=(UIButton *)[gPanel viewWithTag:tag.integerValue];[button setTitle:microphone?(muted?PCLocalized(@"恢复麦克风"):PCLocalized(@"麦克风静音")):(muted?PCLocalized(@"恢复朗读"):PCLocalized(@"朗读静音")) forState:UIControlStateNormal];[button setImage:[UIImage systemImageNamed:microphone?(muted?@"mic.slash.fill":@"mic.fill"):(muted?@"speaker.slash.fill":@"speaker.wave.2.fill")] forState:UIControlStateNormal];button.enabled=gVoiceActive;button.alpha=gVoiceActive?1:.65;button.accessibilityValue=muted?PCLocalized(@"已静音"):PCLocalized(@"已开启");if(gVoiceActive)[button setTitleColor:muted?UIColor.systemRedColor:gStatus.textColor forState:UIControlStateNormal];}
}
static NSString *VoiceCapsuleText(NSString *reply,BOOL finalReply){
    BOOL microphoneMuted=[gVoiceState[@"microphone_muted"] boolValue],speechMuted=[gVoiceState[@"speech_muted"] boolValue];
    BOOL listening=[gVoiceState[@"listening"] boolValue]&&!microphoneMuted,speaking=[gVoiceState[@"speaking"] boolValue]&&!speechMuted;
    NSString *phase=[gVoiceState[@"phase"] isKindOfClass:NSString.class]?gVoiceState[@"phase"]:@"";
    NSString *transcript=[gVoiceState[@"transcript"] isKindOfClass:NSString.class]?gVoiceState[@"transcript"]:@"";
    NSString *spoken=[gVoiceState[@"reply"] isKindOfClass:NSString.class]?gVoiceState[@"reply"]:@"";
    if(speaking)phase=PCLocalized(@"正在朗读");else if(listening)phase=transcript.length?PCLocalized(@"正在识别"):PCLocalized(@"正在聆听");
    if(!phase.length)phase=microphoneMuted?PCLocalized(@"麦克风已静音"):PCLocalized(@"语音已开启");
    phase=PCLocalized(phase);gCapsuleVoicePhase=phase;
    NSMutableArray *parts=[NSMutableArray arrayWithObject:phase];
    if(microphoneMuted&&![phase containsString:@"麦克风"]) [parts addObject:PCLocalized(@"麦克风已静音")];
    if(speechMuted&&![phase containsString:@"朗读已静音"]) [parts addObject:PCLocalized(@"朗读已静音")];
    NSString *detail=finalReply?reply:listening?transcript:speaking?spoken:reply;
    if(detail.length&&![detail isEqual:phase])[parts addObject:detail];
    return [parts componentsJoinedByString:@" · "];
}
static void UpdateCapsuleVoiceFeedback(void){
    BOOL listening=gVoiceActive&&[gVoiceState[@"listening"] boolValue]&&![gVoiceState[@"microphone_muted"] boolValue];
    gCapsuleVoiceDot.hidden=!gVoiceActive||gCapsule.hidden;
    gCapsuleVoiceDot.position=CGPointMake(14,CGRectGetHeight(gCapsule.bounds)/2);
    gCapsuleVoiceDot.backgroundColor=(listening?UIColor.systemGreenColor:[gVoiceState[@"microphone_muted"] boolValue]?UIColor.systemOrangeColor:gCapsule.tintColor).CGColor;
    gCapsule.contentEdgeInsets=gVoiceActive?UIEdgeInsetsMake(0,26,0,14):UIEdgeInsetsMake(0,14,0,14);
    BOOL pulse=listening&&!gCapsuleVoiceDot.hidden&&!UIAccessibilityIsReduceMotionEnabled();
    if(pulse&&![gCapsuleVoiceDot animationForKey:@"voice-listening"]){CABasicAnimation *animation=[CABasicAnimation animationWithKeyPath:@"opacity"];animation.fromValue=@.4;animation.toValue=@1;animation.duration=.8;animation.autoreverses=YES;animation.repeatCount=HUGE_VALF;animation.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];[gCapsuleVoiceDot addAnimation:animation forKey:@"voice-listening"];}
    else if(!pulse)[gCapsuleVoiceDot removeAnimationForKey:@"voice-listening"];
    // This is a state indicator, not an audio-level meter; only the dot animates.
}
static void WriteTask(NSString *name,NSDictionary *value){NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];NSString *file=TaskPath(name);if(data&&[data writeToFile:file options:NSDataWritingAtomic error:nil]){chmod(file.fileSystemRepresentation,0600);chown(file.fileSystemRepresentation,501,501);}}
static void Feedback(void){PCHapticWithStyle(@"select",gHapticStyle);}
static void Command(NSString *value) {
    Feedback();NSDictionary *job=ReadTask(S("state.json"));
    if([job[S("running")] boolValue]&&job[S("id")]){WriteTask(S("command.json"),@{S("job"):job[S("id")],S("command"):value,S("id"):NSUUID.UUID.UUIDString.lowercaseString});return;}
    if([value isEqual:S("continue")]){NSMutableDictionary *request=[ReadTask(S("request.json")) mutableCopy];if(request[S("id")]&&[request[S("id")] isEqual:job[S("id")]]){request[S("id")]=NSUUID.UUID.UUIDString.lowercaseString;request[S("message")]=S("继续");request[S("attachments")]=@[];request[S("history")]=job[S("history")]?:@[];NSMutableDictionary *context=[request[S("context")] mutableCopy]?:[NSMutableDictionary new];context[S("transcript")]=job[S("transcript")]?:S("");request[S("context")]=context;request[S("created")]=@(NSDate.date.timeIntervalSince1970);WriteTask(S("request.json"),request);return;}}
    if (!gRunning && ![value isEqual:S("continue")]) return;
    NSString *path = ControlPath(S("command.json"));
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{S("command"):value, S("created"):@(NSDate.date.timeIntervalSince1970)} options:0 error:nil];
    if ([data writeToFile:path options:NSDataWritingAtomic error:nil]) { chmod(path.fileSystemRepresentation, 0600); chown(path.fileSystemRepresentation, 501, 501); }
}

static void Toggle(id self, SEL selector) {
    Feedback();gPanel.hidden = !gPanel.hidden;
    if(gPanel.hidden){if(gComposing)EndComposition();else DismissKeyboard(nil,NULL);}
    PositionPanel();Diagnostic(gPanel.hidden ? S("panel_closed") : S("panel_open"));
}
void PCOverlayPrepareScreen(void) {
    NSString *path=ControlPath(S("screen-prepare.json"));NSData *data=[NSData dataWithContentsOfFile:path];NSDictionary *request=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![request[S("id")] isKindOfClass:NSString.class]||fabs(NSDate.date.timeIntervalSince1970-[request[S("created")] doubleValue])>2)return;
    if(![ReadTask(S("state.json"))[S("question")] isKindOfClass:NSDictionary.class]){gAIScreenPrepareID=request[S("id")];gAIScreenPassUntil=NSDate.date.timeIntervalSince1970+8;gPanel.hidden=YES;gBubble.hidden=YES;gCapsule.hidden=YES;if(gKeyboardRequested)DismissKeyboard(nil,NULL);[CATransaction flush];}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_MSEC),dispatch_get_main_queue(),^{NSString *file=ControlPath(S("screen-prepared.json"));NSData *ack=[NSJSONSerialization dataWithJSONObject:@{S("id"):request[S("id")]} options:0 error:nil];if([ack writeToFile:file options:NSDataWritingAtomic error:nil]){chmod(file.fileSystemRepresentation,0600);chown(file.fileSystemRepresentation,501,501);}});
}
void PCOverlayFinishScreen(void){NSData *data=[NSData dataWithContentsOfFile:ControlPath(S("screen-finish.json"))];NSDictionary *finish=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;if([finish[S("id")] isEqual:gAIScreenPrepareID])gAIScreenPassUntil=MIN(NSDate.date.timeIntervalSince1970+3,[finish[S("until")] doubleValue]);Refresh(nil,NULL);}
static void Pause(id self, SEL selector) {PCHapticWithStyle(gRunning&&!gPaused?@"pause":@"start",gHapticStyle);gComposePausedJob=nil;Command(!gRunning?S("continue"):gPaused?S("resume"):S("pause")); }
static void Stop(id self, SEL selector) {PCHapticWithStyle(@"stop",gHapticStyle);Command(S("stop")); }
static void Open(id self, SEL selector) {
    if(gComposing)EndComposition();gPanel.hidden=YES;DismissKeyboard(nil,NULL);
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:S("pocketagent://open")] options:@{} completionHandler:nil];
}

static void PositionPanel(void){
    CGFloat screenWidth=CGRectGetWidth(ContentBounds()),sideInset=ContentSideInset();
    CGFloat width=MIN(Landscape()?560:332,screenWidth-2*sideInset-32),padding=16,gap=8,column=(width-padding*2-gap)/2;
    BOOL input=gPending||gComposing,compact=input&&gKeyboardHeight>0;
    CGFloat contentHeight=(compact?272:gComposing?344:gPending?436:260)+96;
    BOOL rootQuestion=[gPending[S("kind")] isEqual:S("root_permission")];NSArray *answers=gPending[S("options")];
    CGFloat landscapePreview=compact?18:rootQuestion?72:32,landscapeReply=38+landscapePreview+8+(input?44:0),landscapeControls=input?landscapeReply+40+((!compact&&gPending&&!gComposing)?ceil(MIN(answers.count,gOptions.count)/4.0)*40:0):38+landscapePreview+8;
    if(Landscape())contentHeight=landscapeControls+124;
    if(gPanel.hidden)gPanelSide=0;
    PCOverlayRect current={gBubble.frame.origin.x-sideInset,gBubble.frame.origin.y,gBubble.frame.size.width,gBubble.frame.size.height};
    PCOverlayMenuLayout layout=PCOverlayLayoutMenuSized(screenWidth-2*sideInset,CGRectGetHeight(ContentBounds()),gKeyboardHeight,ContentTopInset(),current,contentHeight,gPanelSide,width);
    layout.bubble.x+=sideInset;layout.panel.x+=sideInset;
    if(!gPanel.hidden)gPanelSide=layout.side;
    gBubble.frame=CGRectMake(layout.bubble.x,layout.bubble.y,layout.bubble.width,layout.bubble.height);
    BOOL sizeChanged=!CGSizeEqualToSize(gPanelViewport.bounds.size,CGSizeMake(layout.panel.width,layout.panel.height));
    gPanel.frame=CGRectMake(layout.panel.x,layout.panel.y,layout.panel.width,layout.panel.height);
    gPanelViewport.frame=gPanel.bounds;gPanelContentHeight=contentHeight;
    gPanelScrollOffset=MIN(MAX(0,gPanelScrollOffset),MAX(0,contentHeight-layout.panel.height));gPanelScrollPan.enabled=layout.panel.height<contentHeight-.5;
    [gPanel viewWithTag:410].frame=CGRectMake(16,compact?19:25,6,6);
    gStatus.frame=CGRectMake(30,compact?12:16,width-46,20);
    gPreview.frame=CGRectMake(padding,compact?38:46,width-2*padding,rootQuestion?96:compact?18:42);gPreview.numberOfLines=rootQuestion?5:compact?1:2;
    gAnswer.frame=CGRectMake(padding,compact?62:gComposing?92:104,width-2*padding,compact?40:44);
    CGFloat replyY=compact?110:gComposing?146:250;gReply.frame=CGRectMake(padding,replyY,width-2*padding-90,compact?34:40);[gPanel viewWithTag:403].frame=CGRectMake(width-padding-82,replyY,82,compact?34:40);
    CGFloat controlsY=compact?152:gComposing?196:gPending?300:104,rowHeight=compact?34:40;
    gPauseButton.frame=CGRectMake(padding,controlsY,column,rowHeight);gStopButton.frame=CGRectMake(padding+column+gap,controlsY,column,rowHeight);
    CGFloat messageY=compact?194:controlsY+48;[gPanel viewWithTag:405].frame=CGRectMake(padding,messageY,column,rowHeight);[gPanel viewWithTag:406].frame=CGRectMake(padding+column+gap,messageY,column,rowHeight);
    CGFloat voiceY=compact?236:messageY+48;[gPanel viewWithTag:407].frame=CGRectMake(padding,voiceY,column,rowHeight);[gPanel viewWithTag:408].frame=CGRectMake(padding+column+gap,voiceY,column,rowHeight);
    CGFloat muteY=voiceY+48;[gPanel viewWithTag:409].frame=CGRectMake(padding,muteY,column,rowHeight);[gPanel viewWithTag:411].frame=CGRectMake(padding+column+gap,muteY,column,rowHeight);
    gVoiceCard.frame=CGRectMake(8,voiceY-4,width-16,muteY+rowHeight-voiceY+8);
    CGFloat bottomY=muteY+48;[gPanel viewWithTag:401].frame=CGRectMake(padding,bottomY,column,compact?24:28);[gPanel viewWithTag:404].frame=CGRectMake(padding+column+gap,bottomY,column,compact?24:28);
    [((UIButton *)[gPanel viewWithTag:403]) setTitle:PCLocalized(@"收起") forState:UIControlStateNormal];
    for(NSUInteger i=0;i<gOptions.count;i++){UIButton *button=gOptions[i];button.frame=CGRectMake(padding+(i%2)*(column+gap),154+(i/2)*48,column,40);button.hidden=compact||gComposing||!gPending||i>=answers.count;}
    if(Landscape()){
        CGFloat col=(width-2*padding-3*gap)/4;[gPanel viewWithTag:410].frame=CGRectMake(16,19,6,6);gStatus.frame=CGRectMake(30,12,width-46,20);gPreview.frame=CGRectMake(padding,38,width-2*padding,landscapePreview);gPreview.numberOfLines=rootQuestion?4:compact?1:2;
        gAnswer.frame=CGRectMake(padding,38+landscapePreview+8,width-2*padding,36);gReply.frame=CGRectMake(padding,landscapeReply,width-2*padding-90,32);[gPanel viewWithTag:403].frame=CGRectMake(width-padding-82,landscapeReply,82,32);
        UIButton *dismiss=(UIButton *)[gPanel viewWithTag:403];
        if(compact){
            CGFloat y=CGRectGetMinY(gAnswer.frame),action=36;
            gAnswer.frame=CGRectMake(padding,y,width-2*padding-2*(action+gap),36);
            gReply.frame=CGRectMake(width-padding-2*action-gap,y,action,36);dismiss.frame=CGRectMake(width-padding-action,y,action,36);
            gReply.accessibilityLabel=gComposing?PCLocalized(@"发送消息"):PCLocalized(@"发送回答");[gReply setTitle:@"" forState:UIControlStateNormal];
        }
        [dismiss setTitle:compact?@"":PCLocalized(@"收起") forState:UIControlStateNormal];dismiss.accessibilityLabel=PCLocalized(@"收起键盘");
        NSArray *controls=@[gPauseButton,gStopButton,[gPanel viewWithTag:405],[gPanel viewWithTag:406],[gPanel viewWithTag:407],[gPanel viewWithTag:408],[gPanel viewWithTag:409],[gPanel viewWithTag:411]];
        for(NSUInteger i=0;i<controls.count;i++)[(UIView *)controls[i] setFrame:CGRectMake(padding+(i%4)*(col+gap),landscapeControls+(i/4)*42,col,34)];
        gVoiceCard.frame=CGRectMake(8,landscapeControls+38,width-16,42);
        [gPanel viewWithTag:401].frame=CGRectMake(padding,landscapeControls+84,column,24);[gPanel viewWithTag:404].frame=CGRectMake(padding+column+gap,landscapeControls+84,column,24);
        for(NSUInteger i=0;i<gOptions.count;i++)[(UIButton *)gOptions[i] setFrame:CGRectMake(padding+(i%4)*(col+gap),landscapeReply+40+(i/4)*40,col,34)];
    }
    if(gAnswer.isFirstResponder&&(sizeChanged||gEnsureAnswerVisible)){CGRect answer=CGRectInset(gAnswer.frame,0,layout.panel.height<60?0:-8);if(CGRectGetMaxY(answer)>gPanelScrollOffset+layout.panel.height)gPanelScrollOffset=CGRectGetMaxY(answer)-layout.panel.height;if(CGRectGetMinY(answer)<gPanelScrollOffset)gPanelScrollOffset=CGRectGetMinY(answer);gEnsureAnswerVisible=NO;}
    ApplyPanelScroll();
    [gContentView bringSubviewToFront:gBubble];if(gFullInfoView)[gContentView bringSubviewToFront:gFullInfoView];

}
static void ApplyPanelScroll(void){
    CGFloat height=CGRectGetHeight(gPanelViewport.bounds),width=CGRectGetWidth(gPanelViewport.bounds),maximum=MAX(0,gPanelContentHeight-height);
    gPanelScrollOffset=MIN(MAX(0,gPanelScrollOffset),maximum);gPanelContent.frame=CGRectMake(0,-gPanelScrollOffset,width,gPanelContentHeight);gPanelScrollThumb.hidden=maximum<.5;
    if(maximum>.5){CGFloat track=MAX(0,height-16),thumb=MIN(track,MAX(20,track*height/gPanelContentHeight));gPanelScrollThumb.frame=CGRectMake(width-4,8+(track-thumb)*gPanelScrollOffset/maximum,2,thumb);}
}
static void ScrollPanel(id self,SEL selector,UIPanGestureRecognizer *gesture){
    if(gesture.state==UIGestureRecognizerStateBegan)gPanelScrollStart=gPanelScrollOffset;
    CGFloat offset=gPanelScrollStart-[gesture translationInView:gContentView].y;
    [UIView performWithoutAnimation:^{gPanelScrollOffset=offset;ApplyPanelScroll();}];
    if(gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled)Diagnostic(S("panel_scrolled"));
}
static void Keyboard(id self,SEL selector,NSNotification *note){
    CGRect frame=[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    // Scene-less UIKit reports legacy keyboard rectangles in the current
    // interface coordinate space; the hosted overlay window stays physical.
    BOOL logical=Landscape()&&CGRectGetWidth(frame)>CGRectGetWidth(gWindow.bounds)+1;
    CGRect local=logical?frame:[gContentView convertRect:frame fromView:gWindow];
    gKeyboardScreenFrame=logical?[gContentView convertRect:frame toView:gWindow]:frame;
    CGRect overlap=CGRectIntersection(ContentBounds(),local);CGFloat height=!CGRectIsNull(overlap)&&CGRectGetWidth(overlap)>CGRectGetWidth(ContentBounds())*.6?CGRectGetHeight(overlap):0;
    if([note.name isEqual:UIKeyboardWillHideNotification]){height=0;gKeyboardScreenFrame=CGRectZero;}
    if(height>0)gLastKeyboardHeight=height;gKeyboardHeight=gKeyboardRequested?(height>0?height:gLastKeyboardHeight):0;PositionPanel();
}
static void Drag(id self, SEL selector, UIPanGestureRecognizer *gesture) {
    if(gesture.state==UIGestureRecognizerStateBegan){gDraggingBubble=YES;gDragBubbleStart=gBubble.frame;Feedback();}
    CGPoint delta=[gesture translationInView:gContentView];CGRect frame=gDragBubbleStart;
    frame.origin.x=MIN(MAX(ContentSideInset()+12,frame.origin.x+delta.x),CGRectGetWidth(ContentBounds())-ContentSideInset()-frame.size.width-12);
    frame.origin.y=MIN(MAX(ContentTopInset(),frame.origin.y+delta.y),CGRectGetHeight(ContentBounds())-gKeyboardHeight-frame.size.height-20);
    BOOL ended=gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled||gesture.state==UIGestureRecognizerStateFailed;
    [UIView performWithoutAnimation:^{gBubble.frame=frame;if(ended)gDraggingBubble=NO;PositionPanel();}];
    // UIKit handles compositor invalidation; forcing root-view redraw on every touch caused flashes.
    if(ended){Feedback();Diagnostic(S("bubble_drag_finished"));}
}

static void HideCapsule(id self,SEL selector){gCapsuleDismissed=YES;Refresh(nil,NULL);Feedback();Diagnostic(S("capsule_hidden"));}
static void ShowCapsule(id self,SEL selector){Refresh(nil,NULL);if(!gCapsuleNeeded)return;gCapsuleDismissed=!gCapsule.hidden;Refresh(nil,NULL);Feedback();Diagnostic(gCapsule.hidden?S("capsule_hidden"):S("capsule_shown"));}
static void ResetCapsulePosition(void){CGFloat width=MIN(320,CGRectGetWidth(ContentBounds())-32);gCapsule.frame=CGRectMake((CGRectGetWidth(ContentBounds())-width)/2,Landscape()?16:gDisplayCornerRadius>0?60:26,width,38);}
static void DragCapsule(id self,SEL selector,UIPanGestureRecognizer *gesture){
    if(gCapsuleLocked){[gesture setTranslation:CGPointZero inView:gContentView];return;}
    CGPoint delta=[gesture translationInView:gContentView];CGRect frame=gCapsule.frame;frame.origin.x=MIN(MAX(ContentSideInset()+8,frame.origin.x+delta.x),CGRectGetWidth(ContentBounds())-ContentSideInset()-frame.size.width-8);frame.origin.y=MIN(MAX(ContentTopInset(),frame.origin.y+delta.y),CGRectGetHeight(ContentBounds())-frame.size.height-20);[UIView performWithoutAnimation:^{gCapsule.frame=frame;}];[gesture setTranslation:CGPointZero inView:gContentView];
    if(gesture.state==UIGestureRecognizerStateEnded){Feedback();Diagnostic(S("capsule_dragged"));}
}
static void SetOverlayOrientation(UIInterfaceOrientation orientation){
    if(orientation<UIInterfaceOrientationPortrait||orientation>UIInterfaceOrientationLandscapeRight||orientation==gOrientation||!gContentView)return;
    CGRect old=ContentBounds();CGFloat x=CGRectGetMidX(gBubble.frame)/MAX(1,old.size.width),y=CGRectGetMidY(gBubble.frame)/MAX(1,old.size.height);CGPoint capsule=CGPointMake(CGRectGetMidX(gCapsule.frame)/MAX(1,old.size.width),CGRectGetMidY(gCapsule.frame)/MAX(1,old.size.height));
    PCOverlayCancelTouch();gDraggingBubble=NO;if(gKeyboardRequested)DismissKeyboard(nil,NULL);gKeyboardScreenFrame=CGRectZero;gKeyboardHeight=0;gLastKeyboardHeight=0;gOrientation=orientation;gPanelSide=0;gPanelScrollOffset=0;
    CGRect physical=gWindow.bounds;CGSize size=UIInterfaceOrientationIsLandscape(orientation)?CGSizeMake(physical.size.height,physical.size.width):physical.size;CGFloat angle=orientation==UIInterfaceOrientationLandscapeLeft?-M_PI_2:orientation==UIInterfaceOrientationLandscapeRight?M_PI_2:orientation==UIInterfaceOrientationPortraitUpsideDown?M_PI:0;
    [UIView performWithoutAnimation:^{gContentView.bounds=(CGRect){CGPointZero,size};gContentView.center=CGPointMake(CGRectGetMidX(physical),CGRectGetMidY(physical));gContentView.transform=CGAffineTransformMakeRotation(angle);gBubble.center=CGPointMake(x*size.width,y*size.height);gCapsule.center=CGPointMake(capsule.x*size.width,capsule.y*size.height);if(gCapsuleLocked)ResetCapsulePosition();else {CGRect f=gCapsule.frame;f.origin.x=MIN(MAX(ContentSideInset()+8,f.origin.x),size.width-ContentSideInset()-f.size.width-8);f.origin.y=MIN(MAX(ContentTopInset(),f.origin.y),size.height-f.size.height-12);gCapsule.frame=f;}PositionPanel();}];
    Diagnostic(@"orientation_changed");
}
static void ObserveOrientation(void){
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_NOW);Class type=NSClassFromString(@"FBSOrientationObserver");if(![type instancesRespondToSelector:@selector(setHandler:)])return;
    gOrientationObserver=[type new];[gOrientationObserver setHandler:^(id update){SEL selector=NSSelectorFromString(@"orientation");if(![update respondsToSelector:selector])return;UIInterfaceOrientation orientation=(UIInterfaceOrientation)((long long(*)(id,SEL))objc_msgSend)(update,selector);dispatch_async(dispatch_get_main_queue(),^{SetOverlayOrientation(orientation);});}];
    if([gOrientationObserver respondsToSelector:@selector(activeInterfaceOrientation)])SetOverlayOrientation((UIInterfaceOrientation)[gOrientationObserver activeInterfaceOrientation]);
}
static void EndComposition(void){gComposeDraft=gAnswer.text;gComposing=NO;gAnswer.text=gQuestionDraft?:S("");if(gComposePausedJob&&[gComposePausedJob isEqual:ReadTask(S("state.json"))[S("id")]])Command(S("resume"));gComposePausedJob=nil;DismissKeyboard(nil,NULL);}
static void ComposeMessage(id self,SEL selector){
    if(gComposing){EndComposition();Refresh(nil,NULL);return;}
    if(gSendingID)return;
    gQuestionDraft=gAnswer.text;gAnswer.text=gComposeDraft?:S("");gComposing=YES;gMessageFeedback=nil;
    NSDictionary *job=ReadTask(S("state.json"));gComposeJob=[job[S("running")] boolValue]?job[S("id")]:nil;gComposeContext=ReadTask(S("composer.json"))[S("context")];
    if(gComposeJob&&![job[S("paused")] boolValue]&&!gPending){gComposePausedJob=gComposeJob;Command(S("pause"));}
    PositionPanel();Refresh(nil,NULL);Diagnostic(S("compose_open"));
}
static void HideOverlay(id self,SEL selector){
    if(gVoiceActive)VoiceCommand(@"stop");
    if(gComposing)EndComposition();gPanel.hidden=YES;DismissKeyboard(nil,NULL);Feedback();
    NSData *data=[NSData dataWithContentsOfFile:ControlPath(S("state.json"))];NSDictionary *state=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    NSString *path=ControlPath(S("visibility-override.json"));NSDictionary *value=@{S("base_request"):state[S("visibility_request")]?:S("initial"),S("request"):NSUUID.UUID.UUIDString.lowercaseString,S("enabled"):@NO};
    if([[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] writeToFile:path options:NSDataWritingAtomic error:nil]){chmod(path.fileSystemRepresentation,0600);chown(path.fileSystemRepresentation,501,501);}Refresh(nil,NULL);Diagnostic(S("hidden_by_menu"));
}
static void SendAnswer(id self,SEL selector){
    if(gComposing){
        if(gSendingID||!gAnswer.text.length)return;NSString *error=nil;
        NSString *identifier=PCMessageEnqueue(TaskPath(S("")),gAnswer.text,gComposeJob,gComposeContext,&error);
        if(identifier){gSendingID=identifier;gSendingText=gAnswer.text;gMessageFeedback=PCLocalized(S("正在发送…"));}else gMessageFeedback=error;
        Refresh(nil,NULL);Feedback();return;
    }
    if(!gPending||!gJob[S("id")]||!gAnswer.text.length)return;WriteTask(S("reply.json"),@{S("job"):gJob[S("id")],S("prompt"):gPending[S("id")],S("value"):gAnswer.text});gAnswer.text=S("");DismissKeyboard(nil,NULL);Feedback();
}
static void FocusAnswer(id self,SEL selector){
    if(gKeyboardRequested&&gAnswer.isFirstResponder)return;gKeyboardRequested=YES;gEnsureAnswerVisible=YES;[gWindow makeKeyAndVisible];
    UIView *accessory=gAnswer.inputAccessoryView;accessory.frame=CGRectMake(0,0,CGRectGetWidth(ContentBounds()),44);accessory.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    if(!gAnswer.isFirstResponder)[gAnswer becomeFirstResponder];[gAnswer reloadInputViews];if(gLastKeyboardHeight>0)gKeyboardHeight=gLastKeyboardHeight;PositionPanel();
    @try{
        id keyboard=[NSClassFromString(@"UIKeyboardImpl") sharedInstance];NSMutableDictionary *runtime=[NSMutableDictionary new];runtime[@"status_orientation"]=@(UIApplication.sharedApplication.statusBarOrientation);
        for(NSString *name in @[@"isInHardwareKeyboardMode",@"hardwareKeyboardIsSeen"]){SEL get=NSSelectorFromString(name);if([keyboard respondsToSelector:get])runtime[name]=@(((BOOL(*)(id,SEL))objc_msgSend)(keyboard,get));}
        if([keyboard respondsToSelector:@selector(setAutomaticMinimizationEnabled:)])[keyboard setAutomaticMinimizationEnabled:NO];
        if([keyboard respondsToSelector:@selector(updateLayoutToCurrentInterfaceOrientation)])[keyboard updateLayoutToCurrentInterfaceOrientation];
        if([keyboard respondsToSelector:@selector(showKeyboard)])[keyboard showKeyboard];gKeyboardRuntime=runtime;
    }@catch(NSException *exception){NSLog(@"AsterHand keyboard: %@",exception.name);}
    // DismissKeyboard hides this process's keyboard windows immediately. UIKit
    // can reuse them without clearing hidden, so undo that only on explicit focus.
    void (^restoreKeyboard)(void)=^{if(!gKeyboardRequested||!gAnswer.isFirstResponder)return;for(UIWindow *window in PCOverlayAllWindows()){NSString *name=NSStringFromClass(window.class);if(window!=gWindow&&([name containsString:@"Keyboard"]||[name containsString:@"TextEffects"])){
        if([window respondsToSelector:@selector(_setRotatableViewOrientation:updateStatusBar:duration:force:)])[window _setRotatableViewOrientation:gOrientation updateStatusBar:NO duration:0 force:YES];window.hidden=NO;
    }}};
    restoreKeyboard();dispatch_async(dispatch_get_main_queue(),restoreKeyboard);
    Diagnostic(S("answer_focus_requested"));dispatch_after(dispatch_time(DISPATCH_TIME_NOW,400*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(gKeyboardRequested&&gAnswer.isFirstResponder){
            CGRect physical=CGRectNull;NSMutableArray *hosts=[NSMutableArray new];
            for(UIWindow *window in PCOverlayAllWindows())if(window!=gWindow&&!window.hidden){
                NSMutableArray *queue=[NSMutableArray arrayWithObject:window];
                for(NSUInteger index=0;index<queue.count&&index<512;index++){UIView *view=queue[index];[queue addObjectsFromArray:view.subviews];
                    if([NSStringFromClass(view.class) containsString:@"UIInputSetHostView"]&&!view.hidden&&view.alpha>0&&!CGRectIsEmpty(view.bounds)){
                        CGRect rect=[view convertRect:view.bounds toView:gWindow];physical=CGRectIsNull(physical)?rect:CGRectUnion(physical,rect);[hosts addObject:@{@"class":NSStringFromClass(view.class),@"physical_frame":NSStringFromCGRect(rect)}];
                    }
                }
            }
            NSMutableDictionary *runtime=[gKeyboardRuntime mutableCopy]?:[NSMutableDictionary new];runtime[@"hosts"]=hosts;gKeyboardRuntime=runtime;
            if(!CGRectIsNull(physical)){
                gKeyboardScreenFrame=physical;CGRect local=[gContentView convertRect:physical fromView:gWindow],overlap=CGRectIntersection(ContentBounds(),local);
                if(!CGRectIsNull(overlap)&&CGRectGetWidth(overlap)>CGRectGetWidth(ContentBounds())*.6){gKeyboardHeight=CGRectGetHeight(overlap);gLastKeyboardHeight=gKeyboardHeight;gEnsureAnswerVisible=YES;PositionPanel();}
            }
        }
        Diagnostic(S("answer_focused"));
    });
}
UIInterfaceOrientation PCOverlayInterfaceOrientation(void){return gOrientation;}
static void PickAnswer(id self,SEL selector,UIButton *button){NSArray *options=gPending[S("options")];if(button.tag<0||button.tag>=options.count)return;WriteTask(S("reply.json"),@{S("job"):gJob[S("id")],S("prompt"):gPending[S("id")],S("value"):options[button.tag]});Feedback();}

static NSMutableArray *MakeRings(UIView *view){NSMutableArray *rings=[NSMutableArray new];NSArray *colors=@[UIColor.systemGreenColor,UIColor.systemOrangeColor,UIColor.systemBlueColor];for(UIColor *color in colors){CAShapeLayer *ring=[CAShapeLayer layer];LayerInput(ring,NO);ring.fillColor=UIColor.clearColor.CGColor;ring.strokeColor=color.CGColor;ring.lineWidth=2;[view.layer addSublayer:ring];[rings addObject:ring];}return rings;}
static void UpdateRingOrder(void){BOOL flags[]={gAIActive&&gEffects[0],gManualActive&&gEffects[1],gConnected&&gEffects[2]};if(!gRingOrder)gRingOrder=[NSMutableArray new];for(NSNumber *index in [gRingOrder copy])if(!flags[index.unsignedIntegerValue])[gRingOrder removeObject:index];for(NSUInteger i=0;i<3;i++)if(flags[i]&&![gRingOrder containsObject:@(i)])[gRingOrder addObject:@(i)];[gRingOrder sortUsingComparator:^NSComparisonResult(NSNumber *a,NSNumber *b){double x=gRingStarted[a.unsignedIntegerValue],y=gRingStarted[b.unsignedIntegerValue];return x<y?NSOrderedAscending:x>y?NSOrderedDescending:[a compare:b];}];}
static void UpdateRings(UIView *view,NSArray *rings){[CATransaction begin];[CATransaction setDisableActions:YES];for(NSUInteger i=0;i<rings.count;i++){CAShapeLayer *ring=rings[i];NSUInteger position=[gRingOrder indexOfObject:@(i)];ring.hidden=position==NSNotFound;if(position==NSNotFound)continue;ring.frame=view.bounds;CGFloat inset=1+position*2;ring.path=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(view.bounds,-inset,-inset) cornerRadius:view.layer.cornerRadius+inset].CGPath;}[CATransaction commit];}
void PCOverlayRecordGesture(CGPoint point,UITouchPhase phase){
    if(!gVisible||(!gAIActive&&!gConnected&&!gManualActive))return;
    if(phase==UITouchPhaseBegan||!gTrail){gTrail=[CAShapeLayer layer];LayerInput(gTrail,NO);gTrail.frame=gWindow.bounds;gTrail.strokeColor=[UIColor colorWithWhite:1 alpha:0.55].CGColor;gTrail.fillColor=UIColor.clearColor.CGColor;gTrail.lineWidth=5;gTrail.lineCap=kCALineCapRound;gTrail.lineJoin=kCALineJoinRound;gTrailPath=[UIBezierPath bezierPath];[gTrailPath moveToPoint:point];[gWindow.rootViewController.view.layer insertSublayer:gTrail below:gContentView.layer];
        CAShapeLayer *dot=[CAShapeLayer layer];LayerInput(dot,NO);dot.frame=gWindow.bounds;dot.path=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(point.x-13,point.y-13,26,26)].CGPath;dot.fillColor=[UIColor colorWithRed:0.3 green:0.65 blue:1 alpha:0.22].CGColor;dot.strokeColor=[UIColor colorWithWhite:1 alpha:0.5].CGColor;dot.lineWidth=2;[gWindow.rootViewController.view.layer insertSublayer:dot below:gContentView.layer];CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];fade.fromValue=@1;fade.toValue=@0;fade.duration=0.65;dot.opacity=0;[dot addAnimation:fade forKey:@"tap"];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,800*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[dot removeFromSuperlayer];});
    }
    [gTrailPath addLineToPoint:point];gTrail.path=gTrailPath.CGPath;
    if(phase==UITouchPhaseEnded||phase==UITouchPhaseCancelled){CAShapeLayer *trail=gTrail;gTrail=nil;gTrailPath=nil;CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];fade.fromValue=@1;fade.toValue=@0;fade.duration=0.75;trail.opacity=0;[trail addAnimation:fade forKey:@"fade"];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[trail removeFromSuperlayer];});}
}
static void Refresh(id self, SEL selector) {
    RefreshVoice();
    // The standalone UIKit host has no scene to receive updated traits. Watch
    // the real system preferences as a fallback to the Darwin change signal.
    static struct timespec lastStyleChange;struct stat appearanceStat;
    // Native helpers use physical paths; /rootfs is a shell/SFTP alias, not a
    // physical directory. Do not redirect system preferences into the jbroot.
    const char *appearancePath="/var/mobile/Library/Preferences/com.apple.uikitservices.userInterfaceStyleMode.plist";
    if(stat(appearancePath,&appearanceStat)==0&&(lastStyleChange.tv_sec!=appearanceStat.st_mtimespec.tv_sec||lastStyleChange.tv_nsec!=appearanceStat.st_mtimespec.tv_nsec)){lastStyleChange=appearanceStat.st_mtimespec;PCOverlayRequestAppearance();}
    ApplyTheme();
    BOOL wasCapsuleHidden=gCapsule.hidden,wasLocked=gCapsuleLocked;
    NSData *data=[NSData dataWithContentsOfFile:ControlPath(S("state.json"))];NSDictionary *state=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;PCSetProcessUILanguage(state[@"ui_language"]);
    [((UIButton *)[gPanel viewWithTag:401]) setTitle:PCLocalized(S("打开应用")) forState:UIControlStateNormal];
    [((UIButton *)[gPanel viewWithTag:406]) setTitle:PCLocalized(S("隐藏悬浮窗")) forState:UIControlStateNormal];
    [gStopButton setTitle:PCLocalized(S("停止")) forState:UIControlStateNormal];
    gBubble.accessibilityLabel=PCLocalized(S("AsterHand 任务控制"));
    gHapticStyle=[state[S("haptic_style")] isKindOfClass:NSString.class]?state[S("haptic_style")]:@"system";
    NSDictionary *display=state[S("display")];CGFloat safeTop=[display[S("safe_top")] doubleValue],safeBottom=[display[S("safe_bottom")] doubleValue];
    gEdgeProfile=PCEdgeMakeProfile(CGRectGetWidth(gWindow.bounds),CGRectGetHeight(gWindow.bounds),safeTop,safeBottom,gDisplayCornerRadius,-1);
    static CGSize geometrySize;static BOOL previousIgnore;BOOL ignoreCutout=safeTop>=54;
    if(!gSystemGeometry||!CGSizeEqualToSize(geometrySize,gWindow.bounds.size)||ignoreCutout!=previousIgnore){geometrySize=gWindow.bounds.size;previousIgnore=ignoreCutout;id boundary=nil;gSystemGeometry=PCSystemScreenMetrics(gWindow,&boundary);gSystemBoundary=boundary;NSValue *value=gSystemGeometry[@"exclusion"];CGRect cutout=value?value.CGRectValue:CGRectZero;gIgnoreTopCutout=value?(cutout.origin.y>1&&cutout.size.height>0):ignoreCutout;id image=PCGeometryObject(boundary,@"_imageRepresentation");gSystemEdgeMask=[image isKindOfClass:UIImage.class]?[[PCScreenEdgeMask alloc] initWithSystemImage:image screenSize:gWindow.bounds.size topCutout:cutout ignoreTopCutout:gIgnoreTopCutout cornerRadius:gDisplayCornerRadius]:nil;}
    NSValue *exclusion=gSystemGeometry[@"exclusion"];if(exclusion){CGRect rect=exclusion.CGRectValue;gEdgeProfile.notchWidth=!gIgnoreTopCutout&&rect.size.height>0&&rect.origin.y<1?rect.size.width:0;gEdgeProfile.notchDepth=!gIgnoreTopCutout&&rect.size.height>0&&rect.origin.y<1?CGRectGetMaxY(rect):0;gEdgeProfile.kind=gEdgeProfile.notchWidth>0?2:gEdgeProfile.corner>0?1:0;}
    NSData *overrideData=[NSData dataWithContentsOfFile:ControlPath(S("visibility-override.json"))];NSDictionary *override=overrideData?[NSJSONSerialization JSONObjectWithData:overrideData options:0 error:nil]:nil;
    if([override[S("base_request")] isEqual:state[S("visibility_request")]]||[override[S("request")] isEqual:state[S("visibility_request")]]){NSMutableDictionary *merged=[state mutableCopy];merged[S("enabled")]=override[S("enabled")];merged[S("visibility_request")]=override[S("request")];state=merged;}
    BOOL locked=[state[S("capsule_locked")] boolValue];if(locked&&!gCapsuleLocked)ResetCapsulePosition();gCapsuleLocked=locked;
    for(UIGestureRecognizer *gesture in gCapsule.gestureRecognizers)if([gesture isKindOfClass:UIPanGestureRecognizer.class])gesture.enabled=!locked;
    NSArray *effectKeys=@[S("effectAI"),S("effectRemoteInput"),S("effectRemoteConnected"),S("effectScreenEdge")];for(NSUInteger i=0;i<4;i++)gEffects[i]=![state[S("effects")][effectKeys[i]] isEqual:@NO];
    gJob=ReadTask(S("state.json"));gPending=[gJob[S("running")] boolValue]&&[gJob[S("question")] isKindOfClass:NSDictionary.class]?gJob[S("question")]:nil;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;BOOL workerAlive=now-[gJob[S("updated")] doubleValue]<8;gRunning=workerAlive&&[gJob[S("running")] boolValue];gPaused=gRunning&&[gJob[S("paused")] boolValue];
    const char *presenceRoot=jbroot("/var/mobile/Library/AgentGoControl/remote-presence.json");NSData *presenceData=presenceRoot?[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:presenceRoot]]:nil;NSDictionary *presence=presenceData?[NSJSONSerialization JSONObjectWithData:presenceData options:0 error:nil]:nil;
    gConnected=NO;gManualActive=NO;gAIActive=gRunning&&[gJob[S("screen_session")] boolValue];gRingStarted[0]=gAIActive?[gJob[S("screen_started_at")] doubleValue]:DBL_MAX;gRingStarted[1]=gRingStarted[2]=DBL_MAX;NSString *remoteReply=nil,*remoteSession=nil;
    NSDictionary *connections=presence[S("connections")];for(NSString *identifier in connections){NSDictionary *entry=connections[identifier];if([entry[S("connected_until")] doubleValue]>now){gConnected=YES;remoteSession=identifier;gRingStarted[2]=MIN(gRingStarted[2],[entry[S("connected_since")] doubleValue]?:now);}if([entry[S("manual_until")] doubleValue]>now){gManualActive=YES;gRingStarted[1]=MIN(gRingStarted[1],[entry[S("manual_since")] doubleValue]?:now);}if([entry[S("ai_until")] doubleValue]>now){gAIActive=YES;gRingStarted[0]=MIN(gRingStarted[0],[entry[S("ai_since")] doubleValue]?:now);}if([entry[S("latest_reply")] isKindOfClass:NSString.class])remoteReply=entry[S("latest_reply")];}
    const char *vncFile=jbroot("/var/mobile/Library/AgentGoControl/vnc-presence.json");NSData *vncData=vncFile?[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:vncFile]]:nil;NSDictionary *vnc=vncData?[NSJSONSerialization JSONObjectWithData:vncData options:0 error:nil]:nil;if([vnc[S("active_until")] doubleValue]>now){gConnected=YES;if(!gVNCStarted)gVNCStarted=now;gRingStarted[2]=MIN(gRingStarted[2],gVNCStarted);}else gVNCStarted=0;
    NSString *capsuleSession=gRunning?gJob[S("id")]:gAIActive?remoteSession:gCapsuleSession;
    BOOL newTask=(gRunning&&!gPreviousLocalRunning)||(capsuleSession&&![capsuleSession isEqual:gCapsuleSession])||(!gRunning&&gAIActive&&!gPreviousCapsuleAI);
    if(newTask){gCapsuleDismissed=NO;gCapsuleTailUntil=0;gCapsuleSession=capsuleSession;ResetCapsulePosition();}
    NSString *voiceSession=[gVoiceState[@"session"] isKindOfClass:NSString.class]?gVoiceState[@"session"]:@"";BOOL newVoice=gVoiceActive&&(!gPreviousVoiceActive||![voiceSession isEqual:gCapsuleVoiceSession]);
    if(newVoice){gCapsuleDismissed=NO;ResetCapsulePosition();}gPreviousVoiceActive=gVoiceActive;if(gVoiceActive)gCapsuleVoiceSession=voiceSession;
    BOOL finishedLocal=gPreviousLocalRunning&&!gRunning&&![gJob[S("running")] boolValue]&&[gJob[S("id")] isEqual:gCapsuleSession];
    BOOL finishedRemote=gPreviousCapsuleAI&&!gAIActive&&!gRunning;
    if(finishedLocal||finishedRemote){gCapsuleFinalText=finishedLocal?(gJob[S("latest_reply")]?:gJob[S("status")]):gLastCapsuleText;gCapsuleTailUntil=now+3;gAIScreenPassUntil=0;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{Refresh(nil,NULL);Diagnostic(S("capsule_tail_expired"));});}
    gPreviousLocalRunning=gRunning;gPreviousCapsuleAI=gAIActive;
    BOOL tail=gCapsuleTailUntil>now;
    BOOL automatic=gAIActive||gRunning||gManualActive||gPending||tail||gComposing||gVoiceActive;NSString *session=gRunning||tail?gCapsuleSession:remoteSession?:gVoiceActive?gVoiceState[@"session"]:S("remote");if(![session isEqual:gAutoSession]||!automatic){gAutoSuppressed=NO;gAutoSession=session;}
    NSString *request=state[S("visibility_request")];if(gVisibilityRequest&&request&&![request isEqual:gVisibilityRequest])gAutoSuppressed=![state[S("enabled")] boolValue]&&automatic;if(request)gVisibilityRequest=request;
    BOOL visible=![state[S("enabled")] isEqual:@NO]||(automatic&&!gAutoSuppressed);if(gVisible!=visible){PCOverlayCancelTouch();gVisible=visible;gBubble.hidden=!visible;gPanel.hidden=YES;if(visible)PCOverlayRehostWindow();else[gAnswer resignFirstResponder];Diagnostic(visible?S("shown"):S("hidden"));}
    NSDictionary *foreground=ReadTask(S("foreground.json"));BOOL appVisible=[foreground[S("active")] boolValue]&&now-[foreground[S("updated")] doubleValue]<5;NSString *questionID=gPending[S("id")];BOOL changed=![questionID isEqual:gQuestionID];if(changed){gQuestionID=questionID;gQuestionDraft=S("");if(!gComposing)gAnswer.text=S("");}if(gPending&&visible&&!appVisible&&(changed||gPreviousAppVisible)){gPanel.hidden=NO;gQuestionAutoPanel=YES;}if(appVisible&&gQuestionAutoPanel){gPanel.hidden=YES;gQuestionAutoPanel=NO;[gAnswer resignFirstResponder];}gPreviousAppVisible=appVisible;
    gStatus.text=gComposing?PCLocalized(S("给 AI 发消息")):gPending?PCLocalized(S("等待你回答")):gAIActive?(gManualActive?PCLocalized(S("AI 控制 · 远端操作")):PCLocalized(S("AI 正在操控屏幕"))):gManualActive?PCLocalized(S("远端正在操作")):gConnected?PCLocalized(S("远程已连接")):gRunning?(gPaused?PCLocalized(S("任务已暂停")):PCLocalized(S("AI 正在运行"))):PCLocalized(S("任务已结束"));
    gPreview.text=gComposing?(gMessageFeedback?:(gComposeJob?PCLocalized(S("补充到当前任务，不会批准待确认操作")):PCLocalized(S("发送到应用中选中的对话")))):gPending?gPending[S("text")]:remoteReply?:gJob[S("latest_reply")]?:gJob[S("status")]?:PCLocalized(S("点继续可接着上次任务"));
    if(gVoiceActive&&!gPending&&!gComposing){gStatus.text=gAIActive?PCLocalized(@"AI 控屏 · 语音开启"):PCLocalized(gVoiceState[@"phase"])?:PCLocalized(@"悬浮语音");NSString *text=[gVoiceState[@"listening"] boolValue]?gVoiceState[@"transcript"]:nil;if(!text.length)text=gVoiceState[@"reply"];gPreview.text=[text length]?text:PCLocalized(@"说完停顿后发送，回复后继续聆听");}
    else if(!gVoiceActive&&!gPending&&!gComposing&&NSDate.date.timeIntervalSince1970-[gVoiceState[@"updated"] doubleValue]<8&&([gVoiceState[@"phase"] hasPrefix:@"暂时无法"]||[gVoiceState[@"phase"] hasPrefix:@"需要在应用"]||[gVoiceState[@"phase"] isEqual:@"语音已自动结束"])){gStatus.text=PCLocalized(gVoiceState[@"phase"]);gPreview.text=PCLocalized(gVoiceState[@"detail"]);}
    BOOL rootQuestion=[gPending[S("kind")] isEqual:S("root_permission")];
    if(rootQuestion){gStatus.text=PCLocalized(S("AI 申请 Root 权限"));gPreview.text=[NSString stringWithFormat:PCLocalized(@"%@\n%@\n打开应用可查看完整申请与操作"),gPending[S("name")]?:PCLocalized(S("本机操作")),gPending[S("arguments")][S("command")]?:gPending[S("arguments")][S("path")]?:S("")];}
    [gPauseButton setTitle:!gRunning?PCLocalized(S("继续")):gPaused?PCLocalized(S("继续")):PCLocalized(S("暂停")) forState:UIControlStateNormal];gPauseButton.enabled=YES;gStopButton.enabled=gRunning;gStopButton.alpha=gRunning?1:.65;[gPauseButton setImage:[UIImage systemImageNamed:gRunning&&!gPaused?S("pause.fill"):S("play.fill")] forState:UIControlStateNormal];[gPanel viewWithTag:410].backgroundColor=gPending?UIColor.systemOrangeColor:gRunning?UIColor.systemGreenColor:[UIColor colorWithWhite:.5 alpha:1];
    if(gSendingID){NSDictionary *receipt=PCMessageReceipt(TaskPath(S("")),gSendingID);if(receipt){BOOL accepted=[receipt[S("status")] isEqual:S("accepted")];gMessageFeedback=receipt[S("detail")];gSendingID=nil;if(accepted){if([gAnswer.text isEqual:gSendingText])gAnswer.text=S("");gComposeDraft=gAnswer.text;if(gComposing)EndComposition();}gSendingText=nil;}}
    gAnswer.placeholder=gComposing?PCLocalized(S("给 AI 发消息…")):PCLocalized(S("输入回答…"));gAnswer.hidden=gReply.hidden=!(gPending||gComposing);[gReply setTitle:gComposing?PCLocalized(S("发送消息")):PCLocalized(S("发送回答")) forState:UIControlStateNormal];gReply.enabled=!gSendingID;
    if(rootQuestion&&!gComposing){gAnswer.hidden=gReply.hidden=YES;if(gKeyboardRequested)DismissKeyboard(nil,NULL);}
    [((UIButton *)[gPanel viewWithTag:405]) setTitle:gComposing?PCLocalized(S("取消发消息")):PCLocalized(S("发消息")) forState:UIControlStateNormal];
    [gPanel viewWithTag:403].hidden=!(gPending||gComposing)||!gAnswer.isFirstResponder;if(!gPending&&!gComposing&&gKeyboardRequested)DismissKeyboard(nil,NULL);
    NSArray *answers=[gPending[S("options")] isKindOfClass:NSArray.class]?gPending[S("options")]:@[];for(NSUInteger i=0;i<gOptions.count;i++){UIButton *button=gOptions[i];button.hidden=!gPending||i>=answers.count;if(i<answers.count&&[answers[i] isKindOfClass:NSString.class])[button setTitle:answers[i] forState:UIControlStateNormal];}
    BOOL passing=gAIScreenPassUntil>now;gBubble.hidden=!visible||passing;if(passing)gPanel.hidden=YES;gFullInfoView.hidden=!visible||passing;
    NSString *capsuleText=tail?gCapsuleFinalText:gRunning?(gJob[S("latest_reply")]?:gJob[S("status")]):remoteReply;
    gLastCapsuleText=capsuleText?:PCLocalized(S("AI 正在操控屏幕"));
    if(gVoiceActive)capsuleText=VoiceCapsuleText(capsuleText,tail);else gCapsuleVoicePhase=nil;
    capsuleText=capsuleText?:PCLocalized(S("AI 正在操控屏幕"));capsuleText=[[capsuleText componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:S(" ")];
    gCapsuleNeeded=gRunning||gAIActive||tail||gVoiceActive;[gCapsule setTitle:capsuleText forState:UIControlStateNormal];gCapsule.accessibilityLabel=capsuleText;gCapsule.hidden=!visible||!gCapsuleNeeded||gCapsuleDismissed||passing;UpdateCapsuleVoiceFeedback();
    UIButton *capsuleToggle=(UIButton *)[gPanel viewWithTag:404];[capsuleToggle setTitle:gCapsule.hidden?PCLocalized(S("显示胶囊")):PCLocalized(S("隐藏胶囊")) forState:UIControlStateNormal];[capsuleToggle setImage:[UIImage systemImageNamed:gCapsule.hidden?@"capsule":@"eye.slash"] forState:UIControlStateNormal];capsuleToggle.enabled=gCapsuleNeeded;capsuleToggle.alpha=gCapsuleNeeded?1:.65;
    CGFloat width=[state[S("edge_width")] respondsToSelector:@selector(doubleValue)]?[state[S("edge_width")] doubleValue]:14;CGFloat opacity=[state[S("edge_opacity")] respondsToSelector:@selector(doubleValue)]?[state[S("edge_opacity")] doubleValue]:.7;UpdateEdgeStyle(width,opacity);
    gBubble.layer.borderWidth=0;PositionPanel();UpdateRingOrder();UpdateRings(gBubble,gBubbleRings);gEdge.hidden=!gAIActive||!gEffects[3]||gAutoSuppressed;
    if(newTask||newVoice||finishedLocal||finishedRemote||wasCapsuleHidden!=gCapsule.hidden||wasLocked!=gCapsuleLocked)Diagnostic(tail?S("capsule_final_reply"):S("capsule_updated"));
}

static BOOL WindowYes(id self, SEL selector) { return YES; }
static BOOL WindowNo(id self, SEL selector) { return NO; }

static CGFloat DisplayCornerRadius(void) {
    for(NSString *name in @[@"_displayCornerRadius",@"_traitCollectionDisplayCornerRadius"]){SEL selector=NSSelectorFromString(name);Method method=class_getInstanceMethod(UIScreen.mainScreen.class,selector);if(method&&method_getNumberOfArguments(method)==2){char *type=method_copyReturnType(method);BOOL numeric=type&&type[0]=='d';free(type);if(numeric){CGFloat radius=((CGFloat(*)(id,SEL))objc_msgSend)(UIScreen.mainScreen,selector);if(isfinite(radius)&&radius>=0&&radius<100)return radius;}}}
    return 0; // Unknown geometry stays conservative instead of guessing a model.
}
static void CreateEdgeEffect(UIView *view) {
    const CGFloat width=28;gDisplayCornerRadius=DisplayCornerRadius();
    gEdge=[CALayer layer];gEdge.frame=gWindow.bounds;gEdge.hidden=YES;LayerInput(gEdge,NO);
    CGFloat diameter=hypot(CGRectGetWidth(gWindow.bounds),CGRectGetHeight(gWindow.bounds))+width*2;
    CAGradientLayer *light=[CAGradientLayer layer];light.bounds=CGRectMake(0,0,diameter,diameter);light.position=CGPointMake(CGRectGetMidX(gWindow.bounds),CGRectGetMidY(gWindow.bounds));light.type=kCAGradientLayerConic;light.startPoint=CGPointMake(.5,.5);light.endPoint=CGPointMake(1,.5);
    light.colors=@[(id)[UIColor colorWithRed:0 green:.75 blue:1 alpha:1].CGColor,(id)[UIColor colorWithRed:.7 green:.12 blue:1 alpha:1].CGColor,(id)[UIColor colorWithRed:1 green:.08 blue:.5 alpha:1].CGColor,(id)[UIColor colorWithRed:1 green:.48 blue:.03 alpha:1].CGColor,(id)[UIColor colorWithRed:0 green:.75 blue:1 alpha:1].CGColor];
    light.locations=@[@0,@.25,@.50,@.75,@1];LayerInput(light,NO);[gEdge addSublayer:light];[view.layer addSublayer:gEdge];
    UpdateEdgeStyle(14,.7);
    CABasicAnimation *flow=[CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];flow.fromValue=@0;flow.toValue=@(M_PI*2);flow.duration=7;flow.repeatCount=HUGE_VALF;flow.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];[light addAnimation:flow forKey:@"edgeFlow"];
}
static UIBezierPath *EdgeOutline(CGRect rect,CGFloat radius,CGFloat notchWidth,CGFloat notchBottom,CGFloat notchCorner,CGFloat shoulder){
    if(notchWidth<=0)return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
    CGFloat x=CGRectGetMinX(rect),y=CGRectGetMinY(rect),right=CGRectGetMaxX(rect),bottom=CGRectGetMaxY(rect),center=CGRectGetMidX(rect),leftNotch=center-notchWidth/2,rightNotch=center+notchWidth/2;
    radius=MIN(radius,CGRectGetWidth(rect)/4);shoulder=MIN(shoulder,MAX(0,leftNotch-x-radius));notchCorner=MIN(notchCorner,MIN(notchWidth/2,MAX(0,notchBottom-y-shoulder)));
    UIBezierPath *path=[UIBezierPath bezierPath];[path moveToPoint:CGPointMake(x+radius,y)];[path addLineToPoint:CGPointMake(leftNotch-shoulder,y)];[path addQuadCurveToPoint:CGPointMake(leftNotch,y+shoulder) controlPoint:CGPointMake(leftNotch,y)];[path addLineToPoint:CGPointMake(leftNotch,notchBottom-notchCorner)];[path addQuadCurveToPoint:CGPointMake(leftNotch+notchCorner,notchBottom) controlPoint:CGPointMake(leftNotch,notchBottom)];[path addLineToPoint:CGPointMake(rightNotch-notchCorner,notchBottom)];[path addQuadCurveToPoint:CGPointMake(rightNotch,notchBottom-notchCorner) controlPoint:CGPointMake(rightNotch,notchBottom)];[path addLineToPoint:CGPointMake(rightNotch,y+shoulder)];[path addQuadCurveToPoint:CGPointMake(rightNotch+shoulder,y) controlPoint:CGPointMake(rightNotch,y)];[path addLineToPoint:CGPointMake(right-radius,y)];[path addQuadCurveToPoint:CGPointMake(right,y+radius) controlPoint:CGPointMake(right,y)];[path addLineToPoint:CGPointMake(right,bottom-radius)];[path addQuadCurveToPoint:CGPointMake(right-radius,bottom) controlPoint:CGPointMake(right,bottom)];[path addLineToPoint:CGPointMake(x+radius,bottom)];[path addQuadCurveToPoint:CGPointMake(x,bottom-radius) controlPoint:CGPointMake(x,bottom)];[path addLineToPoint:CGPointMake(x,y+radius)];[path addQuadCurveToPoint:CGPointMake(x+radius,y) controlPoint:CGPointMake(x,y)];[path closePath];return path;
}
static void UpdateEdgeStyle(CGFloat width,CGFloat opacity){
    static PCEdgeProfile previous;static CGSize previousSize;
    static PCScreenEdgeMask *previousSystemMask;
    width=isfinite(width)?MIN(28,MAX(4,width)):14;opacity=isfinite(opacity)?MIN(1,MAX(.2,opacity)):.7;
    if(gSystemEdgeMask){
        BOOL cached=gEdge.mask&&previousSystemMask==gSystemEdgeMask&&CGSizeEqualToSize(previousSize,gWindow.bounds.size)&&fabs(width-gEdgeWidth)<.01;
        if(!cached){CGImageRef band=[gSystemEdgeMask copyBandWithWidth:width];if(band){CALayer *mask=[CALayer layer];mask.frame=gWindow.bounds;mask.contents=(__bridge id)band;mask.contentsScale=UIScreen.mainScreen.scale;gEdge.mask=mask;CGImageRelease(band);previousSystemMask=gSystemEdgeMask;previousSize=gWindow.bounds.size;gEdgeWidth=width;cached=YES;}}
        if(cached){[CATransaction begin];[CATransaction setDisableActions:YES];gEdge.opacity=opacity;gEdgeOpacity=opacity;[CATransaction commit];return;}
    }
    previousSystemMask=nil;
    BOOL sameProfile=previous.kind==gEdgeProfile.kind&&fabs(previous.corner-gEdgeProfile.corner)<.01&&fabs(previous.notchWidth-gEdgeProfile.notchWidth)<.01&&fabs(previous.notchDepth-gEdgeProfile.notchDepth)<.01;
    if(gEdge.mask&&sameProfile&&CGSizeEqualToSize(previousSize,gWindow.bounds.size)&&fabs(width-gEdgeWidth)<.01&&fabs(opacity-gEdgeOpacity)<.005)return;
    previous=gEdgeProfile;previousSize=gWindow.bounds.size;gEdgeWidth=width;gEdgeOpacity=opacity;
    BOOL landscape=CGRectGetWidth(gWindow.bounds)>CGRectGetHeight(gWindow.bounds);CGRect bounds=landscape?CGRectMake(0,0,CGRectGetHeight(gWindow.bounds),CGRectGetWidth(gWindow.bounds)):gWindow.bounds;
    UIBezierPath *band=EdgeOutline(bounds,gEdgeProfile.corner,gEdgeProfile.notchWidth,gEdgeProfile.notchDepth,gEdgeProfile.notchCorner,gEdgeProfile.shoulder);
    CGFloat innerRadius=gEdgeProfile.corner>0?MAX(0,gEdgeProfile.corner-width):14;
    [band appendPath:EdgeOutline(CGRectInset(bounds,width,width),innerRadius,gEdgeProfile.notchWidth>0?gEdgeProfile.notchWidth+2*width:0,gEdgeProfile.notchDepth+width,gEdgeProfile.notchCorner+width,MAX(0,gEdgeProfile.shoulder-width))];
    if(landscape)[band applyTransform:CGAffineTransformMake(0,-1,1,0,0,CGRectGetHeight(gWindow.bounds))];
    [CATransaction begin];[CATransaction setDisableActions:YES];CAShapeLayer *mask=[CAShapeLayer layer];mask.frame=gWindow.bounds;mask.path=band.CGPath;mask.fillRule=kCAFillRuleEvenOdd;mask.fillColor=UIColor.whiteColor.CGColor;gEdge.mask=mask;gEdge.opacity=opacity;[CATransaction commit];
}
static void Start(id self, SEL selector) {
    if (gWindow) return;
    Class windowType = objc_allocateClassPair(UIWindow.class, "PCPocketPassWindow", 0);
    class_addMethod(windowType, @selector(pointInside:withEvent:), (IMP)PointInside, "B@:{CGPoint=dd}@");
    class_addMethod(object_getClass(windowType), sel_registerName("_isSystemWindow"), (IMP)WindowYes, "B@:");
    class_addMethod(windowType, sel_registerName("_isWindowServerHostingManaged"), (IMP)WindowNo, "B@:");
    class_addMethod(windowType, sel_registerName("_ignoresHitTest"), (IMP)WindowNo, "B@:");
    class_addMethod(windowType, sel_registerName("canBecomeKeyWindow"), (IMP)WindowYes, "B@:");
    class_addMethod(windowType, sel_registerName("_canBecomeKeyWindow"), (IMP)WindowYes, "B@:");
    class_addMethod(windowType, sel_registerName("_isSecure"), (IMP)WindowYes, "B@:");
    class_addMethod(windowType, sel_registerName("_shouldCreateContextAsSecure"), (IMP)WindowYes, "B@:");
    objc_registerClassPair(windowType);
    gWindow = [[windowType alloc] initWithFrame:UIScreen.mainScreen.bounds];
    gWindow.windowLevel = 10000010.0;
    gWindow.backgroundColor = UIColor.clearColor;
    gWindow.opaque=NO;
    UIViewController *controller = [PCAsterOverlayController new];
    controller.view.backgroundColor = UIColor.clearColor;
    controller.view.opaque=NO;
    gWindow.rootViewController = controller;
    gContentView=[[UIView alloc] initWithFrame:gWindow.bounds];gContentView.backgroundColor=UIColor.clearColor;gContentView.opaque=NO;
    // Preserve hit testing of the controls, without an opaque full-screen
    // backing surface intercepting the app underneath.
    for(CALayer *layer in @[gWindow.layer,controller.view.layer,gContentView.layer]){
        SEL selector=NSSelectorFromString(@"setHitTestsAsOpaque:");
        if([layer respondsToSelector:selector])((void(*)(id,SEL,BOOL))objc_msgSend)(layer,selector,NO);
    }
    CreateEdgeEffect(controller.view);
    [controller.view addSubview:gContentView];
    CGFloat x = CGRectGetWidth(gWindow.bounds) - 68;
    CGFloat y = CGRectGetHeight(gWindow.bounds) * 0.55;
    gBubble = Button(nil, @selector(togglePanel));
    gBubble.hidden = YES;
    gBubble.frame = CGRectMake(x, y, 52, 52);
    gBubble.backgroundColor = UIColor.clearColor;
    [gBubble setImage:BrandIcon(SystemStyle()==UIUserInterfaceStyleDark) forState:UIControlStateNormal];
    gBubble.tintColor = UIColor.whiteColor;
    gBubble.imageEdgeInsets = UIEdgeInsetsZero;
    gBubble.imageView.contentMode = UIViewContentModeScaleAspectFit;
    gBubble.accessibilityLabel = PCLocalized(S("AsterHand 任务控制"));
    [gBubble setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    gBubble.titleLabel.font = [UIFont systemFontOfSize:27 weight:UIFontWeightMedium];
    gBubble.layer.cornerRadius = 52*.224;
    gBubble.layer.cornerCurve = kCACornerCurveContinuous;
    gBubble.layer.shadowColor = UIColor.blackColor.CGColor;
    gBubble.layer.shadowOpacity = 0.3;
    gBubble.layer.shadowRadius = 7;
    [gBubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:gController action:@selector(drag:)]];
    [gContentView addSubview:gBubble];
    gPanel=[[UIView alloc] initWithFrame:CGRectMake(12,y-54,280,220)];gPanel.backgroundColor=[UIColor colorWithWhite:0.12 alpha:.8];gPanel.layer.cornerRadius=24;gPanel.layer.cornerCurve=kCACornerCurveContinuous;gPanel.layer.shadowColor=UIColor.blackColor.CGColor;gPanel.layer.shadowOpacity=.25;gPanel.layer.shadowRadius=24;gPanel.layer.shadowOffset=CGSizeMake(0,8);gPanel.hidden=YES;
    gPanelMaterial=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];gPanelMaterial.frame=gPanel.bounds;gPanelMaterial.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;gPanelMaterial.layer.cornerRadius=24;gPanelMaterial.clipsToBounds=YES;gPanelMaterial.userInteractionEnabled=NO;LayerInput(gPanelMaterial.layer,NO);[gPanel addSubview:gPanelMaterial];
    gPanelViewport=[[UIView alloc] initWithFrame:gPanel.bounds];gPanelViewport.layer.cornerRadius=24;gPanelViewport.clipsToBounds=YES;[gPanel addSubview:gPanelViewport];
    gPanelContent=[UIView new];[gPanelViewport addSubview:gPanelContent];
    gVoiceCard=[UIView new];gVoiceCard.layer.cornerRadius=16;gVoiceCard.layer.cornerCurve=kCACornerCurveContinuous;gVoiceCard.userInteractionEnabled=NO;LayerInput(gVoiceCard.layer,NO);[gPanelContent addSubview:gVoiceCard];
    gPanelScrollThumb=[UIView new];gPanelScrollThumb.backgroundColor=[UIColor colorWithWhite:1 alpha:.35];gPanelScrollThumb.layer.cornerRadius=1;gPanelScrollThumb.userInteractionEnabled=NO;[gPanelViewport addSubview:gPanelScrollThumb];
    gPanelScrollPan=[[UIPanGestureRecognizer alloc] initWithTarget:gController action:@selector(scrollPanel:)];gPanelScrollPan.maximumNumberOfTouches=1;[gPanelViewport addGestureRecognizer:gPanelScrollPan];
    // Listen on the menu surface so disabled controls also expose their help.
    UILongPressGestureRecognizer *menuInfo=[[UILongPressGestureRecognizer alloc] initWithTarget:gController action:@selector(showFullInfo:)];menuInfo.minimumPressDuration=.5;menuInfo.cancelsTouchesInView=YES;[gPanelViewport addGestureRecognizer:menuInfo];
    gStatus=[[UILabel alloc] initWithFrame:CGRectMake(14,12,252,24)];gStatus.textColor=UIColor.whiteColor;gStatus.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];gStatus.lineBreakMode=NSLineBreakByTruncatingTail;[gPanelContent addSubview:gStatus];
    gPreview=[[UILabel alloc] initWithFrame:CGRectMake(14,42,252,52)];gPreview.textColor=[UIColor colorWithWhite:0.8 alpha:1];gPreview.font=[UIFont systemFontOfSize:13];gPreview.numberOfLines=2;AddFullInfo(gPreview,nil);AddFullInfo(gStatus,nil);gPreview.lineBreakMode=NSLineBreakByTruncatingTail;[gPanelContent addSubview:gPreview];
    gPauseButton=Button(PCLocalized(S("继续")),@selector(pauseOrResume));gStopButton=Button(PCLocalized(S("停止")),@selector(stopTask));[gStopButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];[gPanelContent addSubview:gPauseButton];[gPanelContent addSubview:gStopButton];
    UIButton *open=Button(PCLocalized(S("打开应用")),@selector(openApp));open.tag=401;[gPanelContent addSubview:open];
    gAnswer=[[UITextField alloc] initWithFrame:CGRectMake(14,104,252,38)];gAnswer.placeholder=PCLocalized(S("输入回答"));gAnswer.backgroundColor=[UIColor colorWithWhite:0.2 alpha:1];gAnswer.textColor=UIColor.whiteColor;gAnswer.layer.cornerRadius=12;gAnswer.font=[UIFont systemFontOfSize:15];gAnswer.clearButtonMode=UITextFieldViewModeWhileEditing;gAnswer.leftView=[[UIView alloc] initWithFrame:CGRectMake(0,0,12,1)];gAnswer.leftViewMode=UITextFieldViewModeAlways;gAnswer.returnKeyType=UIReturnKeySend;[gAnswer addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:gController action:@selector(focusAnswer)]];[gAnswer addTarget:gController action:@selector(focusAnswer) forControlEvents:UIControlEventEditingDidBegin];[gAnswer addTarget:gController action:@selector(sendAnswer) forControlEvents:UIControlEventEditingDidEndOnExit];[gPanelContent addSubview:gAnswer];
    gOptions=[NSMutableArray new];for(NSInteger i=0;i<4;i++){UIButton *button=Button(nil,@selector(pickAnswer:));button.tag=i;button.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;button.titleLabel.numberOfLines=1;button.frame=CGRectMake(12+(i%2)*134,150+(i/2)*44,122,38);button.backgroundColor=[UIColor colorWithWhite:0.2 alpha:1];button.layer.cornerRadius=10;[gPanelContent addSubview:button];[gOptions addObject:button];}
    gReply=Button(PCLocalized(S("发送回答")),@selector(sendAnswer));gReply.frame=CGRectMake(14,244,172,36);[gPanelContent addSubview:gReply];
    UIButton *dismiss=Button(PCLocalized(S("收起键盘")),@selector(dismissKeyboard));dismiss.frame=CGRectMake(194,244,72,36);dismiss.titleLabel.font=[UIFont systemFontOfSize:13];dismiss.tag=403;[gPanelContent addSubview:dismiss];UIToolbar *toolbar=[[UIToolbar alloc] initWithFrame:CGRectMake(0,0,CGRectGetWidth(gWindow.bounds),44)];toolbar.items=@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],[[UIBarButtonItem alloc] initWithTitle:PCLocalized(S("收起键盘")) style:UIBarButtonItemStyleDone target:gController action:@selector(dismissKeyboard)]];gAnswer.inputAccessoryView=toolbar;
    [gContentView addSubview:gPanel];
    UIButton *show=Button(PCLocalized(S("显示胶囊")),@selector(showCapsule));show.tag=404;show.titleLabel.font=[UIFont systemFontOfSize:13];[gPanelContent addSubview:show];
    CGFloat capsuleWidth=MIN(320,CGRectGetWidth(gWindow.bounds)-32),capsuleY=gDisplayCornerRadius>0?60:26;gCapsule=Button(PCLocalized(S("AI 正在操控屏幕")),@selector(hideCapsule));gCapsule.frame=CGRectMake((CGRectGetWidth(gWindow.bounds)-capsuleWidth)/2,capsuleY,capsuleWidth,38);gCapsule.backgroundColor=[UIColor colorWithWhite:.15 alpha:.94];gCapsule.layer.cornerRadius=18;gCapsule.layer.borderWidth=.5;gCapsule.layer.borderColor=[UIColor colorWithWhite:.5 alpha:.35].CGColor;gCapsule.tintColor=UIColor.whiteColor;gCapsule.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];gCapsule.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;gCapsule.titleLabel.numberOfLines=1;gCapsule.contentEdgeInsets=UIEdgeInsetsMake(0,14,0,14);[gCapsule setTitleColor:[UIColor colorWithWhite:.9 alpha:1] forState:UIControlStateNormal];gCapsule.hidden=YES;[gCapsule addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:gController action:@selector(dragCapsule:)]];[gContentView addSubview:gCapsule];
    gCapsuleVoiceDot=[CALayer layer];gCapsuleVoiceDot.bounds=CGRectMake(0,0,6,6);gCapsuleVoiceDot.cornerRadius=3;gCapsuleVoiceDot.hidden=YES;LayerInput(gCapsuleVoiceDot,NO);[gCapsule.layer addSublayer:gCapsuleVoiceDot];
    UILongPressGestureRecognizer *capsuleInfo=[[UILongPressGestureRecognizer alloc] initWithTarget:gController action:@selector(showFullInfo:)];capsuleInfo.minimumPressDuration=.5;capsuleInfo.cancelsTouchesInView=YES;[gCapsule addGestureRecognizer:capsuleInfo];
    /* Drag position intentionally lasts only for this task. */


    UIButton *message=Button(PCLocalized(S("发消息")),@selector(composeMessage));message.tag=405;[gPanelContent addSubview:message];UIButton *hide=Button(PCLocalized(S("隐藏悬浮窗")),@selector(hideOverlay));hide.tag=406;[gPanelContent addSubview:hide];
    UIButton *voice=Button(PCLocalized(@"语音对话"),@selector(voiceToggle));voice.tag=407;[gPanelContent addSubview:voice];UIButton *voiceSecondary=Button(PCLocalized(@"发送这句"),@selector(voiceSecondary));voiceSecondary.tag=408;[gPanelContent addSubview:voiceSecondary];StyleMenuButton(voice,@"waveform");StyleMenuButton(voiceSecondary,@"arrow.up");
    UIButton *muteMic=Button(PCLocalized(@"麦克风静音"),@selector(voiceMuteMicrophone));muteMic.tag=409;[gPanelContent addSubview:muteMic];StyleMenuButton(muteMic,@"mic.fill");UIButton *muteSpeech=Button(PCLocalized(@"朗读静音"),@selector(voiceMuteSpeech));muteSpeech.tag=411;[gPanelContent addSubview:muteSpeech];StyleMenuButton(muteSpeech,@"speaker.wave.2.fill");
    StyleMenuButton(gPauseButton,S("play.fill"));StyleMenuButton(gStopButton,S("stop.fill"));gStopButton.backgroundColor=[UIColor.systemRedColor colorWithAlphaComponent:.12];gStopButton.tintColor=UIColor.systemRedColor;[gStopButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    StyleMenuButton(message,S("bubble.left"));StyleMenuButton(hide,S("eye.slash"));StyleMenuButton(open,S("arrow.up.forward.app"));StyleMenuButton(show,S("capsule"));
    for(UIButton *button in @[open,show]){button.backgroundColor=UIColor.clearColor;button.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];button.tintColor=[UIColor colorWithWhite:.7 alpha:1];[button setTitleColor:button.tintColor forState:UIControlStateNormal];}
    StyleMenuButton(gReply,S("arrow.up"));gReply.backgroundColor=[UIColor colorWithWhite:.94 alpha:1];gReply.tintColor=UIColor.blackColor;[gReply setTitleColor:UIColor.blackColor forState:UIControlStateNormal];StyleMenuButton(dismiss,S("keyboard.chevron.compact.down"));[dismiss setTitle:PCLocalized(S("收起")) forState:UIControlStateNormal];dismiss.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    for(UIButton *button in gOptions)StyleMenuButton(button,nil);
    UIView *dot=[[UIView alloc] initWithFrame:CGRectZero];dot.tag=410;dot.layer.cornerRadius=3;dot.backgroundColor=UIColor.systemGreenColor;[gPanelContent addSubview:dot];
    gBubbleRings=MakeRings(gBubble);
    [NSTimer scheduledTimerWithTimeInterval:0.5 target:gController selector:@selector(refresh) userInfo:nil repeats:YES];
    ApplyTheme();Refresh(nil, NULL);
    Diagnostic(S("window_created"));
}

void PCOverlayCreateControls(void) {
    Class type = objc_allocateClassPair(NSObject.class, "PCPocketOverlayController", 0);
    class_addMethod(type,@selector(showFullInfo:),(IMP)FullInfo,"v@:@");
    class_addMethod(type,@selector(closeFullInfo),(IMP)CloseFullInfo,"v@:");
    class_addMethod(type, @selector(start), (IMP)Start, "v@:");
    class_addMethod(type, @selector(refresh), (IMP)Refresh, "v@:");
    class_addMethod(type, @selector(togglePanel), (IMP)Toggle, "v@:");
    class_addMethod(type, @selector(pauseOrResume), (IMP)Pause, "v@:");
    class_addMethod(type, @selector(stopTask), (IMP)Stop, "v@:");
    class_addMethod(type, @selector(openApp), (IMP)Open, "v@:");
    class_addMethod(type,@selector(sendAnswer),(IMP)SendAnswer,"v@:");
    class_addMethod(type,@selector(focusAnswer),(IMP)FocusAnswer,"v@:");
    class_addMethod(type,@selector(dismissKeyboard),(IMP)DismissKeyboard,"v@:");
    class_addMethod(type,@selector(pickAnswer:),(IMP)PickAnswer,"v@:@");
    class_addMethod(type,@selector(keyboardChanged:),(IMP)Keyboard,"v@:@");
    class_addMethod(type, @selector(drag:), (IMP)Drag, "v@:@");
    class_addMethod(type, @selector(dragCapsule:), (IMP)DragCapsule, "v@:@");
    class_addMethod(type, @selector(hideCapsule), (IMP)HideCapsule, "v@:");
    class_addMethod(type,@selector(scrollPanel:),(IMP)ScrollPanel,"v@:@");
    class_addMethod(type,@selector(composeMessage),(IMP)ComposeMessage,"v@:");
    class_addMethod(type,@selector(hideOverlay),(IMP)HideOverlay,"v@:");
    class_addMethod(type,@selector(voiceToggle),(IMP)VoiceToggle,"v@:");
    class_addMethod(type,@selector(voiceMuteMicrophone),(IMP)VoiceMuteMicrophone,"v@:");
    class_addMethod(type,@selector(voiceMuteSpeech),(IMP)VoiceMuteSpeech,"v@:");
    class_addMethod(type,@selector(voiceSecondary),(IMP)VoiceSecondary,"v@:");
    class_addMethod(type, @selector(showCapsule), (IMP)ShowCapsule, "v@:");
    objc_registerClassPair(type);
    gController = [type new];
    [NSNotificationCenter.defaultCenter addObserver:gController selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:gController selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:gController selector:@selector(keyboardChanged:) name:UIKeyboardDidShowNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:gController selector:@selector(keyboardChanged:) name:UIKeyboardDidChangeFrameNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:gController selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    Start(gController, NULL);
    [gWindow makeKeyAndVisible];
    ObserveOrientation();
    Refresh(nil, NULL);
}

UIWindow *PCOverlayWindow(void) { return gWindow; }
BOOL PCOverlayControlsVisible(void) { return gVisible&&gAIScreenPassUntil<=NSDate.date.timeIntervalSince1970; }
BOOL PCOverlayAnswerFocused(void) {return gVisible&&gKeyboardRequested&&(gPending||gComposing)&&gAnswer.isFirstResponder;}
CGFloat PCOverlayKeyboardHeight(void) {return gKeyboardHeight;}
BOOL PCOverlayPointInKeyboard(CGPoint point){return gKeyboardRequested&&!CGRectIsEmpty(gKeyboardScreenFrame)&&CGRectContainsPoint(gKeyboardScreenFrame,point);}
UIWindow *PCOverlayInputAccessoryWindowAtPoint(CGPoint point) {UIView *accessory=gAnswer.inputAccessoryView;if(!accessory.window||accessory.hidden)return nil;CGPoint local=[accessory convertPoint:point fromView:gWindow];return CGRectContainsPoint(accessory.bounds,local)?accessory.window:nil;}
