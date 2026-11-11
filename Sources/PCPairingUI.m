#import "PCTheme.h"
#import "PCLocalization.h"
#import "PCButtonCompat.h"
#import "PCPairing.h"
#import "PCControl.h"
#import "PCPages.h"
#import "PCSupport.h"

@implementation PCPairApprovalController
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=[UIColor colorWithWhite:0 alpha:0.5];
    UIView *card=[UIView new];card.backgroundColor=PCSoftColor();card.layer.cornerRadius=28;card.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:card];
    UILabel *title=[UILabel new];title.text=[NSString stringWithFormat:PCLocalized(@"%@ 请求连接"),self.request[@"name"]];title.font=[UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];title.numberOfLines=0;
    UILabel *subtitle=[UILabel new];subtitle.text=[NSString stringWithFormat:PCLocalized(@"设备 %@\n核对码 %@\n允许查看和操作屏幕、文件及终端。Root 权限遵循本机开关。"),[self.request[@"device_id"] substringToIndex:12],self.request[@"code"]];subtitle.numberOfLines=0;subtitle.textColor=PCMutedColor();subtitle.font=[UIFont systemFontOfSize:14];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[title,subtitle]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=16;
    NSArray *labels=@[PCLocalized(@"允许一次"),PCLocalized(@"始终允许"),PCLocalized(@"不允许")];
    for(NSInteger i=0;i<3;i++){UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];if(@available(iOS 15.0,*)){UIButtonConfiguration *style=UIButtonConfiguration.filledButtonConfiguration;style.baseBackgroundColor=i==0?PCTextColor():UIColor.tertiarySystemBackgroundColor;style.baseForegroundColor=i==0?PCCanvasColor():PCTextColor();style.cornerStyle=UIButtonConfigurationCornerStyleCapsule;style.title=labels[i];button.configuration=style;}else{PCStyleButton(button,PCButtonFilled);button.backgroundColor=i==0?PCTextColor():UIColor.tertiarySystemBackgroundColor;button.tintColor=i==0?PCCanvasColor():PCTextColor();[button setTitleColor:button.tintColor forState:UIControlStateNormal];button.layer.cornerRadius=23;[button setTitle:labels[i] forState:UIControlStateNormal];}button.tag=i;[button.heightAnchor constraintEqualToConstant:46].active=YES;[button addTarget:self action:@selector(decide:) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:button];}
    stack.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:stack];UILayoutGuide *g=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[card.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],[card.centerXAnchor constraintEqualToAnchor:g.centerXAnchor],[card.widthAnchor constraintLessThanOrEqualToConstant:380],[card.leadingAnchor constraintGreaterThanOrEqualToAnchor:g.leadingAnchor constant:20],[card.trailingAnchor constraintLessThanOrEqualToAnchor:g.trailingAnchor constant:-20],[stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],[stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-24],[stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22],[stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22]]];
}
- (void)decide:(UIButton *)button {PCHaptic(button.tag==2?@"warning":@"success");NSString *mode=@[@"once",@"always",@"deny"][button.tag];NSDictionary *result=PCPairDecide(self.request[@"id"],mode);if(!result[@"error"]&&button.tag!=2){[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"aiScreenEnabled"];PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){s[@"screen"]=@YES;return nil;});}[self dismissViewControllerAnimated:YES completion:nil];}
@end
void PCPairPromptIfNeeded(UIViewController *presenter) {
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    while(presenter.presentedViewController)presenter=presenter.presentedViewController;
    if([presenter isKindOfClass:PCPairApprovalController.class]||[presenter isKindOfClass:UIAlertController.class]||!presenter.view.window)return;
    NSDictionary *request=PCPairPending().firstObject;if(!request)return;PCPairApprovalController *controller=[PCPairApprovalController new];controller.request=request;controller.modalPresentationStyle=UIModalPresentationOverFullScreen;controller.modalTransitionStyle=UIModalTransitionStyleCrossDissolve;[presenter presentViewController:controller animated:YES completion:nil];
}

@implementation PCRemoteConnectionsController {NSArray *_devices;}
- (void)viewDidLoad {[super viewDidLoad];self.title=PCLocalized(@"连接权限");self.view.tintColor=PCTextColor();self.tableView.backgroundColor=UIColor.systemGroupedBackgroundColor;self.tableView.rowHeight=62;}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];NSMutableDictionary *items=[NSMutableDictionary new];NSDictionary *state=PCControlState();for(NSString *device in state[@"trust"]){NSMutableDictionary *item=[state[@"trust"][device] mutableCopy];item[@"device_id"]=device;items[device]=item;}for(NSDictionary *p in state[@"peers"])if([p[@"incoming"] boolValue]&&p[@"device_id"]&&!items[p[@"device_id"]])items[p[@"device_id"]]=p;_devices=items.allValues;[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {return 2;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return section==0?3:_devices.count;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {return section==0?PCLocalized(@"本机"):PCLocalized(@"已申请的设备");}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {return section==1?PCLocalized(@"允许一次仅限本次会话；断线最多保留 10 分钟用于重连。"):nil;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if(indexPath.section==0){if(indexPath.row==0){cell.textLabel.text=PCLocalized(@"设备名称");cell.detailTextLabel.text=PCControlState()[@"name"];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}else if(indexPath.row==1){cell.textLabel.text=PCLocalized(@"配对码");cell.detailTextLabel.text=PCPairIdentity()[@"pair_code"];}else{cell.textLabel.text=PCLocalized(@"设备标识");cell.detailTextLabel.text=PCPairIdentity()[@"device_id"];cell.detailTextLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;}}
    else {NSDictionary *d=_devices[indexPath.row];cell.textLabel.text=d[@"name"];cell.detailTextLabel.text=@{@"ask":PCLocalized(@"每次询问"),@"once":PCLocalized(@"本次允许"),@"always":PCLocalized(@"始终允许"),@"deny":PCLocalized(@"不允许")}[d[@"mode"]]?:PCLocalized(@"每次询问");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.section==0){if(indexPath.row==1){PCOptionsPage *options=[[PCOptionsPage alloc] initWithStyle:UITableViewStyleInsetGrouped];options.title=PCLocalized(@"配对码");options.options=@[@{@"title":PCLocalized(@"定期更新")},@{@"title":PCLocalized(@"固定当前配对码")},@{@"title":PCLocalized(@"自定义配对码")}];__weak typeof(self) weakSelf=self;options.selectOption=^(NSInteger choice){if(choice<2){NSString *code=PCPairIdentity()[@"pair_code"];PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){s[@"pair_code_mode"]=choice==1?@"fixed":@"rotating";s[@"pair_code_fixed"]=code;s[@"pair_code_expires"]=@0;return nil;});[weakSelf.navigationController popToViewController:weakSelf animated:YES];}else{PCTextEntryPage *input=[PCTextEntryPage new];input.title=PCLocalized(@"自定义配对码");input.submitTitle=PCLocalized(@"保存");input.fieldPlaceholder=PCLocalized(@"6 位数字");input.initialText=PCPairIdentity()[@"pair_code"];input.maximumLength=6;input.validationPattern=@"[0-9]{6}";input.numeric=YES;input.submit=^(NSString *code){PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){s[@"pair_code_mode"]=@"fixed";s[@"pair_code_fixed"]=code;return nil;});[weakSelf.navigationController popToViewController:weakSelf animated:YES];};[weakSelf.navigationController pushViewController:input animated:YES];}};[self.navigationController pushViewController:options animated:YES];return;}if(indexPath.row!=0)return;PCTextEntryPage *page=[PCTextEntryPage new];page.title=PCLocalized(@"设备名称");page.fieldPlaceholder=PCLocalized(@"设备名称");page.initialText=PCControlState()[@"name"];page.submitTitle=PCLocalized(@"保存");page.maximumLength=80;__weak typeof(self) weakSelf=self;page.submit=^(NSString *name){NSString *bounded=[name substringToIndex:MIN(name.length,80)];PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){s[@"name"]=bounded;return nil;});[weakSelf.navigationController popViewControllerAnimated:YES];};[self.navigationController pushViewController:page animated:YES];return;}
    NSDictionary *d=_devices[indexPath.row];PCOptionsPage *page=[[PCOptionsPage alloc] initWithStyle:UITableViewStyleInsetGrouped];page.title=d[@"name"];page.explanation=[NSString stringWithFormat:PCLocalized(@"设备 %@"),[d[@"device_id"] substringToIndex:12]];NSArray *modes=@[@"ask",@"always",@"deny"],*titles=@[PCLocalized(@"允许一次（每次询问）"),PCLocalized(@"始终允许"),PCLocalized(@"不允许")];NSMutableArray *options=[NSMutableArray new];for(NSUInteger i=0;i<3;i++)[options addObject:@{@"title":titles[i],@"selected":@([modes[i] isEqual:d[@"mode"]])}];page.options=options;__weak typeof(self) weakSelf=self;page.selectOption=^(NSInteger selected){PCPairSetTrust(d[@"device_id"],modes[selected]);[weakSelf.navigationController popViewControllerAnimated:YES];};[self.navigationController pushViewController:page animated:YES];
}
@end
