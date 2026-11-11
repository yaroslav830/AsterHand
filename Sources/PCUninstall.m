#import "PCLocalization.h"
#import "PCUninstall.h"
#import "PCProjectStore.h"
#import "PCPlatform.h"
#import "PCPages.h"
#import "PCHaptics.h"

@interface PCUninstallController ()
@property(nonatomic,strong) UISwitch *erase;
@property(nonatomic,strong) NSArray *projects;
@property(nonatomic,copy) NSString *message;
@end
@implementation PCUninstallController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=PCLocalized(@"卸载 AsterHand");self.view.tintColor=UIColor.labelColor;self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=62;
    self.projects=[PCProjectStore new].projects;self.erase=[UISwitch new];self.erase.onTintColor=UIColor.systemRedColor;[self.erase addTarget:self action:@selector(changed) forControlEvents:UIControlEventValueChanged];
}
- (void)changed {PCHaptic(@"select");[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return section==1?self.projects.count:1;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {return @[PCLocalized(@"数据处理"),PCLocalized(@"项目工作目录"),PCLocalized(@"卸载")][section];}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if(section==0)return self.erase.on?PCLocalized(@"删除全部项目、对话记录及 Documents 下的项目工作目录。外部目录和系统目录不会自动删除。"):PCLocalized(@"保留项目、对话和工作文件。卸载仍会结束任务、关闭悬浮窗，并清理登录、配对、缓存和后台服务。");
    if(section==2)return self.message?:PCLocalized(@"打开 Sileo 后，在“软件包”中找到 AsterHand，选择修改 → 卸载并确认。升级不会清理你的数据。");
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;
    if(index.section==0){cell.textLabel.text=PCLocalized(@"同时删除所有项目和文件");cell.accessoryView=self.erase;cell.selectionStyle=UITableViewCellSelectionStyleNone;}
    else if(index.section==1){NSDictionary *project=self.projects[index.row];cell.textLabel.text=project[@"name"]?:PCLocalized(@"项目");cell.detailTextLabel.text=project[@"workspace"];cell.selectionStyle=UITableViewCellSelectionStyleNone;}
    else{cell.textLabel.text=PCLocalized(@"前往 Sileo 卸载");cell.textLabel.textColor=UIColor.systemRedColor;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES];if(index.section!=2)return;PCHaptic(@"warning");
    PCConfirmPage *confirm=[PCConfirmPage new];confirm.title=PCLocalized(@"确认卸载范围");confirm.actionTitle=PCLocalized(@"前往 Sileo");confirm.message=self.erase.on?PCLocalized(@"卸载时删除所有项目、对话记录及 Documents 下的项目文件，同时停止后台服务与悬浮窗。外部工作目录保留。"):PCLocalized(@"卸载时保留项目与文件；清理登录、配对、缓存、悬浮窗和后台服务。");
    __weak typeof(self) weakSelf=self;BOOL erase=self.erase.on;
    confirm.confirm=^{
        NSString *directory=PCRealPath(@"/var/mobile/Library/PocketAgentControl");NSError *error=nil;
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error];
        NSDictionary *choice=@{@"created":@(NSDate.date.timeIntervalSince1970),@"delete_projects":@(erase),@"delete_files":@(erase)};
        NSData *data=[NSJSONSerialization dataWithJSONObject:choice options:0 error:&error];
        if(![data writeToFile:[directory stringByAppendingPathComponent:@"uninstall-choice.json"] options:NSDataWritingAtomic error:&error]){weakSelf.message=error.localizedDescription;[weakSelf.tableView reloadData];return;}
        // Local .deb installs may have no repository depiction. A package URL
        // can show a source-not-found alert; opening Sileo itself also works for them.
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"sileo://"] options:@{} completionHandler:^(BOOL success){if(!success){weakSelf.message=PCLocalized(@"无法打开 Sileo，请在软件包管理器中找到 AsterHand 并移除；所选清理范围已保存，有效期 24 小时。");[weakSelf.tableView reloadData];}}];
    };
    [self.navigationController pushViewController:confirm animated:YES];
}
@end
