#import "PCTheme.h"
#import "PCAppInfo.h"
#import "PCLocalization.h"
#import "PCUninstall.h"
#import "PCKeyboardCompat.h"
#import "PCButtonCompat.h"
#import "PCViewController.h"
#import "PCAgent.h"
#import "PCAPI.h"
#import "PCTools.h"
#import "PCSupport.h"
#import "PCHaptics.h"
#import "PCSelfTest.h"
#import "PCPlatform.h"
#import "PCRemote.h"
#import "PCChatGPTAuth.h"
#import "PCProjectStore.h"
#import "PCRoot.h"
#import "PCAttachment.h"
#import "PCOverlay.h"
#import "PCNotifications.h"
#import "PCControl.h"
#import "PCChatTimeline.h"
#import "PCPages.h"
#import "PCUserGuide.h"
#import "PCPairing.h"
#import "PCPersistentAgent.h"
#import "PCNetworkPermission.h"
#import "PCVoice.h"
#import "PCRecovery.h"
#import "PCAppRPC.h"
#import "PCMessageQueue.h"
#import <UserNotifications/UserNotifications.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "../third_party/qrcodegen/qrcodegen.h"
#import <unistd.h>
#import <notify.h>

static UITextView *textView(void) {
    UITextView *view = [UITextView new];
    view.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    view.backgroundColor = PCSoftColor();
    view.textContainerInset = UIEdgeInsetsMake(14, 12, 14, 12);
    view.layer.cornerRadius = 12;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.alwaysBounceVertical = YES;
    return view;
}
static BOOL PCAppSettingValid(NSString *key,id value){
    if([@[@"overlayEnabled",@"allowBackground",@"capsuleLocked",@"effectAI",@"effectRemoteInput",@"effectRemoteConnected",@"effectScreenEdge"] containsObject:key])return [value isKindOfClass:NSNumber.class]&&([value isEqual:@YES]||[value isEqual:@NO]);
    if([@[@"edgeWidth",@"edgeOpacity",@"voiceIdleTimeoutSeconds"] containsObject:key]){if(![value isKindOfClass:NSNumber.class]||!isfinite([value doubleValue]))return NO;double x=[value doubleValue];return [key isEqual:@"edgeWidth"]?(x>=4&&x<=28):[key isEqual:@"edgeOpacity"]?(x>=.2&&x<=1):(x>=1&&x<=3600);}
    if(![value isKindOfClass:NSString.class]||[value length]>2048)return NO;
    if([key isEqual:@"uiLanguage"])return [PCUILanguages() containsObject:value];
    if([key isEqual:@"provider"])return [@[@"openai",@"chatgpt"] containsObject:value];
    if([key isEqual:@"hapticStyle"])return [@[@"system",@"soft",@"crisp",@"strong",@"firm",@"success",@"selection"] containsObject:value];
    if([key hasPrefix:@"reasoningEffort."])return [@[@"",@"none",@"low",@"medium",@"high",@"xhigh",@"max"] containsObject:value];
    if([key hasPrefix:@"model."])return [value length]>0&&[value length]<=128&&[value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location==NSNotFound;
    if([key isEqual:@"apiBase.openai"]){if(![value length])return YES;NSURLComponents *u=[NSURLComponents componentsWithString:value];return [u.scheme.lowercaseString isEqual:@"https"]&&u.host.length&&!u.user&&!u.password&&!u.query&&!u.fragment;}return NO;
}

@interface PCApprovalController : UIViewController <UIAdaptivePresentationControllerDelegate>
@property(nonatomic, copy) NSString *details;
@property(nonatomic, copy) void (^reply)(BOOL);
- (void)resolve:(BOOL)allowed;
@end
@implementation PCApprovalController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PCCanvasColor();
    self.navigationItem.title = PCLocalized(@"确认本机操作");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"拒绝") style:UIBarButtonItemStylePlain target:self action:@selector(deny)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"执行") style:UIBarButtonItemStyleDone target:self action:@selector(allow)];
    UITextView *text = textView();
    text.editable = NO;
    text.text = self.details;
    [self.view addSubview:text];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[text.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],
        [text.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],
        [text.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [text.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12]]];
}
- (void)deny { [self resolve:NO]; }
- (void)allow { [self resolve:YES]; }
- (void)resolve:(BOOL)allowed {
    void (^reply)(BOOL) = self.reply;
    self.reply = nil;
    UIViewController *presenter = self.navigationController.presentingViewController;
    if (presenter) [presenter dismissViewControllerAnimated:YES completion:^{ if (reply) reply(allowed); }];
    else if (reply) reply(allowed);
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller { [self resolve:NO]; }
@end

@interface PCModelPicker : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, strong) NSArray<NSString *> *models;
@property(nonatomic, strong) NSArray<NSString *> *filtered;
@property(nonatomic, copy) NSString *selectedModel;
@property(nonatomic, copy) void (^selectModel)(NSString *);
@end
@implementation PCModelPicker
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PCLocalized(@"账户模型");
    self.filtered = self.models;
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchResultsUpdater = self;
    search.searchBar.placeholder = PCLocalized(@"搜索模型 ID");
    self.navigationItem.searchController = search;
    self.definesPresentationContext = YES;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)search {
    NSString *q = search.searchBar.text;
    self.filtered = q.length ? [self.models filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *m, NSDictionary *bindings) {
        return [m localizedCaseInsensitiveContainsString:q];
    }]] : self.models;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = self.filtered[indexPath.row];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    cell.accessoryType = [cell.textLabel.text isEqual:self.selectedModel] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.selectModel) self.selectModel(self.filtered[indexPath.row]);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface PCLightingController : UITableViewController
@end
@implementation PCLightingController
- (NSArray *)keys {return @[@"effectAI",@"effectRemoteInput",@"effectRemoteConnected",@"effectScreenEdge"];}
- (void)viewDidLoad {[super viewDidLoad];self.title=PCLocalized(@"灯效");self.view.tintColor=PCTextColor();self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=88;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return 6;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.selectionStyle=UITableViewCellSelectionStyleNone;
    if(index.row>=4){BOOL width=index.row==4;NSString *key=width?@"edgeWidth":@"edgeOpacity";double value=[NSUserDefaults.standardUserDefaults objectForKey:key]?[NSUserDefaults.standardUserDefaults doubleForKey:key]:(width?14:.7);
        cell.textLabel.text=width?PCLocalized(@"光带宽度"):PCLocalized(@"光带不透明度");cell.detailTextLabel.text=width?[NSString stringWithFormat:PCLocalized(@"%.0f 点"),value]:[NSString stringWithFormat:@"%.0f%%",value*100];cell.detailTextLabel.tag=601;
        UISlider *slider=[[UISlider alloc] initWithFrame:CGRectMake(0,0,148,44)];slider.minimumValue=width?4:.2;slider.maximumValue=width?28:1;slider.value=value;slider.tag=index.row;slider.accessibilityLabel=cell.textLabel.text;[slider addTarget:self action:@selector(styleChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=slider;return cell;}
    cell.textLabel.text=@[PCLocalized(@"AI 操控"),PCLocalized(@"远程操作"),PCLocalized(@"远程连接"),PCLocalized(@"屏幕边缘特效")][index.row];cell.detailTextLabel.text=@[PCLocalized(@"AI 查看或操作屏幕时，显示绿色边框。"),PCLocalized(@"远端点击、滑动或输入时，显示橙色边框。"),PCLocalized(@"设备保持远程连接时，显示蓝色边框。"),PCLocalized(@"AI 操控屏幕时，显示屏幕四周的流动光效。")][index.row];cell.detailTextLabel.numberOfLines=2;cell.detailTextLabel.font=[UIFont systemFontOfSize:13];cell.detailTextLabel.textColor=PCMutedColor();UISwitch *toggle=[UISwitch new];toggle.tag=index.row;toggle.on=![NSUserDefaults.standardUserDefaults objectForKey:[self keys][index.row]]||[NSUserDefaults.standardUserDefaults boolForKey:[self keys][index.row]];toggle.onTintColor=@[UIColor.systemGreenColor,UIColor.systemOrangeColor,UIColor.systemBlueColor,UIColor.systemPurpleColor][index.row];toggle.accessibilityLabel=cell.textLabel.text;[toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;return cell;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {return PCLocalized(@"边框按亮起时间由内向外排列，熄灭后自动补位。宽度与不透明度仅调整屏幕光带。");}
- (void)publish {NSDictionary *task=PCAgentTaskState();PCOverlayPublish([NSUserDefaults.standardUserDefaults boolForKey:@"overlayEnabled"],[task[@"running"] boolValue],[task[@"paused"] boolValue]);}
- (void)changed:(UISwitch *)toggle {[NSUserDefaults.standardUserDefaults setBool:toggle.on forKey:[self keys][toggle.tag]];[self publish];PCHaptic(@"select");}
- (void)styleChanged:(UISlider *)slider {BOOL width=slider.tag==4;double value=width?round(slider.value):slider.value;[NSUserDefaults.standardUserDefaults setDouble:value forKey:width?@"edgeWidth":@"edgeOpacity"];UIView *view=slider;while(view&&![view isKindOfClass:UITableViewCell.class])view=view.superview;((UITableViewCell *)view).detailTextLabel.text=width?[NSString stringWithFormat:PCLocalized(@"%.0f 点"),value]:[NSString stringWithFormat:@"%.0f%%",value*100];[self publish];}

@end

@interface PCFloatingSettingsController : UITableViewController
@end
@implementation PCFloatingSettingsController
- (void)viewDidLoad {[super viewDidLoad];self.title=PCLocalized(@"悬浮窗");self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=72;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return 2;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.selectionStyle=UITableViewCellSelectionStyleNone;
    cell.textLabel.text=index.row?PCLocalized(@"始终固定胶囊位置"):PCLocalized(@"显示悬浮窗");cell.detailTextLabel.text=index.row?PCLocalized(@"锁定在顶部；关闭后每次任务从顶部开始，可拖动。"):PCLocalized(@"也可在悬浮菜单中隐藏，从主页重新显示。");cell.detailTextLabel.numberOfLines=0;cell.detailTextLabel.textColor=PCMutedColor();
    UISwitch *toggle=[UISwitch new];toggle.tag=index.row;toggle.on=[NSUserDefaults.standardUserDefaults boolForKey:index.row?@"capsuleLocked":@"overlayEnabled"];toggle.accessibilityLabel=cell.textLabel.text;[toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;return cell;
}
- (void)changed:(UISwitch *)toggle {NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;[defaults setBool:toggle.on forKey:toggle.tag?@"capsuleLocked":@"overlayEnabled"];if(!toggle.tag)[defaults setObject:NSUUID.UUID.UUIDString.lowercaseString forKey:@"overlayVisibilityRequest"];NSDictionary *task=PCAgentTaskState();PCOverlayPublish([defaults boolForKey:@"overlayEnabled"],[task[@"running"] boolValue],[task[@"paused"] boolValue]);PCHaptic(@"select");}
@end

@interface PCNotificationController : UITableViewController
@property(nonatomic,strong) NSDictionary *status;
@property(nonatomic,copy) NSString *message;
@end
@implementation PCNotificationController
- (void)viewDidLoad {[super viewDidLoad];self.title=PCLocalized(@"通知");self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=64;}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self refresh:NO];}
- (void)refresh:(BOOL)explicitRequest {__weak typeof(self) weakSelf=self;PCRequestNotificationsIfNeeded(explicitRequest,^(NSDictionary *status){weakSelf.status=status;[weakSelf.tableView reloadData];});}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return 4;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.text=@[PCLocalized(@"系统通知权限"),PCLocalized(@"申请通知权限"),PCLocalized(@"发送测试通知"),PCLocalized(@"打开系统设置")][index.row];if(index.row==0){NSInteger authorization=[self.status[@"authorization"] integerValue];cell.detailTextLabel.text=authorization==UNAuthorizationStatusAuthorized?PCLocalized(@"已允许"):authorization==UNAuthorizationStatusProvisional?PCLocalized(@"临时允许"):authorization==UNAuthorizationStatusDenied?PCLocalized(@"已关闭，请在系统设置中开启"):PCLocalized(@"系统尚未授权");cell.selectionStyle=UITableViewCellSelectionStyleNone;}if(index.row==2)cell.detailTextLabel.text=self.message?:PCLocalized(@"发送后检查横幅和通知中心。");cell.detailTextLabel.numberOfLines=0;cell.detailTextLabel.textColor=PCMutedColor();return cell;}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {[tableView deselectRowAtIndexPath:index animated:YES];if(index.row==1)[self refresh:YES];else if(index.row==2){__weak typeof(self) weakSelf=self;PCSendNotificationTest(^(NSString *message){dispatch_async(dispatch_get_main_queue(),^{weakSelf.message=PCLocalized(message);[weakSelf.tableView reloadData];});});}else if(index.row==3)[UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];}
@end

@interface PCQRCodeLoginController : UIViewController
@property(nonatomic,copy) NSString *authorizationURL;
@property(nonatomic,copy) void (^connected)(void);
@end
@implementation PCQRCodeLoginController {
    UITextField *_callback;
    UILabel *_status;
    UIButton *_verify;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=PCLocalized(@"扫码登录");self.view.backgroundColor=PCCanvasColor();
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;[self.view addSubview:scroll];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],[scroll.bottomAnchor constraintEqualToAnchor:PCKeyboardTopAnchor(self.view)]]];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]]];
    UILabel *guide=[UILabel new];guide.numberOfLines=0;guide.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];guide.text=PCLocalized(@"用另一台设备扫描并登录。完成授权后，浏览器会跳转到无法打开的 127.0.0.1 地址；复制完整地址，通过安全方式传回这台手机并粘贴到下方。链接 10 分钟内有效。");[stack addArrangedSubview:guide];
    uint8_t temporary[qrcodegen_BUFFER_LEN_MAX],encoded[qrcodegen_BUFFER_LEN_MAX];
    BOOL generated=qrcodegen_encodeText(self.authorizationURL.UTF8String,temporary,encoded,qrcodegen_Ecc_MEDIUM,qrcodegen_VERSION_MIN,qrcodegen_VERSION_MAX,qrcodegen_Mask_AUTO,true);
    UIImageView *qr=[UIImageView new];qr.contentMode=UIViewContentModeScaleAspectFit;qr.backgroundColor=UIColor.whiteColor;qr.layer.cornerRadius=12;qr.clipsToBounds=YES;qr.accessibilityLabel=PCLocalized(@"授权二维码");
    if(generated){int size=qrcodegen_getSize(encoded),scale=4,quiet=4;CGFloat side=(size+quiet*2)*scale;UIGraphicsBeginImageContextWithOptions(CGSizeMake(side,side),YES,1);[[UIColor whiteColor] setFill];UIRectFill(CGRectMake(0,0,side,side));[[UIColor blackColor] setFill];for(int y=0;y<size;y++)for(int x=0;x<size;x++)if(qrcodegen_getModule(encoded,x,y))UIRectFill(CGRectMake((x+quiet)*scale,(y+quiet)*scale,scale,scale));qr.image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();}
    [stack addArrangedSubview:qr];[qr.heightAnchor constraintEqualToConstant:300].active=YES;
    if(!qr.image){guide.text=PCLocalized(@"无法生成二维码，请返回后重试。");return;}
    UILabel *label=[UILabel new];label.text=PCLocalized(@"粘贴完整回调地址");label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];[stack addArrangedSubview:label];
    _callback=[UITextField new];_callback.borderStyle=UITextBorderStyleRoundedRect;_callback.secureTextEntry=YES;_callback.autocorrectionType=UITextAutocorrectionTypeNo;_callback.autocapitalizationType=UITextAutocapitalizationTypeNone;_callback.backgroundColor=PCSoftColor();_callback.layer.cornerRadius=12;_callback.accessibilityLabel=PCLocalized(@"回调地址");[_callback.heightAnchor constraintEqualToConstant:52].active=YES;[stack addArrangedSubview:_callback];
    UIButton *paste=[UIButton buttonWithType:UIButtonTypeSystem];[paste setTitle:PCLocalized(@"粘贴回调地址") forState:UIControlStateNormal];PCStyleButton(paste,PCButtonBordered);[paste addTarget:self action:@selector(pasteCallback) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:paste];
    _verify=[UIButton buttonWithType:UIButtonTypeSystem];[_verify setTitle:PCLocalized(@"完成登录") forState:UIControlStateNormal];PCStyleButton(_verify,PCButtonFilled);[_verify addTarget:self action:@selector(verifyCallback) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:_verify];
    _status=[UILabel new];_status.numberOfLines=0;_status.textColor=PCMutedColor();_status.text=PCLocalized(@"回调链接含一次性授权信息，请勿发给他人。");[stack addArrangedSubview:_status];
}
- (void)pasteCallback {_callback.text=UIPasteboard.generalPasteboard.string?:@"";}
- (void)verifyCallback {
    NSString *value=[_callback.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!value.length){_status.text=PCLocalized(@"请先粘贴浏览器地址栏中的回调地址。");return;}
    _verify.enabled=NO;_status.text=PCLocalized(@"正在验证授权…");[self.view endEditing:YES];
    PCChatGPTCompleteDesktopSignIn(value,^(NSDictionary *credentials,NSError *error){self->_verify.enabled=YES;self->_callback.text=@"";if(error){self->_status.text=error.localizedDescription;return;}self->_status.text=PCLocalized(@"登录成功");if(self.connected)self.connected();[self.navigationController popViewControllerAnimated:YES];});
}
@end

@interface PCSettingsController : UIViewController
@property(nonatomic) NSInteger focusSection;
@property(nonatomic, strong) UISegmentedControl *providerMode;
@property(nonatomic, strong) UITextField *keyField;
@property(nonatomic, strong) UITextField *apiBaseField;
@property(nonatomic, strong) UILabel *apiBaseTitle;
@property(nonatomic, strong) UITextField *modelField;
@property(nonatomic, strong) UISegmentedControl *modelMode;
@property(nonatomic, strong) UIButton *chooseModel;
@property(nonatomic, strong) UILabel *modelHint;
@property(nonatomic, strong) NSArray<NSString *> *modelIDs;
@property(nonatomic, strong) UITextField *workspaceField;
@property(nonatomic, strong) UILabel *note;
@property(nonatomic, strong) UIButton *fetch;
@property(nonatomic, strong) PCAPI *api;
@property(nonatomic, strong) UIButton *chatGPTButton;
@property(nonatomic, strong) UIButton *switchChatGPTButton;
@property(nonatomic, strong) UIButton *desktopChatGPTButton;
@property(nonatomic, strong) UILabel *chatGPTStatus;
@property(nonatomic, strong) UILabel *chatGPTLoginNote;
@property(nonatomic, strong) UILabel *keyTitle;
@property(nonatomic, strong) UIButton *removeCredential;
@property(nonatomic, strong) UIButton *usageButton;
@property(nonatomic, strong) UISegmentedControl *reasoningEffort;
@property(nonatomic, strong) UISwitch *expandedOutput;
@property(nonatomic, strong) UISwitch *rootEnabled;
@property(nonatomic, strong) UISwitch *autoApproveTools;
@property(nonatomic, strong) UISwitch *allowBackground;
@property(nonatomic, strong) UISwitch *overlayEnabled;
@property(nonatomic, strong) UISwitch *aiScreenEnabled;
@property(nonatomic, copy) void (^saveCompletion)(void);
@property(nonatomic, copy) void (^toolsAction)(void);
@end

@implementation PCSettingsController
- (void)aboutApplication {
    UIViewController *page=[UIViewController new];page.title=PCLocalized(@"关于应用");page.view.backgroundColor=PCCanvasColor();
    UILabel *name=[UILabel new];name.text=@"AsterHand";name.font=[UIFont boldSystemFontOfSize:30];name.textColor=PCTextColor();
    PCBrandImageView *brand=[PCBrandImageView new];[brand.widthAnchor constraintEqualToConstant:64].active=YES;[brand.heightAnchor constraintEqualToConstant:64].active=YES;
    UIStackView *heading=[[UIStackView alloc] initWithArrangedSubviews:@[brand,name]];heading.axis=UILayoutConstraintAxisHorizontal;heading.alignment=UIStackViewAlignmentCenter;heading.spacing=16;
    NSDictionary *info=NSBundle.mainBundle.infoDictionary;UILabel *version=[UILabel new];version.text=[NSString stringWithFormat:@"%@ %@ (%@)",PCLocalized(@"版本"),info[@"CFBundleShortVersionString"]?:@"",info[@"CFBundleVersion"]?:@""];version.textColor=PCMutedColor();version.numberOfLines=0;
    UIButton *github=[UIButton buttonWithType:UIButtonTypeSystem];[github setTitle:PCLocalized(@"GitHub 主页") forState:UIControlStateNormal];github.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;github.accessibilityIdentifier=@"aboutGitHub";
    [github addAction:[UIAction actionWithHandler:^(UIAction *action){PCHaptic(@"select");[UIApplication.sharedApplication openURL:[NSURL URLWithString:PCGitHubProfileURL] options:@{} completionHandler:nil];}] forControlEvents:UIControlEventTouchUpInside];
    UILabel *address=[UILabel new];address.text=PCGitHubProfileURL;address.textColor=PCMutedColor();address.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];address.numberOfLines=0;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[heading,version,github,address]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=18;stack.translatesAutoresizingMaskIntoConstraints=NO;
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[page.view addSubview:scroll];[scroll addSubview:stack];UILayoutGuide *safe=page.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],[scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:28],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:24],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-24],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-48]]];
    [self.navigationController pushViewController:page animated:YES];
}
- (void)openSettingsSection:(NSInteger)section {
    PCSettingsController *page=[PCSettingsController new];page.focusSection=section;page.saveCompletion=self.saveCompletion;page.toolsAction=self.toolsAction;
    [self.navigationController pushViewController:page animated:YES];
}
- (UIButton *)hubRow:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon action:(dispatch_block_t)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentFill;button.tintColor=PCTextColor();
    UIImage *symbol=[UIImage systemImageNamed:icon]?:[UIImage systemImageNamed:@"circle"];
    UIImageView *image=[[UIImageView alloc] initWithImage:symbol];image.tintColor=PCTextColor();image.contentMode=UIViewContentModeScaleAspectFit;[image.widthAnchor constraintEqualToConstant:32].active=YES;
    UILabel *name=[UILabel new];name.text=title;name.numberOfLines=0;name.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    UILabel *detail=[UILabel new];detail.text=subtitle;detail.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];detail.textColor=PCMutedColor();detail.numberOfLines=0;
    UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[name,detail]];text.axis=UILayoutConstraintAxisVertical;text.spacing=3;
    UIImageView *arrow=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];arrow.tintColor=PCSubtleColor();arrow.contentMode=UIViewContentModeScaleAspectFit;[arrow.widthAnchor constraintEqualToConstant:14].active=YES;
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[image,text,arrow]];row.axis=UILayoutConstraintAxisHorizontal;row.alignment=UIStackViewAlignmentCenter;row.spacing=12;row.translatesAutoresizingMaskIntoConstraints=NO;row.userInteractionEnabled=NO;[button addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.topAnchor constraintEqualToAnchor:button.topAnchor constant:10],[row.bottomAnchor constraintEqualToAnchor:button.bottomAnchor constant:-10],[row.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],[row.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],[button.heightAnchor constraintGreaterThanOrEqualToConstant:54]]];
    [button addAction:[UIAction actionWithHandler:^(UIAction *event){PCHaptic(@"select");if(action)action();}] forControlEvents:UIControlEventTouchUpInside];return button;
}
- (void)languageSettings {
    PCOptionsPage *page=[[PCOptionsPage alloc] initWithStyle:UITableViewStyleInsetGrouped];page.title=PCLocalized(@"界面语言");
    NSMutableArray *options=[NSMutableArray new];NSString *selected=PCUILanguagePreference();
    for(NSString *code in PCUILanguages())[options addObject:@{@"title":PCUILanguageName(code),@"selected":@([code isEqual:selected])}];
    page.options=options;__weak typeof(self) weakSelf=self;
    page.selectOption=^(NSInteger index){
        if(index<0||(NSUInteger)index>=PCUILanguages().count)return;
        PCSetUILanguage(PCUILanguages()[index]);
        PCOverlayPublish([NSUserDefaults.standardUserDefaults boolForKey:@"overlayEnabled"],NO,NO);
        PCSettingsController *owner=weakSelf;if(!owner)return;
        [owner.navigationController popToViewController:owner animated:YES];
        for(UIView *view in owner.view.subviews)[view removeFromSuperview];
        owner.title=PCLocalized(@"设置");owner.navigationItem.leftBarButtonItem.title=PCLocalized(@"关闭");[owner showHub];
    };
    [self.navigationController pushViewController:page animated:YES];
}
- (void)showHub {
    self.view.backgroundColor=PCCanvasColor();self.view.tintColor=PCTextColor();self.navigationController.navigationBar.tintColor=PCTextColor();
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];
    __weak typeof(self) weakSelf=self;
    NSArray *groups=@[
        [self section:PCLocalized(@"帮助") views:@[[self hubRow:PCLocalized(@"使用指南") subtitle:PCLocalized(@"功能介绍、操作步骤与常见问题") icon:@"book" action:^{PCUserGuideController *guide=[PCUserGuideController new];guide.finished=^(BOOL connectAI){if(connectAI)[weakSelf openSettingsSection:1];};[weakSelf.navigationController pushViewController:guide animated:YES];}]]],
        [self section:PCLocalized(@"智能体") views:@[[self hubRow:PCLocalized(@"AI 连接") subtitle:PCLocalized(@"账户与服务商") icon:@"link" action:^{[weakSelf openSettingsSection:1];}],[self hubRow:PCLocalized(@"模型与推理") subtitle:PCLocalized(@"模型和思考深度") icon:@"bubble.left" action:^{[weakSelf openSettingsSection:2];}],[self hubRow:PCLocalized(@"权限与执行") subtitle:PCLocalized(@"Root、屏幕控制和自动执行") icon:@"shield" action:^{[weakSelf openSettingsSection:3];}]]],
        [self section:PCLocalized(@"设备") views:@[[self hubRow:PCLocalized(@"远程连接") subtitle:PCLocalized(@"设备、配对和远程屏幕") icon:@"link" action:^{[weakSelf remoteConnections];}],[self hubRow:PCLocalized(@"悬浮窗") subtitle:PCLocalized(@"任务按钮和状态胶囊") icon:@"circle.inset.filled" action:^{[weakSelf floatingSettings];}],[self hubRow:PCLocalized(@"灯效") subtitle:PCLocalized(@"屏幕和悬浮边框") icon:@"sparkles" action:^{[weakSelf lighting];}],[self hubRow:PCLocalized(@"触感反馈") subtitle:PCLocalized(@"选择震动样式") icon:@"waveform" action:^{[weakSelf haptics];}],[self hubRow:PCLocalized(@"语音与 Siri") subtitle:PCLocalized(@"连续对话与静音") icon:@"mic" action:^{[weakSelf voiceSettings];}],[self hubRow:PCLocalized(@"通知") subtitle:PCLocalized(@"任务问题提醒") icon:@"bell" action:^{[weakSelf notifications];}]]],
        [self section:PCLocalized(@"更多") views:@[[self hubRow:PCLocalized(@"界面语言") subtitle:PCUILanguageName(PCUILanguagePreference()) icon:@"globe" action:^{[weakSelf languageSettings];}],[self hubRow:PCLocalized(@"高级") subtitle:PCLocalized(@"工作目录、诊断和卸载") icon:@"gearshape" action:^{[weakSelf openSettingsSection:4];}],[self hubRow:PCLocalized(@"关于应用") subtitle:@"AsterHand" icon:@"info.circle" action:^{[weakSelf aboutApplication];}]]]
    ];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:groups];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=18;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],[scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]]];
}
- (UIView *)section:(NSString *)title views:(NSArray *)views {
    UILabel *heading=[self label:title];heading.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];heading.textColor=PCMutedColor();
    UIStackView *content=[[UIStackView alloc] initWithArrangedSubviews:views];content.axis=UILayoutConstraintAxisVertical;content.spacing=12;content.translatesAutoresizingMaskIntoConstraints=NO;
    UIView *card=[PCSurfaceView new];[card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[[content.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],[content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],[content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],[content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14]]];
    UIStackView *group=[[UIStackView alloc] initWithArrangedSubviews:@[heading,card]];group.axis=UILayoutConstraintAxisVertical;group.spacing=8;return group;
}
- (void)remoteConnections {[self.navigationController pushViewController:[[PCDevicesController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
- (void)floatingSettings {[self.navigationController pushViewController:[[PCFloatingSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
- (void)lighting {[self.navigationController pushViewController:[[PCLightingController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
- (void)notifications {[self.navigationController pushViewController:[[PCNotificationController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
- (void)utilities {if(self.toolsAction)self.toolsAction();}
- (UITextField *)field:(NSString *)placeholder {
    UITextField *f = [UITextField new];
    f.borderStyle = UITextBorderStyleRoundedRect;
    f.placeholder = placeholder;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    [f.heightAnchor constraintEqualToConstant:44].active = YES;
    return f;
}
- (UILabel *)label:(NSString *)value {
    UILabel *label = [UILabel new];
    label.text = value;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    return label;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.focusSection==1?PCLocalized(@"AI 连接"):self.focusSection==2?PCLocalized(@"模型与推理"):self.focusSection==3?PCLocalized(@"权限与执行"):self.focusSection==4?PCLocalized(@"高级"):PCLocalized(@"设置");
    self.view.backgroundColor = PCCanvasColor();
    if(!self.focusSection){self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"关闭") style:UIBarButtonItemStylePlain target:self action:@selector(close)];[self showHub];return;}
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"保存") style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scroll];
    self.providerMode = [[UISegmentedControl alloc] initWithItems:@[PCLocalized(@"通用 API"), @"ChatGPT"]];
    NSString *provider = [[NSUserDefaults standardUserDefaults] stringForKey:@"provider"] ?: @"openai";
    self.providerMode.selectedSegmentIndex = [@[@"openai", @"chatgpt"] indexOfObject:provider];
    if (self.providerMode.selectedSegmentIndex == UISegmentedControlNoSegment) self.providerMode.selectedSegmentIndex = 0;
    [self.providerMode addTarget:self action:@selector(providerChanged) forControlEvents:UIControlEventValueChanged];
    self.keyField = [self field:@""];
    self.keyTitle = [self label:@"API Key"];
    self.keyField.secureTextEntry = YES;
    self.keyField.textContentType = UITextContentTypePassword;
    self.apiBaseTitle=[self label:PCLocalized(@"API 地址")];self.apiBaseField=[self field:@"https://api.openai.com/v1"];self.apiBaseField.keyboardType=UIKeyboardTypeURL;self.apiBaseField.autocapitalizationType=UITextAutocapitalizationTypeNone;self.apiBaseField.autocorrectionType=UITextAutocorrectionTypeNo;self.apiBaseField.text=[NSUserDefaults.standardUserDefaults stringForKey:@"apiBase.openai"]?:@"";
    self.modelField = [self field:PCLocalized(@"填写模型 ID")];
    self.modelIDs = @[];
    self.modelMode = [[UISegmentedControl alloc] initWithItems:@[PCLocalized(@"列表选择"), PCLocalized(@"自定义 ID")]];
    NSString *savedMode = [NSUserDefaults.standardUserDefaults stringForKey:@"modelSelectionMode.openai"] ?: [NSUserDefaults.standardUserDefaults stringForKey:@"modelSelectionMode"];
    self.modelMode.selectedSegmentIndex = [savedMode isEqual:@"list"] ? 0 : 1;
    [self.modelMode addTarget:self action:@selector(updateModelMode) forControlEvents:UIControlEventValueChanged];
    self.chooseModel = [UIButton buttonWithType:UIButtonTypeSystem];
    PCStyleButton(self.chooseModel,PCButtonBordered);
    [self.chooseModel addTarget:self action:@selector(chooseCachedModel) forControlEvents:UIControlEventTouchUpInside];
    self.modelHint = [self label:@""];
    self.modelHint.textColor = PCMutedColor();
    [self updateModelMode];
    self.workspaceField = [self field:PCLocalized(@"手机上的绝对目录")];
    self.workspaceField.text = PCWorkspace();
    self.fetch = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.fetch setTitle:PCLocalized(@"刷新账户模型列表") forState:UIControlStateNormal];
    [self.fetch addTarget:self action:@selector(models) forControlEvents:UIControlEventTouchUpInside];
    self.reasoningEffort = [[UISegmentedControl alloc] initWithItems:@[PCLocalized(@"自动"), PCLocalized(@"低"), PCLocalized(@"中"), PCLocalized(@"高"), PCLocalized(@"超高"), PCLocalized(@"最大")]];
    NSArray *efforts = @[@"", @"low", @"medium", @"high", @"xhigh", @"max"];
    NSString *storedEffort = [NSUserDefaults.standardUserDefaults stringForKey:[@"reasoningEffort." stringByAppendingString:provider]] ?: @"medium";
    NSUInteger effortIndex = [efforts indexOfObject:storedEffort];
    self.reasoningEffort.selectedSegmentIndex = effortIndex == NSNotFound ? 2 : effortIndex;
    self.expandedOutput = [UISwitch new];
    self.expandedOutput.on = [NSUserDefaults.standardUserDefaults boolForKey:[@"expandedOutput." stringByAppendingString:provider]];
    UILabel *expandedTitle = [self label:PCLocalized(@"详细输出")];
    [expandedTitle setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *expandedRow = [[UIStackView alloc] initWithArrangedSubviews:@[expandedTitle, self.expandedOutput]];
    expandedRow.axis = UILayoutConstraintAxisHorizontal;
    expandedRow.alignment = UIStackViewAlignmentCenter;
    expandedRow.spacing = 10;
    UILabel *expandedNote = [self label:PCLocalized(@"API Key 输出上限 ×1.5；服务商额度和速度不变")];
    expandedNote.textColor = PCMutedColor();
    self.rootEnabled = [UISwitch new];
    self.rootEnabled.on = [NSUserDefaults.standardUserDefaults boolForKey:@"rootEnabled"];
    UIStackView *rootRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:PCLocalized(@"Root 权限")], self.rootEnabled]];
    rootRow.axis = UILayoutConstraintAxisHorizontal;
    rootRow.alignment = UIStackViewAlignmentCenter;
    rootRow.spacing = 10;
    self.autoApproveTools = [UISwitch new];
    self.autoApproveTools.on = [NSUserDefaults.standardUserDefaults boolForKey:@"autoApproveTools"];
    UIStackView *approvalRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:PCLocalized(@"自动执行工具")], self.autoApproveTools]];
    approvalRow.axis = UILayoutConstraintAxisHorizontal;
    approvalRow.alignment = UIStackViewAlignmentCenter;
    approvalRow.spacing = 10;
    self.allowBackground = [UISwitch new];
    self.allowBackground.on = [NSUserDefaults.standardUserDefaults boolForKey:@"allowBackground"];
    UIStackView *backgroundRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:PCLocalized(@"后台运行")], self.allowBackground]];
    backgroundRow.axis = UILayoutConstraintAxisHorizontal;
    backgroundRow.alignment = UIStackViewAlignmentCenter;
    backgroundRow.spacing = 10;
    self.overlayEnabled = [UISwitch new];
    self.overlayEnabled.on = [NSUserDefaults.standardUserDefaults boolForKey:@"overlayEnabled"];
    UIStackView *overlayRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:PCLocalized(@"悬浮任务按钮")], self.overlayEnabled]];
    overlayRow.axis = UILayoutConstraintAxisHorizontal;
    overlayRow.alignment = UIStackViewAlignmentCenter;
    overlayRow.spacing = 10;
    self.aiScreenEnabled = [UISwitch new];
    self.aiScreenEnabled.on = [NSUserDefaults.standardUserDefaults boolForKey:@"aiScreenEnabled"];
    UIStackView *screenRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:PCLocalized(@"允许 AI 查看与操作屏幕")], self.aiScreenEnabled]];
    screenRow.axis = UILayoutConstraintAxisHorizontal;
    screenRow.alignment = UIStackViewAlignmentCenter;
    screenRow.spacing = 10;
    // UISwitch can receive the stack's spare width on older UIKit versions;
    // its visible thumb then stays at the leading edge of that oversized frame.
    for(UIStackView *row in @[expandedRow,rootRow,approvalRow,backgroundRow,overlayRow,screenRow]){
        UIView *title=row.arrangedSubviews.firstObject,*toggle=row.arrangedSubviews.lastObject;
        [title setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [title setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [toggle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [toggle.widthAnchor constraintEqualToConstant:51].active=YES;
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    }
    self.chatGPTButton = [UIButton buttonWithType:UIButtonTypeSystem];
    PCStyleButton(self.chatGPTButton,PCButtonBordered);
    [self.chatGPTButton setTitle:@"Continue with ChatGPT" forState:UIControlStateNormal];
    [self.chatGPTButton addTarget:self action:@selector(chatGPTSignIn) forControlEvents:UIControlEventTouchUpInside];
    self.switchChatGPTButton=[UIButton buttonWithType:UIButtonTypeSystem];PCStyleButton(self.switchChatGPTButton,PCButtonBordered);[self.switchChatGPTButton setTitle:PCLocalized(@"切换账户或工作区") forState:UIControlStateNormal];[self.switchChatGPTButton addTarget:self action:@selector(switchChatGPTAccount) forControlEvents:UIControlEventTouchUpInside];
    self.desktopChatGPTButton = [UIButton buttonWithType:UIButtonTypeSystem];
    PCStyleButton(self.desktopChatGPTButton,PCButtonBordered);
    [self.desktopChatGPTButton setTitle:PCLocalized(@"扫码或其他设备登录") forState:UIControlStateNormal];
    [self.desktopChatGPTButton addTarget:self action:@selector(chatGPTDesktopSignIn) forControlEvents:UIControlEventTouchUpInside];
    self.chatGPTStatus = [self label:@""];
    self.chatGPTStatus.textColor = PCMutedColor();
    self.chatGPTLoginNote = [self label:PCLocalized(@"登录页在 AsterHand 内打开，必要时注入 URL.canParse 兼容实现。请在 iPhone 上完成登录并确认套餐用量授权；授权回调与令牌校验都在本机完成。")];
    self.chatGPTLoginNote.textColor = PCMutedColor();
    self.usageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.usageButton setTitle:PCLocalized(@"管理 ChatGPT 用量") forState:UIControlStateNormal];
    [self.usageButton addTarget:self action:@selector(openChatGPTUsage) forControlEvents:UIControlEventTouchUpInside];
    self.removeCredential = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.removeCredential setTitle:PCLocalized(@"删除已保存的 API Key") forState:UIControlStateNormal];
    [self.removeCredential setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    [self.removeCredential addTarget:self action:@selector(removeKey) forControlEvents:UIControlEventTouchUpInside];
    self.note = [self label:PCLocalized(@"凭据保存在本机 Keychain；模型请求直连所选服务商。\n\nRoot 与自动允许同时开启时，模型发起的本机工具会直接以 UID 0 执行。\n\n后台任务受 iOS 时间限制；到期自动停止。后台需要工具调用时，请开启自动允许，否则工具请求会被拒绝。远控常驻服务不受此开关影响。\n\nAI 屏幕操作仅支持 OpenAI API 和 ChatGPT 登录。开启后，模型可申请截图、点击、滑动和 ASCII 输入；截图会发送到所选服务商。\n\n附件保存在当前项目的 Attachments；每个附件最多 8 MB，每条消息最多 4 个。")];
    self.note.text = [self.note.text stringByAppendingFormat:@"\n\n%@", PCPathExplanation()];
    self.note.textColor = PCMutedColor();
    self.view.backgroundColor=PCCanvasColor();self.view.tintColor=PCTextColor();self.navigationController.navigationBar.tintColor=PCTextColor();
    self.note.hidden=YES;self.chatGPTLoginNote.hidden=YES;self.modelHint.hidden=YES;
    UIButton *remote=[UIButton buttonWithType:UIButtonTypeSystem];[remote setTitle:PCLocalized(@"远程连接  ›") forState:UIControlStateNormal];remote.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;[remote addTarget:self action:@selector(remoteConnections) forControlEvents:UIControlEventTouchUpInside];
    UIButton *floating=[UIButton buttonWithType:UIButtonTypeSystem];[floating setTitle:PCLocalized(@"悬浮窗  ›") forState:UIControlStateNormal];floating.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;[floating addTarget:self action:@selector(floatingSettings) forControlEvents:UIControlEventTouchUpInside];
    UIButton *lighting=[UIButton buttonWithType:UIButtonTypeSystem];[lighting setTitle:PCLocalized(@"灯效  ›") forState:UIControlStateNormal];lighting.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;[lighting addTarget:self action:@selector(lighting) forControlEvents:UIControlEventTouchUpInside];
    UIButton *haptics=[UIButton buttonWithType:UIButtonTypeSystem];[haptics setTitle:PCLocalized(@"触感反馈  ›") forState:UIControlStateNormal];haptics.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;[haptics addTarget:self action:@selector(haptics) forControlEvents:UIControlEventTouchUpInside];
    UIButton *notifications=[UIButton buttonWithType:UIButtonTypeSystem];[notifications setTitle:PCLocalized(@"通知  ›") forState:UIControlStateNormal];notifications.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;[notifications addTarget:self action:@selector(notifications) forControlEvents:UIControlEventTouchUpInside];
    UIButton *utilities=[UIButton buttonWithType:UIButtonTypeSystem];[utilities setTitle:PCLocalized(@"服务、诊断与日志  ›") forState:UIControlStateNormal];utilities.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;[utilities addTarget:self action:@selector(utilities) forControlEvents:UIControlEventTouchUpInside];
    NSArray *sections=@[
        [self section:PCLocalized(@"AI 连接") views:@[self.providerMode,self.keyTitle,self.keyField,self.apiBaseTitle,self.apiBaseField,self.chatGPTButton,self.switchChatGPTButton,self.desktopChatGPTButton,self.chatGPTStatus,self.usageButton,self.removeCredential]],
        [self section:PCLocalized(@"模型") views:@[self.modelMode,self.chooseModel,self.modelField,self.fetch,[self label:PCLocalized(@"推理深度")],self.reasoningEffort,expandedRow,expandedNote]],
        [self section:PCLocalized(@"执行") views:@[rootRow,approvalRow,screenRow,backgroundRow,[self networkPermissionButton]]],
        [self section:PCLocalized(@"设备") views:@[remote,floating,lighting,haptics,notifications,[self voiceSettingsButton]]],
        [self section:PCLocalized(@"高级") views:@[[self label:PCLocalized(@"工作目录")],self.workspaceField,utilities,[self uninstallButton]]]];
    NSInteger selected=self.focusSection==4?4:self.focusSection-1;for(NSUInteger i=0;i<sections.count;i++)((UIView *)sections[i]).hidden=(i!=(NSUInteger)selected);
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:sections];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:g.topAnchor], [scroll.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]]];
    [self providerChanged];
}
- (void)close { [self.api cancel]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (UIButton *)uninstallButton {UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:PCLocalized(@"卸载 AsterHand  ›") forState:UIControlStateNormal];[button setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;[button addTarget:self action:@selector(uninstallPage) forControlEvents:UIControlEventTouchUpInside];return button;}
- (void)uninstallPage {[self.navigationController pushViewController:[[PCUninstallController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
- (UIButton *)networkPermissionButton {UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:PCLocalized(@"网络授权  ›") forState:UIControlStateNormal];button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;[button addTarget:self action:@selector(networkPermissions) forControlEvents:UIControlEventTouchUpInside];return button;}
- (void)networkPermissions {PCHaptic(@"select");[self.navigationController pushViewController:[[PCNetworkPermissionController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
- (UIButton *)voiceSettingsButton {UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:PCLocalized(@"语音与 Siri  ›") forState:UIControlStateNormal];button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;[button addTarget:self action:@selector(voiceSettings) forControlEvents:UIControlEventTouchUpInside];return button;}
- (void)voiceSettings {[self.navigationController pushViewController:[[PCVoiceSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
- (void)haptics {
    PCOptionsPage *page=[[PCOptionsPage alloc] initWithStyle:UITableViewStyleInsetGrouped];page.title=PCLocalized(@"触感反馈");NSString *current=PCHapticNormalizeStyle([NSUserDefaults.standardUserDefaults stringForKey:@"hapticStyle"]);[NSUserDefaults.standardUserDefaults setObject:current forKey:@"hapticStyle"];NSArray *styles=PCHapticStyles();NSMutableArray *options=[NSMutableArray new];for(NSDictionary *style in styles){NSMutableDictionary *item=[style mutableCopy];item[@"title"]=PCLocalized(item[@"title"]);item[@"selected"]=@([style[@"id"] isEqual:current]);[options addObject:item];}page.options=options;
    __weak typeof(self) weakSelf=self;page.selectOption=^(NSInteger selected){[NSUserDefaults.standardUserDefaults setObject:styles[selected][@"id"] forKey:@"hapticStyle"];NSDictionary *task=PCAgentTaskState();PCOverlayPublish([NSUserDefaults.standardUserDefaults boolForKey:@"overlayEnabled"],[task[@"running"] boolValue],[task[@"paused"] boolValue]);PCHaptic(@"impact");[weakSelf.navigationController popViewControllerAnimated:YES];};[self.navigationController pushViewController:page animated:YES];
}
- (void)alert:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:PCLocalized(@"提示") message:PCLocalized(message) preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"好") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (BOOL)saveKey {
    NSString *key = [self.keyField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!key.length) return YES;
    if ([key rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) { [self alert:PCLocalized(@"Key 不能包含空格或换行。")]; return NO; }
    NSError *error;
    NSString *provider = @[@"openai", @"chatgpt"][self.providerMode.selectedSegmentIndex];
    if (![provider isEqual:@"chatgpt"] && !PCSetAPIKeyForProvider(provider, key, &error)) { [self alert:error.localizedDescription]; return NO; }
    self.keyField.text = @"";
    self.keyField.placeholder = PCLocalized(@"已保存 Key；留空保留");
    return YES;
}
- (void)save {
    PCHaptic(@"select");
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *provider = @[@"openai", @"chatgpt"][self.providerMode.selectedSegmentIndex];
    if(self.focusSection==1){NSString *base=[self.apiBaseField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if([provider isEqual:@"openai"]&&base.length){NSURLComponents *u=[NSURLComponents componentsWithString:base];if(![u.scheme.lowercaseString isEqual:@"https"]||!u.host.length||u.user.length||u.password.length||u.query.length||u.fragment.length){[self alert:PCLocalized(@"API 地址必须是 HTTPS，不能包含账户、查询参数或片段。")];return;}}if(![self saveKey])return;if([provider isEqual:@"openai"])[d setObject:base forKey:@"apiBase.openai"];[d setObject:provider forKey:@"provider"];}
    else if(self.focusSection==2){
        NSString *model=[self.modelField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(!model.length||[model rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound){[self alert:PCLocalized(@"请选择模型，或填写不含空格、换行的模型 ID。")];return;}
        [d setObject:model forKey:[@"model." stringByAppendingString:provider]];[d setObject:model forKey:@"model"];[d setObject:self.modelMode.selectedSegmentIndex==0?@"list":@"custom" forKey:[@"modelSelectionMode." stringByAppendingString:provider]];
        NSArray *efforts=@[@"",@"low",@"medium",@"high",@"xhigh",@"max"];[d setObject:efforts[MAX(0,self.reasoningEffort.selectedSegmentIndex)] forKey:[@"reasoningEffort." stringByAppendingString:provider]];[d setBool:self.expandedOutput.on forKey:[@"expandedOutput." stringByAppendingString:provider]];
    }else if(self.focusSection==3){
        BOOL rootRequested=self.rootEnabled.on;
        if(rootRequested!=[d boolForKey:@"rootEnabled"]){NSDictionary *result=PCSendRootRequest(@{@"action":@"set_enabled",@"enabled":@(rootRequested)},5);if(result[@"error"]||![result[@"enabled"] isEqual:@(rootRequested)]){[self alert:result[@"error"]?:PCLocalized(@"Root 开关未能保存。")];return;}}
        [d setBool:rootRequested forKey:@"rootEnabled"];[d setBool:self.autoApproveTools.on forKey:@"autoApproveTools"];[d setBool:self.allowBackground.on forKey:@"allowBackground"];[d setBool:self.aiScreenEnabled.on forKey:@"aiScreenEnabled"];
    }else if(self.focusSection==4){
        NSString *workspace=[self.workspaceField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!workspace.isAbsolutePath||[workspace rangeOfString:@"\0"].location!=NSNotFound){[self alert:PCLocalized(@"请输入手机上的绝对目录。")];return;}[d setObject:workspace.stringByStandardizingPath forKey:@"workspace"];
    }
    if (self.saveCompletion) self.saveCompletion();
    [self.api cancel];[self.navigationController popViewControllerAnimated:YES];
}
- (void)removeKey {
    NSString *provider = @[@"openai", @"chatgpt"][self.providerMode.selectedSegmentIndex];
    if ([provider isEqual:@"chatgpt"]) {
        if (!PCChatGPTCredentials()) { [self alert:PCLocalized(@"当前没有已保存的 ChatGPT 登录。")]; return; }
        UIAlertController *logout = [UIAlertController alertControllerWithTitle:PCLocalized(@"断开 ChatGPT 登录？") message:PCLocalized(@"将撤销本机保存的 OAuth 会话，并尝试通知 OpenAI 撤销 refresh token。") preferredStyle:UIAlertControllerStyleAlert];
        [logout addAction:[UIAlertAction actionWithTitle:PCLocalized(@"取消") style:UIAlertActionStyleCancel handler:nil]];
        [logout addAction:[UIAlertAction actionWithTitle:PCLocalized(@"断开") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { PCChatGPTSignOut(^(NSString *status) { self.chatGPTStatus.text = status; [self alert:status]; }); }]];
        [self presentViewController:logout animated:YES completion:nil]; return;
    }
    NSString *providerName = [@[PCLocalized(@"通用 API")] objectAtIndex:self.providerMode.selectedSegmentIndex];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:PCLocalized(@"删除 API Key？") message:[NSString stringWithFormat:PCLocalized(@"仅删除本机保存的 %@ Key，不会撤销服务商平台上的密钥。"), providerName] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"取消") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"删除") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *error;
        if (!PCSetAPIKeyForProvider(provider, @"", &error)) { [self alert:error.localizedDescription]; return; }
        self.keyField.text = @"";
        self.keyField.placeholder = [NSString stringWithFormat:PCLocalized(@"在此输入 %@ API Key"), provider];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)models {
    if(self.focusSection==1&&self.providerMode.selectedSegmentIndex==0){NSString *base=[self.apiBaseField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(base.length){NSURLComponents *u=[NSURLComponents componentsWithString:base];if(![u.scheme.lowercaseString isEqual:@"https"]||!u.host.length||u.user.length||u.password.length||u.query.length||u.fragment.length){[self alert:PCLocalized(@"API 地址必须是 HTTPS，不能包含账户、查询参数或片段。")];return;}}[NSUserDefaults.standardUserDefaults setObject:base forKey:@"apiBase.openai"];}
    if (![self saveKey]) return;
    NSString *provider = @[@"openai", @"chatgpt"][self.providerMode.selectedSegmentIndex];
    if (![provider isEqual:@"chatgpt"] && !PCAPIKeyForProvider(provider).length) { [self alert:PCLocalized(@"请先填写 API Key，或切换到自定义 ID 直接输入模型名称。")]; return; }
    if ([provider isEqual:@"chatgpt"] && !PCChatGPTCredentials()) { [self alert:PCLocalized(@"请先使用 Continue with ChatGPT 登录并授权套餐用量。")]; return; }
    [self.view endEditing:YES];
    self.fetch.enabled = NO;
    [self.fetch setTitle:PCLocalized(@"正在获取…") forState:UIControlStateDisabled];
    self.api = [PCAPI new];
    PCAPI *api = self.api;
    api.provider = provider;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error;
        NSDictionary *response = [api request:@"models" body:nil error:&error];
        NSMutableArray *models = [NSMutableArray new];
        NSArray *items = [response[@"models"] isKindOfClass:NSArray.class] ? response[@"models"] : response[@"data"];
        for (NSDictionary *item in items) {
            NSString *identifier = [provider isEqual:@"chatgpt"] ? item[@"slug"] : item[@"id"];
            if ([identifier isKindOfClass:NSString.class] && (![provider isEqual:@"chatgpt"] || [item[@"visibility"] isEqual:@"list"])) [models addObject:identifier];
        }
        if (![provider isEqual:@"chatgpt"]) [models sortUsingSelector:@selector(compare:)];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.fetch.enabled = YES;
            if (api.cancelled || !self.view.window) return;
            if (!models.count) { [self alert:error.localizedDescription ?: PCLocalized(@"模型列表为空。")]; return; }
            self.modelIDs = [[NSOrderedSet orderedSetWithArray:models] array];
            [NSUserDefaults.standardUserDefaults setObject:self.modelIDs forKey:[@"cachedModelIDs." stringByAppendingString:provider]];
            self.modelMode.selectedSegmentIndex = 0;
            [self updateModelMode];
            [self chooseCachedModel];
        });
    });
}
- (void)providerChanged {
    NSString *provider = @[@"openai", @"chatgpt"][self.providerMode.selectedSegmentIndex];
    NSString *display = @[PCLocalized(@"通用 API"), @"ChatGPT"][self.providerMode.selectedSegmentIndex];
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    self.modelIDs = [d stringArrayForKey:[@"cachedModelIDs." stringByAppendingString:provider]] ?: @[];
    self.modelField.text = [d stringForKey:[@"model." stringByAppendingString:provider]] ?: ([provider isEqual:@"openai"] ? [d stringForKey:@"model"] : @"");
    NSArray *efforts = @[@"", @"low", @"medium", @"high", @"xhigh", @"max"];
    NSString *effort = [d stringForKey:[@"reasoningEffort." stringByAppendingString:provider]] ?: @"medium";
    NSUInteger effortIndex = [efforts indexOfObject:effort];
    self.reasoningEffort.selectedSegmentIndex = effortIndex == NSNotFound ? 2 : effortIndex;
    self.reasoningEffort.enabled = [provider isEqual:@"openai"] || [provider isEqual:@"chatgpt"];
    self.expandedOutput.on = [d boolForKey:[@"expandedOutput." stringByAppendingString:provider]];
    NSString *mode = [d stringForKey:[@"modelSelectionMode." stringByAppendingString:provider]];
    self.modelMode.selectedSegmentIndex = [mode isEqual:@"list"] || (!mode && [self.modelIDs containsObject:self.modelField.text]) ? 0 : 1;
    BOOL chatGPT = [provider isEqual:@"chatgpt"];
    self.keyTitle.hidden = chatGPT;
    self.keyField.hidden = chatGPT;
    self.apiBaseTitle.hidden=chatGPT;self.apiBaseField.hidden=chatGPT;
    self.keyField.placeholder = PCAPIKeyForProvider(provider).length ? PCLocalized(@"已保存 Key；留空保留") : [NSString stringWithFormat:PCLocalized(@"在此输入 %@ API Key"), display];
    self.chatGPTButton.hidden = !chatGPT;
    self.switchChatGPTButton.hidden = !chatGPT;
    self.desktopChatGPTButton.hidden = !chatGPT;
    self.chatGPTStatus.hidden = !chatGPT;
    self.chatGPTLoginNote.hidden = YES;
    self.usageButton.hidden = !chatGPT;
    self.removeCredential.hidden = NO;
    [self.removeCredential setTitle:chatGPT ? PCLocalized(@"断开 ChatGPT 登录") : PCLocalized(@"删除已保存的 API Key") forState:UIControlStateNormal];
    NSDictionary *credentials = PCChatGPTCredentials();
    self.chatGPTStatus.text = credentials ? [NSString stringWithFormat:PCLocalized(@"已连接：%@"), credentials[@"email"] ?: PCLocalized(@"ChatGPT 账户")] : PCLocalized(@"尚未登录");
    self.fetch.hidden = NO;
    [self updateModelMode];
}
- (void)openChatGPTUsage {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://chatgpt.com/settings/usage"] options:@{} completionHandler:nil];
}
- (void)chatGPTSignIn { [self startChatGPTSignIn:NO]; }
- (void)switchChatGPTAccount { [self startChatGPTSignIn:YES]; }
- (void)startChatGPTSignIn:(BOOL)newAccount {
    self.chatGPTButton.enabled = NO;
    self.switchChatGPTButton.enabled = NO;
    self.chatGPTStatus.text = PCLocalized(@"请在 iPhone 内完成登录并确认套餐用量授权…");
    void (^done)(NSDictionary *,NSError *)=^(NSDictionary *credentials, NSError *error) {
        self.chatGPTButton.enabled = YES;
        self.switchChatGPTButton.enabled = YES;
        if (error) { self.chatGPTStatus.text = error.localizedDescription; [self alert:error.localizedDescription]; return; }
        self.chatGPTStatus.text = [NSString stringWithFormat:PCLocalized(@"已连接：%@\nChatGPT 套餐用量已授权。"), credentials[@"email"] ?: PCLocalized(@"ChatGPT 账户")];
        self.providerMode.selectedSegmentIndex = 1; [self providerChanged];
        [self models];
    };if(newAccount)PCChatGPTSignInNewAccount(done);else PCChatGPTSignIn(done);
}
- (void)chatGPTDesktopSignIn {
    NSError *error = nil;
    NSString *authorizationURL = PCChatGPTPrepareDesktopAuthorizationURL(&error);
    if (!authorizationURL) { [self alert:error.localizedDescription ?: PCLocalized(@"无法准备 ChatGPT 登录。")]; return; }
    PCQRCodeLoginController *controller=[PCQRCodeLoginController new];controller.authorizationURL=authorizationURL;
    __weak typeof(self) weakSelf=self;controller.connected=^{typeof(self) self=weakSelf;if(!self)return;self.providerMode.selectedSegmentIndex=1;[self providerChanged];[self models];};
    [self.navigationController pushViewController:controller animated:YES];
}
- (void)promptDesktopCallback {
    UIAlertController *prompt = [UIAlertController alertControllerWithTitle:PCLocalized(@"粘贴电脑浏览器回调") message:PCLocalized(@"请粘贴完整地址，格式为 http://127.0.0.1:54321/auth/callback?code=…&state=…&client_id=… 。本机将校验 state、PKCE 和 ID token 后保存授权。") preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"http://127.0.0.1:54321/auth/callback?..."; field.keyboardType = UIKeyboardTypeURL; field.autocorrectionType = UITextAutocorrectionTypeNo; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [prompt addAction:[UIAlertAction actionWithTitle:PCLocalized(@"取消") style:UIAlertActionStyleCancel handler:nil]];
    [prompt addAction:[UIAlertAction actionWithTitle:PCLocalized(@"完成登录") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.desktopChatGPTButton.enabled = NO; self.chatGPTStatus.text = PCLocalized(@"正在验证授权并换取本机登录令牌…");
        PCChatGPTCompleteDesktopSignIn(prompt.textFields.firstObject.text, ^(NSDictionary *credentials, NSError *error) {
            self.desktopChatGPTButton.enabled = YES;
            if (error) { self.chatGPTStatus.text = error.localizedDescription; [self alert:error.localizedDescription]; return; }
            self.chatGPTStatus.text = [NSString stringWithFormat:PCLocalized(@"已连接：%@\nChatGPT 套餐用量已授权。"), credentials[@"email"] ?: PCLocalized(@"ChatGPT 账户")];
            self.providerMode.selectedSegmentIndex = 1; [self providerChanged]; [self models];
        });
    }]];
    [self presentViewController:prompt animated:YES completion:nil];
}
- (void)updateModelMode {
    BOOL list = self.modelMode.selectedSegmentIndex == 0;
    [self.view endEditing:YES];
    self.modelField.hidden = list;
    self.chooseModel.hidden = !list;
    [self.chooseModel setTitle:self.modelField.text.length ? [PCLocalized(@"选择模型：") stringByAppendingString:self.modelField.text] : PCLocalized(@"点击选择模型") forState:UIControlStateNormal];
    self.modelHint.text = list ? PCLocalized(@"可搜索已缓存的账户模型；首次使用请刷新列表。") : PCLocalized(@"输入完整模型 ID；不必先获取列表。保存后用于下一次请求。");
}
- (void)chooseCachedModel {
    if (!self.modelIDs.count) { [self models]; return; }
    PCModelPicker *picker = [PCModelPicker new];
    picker.models = self.modelIDs;
    picker.selectedModel = self.modelField.text;
    __weak PCSettingsController *weakSelf = self;
    picker.selectModel = ^(NSString *value) {
        weakSelf.modelField.text = value;
        weakSelf.modelMode.selectedSegmentIndex = 0;
        [weakSelf updateModelMode];
    };
    [self.navigationController pushViewController:picker animated:YES];
}
@end

@interface PCWorkspaceManager : UITableViewController
@property(nonatomic, strong) PCProjectStore *store;
@property(nonatomic, copy) void (^changed)(void);
@end
@implementation PCWorkspaceManager {
    UIBarButtonItem *_selection, *_create, *_all, *_rename, *_delete;
}
- (NSArray *)chats { return [[self.store.currentProject[@"chats"] reverseObjectEnumerator] allObjects] ?: @[]; }
- (NSDictionary *)item:(NSIndexPath *)index { return index.section==0?self.store.projects[index.row]:[self chats][index.row]; }
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"AsterHand";self.view.tintColor=PCTextColor();self.navigationController.navigationBar.tintColor=PCTextColor();
    self.tableView.backgroundColor=PCCanvasColor();self.tableView.separatorStyle=UITableViewCellSeparatorStyleNone;self.tableView.rowHeight=58;self.tableView.allowsMultipleSelectionDuringEditing=YES;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"完成") style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    _create=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)];_selection=[[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"选择") style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelection)];self.navigationItem.rightBarButtonItems=@[_create,_selection];
    _all=[[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"全选") style:UIBarButtonItemStylePlain target:self action:@selector(selectAll)];_rename=[[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"重命名") style:UIBarButtonItemStylePlain target:self action:@selector(renameSelected)];_delete=[[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"删除") style:UIBarButtonItemStylePlain target:self action:@selector(deleteSelected)];_delete.tintColor=UIColor.systemRedColor;
    self.toolbarItems=@[_all,[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],_rename,[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],_delete];
}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self.tableView reloadData];[self updateSelection];}
- (void)close {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)toggleSelection {
    PCHaptic(@"select");[self setEditing:!self.editing animated:YES];[self updateSelection];}
- (void)updateSelection {NSUInteger n=self.tableView.indexPathsForSelectedRows.count;_all.title=n==self.store.projects.count+[self chats].count?PCLocalized(@"取消全选"):PCLocalized(@"全选");_selection.title=self.editing?PCLocalized(@"取消"):PCLocalized(@"选择");_create.enabled=!self.editing;_rename.enabled=n==1;_delete.enabled=n>0;_delete.title=n?[NSString stringWithFormat:PCLocalized(@"删除 (%lu)"),(unsigned long)n]:PCLocalized(@"删除");[self.navigationController setToolbarHidden:!self.editing animated:YES];}
- (void)selectAll {
    PCHaptic(@"select");NSUInteger count=self.store.projects.count+[self chats].count;BOOL clear=self.tableView.indexPathsForSelectedRows.count==count;for(NSInteger section=0;section<2;section++)for(NSInteger row=0;row<[self.tableView numberOfRowsInSection:section];row++){NSIndexPath *index=[NSIndexPath indexPathForRow:row inSection:section];if(clear)[self.tableView deselectRowAtIndexPath:index animated:NO];else[self.tableView selectRowAtIndexPath:index animated:NO scrollPosition:UITableViewScrollPositionNone];}_all.title=clear?PCLocalized(@"全选"):PCLocalized(@"取消全选");[self updateSelection];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {return 2;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return section==0?self.store.projects.count:[self chats].count;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {return section==0?PCLocalized(@"项目"):PCLocalized(@"对话");}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item=[self item:indexPath];UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.text=item[indexPath.section==0?@"name":@"title"];cell.textLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];cell.detailTextLabel.text=indexPath.section==0?[NSString stringWithFormat:PCLocalized(@"%lu 个对话"),(unsigned long)[item[@"chats"] count]]:nil;cell.accessoryType=[item[@"id"] isEqual:indexPath.section==0?self.store.currentProject[@"id"]:self.store.currentChat[@"id"]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {if(self.editing){[self updateSelection];return;}NSDictionary *item=[self item:indexPath];if(indexPath.section==0)[self.store selectProject:item[@"id"]];else[self.store selectChat:item[@"id"]];if(self.changed)self.changed();[tableView reloadData];if(indexPath.section==1)[self close];}
- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {if(self.editing)[self updateSelection];}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {return YES;}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {return UITableViewCellEditingStyleDelete|UITableViewCellEditingStyleInsert;}
- (void)renameSelected {
    NSIndexPath *index=self.tableView.indexPathsForSelectedRows.firstObject;if(self.tableView.indexPathsForSelectedRows.count!=1)return;NSDictionary *item=[self item:index];PCTextEntryPage *page=[PCTextEntryPage new];page.title=PCLocalized(@"重命名");page.submitTitle=PCLocalized(@"保存");page.initialText=item[index.section==0?@"name":@"title"];page.maximumLength=index.section==0?60:80;page.fieldPlaceholder=[NSString stringWithFormat:PCLocalized(@"最多 %lu 个字符"),(unsigned long)page.maximumLength];__weak typeof(self) weakSelf=self;page.submit=^(NSString *name){PCHaptic(@"success");if(index.section==0)[weakSelf.store renameProject:item[@"id"] name:name];else[weakSelf.store renameChat:item[@"id"] title:name];if(weakSelf.changed)weakSelf.changed();[weakSelf setEditing:NO animated:NO];[weakSelf.navigationController popToViewController:weakSelf animated:YES];};[self.navigationController setToolbarHidden:YES animated:NO];[self.navigationController pushViewController:page animated:YES];
}
- (void)deleteSelected {
    NSMutableArray *projects=[NSMutableArray new],*chats=[NSMutableArray new];for(NSIndexPath *index in self.tableView.indexPathsForSelectedRows){NSDictionary *item=[self item:index];[(index.section==0?projects:chats) addObject:item[@"id"]];}if(!projects.count&&!chats.count)return;
    PCConfirmPage *page=[PCConfirmPage new];page.title=PCLocalized(@"删除所选记录");page.actionTitle=PCLocalized(@"确认删除");page.message=[NSString stringWithFormat:PCLocalized(@"已选择 %lu 个项目、%lu 个对话。\n\n项目内的对话也会删除，项目目录中的文件会保留。"),(unsigned long)projects.count,(unsigned long)chats.count];__weak typeof(self) weakSelf=self;page.confirm=^{PCHaptic(@"warning");for(NSString *identifier in projects)[weakSelf.store deleteProject:identifier];for(NSString *identifier in chats)[weakSelf.store deleteChat:identifier];if(weakSelf.changed)weakSelf.changed();[weakSelf setEditing:NO animated:NO];[weakSelf.navigationController popToViewController:weakSelf animated:YES];};[self.navigationController setToolbarHidden:YES animated:NO];[self.navigationController pushViewController:page animated:YES];
}
- (void)add {
    PCOptionsPage *page=[[PCOptionsPage alloc] initWithStyle:UITableViewStyleInsetGrouped];page.title=PCLocalized(@"新建");page.options=@[@{@"title":PCLocalized(@"新项目"),@"icon":@"folder.badge.plus"},@{@"title":PCLocalized(@"新对话"),@"icon":@"square.and.pencil"}];__weak typeof(self) weakSelf=self;
    page.selectOption=^(NSInteger selected){if(selected==1){[weakSelf.store createChat];if(weakSelf.changed)weakSelf.changed();[weakSelf close];return;}PCTextEntryPage *input=[PCTextEntryPage new];input.title=PCLocalized(@"新项目");input.fieldPlaceholder=PCLocalized(@"项目名称");input.maximumLength=60;__weak PCTextEntryPage *weakInput=input;input.submit=^(NSString *name){if(![weakSelf.store createProject:name]){weakInput.navigationItem.prompt=PCLocalized(@"无法创建项目目录");return;}if(weakSelf.changed)weakSelf.changed();[weakSelf.navigationController popToViewController:weakSelf animated:YES];};[weakSelf.navigationController pushViewController:input animated:YES];};[self.navigationController pushViewController:page animated:YES];
}
@end

@interface PCViewController () <UIDocumentPickerDelegate, PHPickerViewControllerDelegate, UITextViewDelegate>
@property(nonatomic, strong) PCAgent *agent;
@property(nonatomic, strong) PCProjectStore *projectStore;
@property(nonatomic, strong) UITextView *log;
@property(nonatomic, strong) UITextView *input;
@property(nonatomic, strong) PCChatTimeline *timeline;
@property(nonatomic, strong) UILabel *placeholder;
@property(nonatomic, strong) NSLayoutConstraint *inputHeight;
@property(nonatomic, strong) PCSidebarTransition *sidebarTransition;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UIButton *sendButton;
@property(nonatomic, strong) UIButton *stopButton;
@property(nonatomic, strong) PCApprovalController *pendingApproval;
@property(nonatomic, strong) UIButton *projectButton;
@property(nonatomic, strong) UIButton *chatButton;
@property(nonatomic, strong) UIButton *createChatButton;
@property(nonatomic, strong) UIButton *overlayToggleButton;
@property(nonatomic, strong) UIButton *attachmentButton;
@property(nonatomic, strong) UIButton *clearAttachmentsButton;
@property(nonatomic, strong) UILabel *attachmentLabel;
@property(nonatomic, strong) NSMutableArray *pendingAttachments;
@property(nonatomic) UIBackgroundTaskIdentifier workBackgroundTask;
@property(nonatomic,strong) NSMutableDictionary *rpcUploads;
@property(nonatomic) BOOL followLatestMessages;
@property(nonatomic) BOOL scrollToLatestOnNextLayout;
@property(nonatomic,strong) PCVoiceSession *voiceSession;
@property(nonatomic,copy) NSString *voiceJobID,*voiceQuestionKey,*voiceCompletedJob,*pendingVoiceAction;
@property(nonatomic,copy) NSString *voiceLaunchRequestID,*lastVoiceCommandID;
@property(nonatomic) BOOL guideScheduled;
@end

@implementation PCViewController
- (void)refreshUILanguage {
    self.title=PCSelectedAssistantName();
    self.navigationItem.rightBarButtonItem.title=PCLocalized(@"设置");
    self.navigationItem.rightBarButtonItem.accessibilityLabel=PCLocalized(@"设置与设备控制");
    self.navigationItem.leftBarButtonItem.accessibilityLabel=PCLocalized(@"项目与对话侧栏");
    self.createChatButton.accessibilityLabel=PCLocalized(@"新建对话");
    self.log.accessibilityLabel=PCLocalized(@"对话和执行日志");
    self.input.accessibilityLabel=PCLocalized(@"输入任务");
    self.attachmentButton.accessibilityLabel=PCLocalized(@"添加照片或文件");
    [self.timeline refreshUILanguage];[self refreshOverlayToggle];[self updateComposer];
    if(!self.agent.running)self.status.text=PCLocalized(@"就绪");
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.projectStore = [PCProjectStore new];
    self.pendingAttachments = [NSMutableArray new];
    self.workBackgroundTask = UIBackgroundTaskInvalid;
    self.followLatestMessages = YES;
    self.scrollToLatestOnNextLayout = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshUILanguage) name:PCLanguageDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationBecameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(voiceActionNotification:) name:PCVoiceActionNotification object:nil];
    __weak PCViewController *voiceOwner=self;int voiceToken;notify_register_dispatch("local.asterhand.voice-command",&voiceToken,dispatch_get_main_queue(),^(int token){[voiceOwner handleVoiceControl];});
    self.title = PCSelectedAssistantName();
    self.view.backgroundColor = PCCanvasColor();
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:PCLocalized(@"设置") style:UIBarButtonItemStylePlain target:self action:@selector(settings)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = PCLocalized(@"设置与设备控制");
    UIImage *menuImage=[UIImage systemImageNamed:@"line.3.horizontal"];
    if(!menuImage){UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(22,18)];menuImage=[[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){CGContextRef c=context.CGContext;CGContextSetStrokeColorWithColor(c,UIColor.blackColor.CGColor);CGContextSetLineWidth(c,2);CGContextSetLineCap(c,kCGLineCapRound);for(int y=3;y<=15;y+=6){CGContextMoveToPoint(c,2,y);CGContextAddLineToPoint(c,20,y);}CGContextStrokePath(c);}] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];}
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:menuImage style:UIBarButtonItemStylePlain target:self action:@selector(manageChats)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel = PCLocalized(@"项目与对话侧栏");
    self.view.tintColor = PCTextColor();
    self.navigationController.navigationBar.tintColor = PCTextColor();
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground]; appearance.backgroundColor = PCCanvasColor(); appearance.shadowColor = PCBorderColor();
    appearance.titleTextAttributes = @{NSFontAttributeName:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]};
    self.navigationController.navigationBar.standardAppearance = appearance; self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.status = [UILabel new];
    self.status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.status.textColor = PCMutedColor();
    self.status.numberOfLines = 2;
    self.status.text = PCLocalized(@"就绪");
    self.projectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    PCStyleButton(self.projectButton,PCButtonPlain);
    [self.projectButton addTarget:self action:@selector(projectMenu) forControlEvents:UIControlEventTouchUpInside];
    self.chatButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if(@available(iOS 15.0,*)){UIButtonConfiguration *chatStyle=UIButtonConfiguration.plainButtonConfiguration;chatStyle.titleLineBreakMode=NSLineBreakByTruncatingTail;self.chatButton.configuration=chatStyle;}else{PCStyleButton(self.chatButton,PCButtonPlain);self.chatButton.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;}self.chatButton.titleLabel.numberOfLines=1;
    [self.chatButton addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(chatTitleDetails:)]];
    [self.chatButton addTarget:self action:@selector(chatMenu) forControlEvents:UIControlEventTouchUpInside];
    self.createChatButton = [UIButton buttonWithType:UIButtonTypeSystem];
    PCStyleButton(self.createChatButton,PCButtonPlain);
    [self.createChatButton setImage:[UIImage systemImageNamed:@"square.and.pencil"] forState:UIControlStateNormal];
    self.createChatButton.accessibilityLabel = PCLocalized(@"新建对话");
    [self.createChatButton addTarget:self action:@selector(newChat) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *projectRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.projectButton, self.chatButton, self.createChatButton]];
    projectRow.axis = UILayoutConstraintAxisHorizontal;
    projectRow.spacing = 8;
    projectRow.distribution = UIStackViewDistributionFill;
    self.projectButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.projectButton.titleLabel.font = self.chatButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [projectRow.heightAnchor constraintEqualToConstant:32].active = YES;
    self.chatButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.projectButton.widthAnchor constraintEqualToConstant:125].active = YES;
    [self.chatButton setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.chatButton.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [self.createChatButton.widthAnchor constraintEqualToConstant:44].active = YES;
    self.log = textView();
    self.log.editable = NO;
    self.log.delegate = self;
    self.log.accessibilityLabel = PCLocalized(@"对话和执行日志");
    self.timeline = [PCChatTimeline new];
    __weak PCViewController *timelineOwner = self;
    self.timeline.followChanged = ^(BOOL follow) { timelineOwner.followLatestMessages = follow; };
    self.timeline.answerQuestion = ^BOOL(NSString *job,NSString *prompt,NSString *text){PCViewController *owner=timelineOwner;if(![owner.agent isKindOfClass:PCPersistentAgent.class])return NO;BOOL sent=[(PCPersistentAgent *)owner.agent answer:text questionID:prompt jobID:job];owner.status.text=sent?PCLocalized(@"回答已发送"):PCLocalized(@"问题已更新或发送失败，请重试");if(sent){[owner.view endEditing:YES];PCHaptic(@"select");}return sent;};
    self.timeline.showDetails = ^(NSString *title, NSString *body) {
        UIViewController *detail = [UIViewController new]; detail.title = title; detail.view.backgroundColor = PCCanvasColor();
        UITextView *text = textView(); text.editable = NO; text.text = body; [detail.view addSubview:text];
        UILayoutGuide *g = detail.view.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[[text.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],[text.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],[text.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],[text.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12]]];
        [timelineOwner.navigationController pushViewController:detail animated:YES];
    };
    UIButton *top = [UIButton buttonWithType:UIButtonTypeSystem];
    [top setImage:[UIImage systemImageNamed:@"arrow.up.to.line"] forState:UIControlStateNormal];
    top.accessibilityLabel = PCLocalized(@"跳到对话顶部");
    [top addTarget:self action:@selector(scrollLogToTop) forControlEvents:UIControlEventTouchUpInside];
    UIButton *bottom = [UIButton buttonWithType:UIButtonTypeSystem];
    [bottom setImage:[UIImage systemImageNamed:@"arrow.down"] forState:UIControlStateNormal];
    bottom.accessibilityLabel = PCLocalized(@"跳到最新消息");
    [bottom addTarget:self action:@selector(scrollLogToBottom) forControlEvents:UIControlEventTouchUpInside];
    top.titleLabel.font = bottom.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    [top.widthAnchor constraintEqualToConstant:36].active = YES;
    [bottom.widthAnchor constraintEqualToConstant:36].active = YES;
    self.overlayToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.overlayToggleButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    [self.overlayToggleButton.widthAnchor constraintEqualToConstant:96].active = YES;
    [self.overlayToggleButton addTarget:self action:@selector(toggleOverlayVisibility) forControlEvents:UIControlEventTouchUpInside];
    [self refreshOverlayToggle];
    UIStackView *logNavigation = [[UIStackView alloc] initWithArrangedSubviews:@[self.overlayToggleButton, self.status, top, bottom]];
    logNavigation.alignment = UIStackViewAlignmentCenter;
    [self.status setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    self.status.numberOfLines = 1; self.status.lineBreakMode = NSLineBreakByTruncatingTail;
    logNavigation.spacing = 8;
    [logNavigation.heightAnchor constraintEqualToConstant:28].active = YES;
    self.input = textView();
    self.input.accessibilityLabel = PCLocalized(@"输入任务");
    self.input.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.input.autocorrectionType = UITextAutocorrectionTypeNo;
    self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.input.backgroundColor = UIColor.clearColor; self.input.delegate = self;
    self.input.textContainerInset = UIEdgeInsetsMake(8,4,8,4);
    self.inputHeight = [self.input.heightAnchor constraintEqualToConstant:46]; self.inputHeight.active = YES;
    self.placeholder = [UILabel new]; self.placeholder.text = PCLocalized(@"发送消息"); self.placeholder.textColor = UIColor.placeholderTextColor; self.placeholder.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; self.placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    [self.input addSubview:self.placeholder];
    [NSLayoutConstraint activateConstraints:@[[self.placeholder.leadingAnchor constraintEqualToAnchor:self.input.leadingAnchor constant:9],[self.placeholder.topAnchor constraintEqualToAnchor:self.input.topAnchor constant:8]]];
    self.attachmentButton = [UIButton buttonWithType:UIButtonTypeSystem];
    PCStyleButton(self.attachmentButton,PCButtonPlain);
    [self.attachmentButton setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    self.attachmentButton.accessibilityLabel = PCLocalized(@"添加照片或文件");
    [self.attachmentButton addTarget:self action:@selector(chooseAttachment) forControlEvents:UIControlEventTouchUpInside];
    self.clearAttachmentsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearAttachmentsButton setTitle:PCLocalized(@"清空") forState:UIControlStateNormal];
    [self.clearAttachmentsButton addTarget:self action:@selector(clearAttachments) forControlEvents:UIControlEventTouchUpInside];
    self.attachmentLabel = [UILabel new];
    self.attachmentLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.attachmentLabel.textColor = PCMutedColor();
    self.attachmentLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    UIStackView *attachmentRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.attachmentButton, self.attachmentLabel, self.clearAttachmentsButton]];
    attachmentRow.axis = UILayoutConstraintAxisHorizontal;
    attachmentRow.alignment = UIStackViewAlignmentCenter;
    attachmentRow.spacing = 8;
    [self.attachmentButton.widthAnchor constraintEqualToConstant:36].active = YES;
    [self.clearAttachmentsButton.widthAnchor constraintEqualToConstant:44].active = YES;
    [self updateAttachmentLabel];
    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    PCStyleButton(self.sendButton,PCButtonFilled);
    if(@available(iOS 15.0,*)){UIButtonConfiguration *sendStyle = UIButtonConfiguration.filledButtonConfiguration; sendStyle.baseBackgroundColor = PCTextColor(); sendStyle.baseForegroundColor = PCCanvasColor(); sendStyle.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    self.sendButton.configuration = sendStyle;}else{self.sendButton.backgroundColor=PCTextColor();self.sendButton.tintColor=PCCanvasColor();self.sendButton.layer.cornerRadius=22;} [self.sendButton setImage:[UIImage systemImageNamed:@"arrow.up"] forState:UIControlStateNormal]; self.sendButton.accessibilityLabel = PCLocalized(@"发送消息");
    [self.sendButton.widthAnchor constraintEqualToConstant:36].active = YES; [self.sendButton.heightAnchor constraintEqualToConstant:36].active = YES;
    [self.sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    PCStyleButton(self.stopButton,PCButtonBordered);
    [self.stopButton setImage:[UIImage systemImageNamed:@"stop.fill"] forState:UIControlStateNormal]; self.stopButton.accessibilityLabel = PCLocalized(@"停止任务");
    [self.stopButton.widthAnchor constraintEqualToConstant:36].active = YES; [self.stopButton.heightAnchor constraintEqualToConstant:36].active = YES;
    [self.stopButton addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton.enabled = NO;
    UIButton *voice=[UIButton buttonWithType:UIButtonTypeSystem];[voice setImage:[UIImage systemImageNamed:@"waveform"] forState:UIControlStateNormal];voice.accessibilityLabel=PCLocalized(@"连续语音对话");[voice.widthAnchor constraintEqualToConstant:36].active=YES;[voice.heightAnchor constraintEqualToConstant:36].active=YES;[voice addTarget:self action:@selector(openVoice) forControlEvents:UIControlEventTouchUpInside];
    [attachmentRow addArrangedSubview:voice];[attachmentRow addArrangedSubview:self.stopButton]; [attachmentRow addArrangedSubview:self.sendButton];
    UIView *composer = [PCSurfaceView new]; composer.backgroundColor = PCSurfaceColor(); composer.layer.cornerRadius = PCComposerRadius;
    UIStackView *composeStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.input,attachmentRow]];
    composeStack.axis = UILayoutConstraintAxisVertical; composeStack.spacing = 2; composeStack.translatesAutoresizingMaskIntoConstraints = NO; [composer addSubview:composeStack];
    [NSLayoutConstraint activateConstraints:@[[composeStack.topAnchor constraintEqualToAnchor:composer.topAnchor constant:6],[composeStack.bottomAnchor constraintEqualToAnchor:composer.bottomAnchor constant:-6],[composeStack.leadingAnchor constraintEqualToAnchor:composer.leadingAnchor constant:8],[composeStack.trailingAnchor constraintEqualToAnchor:composer.trailingAnchor constant:-8]]];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[projectRow,self.timeline,logNavigation,composer]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 4; stack.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:g.topAnchor],[stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],[stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],[stack.bottomAnchor constraintEqualToAnchor:PCKeyboardTopAnchor(self.view) constant:-8]]];
    self.agent = [PCPersistentAgent new];
    NSDictionary *active=PCAgentTaskState();if([active[@"running"] boolValue]&&active[@"context"][@"chat"]){[self.projectStore selectProject:active[@"context"][@"project"]];[self.projectStore selectChat:active[@"context"][@"chat"]];}
    [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(pollOverlay) userInfo:nil repeats:YES];
    self.agent.workspace = self.projectStore.currentProject[@"workspace"];
    [self.agent restoreHistory:self.projectStore.currentChat[@"history"] ?: @[]];
    __weak PCViewController *weakSelf = self;
    self.agent.event = ^(NSString *kind, NSString *text) {
        PCViewController *s = weakSelf;
        if ([kind isEqual:@"记录同步"]) {s.log.text=text;[s.timeline showTranscript:text];[s.projectStore saveTranscript:text];if(s.followLatestMessages){s.scrollToLatestOnNextLayout=YES;[s.view setNeedsLayout];}}
        else if ([kind isEqual:@"提问"]) {s.status.text=PCLocalized(@"等待你回答");[s updateComposer];}
        else if ([kind isEqual:@"状态"]) s.status.text = PCLocalized(text);
        else [s append:kind text:text];
    };
    self.agent.finished = ^{
        PCViewController *s = weakSelf;
        s.sendButton.enabled = YES;
        s.attachmentButton.enabled = YES;
        [s endWorkBackgroundTask];
        s.stopButton.enabled = NO;
        s.navigationItem.rightBarButtonItem.enabled = YES;
        s.status.text = s.agent.cancelled ? PCLocalized(@"任务已停止 · 可继续发送") : s.agent.failed ? PCLocalized(@"任务失败 · 检查错误后可重试") : PCLocalized(@"任务已完成 · 可继续发送");
        [s.projectStore saveHistory:[s.agent historySnapshot] transcript:s.log.text];
        [s refreshProjectControls];
        s.projectButton.enabled = YES; s.chatButton.enabled = YES; s.createChatButton.enabled = YES;
        [s.pendingApproval resolve:NO];
        s.pendingApproval = nil;
    };
    self.agent.approval = ^(NSString *name, NSDictionary *args, void (^reply)(BOOL)) {
        PCViewController *s = weakSelf;
        if (!s || !s.view.window || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { if(![s.agent isKindOfClass:PCPersistentAgent.class])reply(NO); return; }
        if(s.pendingApproval)return;
        [s.view endEditing:YES];
        PCApprovalController *approval = [PCApprovalController new];
        NSString *provider = [[NSUserDefaults standardUserDefaults] stringForKey:@"provider"] ?: @"openai";
        BOOL root = [NSUserDefaults.standardUserDefaults boolForKey:@"rootEnabled"];
        approval.details = PCRedact([NSString stringWithFormat:PCLocalized(@"工具：%@\n执行身份：%@\n工作目录：%@\n\n%@\n\n操作将在这台 iPhone 上执行。工作目录不是沙盒边界。命令可能读写其他可访问路径，结果会发送给 %@。\n\nwrite_file 覆盖文件时先备份；shell 改动不会自动备份。确认后执行，停止不会撤销已完成的改动。"), name, root ? @"Root (UID 0)" : PCLocalized(@"App 用户"), s.agent.workspace ?: PCWorkspace(), PCJSON(args), provider]);
        approval.reply = ^(BOOL allowed) { weakSelf.pendingApproval = nil; reply(allowed); };
        s.pendingApproval = approval;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:approval];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        nav.presentationController.delegate = approval;
        [s presentViewController:nav animated:YES completion:nil];
    };
    [self refreshProjectControls];
    NSDictionary *savedChat = self.projectStore.currentChat;
    self.log.text = [savedChat[@"transcript"] isKindOfClass:NSString.class] ? savedChat[@"transcript"] : @"";
    [self.timeline showTranscript:self.log.text];
    if (!self.log.text.length) [self append:@"欢迎" text:PCLocalized(@"选择模型，输入任务，或添加附件。")];
    [self updatePersistentContext];
    [self pollOverlay];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self scrollLogToBottom];
    if (!PCUserGuideCompleted() && !self.guideScheduled) {
        self.guideScheduled=YES;
        __weak typeof(self) weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PCViewController *owner=weakSelf;owner.guideScheduled=NO;
            if (!owner || PCUserGuideCompleted() || !owner.view.window || owner.presentedViewController || owner.navigationController.topViewController!=owner || owner.agent.running || owner.pendingVoiceAction || owner.voiceSession.active) return;
            PCUserGuideController *guide=[PCUserGuideController new];guide.onboarding=YES;
            guide.finished=^(BOOL connectAI){[weakSelf dismissViewControllerAnimated:YES completion:^{if(connectAI)[weakSelf settingsWithSection:1];}];};
            UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:guide];nav.modalPresentationStyle=UIModalPresentationFullScreen;
            [owner presentViewController:nav animated:YES completion:nil];
        });
    }
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.scrollToLatestOnNextLayout && self.timeline.bounds.size.height > 0) {
        self.scrollToLatestOnNextLayout = NO;
        [self scrollLogToBottom];
    }
}
- (void)applicationBecameActive {
    if([self.agent isKindOfClass:PCPersistentAgent.class])[(PCPersistentAgent *)self.agent resetPromptDelivery];
    self.followLatestMessages = YES;
    self.scrollToLatestOnNextLayout = YES;
    [self.view setNeedsLayout];
    if(self.pendingVoiceAction){NSString *action=self.pendingVoiceAction;self.pendingVoiceAction=nil;[self performVoiceAction:action];}
}
- (void)scrollLogToTop {
    self.followLatestMessages = NO;
    self.timeline.automaticFollow = NO;
    self.scrollToLatestOnNextLayout = NO;
    [self.timeline setContentOffset:CGPointMake(0,-self.timeline.adjustedContentInset.top) animated:NO];
}
- (void)scrollLogToBottom {
    self.followLatestMessages = YES;
    [self.timeline jumpToLatest];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.log || (!scrollView.dragging && !scrollView.decelerating)) return;
    CGFloat bottom = MAX(-scrollView.adjustedContentInset.top,
        scrollView.contentSize.height - scrollView.bounds.size.height + scrollView.adjustedContentInset.bottom);
    self.followLatestMessages = scrollView.contentOffset.y >= bottom - 24;
}
- (void)pollOverlay {
    __weak typeof(self) rpcOwner=self;PCAppRPCServe(^NSDictionary *(NSDictionary *arguments){return [rpcOwner handleAppRPC:arguments];});
    NSString *command = PCOverlayTakeCommand();
    if ([command isEqual:@"stop"] && self.agent.running) [self stop];
    else if ([command isEqual:@"pause"]) [self.agent pause];
    else if ([command isEqual:@"resume"]) [self.agent resume];
    PCOverlayPublish([NSUserDefaults.standardUserDefaults boolForKey:@"overlayEnabled"], self.agent.running, self.agent.paused);
    NSDictionary *policy=PCControlState();NSDictionary *desired=@{@"root":@([NSUserDefaults.standardUserDefaults boolForKey:@"rootEnabled"]),@"workspace":self.agent.workspace?:PCWorkspace()};
    // Existing control.json screen permission is retained on upgrade. Remote
    // screen authorization is managed separately in Remote Connections.
    if (![policy[@"root"] isEqual:desired[@"root"]]||![policy[@"workspace"] isEqual:desired[@"workspace"]])PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){[s addEntriesFromDictionary:desired];return nil;});
    [self refreshOverlayToggle];
    [self updateComposer];
    [self pollVoiceTask];
    [self handleVoiceControl];[self.voiceSession publishState];
}
- (NSDictionary *)handleAppRPC:(NSDictionary *)a {
    NSString *action=[a[@"action"] isKindOfClass:NSString.class]?a[@"action"]:@"";NSString *identifier=[a[@"id"] isKindOfClass:NSString.class]?a[@"id"]:@"";
    if([action isEqual:@"capabilities"])return @{@"version":@1,@"ui_required":@YES,@"groups":@[@"project",@"chat",@"ai",@"attachment",@"settings",@"voice",@"services"]};
    if([action isEqual:@"ai.status"]){NSDictionary *s=PCAgentTaskState();NSMutableDictionary *result=[NSMutableDictionary new];for(NSString *k in @[@"id",@"running",@"paused",@"failed",@"cancelled",@"status",@"latest_reply",@"question",@"context",@"revision"])if(s[k])result[k]=s[k];return result;}
    if([action isEqual:@"project.list"]||[action isEqual:@"chat.list"]){NSMutableArray *rows=[NSMutableArray new];for(NSDictionary *p in self.projectStore.projects){NSMutableArray *chats=[NSMutableArray new];for(NSDictionary *c in p[@"chats"])[chats addObject:@{@"id":c[@"id"],@"title":c[@"title"]?:@""}];[rows addObject:@{@"id":p[@"id"],@"name":p[@"name"]?:@"",@"workspace":p[@"workspace"]?:@"",@"chats":chats}];}return @{@"projects":rows,@"project":self.projectStore.currentProject[@"id"]?:@"",@"chat":self.projectStore.currentChat[@"id"]?:@""};}
    if([action isEqual:@"chat.read"]||[action isEqual:@"project.export"]){if(![identifier isEqual:self.projectStore.currentChat[@"id"]]&&[action isEqual:@"chat.read"])return @{@"error":PCLocalized(@"请先选择目标对话")};return [action isEqual:@"project.export"]?@{@"project":self.projectStore.currentProject?:@{},@"includes_credentials":@NO}:@{@"chat":self.projectStore.currentChat?:@{}};}
    if([action hasPrefix:@"project."]||[action hasPrefix:@"chat."]){if(self.agent.running)return @{@"error":PCLocalized(@"任务正在运行，不能更改项目或对话")};BOOL ok=NO;[self.projectStore saveHistory:[self.agent historySnapshot] transcript:self.log.text];
        if([action isEqual:@"project.create"])ok=[self.projectStore createProject:a[@"name"]]!=nil;
        else if([action isEqual:@"chat.create"])ok=[self.projectStore createChat]!=nil;
        else if([action isEqual:@"project.select"])ok=[self.projectStore selectProject:identifier];
        else if([action isEqual:@"chat.select"])ok=[self.projectStore selectChat:identifier];
        else if([action isEqual:@"project.rename"])ok=[self.projectStore renameProject:identifier name:a[@"name"]?:@""];
        else if([action isEqual:@"chat.rename"])ok=[self.projectStore renameChat:identifier title:a[@"name"]?:@""];
        else if([action isEqual:@"project.delete"]||[action isEqual:@"chat.delete"]){if(![a[@"confirm"] isEqual:@YES])return @{@"error":PCLocalized(@"删除操作需要 confirm:true")};ok=[action hasPrefix:@"project"]?[self.projectStore deleteProject:identifier]:[self.projectStore deleteChat:identifier];}
        if(ok)[self loadSelectedChat];return ok?@{@"ok":@YES,@"project":self.projectStore.currentProject[@"id"]?:@"",@"chat":self.projectStore.currentChat[@"id"]?:@""}:@{@"error":PCLocalized(@"项目操作失败或不支持")};
    }
    if([action isEqual:@"ai.send"]){if(!PCServicesEnabled())return @{@"error":PCLocalized(@"所有服务已关闭")};NSString *text=a[@"text"];if(![text isKindOfClass:NSString.class]||!text.length||text.length>32768)return @{@"error":PCLocalized(@"任务文字无效")};if(![a[@"project"] isEqual:self.projectStore.currentProject[@"id"]]||![a[@"chat"] isEqual:self.projectStore.currentChat[@"id"]])return @{@"error":PCLocalized(@"项目或对话已变化")};if(self.agent.running){if(![a[@"job"] isEqual:((PCPersistentAgent *)self.agent).currentTaskID])return @{@"error":PCLocalized(@"追加消息需要当前任务标识")};NSString *error=nil,*message=PCMessageEnqueue(PCRealPath(@"/var/mobile/Library/AgentGoTasks"),text,((PCPersistentAgent *)self.agent).currentTaskID,nil,&error);return message?@{@"queued":message}:@{@"error":error?:PCLocalized(@"消息未提交")};}[self updatePersistentContext];[self.agent send:text attachments:[self.pendingAttachments copy]];[self clearAttachments];return @{@"job":((PCPersistentAgent *)self.agent).currentTaskID?:@"",@"accepted":@YES};}
    if([action hasPrefix:@"ai."]){PCPersistentAgent *agent=(PCPersistentAgent *)self.agent;if(![a[@"job"] isEqual:agent.currentTaskID])return @{@"error":PCLocalized(@"任务标识已变化")};if([action isEqual:@"ai.stop"])[self stop];else if([action isEqual:@"ai.pause"])[agent pause];else if([action isEqual:@"ai.continue"])[agent resume];else if([action isEqual:@"ai.answer"]){BOOL ok=[agent answer:a[@"text"]?:@"" questionID:a[@"question"] jobID:a[@"job"]];return @{@"accepted":@(ok)};}else return @{@"error":PCLocalized(@"未知任务操作")};return @{@"accepted":@YES};}
    if([action isEqual:@"attachment.list"])return @{@"attachments":self.pendingAttachments?:@[]};
    if([action isEqual:@"attachment.cancel"]){NSDictionary *upload=self.rpcUploads[identifier];if(upload){[NSFileManager.defaultManager removeItemAtPath:[upload[@"path"] stringByDeletingLastPathComponent] error:nil];[self.rpcUploads removeObjectForKey:identifier];}return @{@"ok":@YES};}
    if([action isEqual:@"attachment.chunk"]){
        if(self.agent.running||![a[@"project"] isEqual:self.projectStore.currentProject[@"id"]]||![a[@"chat"] isEqual:self.projectStore.currentChat[@"id"]])return @{@"error":PCLocalized(@"项目或任务已变化，附件未提交")};
        if(![[NSUUID alloc] initWithUUIDString:identifier])return @{@"error":PCLocalized(@"传输标识无效")};NSString *name=a[@"name"];NSUInteger total=[a[@"total"] unsignedIntegerValue],offset=[a[@"offset"] unsignedIntegerValue];NSData *bytes=[a[@"data"] isKindOfClass:NSString.class]?[[NSData alloc] initWithBase64EncodedString:a[@"data"] options:0]:nil;
        if(![name isKindOfClass:NSString.class]||![name isEqual:name.lastPathComponent]||!name.length||[@[@".",@".."] containsObject:name]||[name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound||name.length>120||!total||total>8*1024*1024||!bytes.length||bytes.length>192*1024||offset>total||bytes.length>total-offset||self.pendingAttachments.count>=4)return @{@"error":PCLocalized(@"附件分块或大小无效")};
        if(!self.rpcUploads)self.rpcUploads=[NSMutableDictionary new];NSMutableDictionary *upload=self.rpcUploads[identifier];
        if(!upload){if(offset||self.rpcUploads.count>=4)return @{@"error":PCLocalized(@"传输不存在或过多")};NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"asterhand-upload-" stringByAppendingString:identifier]];if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil])return @{@"error":PCLocalized(@"无法创建传输目录")};NSString *path=[directory stringByAppendingPathComponent:name];if(![NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}])return @{@"error":PCLocalized(@"无法创建附件")};upload=[@{@"path":path,@"offset":@0,@"total":@(total),@"name":name,@"chat":a[@"chat"]} mutableCopy];self.rpcUploads[identifier]=upload;}
        if([upload[@"offset"] unsignedIntegerValue]!=offset||![upload[@"total"] isEqual:@(total)]||![upload[@"name"] isEqual:name]||![upload[@"chat"] isEqual:a[@"chat"]])return @{@"error":PCLocalized(@"附件分块顺序或上下文不一致")};NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:upload[@"path"]];if(!file)return @{@"error":PCLocalized(@"无法写入附件")};[file seekToEndOfFile];[file writeData:bytes];[file closeFile];upload[@"offset"]=@(offset+bytes.length);
        if(offset+bytes.length==total){NSError *error=nil;NSDictionary *imported=PCAttachmentImport([NSURL fileURLWithPath:upload[@"path"]],self.projectStore.currentProject[@"workspace"],&error);[NSFileManager.defaultManager removeItemAtPath:[upload[@"path"] stringByDeletingLastPathComponent] error:nil];[self.rpcUploads removeObjectForKey:identifier];if(!imported)return @{@"error":error.localizedDescription?:PCLocalized(@"附件导入失败")};[self.pendingAttachments addObject:imported];[self updateAttachmentLabel];return @{@"complete":@YES,@"attachment":imported};}return @{@"offset":upload[@"offset"],@"complete":@NO};
    }
    if([action isEqual:@"attachment.add"]){if(self.agent.running)return @{@"error":PCLocalized(@"请等待任务结束")};NSString *path=a[@"path"];if(![path isKindOfClass:NSString.class]||!path.isAbsolutePath||self.pendingAttachments.count>=4)return @{@"error":PCLocalized(@"附件路径无效或已达上限")};NSError *error=nil;NSDictionary *file=PCAttachmentImport([NSURL fileURLWithPath:PCRealPath(path)],self.projectStore.currentProject[@"workspace"]?:PCWorkspace(),&error);if(!file)return @{@"error":error.localizedDescription?:PCLocalized(@"附件导入失败")};[self.pendingAttachments addObject:file];[self updateAttachmentLabel];return @{@"attachment":file};}
    if([action isEqual:@"attachment.clear"]){[self clearAttachments];return @{@"ok":@YES};}
    if([action isEqual:@"ui.open"]){NSString *page=a[@"page"];if([page isEqual:@"settings"])[self settings];else if([page isEqual:@"projects"])[self manageChats];else if([page isEqual:@"voice"])[self openVoice];else if([page isEqual:@"devices"])[self.navigationController pushViewController:[PCDevicesController new] animated:YES];else if([page isEqual:@"diagnostics"])[self utilitiesPage];else return @{@"error":PCLocalized(@"页面无效")};return @{@"opened":page};}
    NSArray *settingKeys=@[@"uiLanguage",@"overlayEnabled",@"allowBackground",@"voiceIdleTimeoutSeconds",@"capsuleLocked",@"hapticStyle",@"provider",@"model.openai",@"model.chatgpt",@"reasoningEffort.openai",@"reasoningEffort.chatgpt",@"apiBase.openai",@"edgeWidth",@"edgeOpacity",@"effectAI",@"effectRemoteInput",@"effectRemoteConnected",@"effectScreenEdge"];
    if([action isEqual:@"settings.get"]){NSMutableDictionary *values=[NSMutableDictionary new];for(NSString *key in settingKeys)if([NSUserDefaults.standardUserDefaults objectForKey:key])values[key]=[NSUserDefaults.standardUserDefaults objectForKey:key];return @{@"settings":values};}
    if([action isEqual:@"settings.set"]){if(self.agent.running)return @{@"error":PCLocalized(@"请等待当前任务结束后修改设置")};NSDictionary *values=a[@"values"];if(![values isKindOfClass:NSDictionary.class])return @{@"error":PCLocalized(@"设置参数无效")};for(NSString *key in values)if(![settingKeys containsObject:key])return @{@"error":PCLocalized(@"此设置需在手机上修改或不支持")};for(NSString *key in values){id value=values[key];if(!PCAppSettingValid(key,value))return @{@"error":PCLocalized(@"设置值无效")};}if(values[@"provider"]&&![@[@"openai",@"chatgpt"] containsObject:values[@"provider"]])return @{@"error":PCLocalized(@"服务商无效")};if(values[@"apiBase.openai"]&&[values[@"apiBase.openai"] length]){NSURLComponents *u=[NSURLComponents componentsWithString:values[@"apiBase.openai"]];if(![u.scheme.lowercaseString isEqual:@"https"]||!u.host.length||u.user||u.password||u.query||u.fragment)return @{@"error":PCLocalized(@"API 地址无效")};}for(NSString *key in values)[NSUserDefaults.standardUserDefaults setObject:values[key] forKey:key];if(values[@"uiLanguage"])PCSetUILanguage(values[@"uiLanguage"]);if(values[@"overlayEnabled"])[NSUserDefaults.standardUserDefaults setObject:NSUUID.UUID.UUIDString.lowercaseString forKey:@"overlayVisibilityRequest"];PCOverlayPublish([NSUserDefaults.standardUserDefaults boolForKey:@"overlayEnabled"],self.agent.running,self.agent.paused);[self updatePersistentContext];return @{@"ok":@YES};}
    if([action isEqual:@"settings.api-key"]){if(self.agent.running)return @{@"error":PCLocalized(@"请等待任务结束")};NSString *key=a[@"key"];if(![key isKindOfClass:NSString.class]||key.length>8192)return @{@"error":PCLocalized(@"密钥无效")};if(!key.length&&![a[@"confirm"] isEqual:@YES])return @{@"error":PCLocalized(@"删除密钥需确认")};NSError *error=nil;BOOL ok=PCSetAPIKeyForProvider(@"openai",key,&error);return ok?@{@"saved":@YES}:@{@"error":PCLocalized(@"密钥未保存")};}
    if([action isEqual:@"voice.status"])return @{@"active":@(self.voiceSession.active),@"listening":@(self.voiceSession.listening),@"speaking":@(self.voiceSession.speaking),@"phase":self.voiceSession.phase?:@"",@"microphone_muted":@(self.voiceSession.microphoneMuted),@"speech_muted":@(self.voiceSession.speechMuted)};
    if([action isEqual:@"voice.start"]){[self openVoice];return @{@"requested":@YES,@"system_permissions_required":@YES};}
    if([action isEqual:@"voice.stop"]){[self.voiceSession stop];return @{@"ok":@YES};}
    if([action isEqual:@"voice.mute"]){if([a[@"microphone"] isKindOfClass:NSNumber.class])self.voiceSession.microphoneMuted=[a[@"microphone"] boolValue];if([a[@"speech"] isKindOfClass:NSNumber.class])self.voiceSession.speechMuted=[a[@"speech"] boolValue];return @{@"ok":@YES};}
    if([action isEqual:@"services.status"])return @{@"enabled":@(PCServicesEnabled())};
    if([action isEqual:@"services.result"]){NSDictionary *result=PCServicesResult(identifier);return result?:@{@"pending":@YES};}
    if([@[@"services.restart",@"services.stop",@"services.start"] containsObject:action]){[self stop];NSError *error=nil;NSString *nonce=PCServicesRequest([action isEqual:@"services.stop"]?@"stop_services":@"restart_services",&error);return nonce?@{@"request":nonce,@"connection_may_close":@YES}:@{@"error":error.localizedDescription?:PCLocalized(@"服务请求失败")};}
    return @{@"error":PCLocalized(@"此应用操作尚不支持")};
}
- (void)refreshOverlayToggle {
    NSData *statusData=[NSData dataWithContentsOfFile:[PCOverlayDirectory() stringByAppendingPathComponent:@"overlay-status.json"]];NSDictionary *status=statusData?[NSJSONSerialization JSONObjectWithData:statusData options:0 error:nil]:nil;BOOL visible=status[@"visible"]?[status[@"visible"] boolValue]:[NSUserDefaults.standardUserDefaults boolForKey:@"overlayEnabled"];
    NSString *title = visible ? PCLocalized(@"隐藏悬浮") : PCLocalized(@"显示悬浮");
    if (![self.overlayToggleButton.currentTitle isEqualToString:title]) [self.overlayToggleButton setTitle:title forState:UIControlStateNormal];
    self.overlayToggleButton.accessibilityLabel = visible ? PCLocalized(@"隐藏悬浮按钮") : PCLocalized(@"显示悬浮按钮");
}
- (void)toggleOverlayVisibility {
    PCHaptic(@"select");
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSData *statusData=[NSData dataWithContentsOfFile:[PCOverlayDirectory() stringByAppendingPathComponent:@"overlay-status.json"]];NSDictionary *status=statusData?[NSJSONSerialization JSONObjectWithData:statusData options:0 error:nil]:nil;BOOL visible=status[@"visible"]?[status[@"visible"] boolValue]:[defaults boolForKey:@"overlayEnabled"];[defaults setBool:!visible forKey:@"overlayEnabled"];[defaults setObject:NSUUID.UUID.UUIDString.lowercaseString forKey:@"overlayVisibilityRequest"];
    [self pollOverlay];
}
- (void)refreshProjectControls {
    NSDictionary *project = self.projectStore.currentProject ?: @{};
    NSDictionary *chat = self.projectStore.currentChat ?: @{};
    [self.projectButton setTitle:[NSString stringWithFormat:@"%@ ▾", project[@"name"] ?: PCLocalized(@"默认项目")] forState:UIControlStateNormal];
    [self.chatButton setTitle:chat[@"title"] ?: PCLocalized(@"新对话") forState:UIControlStateNormal];
}
- (void)updatePersistentContext {
    if([self.agent isKindOfClass:PCPersistentAgent.class]){((PCPersistentAgent *)self.agent).projectContext=@{@"storage":[self.projectStore persistentPath],@"project":self.projectStore.currentProject[@"id"]?:@"",@"chat":self.projectStore.currentChat[@"id"]?:@"",@"transcript":self.log.text?:@""};[((PCPersistentAgent *)self.agent) publishOverlayContext];}
}
- (void)loadSelectedChat {
    [self.voiceSession stop];
    [self clearAttachments];
    NSDictionary *project = self.projectStore.currentProject ?: @{};
    NSDictionary *chat = self.projectStore.currentChat ?: @{};
    self.agent.workspace = project[@"workspace"];
    if([self.agent.workspace isAbsolutePath])[NSFileManager.defaultManager createDirectoryAtPath:PCRealPath(self.agent.workspace) withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    [self.agent restoreHistory:chat[@"history"] ?: @[]];
    self.log.text = [chat[@"transcript"] isKindOfClass:NSString.class] ? chat[@"transcript"] : @"";
    self.followLatestMessages = YES;
    self.scrollToLatestOnNextLayout = YES;
    [self.view setNeedsLayout];
    [self refreshProjectControls];
    [self updatePersistentContext];
    [self.timeline showTranscript:self.log.text];
    if (!self.log.text.length) [self append:@"新对话" text:project[@"name"] ?: PCLocalized(@"项目")];
}
- (void)projectMenu {
    [self manageChats];
}
- (void)chatTitleDetails:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan)return;
    PCOptionsPage *page=[[PCOptionsPage alloc] initWithStyle:UITableViewStyleInsetGrouped];page.title=PCLocalized(@"对话信息");page.options=@[];page.explanation=[NSString stringWithFormat:PCLocalized(@"%@\n\n项目：%@"),self.projectStore.currentChat[@"title"]?:PCLocalized(@"新对话"),self.projectStore.currentProject[@"name"]?:PCLocalized(@"默认项目")];[self.navigationController pushViewController:page animated:YES];
}
- (void)chatMenu {
    [self manageChats];
}
- (void)manageChats {
    if (self.agent.running) return;
    [self.projectStore saveHistory:[self.agent historySnapshot] transcript:self.log.text];
    PCWorkspaceManager *manager = [[PCWorkspaceManager alloc] initWithStyle:UITableViewStyleInsetGrouped];
    manager.store = self.projectStore;
    __weak PCViewController *weakSelf = self;
    manager.changed = ^{ [weakSelf loadSelectedChat]; };
    self.sidebarTransition = [PCSidebarTransition new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:manager];
    nav.modalPresentationStyle = UIModalPresentationCustom; nav.transitioningDelegate = self.sidebarTransition;
    [self.view endEditing:YES];
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)newChat {
    PCHaptic(@"impact");
    if (self.agent.running) return;
    [self.projectStore saveHistory:[self.agent historySnapshot] transcript:self.log.text];
    [self.projectStore createChat];
    [self loadSelectedChat];
}
- (void)append:(NSString *)kind text:(NSString *)text {
    NSString *value = [self.log.text stringByAppendingFormat:@"\n[%@]\n%@\n", kind, PCRedact(text ?: @"")];
    if (value.length > 160000) value = [PCLocalized(@"[较早的显示日志已截断；模型上下文未因此缩短]\n") stringByAppendingString:[value substringFromIndex:value.length - 140000]];
    self.log.text = value;
    [self.timeline showTranscript:value];
    [self.projectStore saveTranscript:value];
    if (self.followLatestMessages) {
        self.scrollToLatestOnNextLayout = YES;
        [self.view setNeedsLayout];
    }
}
- (void)updateAttachmentLabel {
    if (!self.pendingAttachments.count) self.attachmentLabel.text = @"";
    else {
        NSMutableArray *names = [NSMutableArray new];
        for (NSDictionary *file in self.pendingAttachments) [names addObject:file[@"name"] ?: PCLocalized(@"附件")];
        self.attachmentLabel.text = [NSString stringWithFormat:PCLocalized(@"%lu 个：%@"), (unsigned long)names.count, [names componentsJoinedByString:@"、"]];
    }
    self.clearAttachmentsButton.hidden = !self.pendingAttachments.count;
}
- (void)clearAttachments { [self.pendingAttachments removeAllObjects]; [self updateAttachmentLabel]; }
- (void)addAttachment:(NSDictionary *)file {
    if (!file) return;
    if (self.pendingAttachments.count >= 4) { [self append:@"附件" text:PCLocalized(@"每条消息最多选择 4 个附件。")]; return; }
    [self.pendingAttachments addObject:file];
    [self updateAttachmentLabel];
    [self append:@"附件" text:[NSString stringWithFormat:PCLocalized(@"已导入当前项目：%@（%@ 字节）。发送任务时才会上传到所选 AI 服务。"), file[@"name"], file[@"size"]]];
}
- (void)chooseAttachment {
    if(self.agent.running)return;PCOptionsPage *page=[[PCOptionsPage alloc] initWithStyle:UITableViewStyleInsetGrouped];page.title=PCLocalized(@"添加附件");page.options=@[@{@"title":PCLocalized(@"照片"),@"icon":@"photo"},@{@"title":PCLocalized(@"文件"),@"icon":@"doc"}];__weak typeof(self) weakSelf=self;
    page.selectOption=^(NSInteger selected){[weakSelf.navigationController popToViewController:weakSelf animated:NO];if(selected==0){PHPickerConfiguration *config=[PHPickerConfiguration new];config.filter=PHPickerFilter.imagesFilter;config.selectionLimit=MAX(1,4-(NSInteger)weakSelf.pendingAttachments.count);PHPickerViewController *picker=[[PHPickerViewController alloc] initWithConfiguration:config];picker.delegate=weakSelf;[weakSelf presentViewController:picker animated:YES completion:nil];}else{UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];picker.delegate=weakSelf;picker.allowsMultipleSelection=YES;[weakSelf presentViewController:picker animated:YES completion:nil];}};[self.navigationController pushViewController:page animated:YES];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) {
        if (self.pendingAttachments.count >= 4) break;
        NSError *error = nil;
        NSDictionary *file = PCAttachmentImport(url, self.projectStore.currentProject[@"workspace"] ?: PCWorkspace(), &error);
        if (file) [self addAttachment:file];
        else [self append:@"附件错误" text:error.localizedDescription ?: PCLocalized(@"导入文件失败。")]; 
    }
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSString *workspace = self.projectStore.currentProject[@"workspace"] ?: PCWorkspace();
    for (PHPickerResult *result in results) {
        [result.itemProvider loadDataRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSData *data, NSError *loadError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.pendingAttachments.count >= 4) return;
                NSError *error = loadError;
                NSDictionary *file = data ? PCAttachmentImportImage(data, workspace, &error) : nil;
                if (file) [self addAttachment:file];
                else [self append:@"附件错误" text:error.localizedDescription ?: PCLocalized(@"读取图片失败。")]; 
            });
        }];
    }
}
- (void)updateComposer {
    self.placeholder.hidden = self.input.text.length > 0;
    NSDictionary *prompt=[self.agent isKindOfClass:PCPersistentAgent.class]?((PCPersistentAgent *)self.agent).pendingQuestion:nil;
    [self.timeline showPendingQuestion:prompt];BOOL question=prompt!=nil,submitted=[prompt[@"client_submitted"] boolValue];
    BOOL rootQuestion=[prompt[@"kind"] isEqual:@"root_permission"];self.input.editable=!rootQuestion;
    self.placeholder.text=question?PCLocalized(@"回答 AI…"):PCLocalized(@"发送消息");self.stopButton.hidden=!self.agent.running;self.sendButton.hidden=self.agent.running&&!question;self.sendButton.enabled=(!self.agent.running||question)&&!submitted&&(self.input.text.length||self.pendingAttachments.count);
    if(rootQuestion){self.placeholder.text=PCLocalized(@"请选择上方的 Root 授权选项");self.sendButton.hidden=YES;}
}
- (void)textViewDidChange:(UITextView *)textView {
    if (textView != self.input) return;
    CGFloat height = [self.input sizeThatFits:CGSizeMake(MAX(100,self.input.bounds.size.width),CGFLOAT_MAX)].height;
    self.inputHeight.constant = MAX(46,MIN(132,height)); self.input.scrollEnabled = height>132; [self updateComposer];
}
- (void)send {
    if(!PCServicesEnabled()){self.status.text=PCLocalized(@"所有服务已关闭，请先在设置中开启");return;}
    PCHaptic(@"impact");
    NSString *message = [self.input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if([self.agent isKindOfClass:PCPersistentAgent.class]&&((PCPersistentAgent *)self.agent).pendingQuestion){NSDictionary *prompt=((PCPersistentAgent *)self.agent).pendingQuestion;if(message.length&&[(PCPersistentAgent *)self.agent answer:message questionID:prompt[@"id"] jobID:prompt[@"job_id"]]){self.input.text=@"";[self textViewDidChange:self.input];self.status.text=PCLocalized(@"回答已发送");}return;}
    if ((!message.length && !self.pendingAttachments.count) || self.agent.running) return;
    [self updatePersistentContext];
    PCRequestNotificationsIfNeeded(NO,nil);
    if (message.length > 32768) { [self append:@"提示" text:PCLocalized(@"单条任务最多 32768 个字符。")]; return; }
    [self.view endEditing:YES];
    self.input.text = @"";
    [self textViewDidChange:self.input];
    NSArray *attachments = [self.pendingAttachments copy];
    NSMutableArray *names = [NSMutableArray new];
    for (NSDictionary *file in attachments) [names addObject:file[@"name"] ?: PCLocalized(@"附件")];
    [self append:@"你" text:[NSString stringWithFormat:@"%@%@", message, names.count ? [NSString stringWithFormat:PCLocalized(@"\n[附件] %@"), [names componentsJoinedByString:@"、"]] : @""]];
    [self clearAttachments];
    self.sendButton.enabled = NO;
    self.attachmentButton.enabled = NO;
    self.stopButton.enabled = YES;
    self.projectButton.enabled = NO;
    self.chatButton.enabled = NO;
    self.createChatButton.enabled = NO;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    if (![self.agent isKindOfClass:PCPersistentAgent.class] && [NSUserDefaults.standardUserDefaults boolForKey:@"allowBackground"]) {
        __weak PCViewController *weakSelf = self;
        self.workBackgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"AsterHand task" expirationHandler:^{
            PCViewController *controller = weakSelf;
            if (!controller) return;
            [controller.agent stop];
            [controller append:@"后台" text:PCLocalized(@"系统后台执行时间已用尽，任务已停止。")];
            [controller endWorkBackgroundTask];
        }];
        if (self.workBackgroundTask == UIBackgroundTaskInvalid) [self append:@"后台" text:PCLocalized(@"系统未授予后台执行时间；切到后台时任务将停止。")];
    }
    [self.agent send:message attachments:attachments];
}
- (void)endWorkBackgroundTask {
    UIBackgroundTaskIdentifier identifier = self.workBackgroundTask;
    self.workBackgroundTask = UIBackgroundTaskInvalid;
    if (identifier != UIBackgroundTaskInvalid) [UIApplication.sharedApplication endBackgroundTask:identifier];
}
- (void)stop {
    BOOL wasRunning = self.agent.running;
    [self.voiceSession stop];
    PCHaptic(@"warning");
    [self.agent stop];
    [self.pendingApproval resolve:NO];
    self.pendingApproval = nil;
    self.status.text = wasRunning ? PCLocalized(@"正在停止…") : PCLocalized(@"就绪");
}
- (void)stopForBackground {
    PCAgentSetForeground(NO);
    if([self.agent isKindOfClass:PCPersistentAgent.class])return;
    if (!self.agent.running) return;
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"allowBackground"] && self.workBackgroundTask != UIBackgroundTaskInvalid) {
        [self append:@"后台" text:PCLocalized(@"任务将在系统允许的后台时间内继续；返回 App 可查看结果。")];
        return;
    }
    UIApplication *app = UIApplication.sharedApplication;
    /* A short cleanup grant gives the worker time to reap its cancelled child. */
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    task = [app beginBackgroundTaskWithName:@"Stop local task" expirationHandler:^{
        [self.agent stop];
        if (task != UIBackgroundTaskInvalid) { [app endBackgroundTask:task]; task = UIBackgroundTaskInvalid; }
    }];
    [self stop];
    [self append:@"已停止" text:PCLocalized(@"App 已进入后台，停止当前任务。返回后可检查结果再继续。")];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        for (int i = 0; i < 100 && self.agent.running; i++) usleep(50000);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task != UIBackgroundTaskInvalid) { [app endBackgroundTask:task]; task = UIBackgroundTaskInvalid; }
        });
    });
}
- (void)settings {
    [self settingsWithSection:0];
}
- (void)settingsWithSection:(NSInteger)section {
    if (self.agent.running) return;
    PCSettingsController *controller = [PCSettingsController new];
    __weak PCViewController *weakSelf = self;
    __weak PCSettingsController *weakSettings = controller;
    controller.toolsAction = ^{ [weakSettings dismissViewControllerAnimated:YES completion:^{ [weakSelf utilitiesPage]; }]; };
    controller.saveCompletion = ^{
        PCViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if ([strongSelf.projectStore syncDefaultWorkspace]) strongSelf.agent.workspace = strongSelf.projectStore.currentProject[@"workspace"];
        strongSelf.title = PCSelectedAssistantName();
        [strongSelf refreshProjectControls];
        [strongSelf updatePersistentContext];
        [strongSelf pollOverlay];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    if(section){PCSettingsController *detail=[PCSettingsController new];detail.focusSection=section;detail.saveCompletion=controller.saveCompletion;detail.toolsAction=controller.toolsAction;nav.viewControllers=@[controller,detail];}
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)voiceActionNotification:(NSNotification *)note {if([note.object isKindOfClass:NSString.class])[self performVoiceAction:note.object];}
- (void)openVoice {[self performVoiceAction:@"voice"];}
- (void)performFloatingVoiceRequest:(NSString *)requestID {if(!PCVoiceFloatingLaunchValid(requestID))return;self.voiceLaunchRequestID=requestID;[self performVoiceAction:@"floating-voice"];}
- (void)performVoiceAction:(NSString *)action {
    if(!PCServicesEnabled()&&![action isEqual:@"open"]){self.status.text=PCLocalized(@"所有服务已关闭，请先在设置中开启");return;}
    BOOL floating=[action isEqual:@"floating-voice"];if(!PCVoiceActionValid(action)&&!floating)return;[self loadViewIfNeeded];
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){self.pendingVoiceAction=action;return;}
    __weak typeof(self) weakSelf=self;
    void(^open)(void)=^{PCViewController *s=weakSelf;if(!s)return;UINavigationController *nav=s.navigationController;
        if(([action isEqual:@"voice"]||floating)&&[nav.topViewController isKindOfClass:PCVoiceController.class]){if(!s.voiceSession.active){s.voiceSession.allowsBackground=floating;s.voiceSession.launchRequestID=floating?s.voiceLaunchRequestID:nil;if(s.agent.running&&[s.agent isKindOfClass:PCPersistentAgent.class])s.voiceJobID=((PCPersistentAgent *)s.agent).currentTaskID;[s.voiceSession startWaiting:s.agent.running];}return;}
        [nav popToRootViewControllerAnimated:NO];if([action isEqual:@"open"])return;
        if(!s.voiceSession){s.voiceSession=[PCVoiceSession new];s.voiceSession.submitText=^BOOL(NSString *text){return [weakSelf sendVoiceText:text];};}
        BOOL reuse=s.voiceSession.active&&s.voiceSession.allowsBackground;
        if(!reuse){[s.voiceSession stop];s.voiceSession.allowsBackground=floating;s.voiceSession.launchRequestID=floating?s.voiceLaunchRequestID:nil;s.voiceJobID=nil;s.voiceQuestionKey=nil;s.voiceCompletedJob=nil;}
        PCVoiceController *page=[PCVoiceController new];page.session=s.voiceSession;page.AIIsRunning=^BOOL{return weakSelf.agent.running;};page.stopAI=^{[weakSelf stop];};page.startOnAppearance=([action isEqual:@"voice"]||floating)&&!reuse;
        if(s.agent.running&&[s.agent isKindOfClass:PCPersistentAgent.class])s.voiceJobID=((PCPersistentAgent *)s.agent).currentTaskID;
        page.userActivity=PCVoiceShortcutActivity(floating?@"voice":action);[page.userActivity becomeCurrent];[nav pushViewController:page animated:YES];
        if([action isEqual:@"status"]){NSDictionary *state=PCAgentTaskState();NSString *status=[state[@"running"] boolValue]?state[@"question"]?PCLocalized(@"AI 正在等待你确认或回答"):state[@"status"]?:PCLocalized(@"AI 正在运行"):[state[@"failed"] boolValue]?PCLocalized(@"上次任务遇到问题，请在聊天页面查看"):state[@"status"]?:PCLocalized(@"当前没有运行中的任务");dispatch_after(dispatch_time(DISPATCH_TIME_NOW,400*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(nav.topViewController==page)[page.session speak:status thenListen:NO];});}
    };
    if(self.presentedViewController)[self dismissViewControllerAnimated:YES completion:open];else open();
}
- (BOOL)sendVoiceText:(NSString *)text {
    if(!PCServicesEnabled())return NO;
    if(!self.voiceSession.active||(!self.voiceSession.allowsBackground&&UIApplication.sharedApplication.applicationState!=UIApplicationStateActive))return NO;
    if(![self.agent isKindOfClass:PCPersistentAgent.class])return NO;
    PCPersistentAgent *agent=(PCPersistentAgent *)self.agent;NSDictionary *question=agent.pendingQuestion;
    if(question){
        // Voice never grants Root or tool approval. Those remain explicit UI choices.
        if([@[@"root_permission",@"approval"] containsObject:question[@"kind"]?:@""])return NO;
        NSString *key=[NSString stringWithFormat:@"%@/%@",question[@"job_id"],question[@"id"]];if(![key isEqual:self.voiceQuestionKey]||[question[@"client_submitted"] boolValue])return NO;
        BOOL sent=[agent answer:text questionID:question[@"id"] jobID:question[@"job_id"]];if(sent)self.voiceJobID=question[@"job_id"];return sent;
    }
    if(agent.running||self.input.text.length||self.pendingAttachments.count)return NO;
    NSString *previous=agent.currentTaskID;self.input.text=text;[self textViewDidChange:self.input];[self send];
    if(!agent.running||[previous isEqual:agent.currentTaskID])return NO;
    self.voiceJobID=agent.currentTaskID;self.voiceQuestionKey=nil;self.voiceCompletedJob=nil;return YES;
}
- (void)handleVoiceControl {
    if(!PCServicesEnabled()){if(self.voiceSession.active)[self.voiceSession stop];return;}
    NSString *path=[PCOverlayDirectory() stringByAppendingPathComponent:@"voice-command.json"];NSData *data=[NSData dataWithContentsOfFile:path];if(!data||data.length>4096)return;NSDictionary *command=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];if(![command isKindOfClass:NSDictionary.class]||![command[@"id"] isKindOfClass:NSString.class]||[command[@"id"] isEqual:self.lastVoiceCommandID]||fabs(NSDate.date.timeIntervalSince1970-[command[@"created"] doubleValue])>15)return;
    if([command[@"action"] isEqual:@"start"]&&PCVoiceFloatingLaunchValid(command[@"id"])){
        if(![command[@"wake_ready"] boolValue])return;
        self.lastVoiceCommandID=command[@"id"];if(self.voiceSession.active)return;
        if(!self.voiceSession){self.voiceSession=[PCVoiceSession new];__weak typeof(self) weakSelf=self;self.voiceSession.submitText=^BOOL(NSString *text){return [weakSelf sendVoiceText:text];};}
        self.voiceSession.allowsBackground=YES;self.voiceSession.launchRequestID=command[@"id"];self.voiceCompletedJob=nil;self.voiceQuestionKey=nil;self.voiceJobID=self.agent.running&&[self.agent isKindOfClass:PCPersistentAgent.class]?((PCPersistentAgent *)self.agent).currentTaskID:nil;
        [self.voiceSession startWaiting:self.agent.running];return;
    }
    if(![command[@"session"] isEqual:self.voiceSession.controlSessionID])return;
    self.lastVoiceCommandID=command[@"id"];NSString *action=command[@"action"];
    if([action isEqual:@"stop"])[self.voiceSession stop];
    else if([action isEqual:@"interrupt"])[self.voiceSession interruptAndListen];
    else if([action isEqual:@"submit"])[self.voiceSession submitUtterance];
    else if([action isEqual:@"microphone_mute"]&&[command[@"muted"] isKindOfClass:NSNumber.class])self.voiceSession.microphoneMuted=[command[@"muted"] boolValue];
    else if([action isEqual:@"speech_mute"]&&[command[@"muted"] isKindOfClass:NSNumber.class])self.voiceSession.speechMuted=[command[@"muted"] boolValue];
    else if([action isEqual:@"return_home"]&&self.voiceSession.active&&self.voiceSession.allowsBackground&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive){SEL selector=NSSelectorFromString(@"suspend");if([UIApplication.sharedApplication respondsToSelector:selector])[UIApplication.sharedApplication performSelector:selector];}
}
- (void)pollVoiceTask {
    if(!self.voiceSession.active||!self.voiceJobID)return;
    NSDictionary *state=PCAgentTaskState();if(![state[@"id"] isEqual:self.voiceJobID]||![state[@"context"][@"chat"] isEqual:self.projectStore.currentChat[@"id"]])return;
    NSDictionary *question=[state[@"question"] isKindOfClass:NSDictionary.class]?state[@"question"]:nil;
    if([state[@"running"] boolValue]&&question){
        NSString *key=[NSString stringWithFormat:@"%@/%@",state[@"id"],question[@"id"]];if([key isEqual:self.voiceQuestionKey])return;self.voiceQuestionKey=key;
        BOOL confirm=[@[@"root_permission",@"approval"] containsObject:question[@"kind"]?:@""];
        NSString *text=confirm?PCLocalized(@"这项操作需要你在聊天页面确认权限。语音不会自动允许操作。"):question[@"text"]?:PCLocalized(@"AI 需要你回答");
        if(!confirm&&[question[@"options"] count])text=[text stringByAppendingFormat:PCLocalized(@"。可选：%@。也可以直接说出回答。"),[question[@"options"] componentsJoinedByString:@"，"]];
        [self.voiceSession speak:text thenListen:!confirm];return;
    }
    if([state[@"running"] boolValue]){if(self.voiceQuestionKey){self.voiceQuestionKey=nil;[self.voiceSession waitForAI];}return;}
    if([self.voiceCompletedJob isEqual:self.voiceJobID])return;self.voiceCompletedJob=self.voiceJobID;
    NSString *reply=[state[@"latest_reply"] isKindOfClass:NSString.class]?state[@"latest_reply"]:nil;
    if([state[@"cancelled"] boolValue]){[self.voiceSession stop];return;}
    if([state[@"failed"] boolValue]){[self.voiceSession blockForConfirmation:PCLocalized(@"任务遇到问题，请返回聊天页面查看错误后重试。")];return;}
    [self.voiceSession speak:reply.length?reply:PCLocalized(@"本轮没有可朗读的回复，请查看聊天记录。") thenListen:reply.length>0];
}
- (void)utilitiesPage {
    PCOptionsPage *page=[[PCOptionsPage alloc] initWithStyle:UITableViewStyleInsetGrouped];page.title=PCLocalized(@"诊断与日志");__weak PCOptionsPage *weakPage=page;page.options=@[@{@"title":PCLocalized(@"本机诊断")},@{@"title":PCLocalized(@"离线自检")},@{@"title":PCLocalized(@"导出对话日志")},@{@"title":PCLocalized(@"服务总开关与恢复"),@"subtitle":PCLocalized(@"停止任务、语音、远控与悬浮窗"),@"icon":@"arrow.clockwise"}];__weak typeof(self) weakSelf=self;
    page.selectOption=^(NSInteger option){if(option==3){PCRecoveryController *recovery=[PCRecoveryController new];recovery.beforeRestart=^{[weakSelf stop];};[weakPage.navigationController pushViewController:recovery animated:YES];return;}if(option==2){UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[PCRedact(weakSelf.log.text)] applicationActivities:nil];share.popoverPresentationController.sourceView=weakPage.view;[weakPage presentViewController:share animated:YES completion:nil];return;}
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{PCTools *tools=[PCTools new];tools.workspace=weakSelf.agent.workspace;NSString *result=PCJSON(option==0?[tools diagnostics]:PCOfflineSelfTest());dispatch_async(dispatch_get_main_queue(),^{[weakSelf append:option==0?PCLocalized(@"本机诊断"):PCLocalized(@"离线自检") text:result];UIViewController *report=[UIViewController new];report.title=option==0?PCLocalized(@"本机诊断"):PCLocalized(@"离线自检");report.view.backgroundColor=PCCanvasColor();UITextView *text=textView();text.editable=NO;text.text=result;[report.view addSubview:text];UILayoutGuide *g=report.view.safeAreaLayoutGuide;[NSLayoutConstraint activateConstraints:@[[text.topAnchor constraintEqualToAnchor:g.topAnchor],[text.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],[text.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],[text.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12]]];[weakPage.navigationController pushViewController:report animated:YES];});});};[self.navigationController pushViewController:page animated:YES];
}
- (void)more {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *device = [NSString stringWithFormat:@"%@ · iOS %@ · %@", UIDevice.currentDevice.model, UIDevice.currentDevice.systemVersion, PCEnvironmentName()];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[@"AsterHand " stringByAppendingString:version] message:device preferredStyle:UIAlertControllerStyleActionSheet];
      [a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"控制中心") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
          [self.navigationController pushViewController:[PCDevicesController new] animated:YES];
      }]];
    [a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"本机诊断（不联网）") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        PCTools *tools = [PCTools new]; tools.workspace = PCWorkspace();
        [self append:@"本机诊断" text:PCJSON([tools diagnostics])];
    }]];
    if (!self.agent.running) [a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"新建对话") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self newChat];
    }]];
    if (!self.agent.running) [a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"离线自检（文件、shell、Keychain）") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.sendButton.enabled = NO;
        self.navigationItem.rightBarButtonItem.enabled = NO;
        self.navigationItem.leftBarButtonItem.enabled = NO;
        self.status.text = PCLocalized(@"正在离线自检…");
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSDictionary *results = PCOfflineSelfTest();
            dispatch_async(dispatch_get_main_queue(), ^{
                [self append:@"离线自检" text:PCJSON(results)];
                self.sendButton.enabled = YES;
                self.navigationItem.rightBarButtonItem.enabled = YES;
                self.navigationItem.leftBarButtonItem.enabled = YES;
                self.status.text = PCLocalized(@"自检结束 · 请检查各项 true / false");
            });
        });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"导出当前显示日志") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[PCRedact(self.log.text)] applicationActivities:nil];
        share.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
        [self presentViewController:share animated:YES completion:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"设置") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self settings]; }]];
    [a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"取消") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:a animated:YES completion:nil];
}
@end
