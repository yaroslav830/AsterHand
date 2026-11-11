#import <UIKit/UIKit.h>

extern NSString * const PCVoiceActionNotification;
BOOL PCVoiceActionValid(NSString *action);
NSUserActivity *PCVoiceShortcutActivity(NSString *action);
NSDictionary *PCVoiceCapabilities(void);
BOOL PCVoiceFloatingLaunchValid(NSString *requestID);

// Owned by the visible app, never by the Root service or the overlay host.
@interface PCVoiceSession : NSObject
@property(nonatomic,readonly) BOOL active;
@property(nonatomic,readonly) BOOL listening;
@property(nonatomic,readonly) BOOL speaking;
@property(nonatomic,readonly,copy) NSString *phase;
@property(nonatomic,readonly,copy) NSString *detail;
@property(nonatomic,readonly,copy) NSString *transcript;
@property(nonatomic,readonly,copy) NSString *spokenText;
@property(nonatomic) BOOL allowsBackground;
@property(nonatomic) BOOL microphoneMuted;
@property(nonatomic) BOOL speechMuted;
@property(nonatomic,copy) NSString *launchRequestID;
@property(nonatomic,readonly,copy) NSString *controlSessionID;
@property(nonatomic,copy) void (^changed)(void);
@property(nonatomic,copy) BOOL (^submitText)(NSString *text);
- (void)startWaiting:(BOOL)waiting;
- (void)stop;
- (void)waitForAI;
- (void)listen;
- (void)submitUtterance;
- (void)speak:(NSString *)text thenListen:(BOOL)listen;
- (void)interruptAndListen;
- (void)blockForConfirmation:(NSString *)text;
- (void)publishState;
@end

@interface PCVoiceController : UIViewController
@property(nonatomic,strong) PCVoiceSession *session;
@property(nonatomic,copy) BOOL (^AIIsRunning)(void);
@property(nonatomic,copy) void (^stopAI)(void);
@property(nonatomic) BOOL startOnAppearance;
@end

@interface PCVoiceSettingsController : UITableViewController
@end
