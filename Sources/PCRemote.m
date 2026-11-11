#import "PCLocalization.h"
#import "PCButtonCompat.h"
#import "PCRemote.h"
#import "PCPlatform.h"
#import "PCSupport.h"
#include <spawn.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <ifaddrs.h>
#include <arpa/inet.h>

@interface PCRemote ()
- (NSDictionary *)nextPendingConsent;
- (void)answerConsent:(NSString *)requestID allow:(BOOL)allow;
@end

@implementation PCRemote {
    pid_t _pid;
    NSMutableSet<NSString *> *_shownConsentIDs;
}
+ (instancetype)shared { static PCRemote *s; static dispatch_once_t once; dispatch_once(&once, ^{ s = [PCRemote new]; }); return s; }
- (instancetype)init { self = [super init]; if (self) _shownConsentIDs = [NSMutableSet new]; return self; }
- (NSString *)directory { return PCRealPath(@"/var/mobile/Library/PocketCodexRemote"); }
- (NSString *)settingsPath { return [[self directory] stringByAppendingPathComponent:@"remote-settings.json"]; }
- (NSDictionary *)settings {
    NSData *data = [NSData dataWithContentsOfFile:self.settingsPath];
    NSDictionary *settings = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [settings isKindOfClass:NSDictionary.class] ? settings : @{};
}
- (BOOL)autoApproveEnabled { return [self.settings[@"auto_approve"] boolValue]; }
- (void)writeSettings:(NSDictionary *)settings {
    NSString *directory = self.directory;
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:settings options:0 error:nil];
    if ([data writeToFile:self.settingsPath options:NSDataWritingAtomic error:nil]) chmod(self.settingsPath.fileSystemRepresentation, 0600);
}
- (void)setAutoApproveEnabled:(BOOL)enabled {
    NSMutableDictionary *settings = [self.settings mutableCopy];
    settings[@"auto_approve"] = @(enabled);
    [self writeSettings:settings];
}
- (void)trustHost:(NSString *)host {
    if (![host isKindOfClass:NSString.class] || !host.length || host.length > 96) return;
    NSMutableDictionary *settings = [self.settings mutableCopy];
    NSMutableOrderedSet *trusted = [NSMutableOrderedSet orderedSetWithArray:[settings[@"trusted_hosts"] isKindOfClass:NSArray.class] ? settings[@"trusted_hosts"] : @[]];
    [trusted addObject:host];
    settings[@"trusted_hosts"] = trusted.array;
    [self writeSettings:settings];
}
- (BOOL)hasPendingConsent {
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.directory error:nil])
        if ([name hasPrefix:@"pending-"]) return YES;
    return NO;
}
- (NSDictionary *)configuration {
    NSData *data = [NSData dataWithContentsOfFile:[[self directory] stringByAppendingPathComponent:@"phone.json"]];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}
- (BOOL)running {
    pid_t pid = _pid;
    if (pid <= 1) {
        NSString *pidPath = [[self directory] stringByAppendingPathComponent:@"remote.pid"];
        NSString *text = [NSString stringWithContentsOfFile:pidPath encoding:NSUTF8StringEncoding error:nil];
        pid = (pid_t)text.intValue;
    }
    return pid > 1 && (kill(pid, 0) == 0 || errno == EPERM);
}
- (NSString *)descriptionText {
    NSMutableArray *addresses = [NSMutableArray new];
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) == 0) {
        for (struct ifaddrs *p = list; p; p = p->ifa_next) {
            if (!p->ifa_addr || p->ifa_addr->sa_family != AF_INET || strcmp(p->ifa_name, "en0")) continue;
            char buf[INET_ADDRSTRLEN];
            if (inet_ntop(AF_INET, &((struct sockaddr_in *)p->ifa_addr)->sin_addr, buf, sizeof(buf))) [addresses addObject:[NSString stringWithUTF8String:buf]];
        }
        freeifaddrs(list);
    }
    NSDictionary *config = [self configuration];
    NSArray *trusted = [self.settings[@"trusted_hosts"] isKindOfClass:NSArray.class] ? self.settings[@"trusted_hosts"] : @[];
    NSString *mode = self.autoApproveEnabled ? PCLocalized(@"免确认：配对电脑连接时直接允许") : PCLocalized(@"按次确认：未记住的电脑连接时弹窗");
    return [NSString stringWithFormat:PCLocalized(@"后台服务：%@\n连接模式：%@\nWi-Fi：%@\n加密端口：5907\n\n%@\n\n证书 SHA-256：%@\n\n远控由 RootHide launchd 常驻，退出 AsterHand 后仍运行。按次确认模式下，新电脑连接会唤起 AsterHand 显示授权框；拒绝或 60 秒未处理即拒绝连接。选择“始终允许此电脑”后按来源地址记住。\n\n已记住的电脑：%@\n\n文本粘贴会覆盖手机剪贴板；文件传输已关闭。"), self.running ? PCLocalized(@"运行中") : PCLocalized(@"未运行"), mode, addresses.count ? [addresses componentsJoinedByString:@", "] : PCLocalized(@"未连接"), config ? PCLocalized(@"此设备已与电脑配对。电脑打开项目中的“启动手机远控.cmd”。") : PCLocalized(@"尚未配对，请先在电脑完成配对。"), config[@"fingerprint"] ?: PCLocalized(@"未配置"), trusted.count ? [trusted componentsJoinedByString:@", "] : PCLocalized(@"无")];
}
- (NSDictionary *)nextPendingConsent {
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.directory error:nil];
    NSMutableSet<NSString *> *liveIDs = [NSMutableSet new];
    NSMutableArray<NSDictionary *> *requests = [NSMutableArray new];
    for (NSString *name in [names sortedArrayUsingSelector:@selector(compare:)]) {
        if (![name hasPrefix:@"pending-"]) continue;
        NSString *path = [self.directory stringByAppendingPathComponent:name];
        NSData *requestData = [NSData dataWithContentsOfFile:path];
        NSDictionary *request = requestData ? [NSJSONSerialization JSONObjectWithData:requestData options:0 error:nil] : nil;
        NSString *requestID = [request[@"id"] isKindOfClass:NSString.class] ? request[@"id"] : nil;
        if (!requestID.length) continue;
        if ([request[@"created"] respondsToSelector:@selector(doubleValue)] &&
            NSDate.date.timeIntervalSince1970 - [request[@"created"] doubleValue] > 60.0) {
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            continue;
        }
        [liveIDs addObject:requestID];
        [requests addObject:request];
    }
    [_shownConsentIDs intersectSet:liveIDs];
    for (NSDictionary *request in requests) {
        NSString *requestID = request[@"id"];
        if ([_shownConsentIDs containsObject:requestID]) continue;
        [_shownConsentIDs addObject:requestID];
        return request;
    }
    return nil;
}
- (void)answerConsent:(NSString *)requestID allow:(BOOL)allow {
    if (!requestID.length) return;
    NSDictionary *response = @{ @"id": requestID, @"allow": @(allow) };
    NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
    NSString *path = [self.directory stringByAppendingPathComponent:[@"decision-" stringByAppendingString:requestID]];
    if ([data writeToFile:path options:NSDataWritingAtomic error:nil]) chmod(path.fileSystemRepresentation, 0600);
}
- (BOOL)start:(NSError **)error {
    if (self.running) return YES;
    if (error) *error = PCError(PCLocalized(@"RootHide 远控后台服务未运行。请重新安装 RootHide 版 AsterHand，并确认 launchd 服务已加载。"));
    return NO;
}
@end

@implementation PCRemoteController {
    UITextView *_details;
    UIButton *_toggle;
    NSTimer *_timer;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = PCLocalized(@"电脑远控"); self.view.backgroundColor = UIColor.systemBackgroundColor;
    _details = [UITextView new]; _details.editable = NO; _details.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _toggle = [UIButton buttonWithType:UIButtonTypeSystem]; PCStyleButton(_toggle,PCButtonFilled);
    [_toggle addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_details, _toggle]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:g.topAnchor constant:16], [stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-16], [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16], [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16]]];
    [self refresh];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; _timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refresh) userInfo:nil repeats:YES]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; [_timer invalidate]; _timer = nil; }
- (void)refresh {
    _details.text = PCRemote.shared.descriptionText;
    [_toggle setTitle:PCRemote.shared.autoApproveEnabled ? PCLocalized(@"关闭免确认远控") : PCLocalized(@"开启免确认远控") forState:UIControlStateNormal];
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || !self.view.window || self.presentedViewController) return;
    NSDictionary *request = [PCRemote.shared nextPendingConsent];
    if (![request isKindOfClass:NSDictionary.class]) return;
    NSString *requestID = request[@"id"] ?: @"";
    NSString *host = request[@"host"] ?: PCLocalized(@"未知设备");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:PCLocalized(@"允许电脑远控？")
        message:[NSString stringWithFormat:PCLocalized(@"%@ 请求连接。允许后，对方可查看 iPhone 屏幕、点击滑动并输入文字。"), host]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:PCLocalized(@"拒绝") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [PCRemote.shared answerConsent:requestID allow:NO];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:PCLocalized(@"允许本次连接") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [PCRemote.shared answerConsent:requestID allow:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:PCLocalized(@"始终允许此电脑") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [PCRemote.shared trustHost:host];
        [PCRemote.shared answerConsent:requestID allow:YES];
    }]];
    alert.preferredAction = alert.actions.firstObject;
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)toggle {
    [PCRemote.shared setAutoApproveEnabled:!PCRemote.shared.autoApproveEnabled];
    [self refresh];
}
@end
