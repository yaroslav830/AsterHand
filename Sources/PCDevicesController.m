#import "PCTheme.h"
#import "PCLocalization.h"
#import "PCKeyboardCompat.h"
#import "PCControl.h"
#import "PCSupport.h"
#import "PCTerminal.h"
#import "PCRoot.h"
#import "PCRemote.h"
#import "PCPairing.h"
#import "PCPages.h"
#import "PCDiscovery.h"

static void Notice(UIViewController *c,NSString *text) {UIAlertController *a=[UIAlertController alertControllerWithTitle:@"AsterHand" message:PCLocalized(text) preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"好") style:UIAlertActionStyleCancel handler:nil]];[c presentViewController:a animated:YES completion:nil];}
static UIButton *ControlButton(NSString *name,id target,SEL action) {UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:name forState:UIControlStateNormal];[b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];return b;}
static void FitStack(UIViewController *c,UIStackView *stack,BOOL keyboard) {stack.axis=UILayoutConstraintAxisVertical;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=NO;[c.view addSubview:stack];UILayoutGuide *g=c.view.safeAreaLayoutGuide;[NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:g.topAnchor constant:10],[stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],[stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],[stack.bottomAnchor constraintEqualToAnchor:keyboard?PCKeyboardTopAnchor(c.view):g.bottomAnchor constant:-8]]];}

@interface PCCommandController : UIViewController
@property(copy) NSString *peer;
@property(copy) NSString *deviceName;
@end
@implementation PCCommandController {
    UITextView *_output;UITextField *_input;UILabel *_status;NSTimer *_timer;NSString *_session;NSUInteger _offset;BOOL _busy,_closed,_opening;dispatch_queue_t _queue;
}
- (NSDictionary *)call:(NSString *)method args:(NSDictionary *)args {return self.peer?PCControlRequest(self.peer,method,args,nil):PCControlExecute(method,args,@"local-ui");}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=[NSString stringWithFormat:PCLocalized(@"终端 · %@"),self.deviceName?:PCLocalized(@"本机")];self.view.backgroundColor=PCCanvasColor();_queue=dispatch_queue_create("agentgo.terminal.ui",DISPATCH_QUEUE_SERIAL);
    _status=[UILabel new];_status.text=PCLocalized(@"正在打开命令会话…");_status.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    _output=[UITextView new];_output.editable=NO;_output.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];_output.backgroundColor=PCSoftColor();
    _input=[UITextField new];_input.borderStyle=UITextBorderStyleRoundedRect;_input.placeholder=PCLocalized(@"输入命令（保留当前目录和变量）");_input.autocorrectionType=UITextAutocorrectionTypeNo;_input.autocapitalizationType=UITextAutocapitalizationTypeNone;
    UIStackView *buttons=[[UIStackView alloc] initWithArrangedSubviews:@[ControlButton(PCLocalized(@"发送"),self,@selector(send)),ControlButton(PCLocalized(@"中断"),self,@selector(interrupt)),ControlButton(PCLocalized(@"重开"),self,@selector(reopen)),ControlButton(PCLocalized(@"清屏"),self,@selector(clear))]];buttons.distribution=UIStackViewDistributionFillEqually;
    FitStack(self,[[UIStackView alloc] initWithArrangedSubviews:@[_status,_output,_input,buttons]],YES);[_input.heightAnchor constraintEqualToConstant:40].active=YES;
    [self reopen];
}
- (void)reopen {if(_opening||_closed)return;_opening=YES;NSString *old=_session;_session=nil;_offset=0;[_timer invalidate];_timer=nil;_status.text=PCLocalized(@"正在打开命令会话…");dispatch_async(_queue,^{if(old)[self call:@"terminal.close" args:@{@"session":old}];NSDictionary *r=[self call:@"terminal.open" args:@{}];NSString *created=r[@"session"];dispatch_async(dispatch_get_main_queue(),^{self->_opening=NO;if(self->_closed){if(created)dispatch_async(self->_queue,^{[self call:@"terminal.close" args:@{@"session":created}];});return;}self->_session=created;self->_status.text=PCLocalized(r[@"error"])?:PCLocalized(@"命令会话 · 中断后可重开");if(created)self->_timer=[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(poll) userInfo:nil repeats:YES];});});}
- (void)poll {if(_busy||!_session||_closed)return;_busy=YES;NSUInteger offset=_offset;NSString *session=_session;dispatch_async(_queue,^{NSDictionary *r=[self call:@"terminal.read" args:@{@"session":session,@"offset":@(offset)}];dispatch_async(dispatch_get_main_queue(),^{self->_busy=NO;if(self->_closed||![self->_session isEqual:session])return;if(r[@"error"]){self->_status.text=PCLocalized(r[@"error"]);return;}self->_offset=[r[@"next_offset"] unsignedIntegerValue];NSString *text=r[@"output"]?:@"";if(text.length){NSString *combined=[self->_output.text stringByAppendingString:text];if(combined.length>131072)combined=[combined substringFromIndex:combined.length-131072];self->_output.text=combined;[self->_output scrollRangeToVisible:NSMakeRange(combined.length,0)];}if([r[@"ended"] boolValue])self->_status.text=PCLocalized(@"会话已结束");});});}
- (void)send {if(!_session||!_input.text.length)return;NSString *text=[_input.text stringByAppendingString:@"\n"];_input.text=@"";dispatch_async(_queue,^{NSDictionary *r=[self call:@"terminal.write" args:@{@"session":self->_session,@"text":text}];if(r[@"error"])dispatch_async(dispatch_get_main_queue(),^{self->_status.text=PCLocalized(r[@"error"]);});});}
- (void)interrupt {NSString *session=_session;if(session)dispatch_async(_queue,^{NSDictionary *r=[self call:@"terminal.interrupt" args:@{@"session":session}];dispatch_async(dispatch_get_main_queue(),^{if([self->_session isEqual:session]){self->_status.text=PCLocalized(r[@"error"])?:PCLocalized(@"已中断 · 点重开开始新会话");if([r[@"ended"] boolValue]){self->_session=nil;[self->_timer invalidate];self->_timer=nil;}}});});}
- (void)clear {_output.text=@"";}
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];if(self.isMovingFromParentViewController||self.navigationController.isBeingDismissed){_closed=YES;[_timer invalidate];_timer=nil;if(_session)dispatch_async(_queue,^{[self call:@"terminal.close" args:@{@"session":self->_session}];});}}
@end

@interface PCDeviceScreenController : UIViewController
@property(copy) NSString *peer;
@property(copy) NSString *deviceName;
@end
@implementation PCDeviceScreenController {
    UIImageView *_image;UILabel *_status;CGPoint _start;dispatch_queue_t _queue;PCControlStream *_stream;NSUInteger _frames;NSTimeInterval _frameStart;
}
- (void)viewDidLoad {[super viewDidLoad];self.title=self.deviceName;self.view.backgroundColor=PCCanvasColor();_queue=dispatch_queue_create("agentgo.screen.ui",DISPATCH_QUEUE_SERIAL);_status=[UILabel new];_status.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];_status.numberOfLines=2;_status.text=PCLocalized(@"连接设备…");_image=[UIImageView new];_image.contentMode=UIViewContentModeScaleAspectFit;_image.backgroundColor=PCSoftColor();_image.userInteractionEnabled=YES;
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];[tap requireGestureRecognizerToFail:pan];[_image addGestureRecognizer:tap];[_image addGestureRecognizer:pan];
    UIStackView *buttons=[[UIStackView alloc] initWithArrangedSubviews:@[ControlButton(PCLocalized(@"主屏幕"),self,@selector(home)),ControlButton(PCLocalized(@"输入文字"),self,@selector(type)),ControlButton(PCLocalized(@"刷新"),self,@selector(capture))]];buttons.distribution=UIStackViewDistributionFillEqually;FitStack(self,[[UIStackView alloc] initWithArrangedSubviews:@[_status,_image,buttons]],NO);
}
- (void)viewDidAppear:(BOOL)animated {[super viewDidAppear:animated];[self capture];}
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];[_stream stop];_stream=nil;}
- (void)capture {
    [_stream stop];_stream=[PCControlStream new];_frames=0;_frameStart=NSProcessInfo.processInfo.systemUptime;
    __weak PCDeviceScreenController *weakSelf=self;
    _stream.frame=^(NSDictionary *r){PCDeviceScreenController *c=weakSelf;if(!c)return;NSData *data=[r[@"jpeg"] isKindOfClass:NSData.class]?r[@"jpeg"]:[[NSData alloc] initWithBase64EncodedString:r[@"image_base64"] options:0];UIImage *image=[UIImage imageWithData:data];if(image)c->_image.image=image;c->_frames++;NSTimeInterval elapsed=NSProcessInfo.processInfo.systemUptime-c->_frameStart;if(elapsed>=1){c->_status.text=PCLocalized(@"实时画面 · 点击或拖动操控");c->_frames=0;c->_frameStart=NSProcessInfo.processInfo.systemUptime;}};
    _stream.failed=^(NSString *message){PCDeviceScreenController *c=weakSelf;if(c)c->_status.text=PCLocalized(message);};[_stream start:self.peer];
}
- (BOOL)point:(CGPoint)p normalized:(CGPoint *)out {CGSize image=_image.image.size,b=_image.bounds.size;if(!image.width||!image.height)return NO;CGFloat scale=MIN(b.width/image.width,b.height/image.height);CGRect fit=CGRectMake((b.width-image.width*scale)/2,(b.height-image.height*scale)/2,image.width*scale,image.height*scale);if(!CGRectContainsPoint(fit,p))return NO;*out=CGPointMake((p.x-fit.origin.x)/fit.size.width,(p.y-fit.origin.y)/fit.size.height);return YES;}
- (void)action:(NSString *)tool args:(NSDictionary *)args {dispatch_async(_queue,^{NSDictionary *r=PCControlRequest(self.peer,@"execute",@{@"tool":tool,@"arguments":args},nil);dispatch_async(dispatch_get_main_queue(),^{if(r[@"error"])self->_status.text=PCLocalized(r[@"error"]);else self->_status.text=PCLocalized(@"操作已发送");});});}
- (void)tap:(UITapGestureRecognizer *)g {CGPoint p;if([self point:[g locationInView:_image] normalized:&p])[self action:@"screen_tap" args:@{@"x":@(p.x),@"y":@(p.y)}];}
- (void)pan:(UIPanGestureRecognizer *)g {if(g.state==UIGestureRecognizerStateBegan)_start=[g locationInView:_image];if(g.state==UIGestureRecognizerStateEnded){CGPoint a,b;if([self point:_start normalized:&a]&&[self point:[g locationInView:_image] normalized:&b])[self action:@"screen_swipe" args:@{@"x":@(a.x),@"y":@(a.y),@"x2":@(b.x),@"y2":@(b.y),@"duration":@0.4}];}}
- (void)home {[self action:@"screen_home" args:@{}];}
- (void)type {UIAlertController *a=[UIAlertController alertControllerWithTitle:PCLocalized(@"向目标设备输入文字") message:self.deviceName preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:nil];[a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"取消") style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:PCLocalized(@"发送") style:UIAlertActionStyleDefault handler:^(UIAlertAction *v){[self action:@"screen_type" args:@{@"text":a.textFields.firstObject.text?:@""}];}]];[self presentViewController:a animated:YES completion:nil];}
@end

@implementation PCDevicesController {
    NSArray *_peers,*_found;NSString *_status,*_request;NSTimer *_poll;BOOL _busy;
}
- (void)viewDidLoad {[super viewDidLoad];self.title=PCLocalized(@"远程连接");self.view.tintColor=PCTextColor();self.tableView.backgroundColor=PCCanvasColor();self.tableView.rowHeight=58;_found=@[];}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self reloadPeers];}
- (void)reloadPeers {NSMutableArray *peers=[NSMutableArray new];for(NSDictionary *p in PCControlState()[@"peers"])if(![p[@"incoming"] boolValue])[peers addObject:p];_peers=peers;[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return section==0?6:section==1?_found.count:_peers.count;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {return section==0?PCLocalized(@"本机"):section==1?PCLocalized(@"附近设备"):PCLocalized(@"已连接");}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {return section==0?PCLocalized(@"后台常驻控制远控和连接申请；AI 任务运行时始终常驻。"):section==1?_status:nil;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    if(indexPath.section==0){cell.textLabel.text=@[PCLocalized(@"允许被控"),PCLocalized(@"允许远程屏幕操作"),PCLocalized(@"后台常驻"),PCLocalized(@"搜索局域网设备"),PCLocalized(@"连接权限与设备名称"),PCLocalized(@"本地终端")][indexPath.row];if(indexPath.row<=2){UISwitch *toggle=[UISwitch new];if(indexPath.row==0){toggle.on=[PCControlState()[@"enabled"] boolValue];[toggle addTarget:self action:@selector(enable:) forControlEvents:UIControlEventValueChanged];}else if(indexPath.row==1){toggle.on=[PCControlState()[@"screen"] boolValue];toggle.accessibilityLabel=PCLocalized(@"允许远程屏幕操作");[toggle addTarget:self action:@selector(remoteScreen:) forControlEvents:UIControlEventValueChanged];}else{toggle.on=![PCControlState()[@"background"] isEqual:@NO];[toggle addTarget:self action:@selector(background:) forControlEvents:UIControlEventValueChanged];}cell.accessoryView=toggle;cell.accessoryType=UITableViewCellAccessoryNone;}}
    else {NSDictionary *p=indexPath.section==1?_found[indexPath.row]:_peers[indexPath.row];cell.textLabel.text=p[@"name"];NSString *identifier=p[@"device_id"];cell.detailTextLabel.text=identifier.length>=12?[identifier substringToIndex:12]:PCLocalized(@"兼容配对");}
    return cell;
}
- (void)background:(UISwitch *)toggle {PCHaptic(@"select");PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){s[@"background"]=@(toggle.on);return nil;});}
- (void)enable:(UISwitch *)toggle {PCHaptic(@"select");PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){s[@"enabled"]=@(toggle.on);return nil;});}
- (void)remoteScreen:(UISwitch *)toggle {PCHaptic(@"select");NSDictionary *result=PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){s[@"screen"]=@(toggle.on);return nil;});if(result[@"error"]){toggle.on=[PCControlState()[@"screen"] boolValue];Notice(self,result[@"error"]);}}
- (void)terminal:(NSDictionary *)peer {PCCommandController *c=[PCCommandController new];c.peer=peer[@"id"];c.deviceName=peer?peer[@"name"]:PCLocalized(@"本机");[self.navigationController pushViewController:c animated:YES];}
- (void)search {if(_busy)return;PCHaptic(@"impact");_busy=YES;_found=@[];_status=PCLocalized(@"正在搜索…");[self.tableView reloadData];__weak typeof(self) weakSelf=self;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{PCDiscoveryRun(^(NSArray *devices,NSString *status){dispatch_async(dispatch_get_main_queue(),^{PCDevicesController *controller=weakSelf;if(!controller)return;controller->_found=devices;controller->_status=PCLocalized(status);[controller.tableView reloadData];});});dispatch_async(dispatch_get_main_queue(),^{PCDevicesController *controller=weakSelf;if(controller)controller->_busy=NO;});});}
- (void)pollRequest {if(_busy||!_request)return;_busy=YES;NSString *request=_request;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSDictionary *r=PCPairPoll(request);dispatch_async(dispatch_get_main_queue(),^{self->_busy=NO;[self received:r];});});}
- (void)received:(NSDictionary *)r {if(r[@"error"]||![r[@"status"] isEqual:@"pending"]){[_poll invalidate];_poll=nil;_request=nil;_status=PCLocalized(r[@"error"])?:[r[@"status"] isEqual:@"accepted"]?PCLocalized(@"已连接"):PCLocalized(@"对方未允许连接");PCHaptic([r[@"status"] isEqual:@"accepted"]?@"connect":@"warning");[self reloadPeers];}else{_request=r[@"id"];_status=[NSString stringWithFormat:PCLocalized(@"等待对方允许 · 核对码 %@"),r[@"code"]];[self.tableView reloadData];if(!_poll)_poll=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(pollRequest) userInfo:nil repeats:YES];}}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.section==0){if(indexPath.row==3)[self search];else if(indexPath.row==4)[self.navigationController pushViewController:[[PCRemoteConnectionsController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];else if(indexPath.row==5)[self terminal:nil];return;}
    if(indexPath.section==1){if(_busy||_request)return;_busy=YES;NSDictionary *remote=_found[indexPath.row];_status=PCLocalized(@"正在申请…");[tableView reloadData];dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSDictionary *r=PCPairBegin(remote);dispatch_async(dispatch_get_main_queue(),^{self->_busy=NO;[self received:r];});});return;}
    NSDictionary *peer=_peers[indexPath.row];PCOptionsPage *page=[[PCOptionsPage alloc] initWithStyle:UITableViewStyleInsetGrouped];page.title=peer[@"name"];page.options=@[@{@"title":PCLocalized(@"屏幕"),@"icon":@"display"},@{@"title":PCLocalized(@"终端"),@"icon":@"terminal"},@{@"title":PCLocalized(@"断开连接"),@"icon":@"xmark.circle"}];__weak typeof(self) weakSelf=self;page.selectOption=^(NSInteger option){if(option==0){PCDeviceScreenController *c=[PCDeviceScreenController new];c.peer=peer[@"id"];c.deviceName=peer[@"name"];[weakSelf.navigationController pushViewController:c animated:YES];}else if(option==1)[weakSelf terminal:peer];else{dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{PCControlRelease(peer[@"id"]);dispatch_async(dispatch_get_main_queue(),^{[weakSelf.navigationController popToViewController:weakSelf animated:YES];});});}};[self.navigationController pushViewController:page animated:YES];
}
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];if(self.isMovingFromParentViewController||self.navigationController.isBeingDismissed){[_poll invalidate];_poll=nil;}}
@end
