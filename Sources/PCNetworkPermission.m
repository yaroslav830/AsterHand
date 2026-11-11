#import "PCTheme.h"
#import "PCLocalization.h"
#import "PCNetworkPermission.h"
#import "PCPlatform.h"
#import "PCRoot.h"
#import "PCSupport.h"
#include <dlfcn.h>
#include <unistd.h>

// Read only this bundle's rule. Do not unarchive or expose VPN/account objects.
NSDictionary *PCNetworkPermissionRead(void) {
    NSString *path=PCIsRootHide()?PCRealPath(@"/rootfs/var/preferences/com.apple.networkextension.plist"):@"/var/preferences/com.apple.networkextension.plist";
    NSData *data=[NSData dataWithContentsOfFile:path];
    if(!data || data.length>4*1024*1024)return @{@"error":PCLocalized(@"无法读取系统网络策略。")};
    id archive=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil];
    NSArray *objects=[archive isKindOfClass:NSDictionary.class]?archive[@"$objects"]:nil;
    CFTypeID (*uidType)(void)=dlsym(RTLD_DEFAULT,"_CFKeyedArchiverUIDGetTypeID");
    uint32_t (*uidValue)(CFTypeRef)=dlsym(RTLD_DEFAULT,"_CFKeyedArchiverUIDGetValue");
    if(![objects isKindOfClass:NSArray.class]||!uidType||!uidValue)return @{@"error":PCLocalized(@"当前系统的网络策略格式暂不支持。")};
    for(id item in objects){if(![item isKindOfClass:NSDictionary.class])continue;id identifier=item[@"SigningIdentifier"];
        if(!identifier||CFGetTypeID((__bridge CFTypeRef)identifier)!=uidType())continue;uint32_t index=uidValue((__bridge CFTypeRef)identifier);
        if(index>=objects.count||![objects[index] isEqual:@"local.pocketcodex"])continue;
        NSNumber *wifi=item[@"WiFiBehavior"],*cellular=item[@"CellularBehavior"];
        if(![wifi isKindOfClass:NSNumber.class]||![cellular isKindOfClass:NSNumber.class])break;
        return @{@"wifi":wifi,@"cellular":cellular,@"bundle":@"local.pocketcodex"};
    }
    return @{@"error":PCLocalized(@"系统尚未生成 AsterHand 的网络策略。")};
}
NSDictionary *PCNetworkPermissionApply(NSString *mode) {
    if(geteuid()!=0)return @{@"error":PCLocalized(@"需要 Root 服务执行网络授权。")};
    if(![mode isKindOfClass:NSString.class]||![@[@"wifi",@"cellular",@"all"] containsObject:mode])return @{@"error":PCLocalized(@"网络授权选项无效。")};
    static void *library; if(!library)library=dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony",RTLD_NOW|RTLD_LOCAL);
    void *(*create)(CFAllocatorRef,void *,void *)=library?dlsym(library,"_CTServerConnectionCreate"):NULL;
    int64_t (*set)(void *,CFStringRef,CFDictionaryRef)=library?dlsym(library,"_CTServerConnectionSetCellularUsagePolicy"):NULL;
    if(!create||!set)return @{@"error":PCLocalized(@"当前系统不提供网络授权接口。")};
    BOOL wifi=![mode isEqual:@"cellular"],cellular=![mode isEqual:@"wifi"];
    NSDictionary *before=PCNetworkPermissionRead();
    NSMutableDictionary *policy=[NSMutableDictionary new];
    if(wifi)policy[@"kCTWiFiDataUsagePolicy"]=@"kCTCellularDataUsagePolicyAlwaysAllow";
    if(cellular)policy[@"kCTCellularDataUsagePolicy"]=@"kCTCellularDataUsagePolicyAlwaysAllow";
    void *connection=create(kCFAllocatorDefault,NULL,NULL);if(!connection)return @{@"error":PCLocalized(@"无法连接系统网络授权服务。")};
    int64_t code=set(connection,CFSTR("local.pocketcodex"),(__bridge CFDictionaryRef)policy);CFRelease(connection);
    NSDictionary *after=nil;
    for(NSUInteger attempt=0;attempt<20;attempt++){after=PCNetworkPermissionRead();BOOL wifiOK=wifi?[after[@"wifi"] integerValue]==2:(!before[@"wifi"]||[after[@"wifi"] isEqual:before[@"wifi"]]);BOOL cellularOK=cellular?[after[@"cellular"] integerValue]==2:(!before[@"cellular"]||[after[@"cellular"] isEqual:before[@"cellular"]]);if(wifiOK&&cellularOK)return @{@"verified":@YES,@"wifi":after[@"wifi"]?:NSNull.null,@"cellular":after[@"cellular"]?:NSNull.null,@"before":before,@"system_result":@(code)};usleep(200000);}
    return @{@"error":PCLocalized(@"系统未确认网络授权，未显示为成功。"),@"system_result":@(code),@"observed":after?:@{}};
}

@implementation PCNetworkPermissionController {NSDictionary *_policy;NSString *_feedback;BOOL _busy;}
- (void)viewDidLoad {[super viewDidLoad];self.title=PCLocalized(@"网络授权");self.view.tintColor=PCTextColor();self.tableView.backgroundColor=PCCanvasColor();self.tableView.rowHeight=60;[self refresh];}
- (void)refresh {dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSDictionary *p=PCSendRootRequest(@{@"action":@"network_status"},6);dispatch_async(dispatch_get_main_queue(),^{self->_policy=p;[self.tableView reloadData];});});}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 2;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?2:3;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return section==0?PCLocalized(@"当前权限"):PCLocalized(@"Root 强制授权");}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{return section==0?(_feedback?:_policy[@"error"]):PCLocalized(@"仅调整 AsterHand。单独授权保留另一项当前状态，不会开启 AI 的长期 Root 开关。本地网络和远控配对需分别允许。");}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if(path.section==0){cell.textLabel.text=path.row==0?@"Wi-Fi":PCLocalized(@"蜂窝数据");NSNumber *value=_policy[path.row==0?@"wifi":@"cellular"];cell.detailTextLabel.text=value.integerValue==2?PCLocalized(@"已允许"):value.integerValue==1?PCLocalized(@"未允许"):PCLocalized(@"待检测");cell.selectionStyle=UITableViewCellSelectionStyleNone;}
    else{cell.textLabel.text=@[PCLocalized(@"授权 Wi-Fi"),PCLocalized(@"授权蜂窝数据"),PCLocalized(@"全部允许")][path.row];cell.imageView.image=[UIImage systemImageNamed:@[@"wifi",@"antenna.radiowaves.left.and.right",@"network"][path.row]];cell.textLabel.enabled=!_busy;cell.userInteractionEnabled=!_busy;}
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {[tableView deselectRowAtIndexPath:path animated:YES];if(path.section!=1||_busy)return;_busy=YES;_feedback=PCLocalized(@"正在通过 Root 服务授权…");[tableView reloadData];PCHaptic(@"impact");NSString *mode=@[@"wifi",@"cellular",@"all"][path.row];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSDictionary *result=PCSendRootRequest(@{@"action":@"network_grant",@"mode":mode},12);dispatch_async(dispatch_get_main_queue(),^{self->_busy=NO;self->_feedback=[result[@"verified"] boolValue]?PCLocalized(@"已授权，系统策略回读一致。"):result[@"error"]?:PCLocalized(@"未能完成授权。");PCHaptic([result[@"verified"] boolValue]?@"success":@"error");[self refresh];[self.tableView reloadData];});});
}
@end
