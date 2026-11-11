#import "PCLocalization.h"
#import "PCRecovery.h"
#import "PCPlatform.h"
#import "PCHaptics.h"
#import "PCButtonCompat.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static NSString *PCRecoveryDirectory(void){return PCRealPath(@"/var/mobile/Library/PocketAgentControl");}
BOOL PCServicesEnabled(void){NSData *data=[NSData dataWithContentsOfFile:[PCRecoveryDirectory() stringByAppendingPathComponent:@"services-master.json"]];id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;id enabled=[value isKindOfClass:NSDictionary.class]?value[@"enabled"]:nil;return ![enabled isKindOfClass:NSNumber.class]||[enabled boolValue];}
static NSString *PCRecoveryStart(NSString *action,NSError **error){
    NSString *directory=PCRecoveryDirectory();struct stat metadata;
    if(geteuid()!=501||lstat(directory.fileSystemRepresentation,&metadata)||!S_ISDIR(metadata.st_mode)||metadata.st_uid!=501||(metadata.st_mode&0022)){if(error)*error=[NSError errorWithDomain:@"AsterHand.Recovery" code:1 userInfo:@{NSLocalizedDescriptionKey:PCLocalized(@"恢复目录不可安全访问，请重新安装插件。")}];return nil;}
    NSString *nonce=[NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if(![@[@"restart_services",@"stop_services"] containsObject:action])return nil;
    NSDictionary *request=@{@"nonce":nonce,@"created":@(NSDate.date.timeIntervalSince1970),@"action":action};NSData *bytes=[NSJSONSerialization dataWithJSONObject:request options:0 error:error];
    int parent=open(directory.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);NSString *temporary=[@".recover-request-" stringByAppendingString:nonce];int fd=parent>=0?openat(parent,temporary.UTF8String,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600):-1;BOOL ok=bytes&&fd>=0;
    if(ok){size_t offset=0;ssize_t count;while(offset<bytes.length&&(count=write(fd,(const char *)bytes.bytes+offset,bytes.length-offset))>0)offset+=(size_t)count;ok=offset==bytes.length&&fchmod(fd,0600)==0&&fsync(fd)==0;}
    if(fd>=0)close(fd);if(ok)ok=renameat(parent,temporary.UTF8String,parent,"recovery-request.json")==0;if(parent>=0){if(!ok)unlinkat(parent,temporary.UTF8String,0);close(parent);}
    if(!ok){if(error)*error=[NSError errorWithDomain:@"AsterHand.Recovery" code:2 userInfo:@{NSLocalizedDescriptionKey:PCLocalized(@"无法写入恢复请求，请检查应用目录权限。")}];return nil;}return nonce;
}
static NSDictionary *PCRecoveryResult(NSString *nonce){
    NSString *path=[PCRecoveryDirectory() stringByAppendingPathComponent:@"recovery-result.json"];int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);if(fd<0)return nil;struct stat metadata;NSMutableData *bytes=nil;
    if(!fstat(fd,&metadata)&&S_ISREG(metadata.st_mode)&&metadata.st_uid==501&&metadata.st_nlink==1&&(metadata.st_mode&0777)==0600&&metadata.st_size>=2&&metadata.st_size<=32768){bytes=[NSMutableData dataWithLength:(NSUInteger)metadata.st_size];size_t offset=0;ssize_t count;while(offset<bytes.length&&(count=read(fd,(char *)bytes.mutableBytes+offset,bytes.length-offset))>0)offset+=(size_t)count;struct stat after;if(offset!=bytes.length||fstat(fd,&after)||metadata.st_ino!=after.st_ino||metadata.st_dev!=after.st_dev||metadata.st_size!=after.st_size||metadata.st_mtimespec.tv_sec!=after.st_mtimespec.tv_sec||metadata.st_mtimespec.tv_nsec!=after.st_mtimespec.tv_nsec)bytes=nil;}close(fd);
    id result=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil]:nil;return [result isKindOfClass:NSDictionary.class]&&[result[@"nonce"] isEqual:nonce]?result:nil;
}
@interface PCRecoveryController ()
@property(nonatomic,strong) UILabel *message,*progress;
@property(nonatomic,strong) UIButton *restart;
@property(nonatomic,strong) UISwitch *master;
@property(nonatomic) BOOL desiredEnabled;
@property(nonatomic) BOOL previousEnabled;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) NSString *nonce;
@property(nonatomic) NSTimeInterval started;
@end
NSString *PCServicesRequest(NSString *action,NSError **error){return PCRecoveryStart(action,error);}
NSDictionary *PCServicesResult(NSString *nonce){return PCRecoveryResult(nonce);}
@implementation PCRecoveryController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=PCLocalized(@"重启所有服务");self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;self.view.tintColor=UIColor.labelColor;
    self.message=[UILabel new];self.message.text=PCLocalized(@"关闭所有服务会停止 AI 任务、语音、远控和悬浮窗。重新开启后恢复原有服务设置，但不会自动重试任务。\n\n项目、文件、登录与配对会保留。");self.message.numberOfLines=0;self.message.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];self.message.textColor=UIColor.secondaryLabelColor;
    self.progress=[UILabel new];self.progress.numberOfLines=0;self.progress.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];self.progress.textColor=UIColor.labelColor;
    UILabel *masterLabel=[UILabel new];masterLabel.text=PCLocalized(@"所有服务");masterLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.master=[UISwitch new];self.master.on=PCServicesEnabled();[self.master addTarget:self action:@selector(changeMaster:) forControlEvents:UIControlEventValueChanged];
    UIStackView *masterRow=[[UIStackView alloc] initWithArrangedSubviews:@[masterLabel,self.master]];masterRow.axis=UILayoutConstraintAxisHorizontal;masterRow.distribution=UIStackViewDistributionEqualSpacing;masterRow.alignment=UIStackViewAlignmentCenter;
    self.restart=[UIButton buttonWithType:UIButtonTypeSystem];PCStyleButton(self.restart,PCButtonFilled);
    if(@available(iOS 15.0,*)){UIButtonConfiguration *configuration=self.restart.configuration;configuration.baseBackgroundColor=UIColor.labelColor;configuration.baseForegroundColor=UIColor.systemBackgroundColor;self.restart.configuration=configuration;}
    [self.restart setTitle:PCLocalized(@"确认重启所有服务") forState:UIControlStateNormal];[self.restart.heightAnchor constraintGreaterThanOrEqualToConstant:48].active=YES;[self.restart addTarget:self action:@selector(startRecovery) forControlEvents:UIControlEventTouchUpInside];
    self.restart.enabled=self.master.on;UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[masterRow,self.message,self.progress,self.restart]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=24;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:stack];UILayoutGuide *guide=self.view.safeAreaLayoutGuide;[NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:24],[stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-20]]];
}
- (void)dealloc {[self.timer invalidate];}
- (void)startRecovery {
    self.previousEnabled=self.master.on;
    [self beginAction:@"restart_services" desired:YES];
}
- (void)changeMaster:(UISwitch *)sender {self.previousEnabled=!sender.on;[self beginAction:sender.on?@"restart_services":@"stop_services" desired:sender.on];}
- (void)beginAction:(NSString *)action desired:(BOOL)desired {
    if(self.timer)return;self.desiredEnabled=desired;PCHaptic(@"warning");if(self.beforeRestart)self.beforeRestart();NSError *error=nil;self.nonce=PCRecoveryStart(action,&error);
    if(!self.nonce){self.master.on=self.previousEnabled;self.progress.text=error.localizedDescription?:PCLocalized(@"无法发送恢复请求。");return;}
    self.master.enabled=NO;self.restart.enabled=NO;self.started=NSProcessInfo.processInfo.systemUptime;self.progress.text=PCLocalized(@"正在联系独立恢复服务…");__weak typeof(self) weakSelf=self;
    self.timer=[NSTimer timerWithTimeInterval:.5 repeats:YES block:^(NSTimer *timer){PCRecoveryController *s=weakSelf;if(!s){[timer invalidate];return;}NSDictionary *result=PCRecoveryResult(s.nonce);if(result){s.progress.text=[result[@"detail"] isKindOfClass:NSString.class]?result[@"detail"]:PCLocalized(@"正在恢复服务…");if([result[@"done"] boolValue]){[s finishRecovery:[result[@"ok"] boolValue]];return;}}if(NSProcessInfo.processInfo.systemUptime-s.started>135){s.progress.text=PCLocalized(@"恢复服务未及时回应。请检查越狱状态与安装情况；原任务不会自动重放。");[s finishRecovery:NO];}}];[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)finishRecovery:(BOOL)success {[self.timer invalidate];self.timer=nil;self.master.enabled=YES;self.master.on=success?self.desiredEnabled:self.previousEnabled;self.restart.enabled=self.master.on;[self.restart setTitle:success?PCLocalized(@"再次重启"):PCLocalized(@"重新尝试") forState:UIControlStateNormal];PCHaptic(success?@"success":@"error");}
@end
