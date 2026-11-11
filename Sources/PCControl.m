#import "PCControl.h"
#import "PCPlatform.h"
#import "PCSupport.h"
#import "PCTools.h"
#import "PCTerminal.h"
#import "PCRoot.h"
#import "PCScreen.h"
#import "PCPairing.h"
#import "PCOverlay.h"
#import "PCAppRPC.h"
#import "PCDiscovery.h"
#import "PCPersistentAgent.h"
#import <Security/Security.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <ifaddrs.h>
#include <netinet/tcp.h>
#include <pthread.h>

static NSString *Directory(void) {return PCRealPath(@"/var/mobile/Library/AgentGoControl");}
static NSString *StatePath(void) {return [Directory() stringByAppendingPathComponent:@"control.json"];}
static NSMutableSet *Owners(void) {static NSMutableSet *set;static dispatch_once_t once;dispatch_once(&once,^{set=[NSMutableSet new];});return set;}
static void Presence(NSString *owner,NSString *actor,BOOL active,NSDictionary *options) {
    if(!owner)return;@synchronized(Owners()){
        NSString *file=[Directory() stringByAppendingPathComponent:@"remote-presence.json"];NSData *old=[NSData dataWithContentsOfFile:file];NSDictionary *previous=old?[NSJSONSerialization JSONObjectWithData:old options:0 error:nil]:nil;NSMutableDictionary *connections=[previous[@"connections"] mutableCopy]?:[NSMutableDictionary new];double now=NSDate.date.timeIntervalSince1970;
        for(NSString *key in connections.allKeys){NSDictionary *item=connections[key];if(MAX([item[@"connected_until"] doubleValue],MAX([item[@"manual_until"] doubleValue],[item[@"ai_until"] doubleValue]))<now-10)[connections removeObjectForKey:key];}
        NSMutableDictionary *entry=[connections[owner] mutableCopy]?:[NSMutableDictionary new];NSString *key=[actor isEqual:@"ai"]?@"ai_until":[actor isEqual:@"manual"]?@"manual_until":@"connected_until";
        double lease=MIN(120,MAX(6,[options[@"lease_seconds"] doubleValue]));NSString *since=[key stringByReplacingOccurrencesOfString:@"_until" withString:@"_since"];if(active&&([entry[key] doubleValue]<=now||!entry[since]))entry[since]=@(now);if(active&&([entry[@"connected_until"] doubleValue]<=now||!entry[@"connected_since"]))entry[@"connected_since"]=@(now);entry[key]=active?@(MAX(now+lease,[entry[key] doubleValue])):@0;if(!active)[entry removeObjectForKey:since];if(active)entry[@"connected_until"]=@(MAX(now+lease,[entry[@"connected_until"] doubleValue]));
        if([actor isEqual:@"ai"]&&[options[@"latest_reply"] isKindOfClass:NSString.class]){NSString *reply=options[@"latest_reply"];entry[@"latest_reply"]=reply.length>500?[reply substringFromIndex:reply.length-500]:reply;}if(!active&&[actor isEqual:@"ai"])[entry removeObjectForKey:@"latest_reply"];
        connections[owner]=entry;NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"connections":connections} options:0 error:nil];if([data writeToFile:file options:NSDataWritingAtomic error:nil])chmod(file.fileSystemRepresentation,0600);
    }
}
NSDictionary *PCControlReadStateFile(NSString *path,NSError **error) {
    struct stat item;if(lstat(path.fileSystemRepresentation,&item)!=0&&errno==ENOENT)return @{@"enabled":@NO,@"name":@"AsterHand iPhone",@"peers":@[]};
    NSError *failure=nil;NSData *data=[NSData dataWithContentsOfFile:path options:0 error:&failure];
    NSDictionary *s=data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&failure]:nil;
    if(![s isKindOfClass:NSDictionary.class]){if(error)*error=failure?:PCError(@"设备设置损坏，已保留原文件，未重置身份。");return nil;}
    if([s isKindOfClass:NSDictionary.class]){NSString *name=s[@"name"];if([@[@"AgentGo iPhone",@"AgentGo iPhone14Pro"] containsObject:name?:@""]){NSMutableDictionary *renamed=[s mutableCopy];renamed[@"name"]=[@"AsterHand" stringByAppendingString:[name substringFromIndex:7]];return renamed;}return s;}
    return nil;
}
NSDictionary *PCControlState(void) {
    NSError *error=nil;NSDictionary *state=PCControlReadStateFile(StatePath(),&error);
    return state?:@{@"enabled":@NO,@"name":@"AsterHand iPhone",@"peers":@[],@"error":@"无法读取设备设置；已保留原身份和配对文件。"};
}
BOOL PCControlAvailable(void) {NSDictionary *state=PCControlState();if(![state[@"background"] isEqual:@NO])return YES;NSData *data=[NSData dataWithContentsOfFile:PCRealPath(@"/var/mobile/Library/AgentGoTasks/foreground.json")];NSDictionary *foreground=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;return [foreground[@"active"] boolValue]&&NSDate.date.timeIntervalSince1970-[foreground[@"updated"] doubleValue]<5;}
NSDictionary *PCControlUpdate(NSDictionary *(^change)(NSMutableDictionary *state)) {
    [NSFileManager.defaultManager createDirectoryAtPath:Directory() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSString *lock=[Directory() stringByAppendingPathComponent:@"lock"];int fd=open(lock.fileSystemRepresentation,O_RDWR|O_CREAT|O_CLOEXEC,0600);if(fd<0)return @{@"error":@"无法打开设备设置"};
    if(flock(fd,LOCK_EX)!=0){close(fd);return @{@"error":@"无法锁定设备设置，未写入。"};}
    NSError *readError=nil;NSMutableDictionary *state=[PCControlReadStateFile(StatePath(),&readError) mutableCopy];
    if(!state){flock(fd,LOCK_UN);close(fd);return @{@"error":@"无法读取设备设置；已保留原身份和配对文件，未覆盖。"};}
    NSDictionary *result=change(state);
    NSData *data=[NSJSONSerialization dataWithJSONObject:state options:0 error:nil];BOOL ok=data&&[data writeToFile:StatePath() options:NSDataWritingAtomic error:nil];if(ok)chmod(StatePath().fileSystemRepresentation,0600);flock(fd,LOCK_UN);close(fd);
    return ok?(result?:@{@"ok":@YES}):@{@"error":@"无法保存设备设置"};
}
NSArray *PCControlAddresses(void) {
    NSMutableArray *out=[NSMutableArray new];struct ifaddrs *list=NULL;if(getifaddrs(&list)==0){for(struct ifaddrs *p=list;p;p=p->ifa_next){if(!p->ifa_addr||p->ifa_addr->sa_family!=AF_INET||strcmp(p->ifa_name,"en0"))continue;char address[INET_ADDRSTRLEN];if(inet_ntop(AF_INET,&((struct sockaddr_in *)p->ifa_addr)->sin_addr,address,sizeof(address)))[out addObject:@(address)];}freeifaddrs(list);}return out;
}
NSString *PCControlInvitation(NSString *host) {
    if(![PCControlAddresses() containsObject:host]&&![host isEqual:@"127.0.0.1"])return nil;
    uint8_t random[32];if(SecRandomCopyBytes(kSecRandomDefault,32,random))return nil;NSMutableString *secret=[NSMutableString new];for(int i=0;i<32;i++)[secret appendFormat:@"%02x",random[i]];
    NSString *identifier=NSUUID.UUID.UUIDString.lowercaseString;
    NSDictionary *result=PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableArray *peers=[s[@"peers"] mutableCopy]?:[NSMutableArray new];if(peers.count>=32)return @{@"error":@"最多配对 32 台设备"};[peers addObject:@{@"id":identifier,@"key":secret,@"name":@"等待配对",@"host":@"",@"port":@18769}];s[@"peers"]=peers;s[@"enabled"]=@YES;return @{@"ok":@YES};});if(result[@"error"])return nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"v":@1,@"pair":identifier,@"key":secret,@"host":host,@"port":@18769,@"name":PCControlState()[@"name"]} options:0 error:nil];
    NSString *encoded=[[[data base64EncodedStringWithOptions:0] stringByReplacingOccurrencesOfString:@"+" withString:@"-"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [@"agentgo://pair/" stringByAppendingString:[encoded stringByReplacingOccurrencesOfString:@"=" withString:@""]];
}
static NSDictionary *Peer(NSString *identifier) {for(NSDictionary *p in PCControlState()[@"peers"])if([p[@"id"] isEqual:identifier]||([p[@"device_id"] isEqual:identifier]&&![p[@"incoming"] boolValue])){if([p[@"incoming"] boolValue]&&[p[@"mode"] isEqual:@"once"]&&[p[@"expires_at"] doubleValue]<NSDate.date.timeIntervalSince1970)return nil;return p;}return nil;}
static void TouchPeer(NSString *identifier) {NSDictionary *p=Peer(identifier);if(p)Presence(identifier,@"connected",YES,nil);if(![p[@"incoming"] boolValue]||![p[@"mode"] isEqual:@"once"]||[p[@"expires_at"] doubleValue]>NSDate.date.timeIntervalSince1970+540)return;PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableArray *peers=[s[@"peers"] mutableCopy];for(NSUInteger i=0;i<peers.count;i++){NSMutableDictionary *p=[peers[i] mutableCopy];if([p[@"id"] isEqual:identifier]){p[@"expires_at"]=@(NSDate.date.timeIntervalSince1970+600);peers[i]=p;}}s[@"peers"]=peers;return nil;});}
NSDictionary *PCControlRequest(NSString *identifier, NSString *method, NSDictionary *args, BOOL (^cancel)(void)) {
    NSDictionary *peer=Peer(identifier);NSString *host=peer[@"host"];if(![host isKindOfClass:NSString.class]||!host.length)return @{@"error":@"设备尚未完成配对"};
    identifier=peer[@"id"];
    NSString *nonce=NSUUID.UUID.UUIDString.lowercaseString;NSDictionary *payload=@{@"id":nonce,@"ts":@(NSDate.date.timeIntervalSince1970),@"method":method,@"args":args?:@{}};
    NSDictionary *packet=PCControlSeal(identifier,peer[@"key"],payload,@"req");NSData *body=packet?[NSJSONSerialization dataWithJSONObject:packet options:0 error:nil]:nil;if(!body)return @{@"error":@"请求过大或配对密钥无效"};
    NSURLComponents *url=[NSURLComponents new];url.scheme=@"http";url.host=host;url.port=peer[@"port"];url.path=@"/rpc";if(!url.URL)return @{@"error":@"设备地址无效"};
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:130];request.HTTPMethod=@"POST";request.HTTPBody=body;[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    dispatch_semaphore_t done=dispatch_semaphore_create(0);__block NSData *reply;__block NSError *error;__block NSInteger status;
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.connectionProxyDictionary=@{};config.HTTPShouldSetCookies=NO;config.HTTPMaximumConnectionsPerHost=2;config.timeoutIntervalForResource=135;
    NSURLSession *session=[NSURLSession sessionWithConfiguration:config];NSURLSessionDataTask *task=[session dataTaskWithRequest:request completionHandler:^(NSData *d,NSURLResponse *r,NSError *e){reply=d;error=e;status=[(NSHTTPURLResponse *)r statusCode];dispatch_semaphore_signal(done);}];[task resume];
    while(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))!=0)if(cancel&&cancel()){[task cancel];[session invalidateAndCancel];return @{@"error":@"任务已停止；远端已执行的操作不会撤销"};}
    [session finishTasksAndInvalidate];if(error||status!=200||reply.length>2*1024*1024)return @{@"error":error.localizedDescription?:@"对方拒绝连接，请检查设备开关和配对"};
    NSDictionary *response=[NSJSONSerialization JSONObjectWithData:reply options:0 error:nil];NSDictionary *opened=PCControlOpen(response,peer[@"key"],@"res");
    if(![response[@"pair"] isEqual:identifier]||![opened[@"id"] isEqual:nonce]||![opened[@"result"] isKindOfClass:NSDictionary.class])return @{@"error":@"设备响应验证失败"};return opened[@"result"];
}
NSDictionary *PCControlImport(NSString *text) {
    if(![text hasPrefix:@"agentgo://pair/"]||text.length>4096)return @{@"error":@"配对邀请无效"};NSString *encoded=[[[text substringFromIndex:15] stringByReplacingOccurrencesOfString:@"-" withString:@"+"] stringByReplacingOccurrencesOfString:@"_" withString:@"/"];while(encoded.length%4)encoded=[encoded stringByAppendingString:@"="];
    NSData *data=[[NSData alloc] initWithBase64EncodedString:encoded options:0];NSDictionary *p=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![p isKindOfClass:NSDictionary.class]||![p[@"pair"] isKindOfClass:NSString.class]||![[NSUUID alloc] initWithUUIDString:p[@"pair"]]||![p[@"key"] isKindOfClass:NSString.class]||[p[@"key"] length]!=64||![p[@"host"] isKindOfClass:NSString.class]||![p[@"name"] isKindOfClass:NSString.class]||[p[@"name"] length]>80||[p[@"port"] integerValue]<1||[p[@"port"] integerValue]>65535)return @{@"error":@"邀请字段无效"};
    NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:-"] invertedSet];if(![p[@"host"] length]||[p[@"host"] length]>253||[p[@"host"] rangeOfCharacterFromSet:invalid].location!=NSNotFound)return @{@"error":@"设备地址无效"};
    NSDictionary *added=PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableArray *peers=[s[@"peers"] mutableCopy]?:[NSMutableArray new];for(NSDictionary *item in peers)if([item[@"id"] isEqual:p[@"pair"]])return @{@"error":@"设备已配对"};if(peers.count>=32)return @{@"error":@"配对数量已达上限"};[peers addObject:@{@"id":p[@"pair"],@"key":p[@"key"],@"host":p[@"host"],@"port":p[@"port"],@"name":p[@"name"]}];s[@"peers"]=peers;return @{@"ok":@YES};});if(added[@"error"])return added;
    NSDictionary *result=PCControlRequest(p[@"pair"],@"hello",@{@"name":PCControlState()[@"name"],@"port":@18769},nil);
    if(result[@"error"])PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableArray *peers=[s[@"peers"] mutableCopy];NSIndexSet *indices=[peers indexesOfObjectsPassingTest:^BOOL(NSDictionary *v,NSUInteger index,BOOL *stop){return [v[@"id"] isEqual:p[@"pair"]];}];[peers removeObjectsAtIndexes:indices];s[@"peers"]=peers;return nil;});return result;
}
static NSDictionary *Execute(NSString *method, NSDictionary *args, NSString *owner, BOOL (^cancel)(void)) {
    if(![args isKindOfClass:NSDictionary.class])return @{@"error":@"参数无效"};NSDictionary *policy=PCControlState();
    if([method isEqual:@"presence"]){NSString *actor=args[@"actor"];if([@[@"ai",@"manual",@"connected"] containsObject:actor])Presence(owner,actor,![args[@"active"] isEqual:@NO],args);return @{@"ok":@YES};}
    if([method isEqual:@"session.close"]){Presence(owner,@"connected",NO,nil);Presence(owner,@"manual",NO,nil);Presence(owner,@"ai",NO,nil);NSDictionary *p=Peer(owner);if([p[@"incoming"] boolValue]&&[p[@"mode"] isEqual:@"once"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableArray *peers=[s[@"peers"] mutableCopy];NSIndexSet *indices=[peers indexesOfObjectsPassingTest:^BOOL(NSDictionary *p,NSUInteger i,BOOL *stop){return [p[@"id"] isEqual:owner];}];[peers removeObjectsAtIndexes:indices];s[@"peers"]=peers;return nil;});});return @{@"closed":@YES};}
    if([method isEqual:@"info"]){NSMutableDictionary *info=[PCPairIdentity() mutableCopy]?:[NSMutableDictionary new];[info addEntriesFromDictionary:@{@"platform":@"ios",@"terminal":@"persistent-command-shell",@"root":policy[@"root"]?:@NO,@"screen":policy[@"screen"]?:@NO}];return info;}
    if([method isEqual:@"app"]){NSString *action=args[@"action"];
        if([action isEqual:@"settings.api-key"]){NSString *key=args[@"key"];if(![key isKindOfClass:NSString.class]||key.length>8192||(!key.length&&![args[@"confirm"] isEqual:@YES]))return @{@"error":@"密钥或删除确认无效"};if([PCAgentTaskState()[@"running"] boolValue])return @{@"error":@"请等待任务结束"};NSError *error=nil;BOOL ok=PCSetAPIKeyForProvider(@"openai",key,&error);return ok?@{@"saved":@YES}:@{@"error":@"密钥未保存"};}
        if([action isEqual:@"device.list"]){NSMutableArray *peers=[NSMutableArray new];for(NSDictionary *p in policy[@"peers"]){if([p[@"incoming"] boolValue])continue;NSMutableDictionary *row=[NSMutableDictionary new];for(NSString *key in @[@"id",@"name",@"host",@"port",@"device_id",@"mode"])if(p[key])row[key]=p[key];[peers addObject:row];}return @{@"devices":peers};}
        if([action isEqual:@"device.app"]){NSDictionary *nested=args[@"arguments"];if(![nested isKindOfClass:NSDictionary.class]||[nested[@"action"] isEqual:@"device.app"])return @{@"error":@"不能递归转发应用请求"};return PCControlRequest(args[@"id"],@"app",nested,cancel);}
        if([@[@"ai.status",@"ai.stop",@"ai.pause",@"ai.continue",@"ai.answer",@"ai.approve"] containsObject:action])return PCAgentRemoteControl(args);
        if([action isEqual:@"device.discover"])return PCDiscoveryRun(nil);
        if([action isEqual:@"device.begin"]){NSError *error=nil;NSDictionary *remote=PCDiscoveryProbeHost(args[@"host"],args[@"device_id"],&error);return remote?PCPairBegin(remote):@{@"error":error.localizedDescription?:@"设备未响应"};}
        if([action isEqual:@"device.poll"])return PCPairPoll(args[@"id"]);
        if([action isEqual:@"device.pending"])return @{@"pending":PCPairPending()};
        if([action isEqual:@"device.decide"]){if(![args[@"confirm"] isEqual:@YES])return @{@"error":@"授权变更需要明确确认"};return PCPairDecide(args[@"id"],args[@"mode"]);}
        return PCAppRPCRequest(args,cancel);
    }
    if([method isEqual:@"vnc.info"]){
        if(![policy[@"screen"] boolValue])return @{@"error":@"本机已关闭屏幕控制"};
        NSString *dir=PCRealPath(@"/var/mobile/Library/PocketCodexRemote");NSData *data=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"phone.json"]];NSDictionary *settings=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        NSString *certificate=[NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"server.pem"] encoding:NSUTF8StringEncoding error:nil];
        if(![settings[@"password"] isKindOfClass:NSString.class]||!certificate.length)return @{@"error":@"兼容串流未配置"};
        uint8_t random[8];if(SecRandomCopyBytes(kSecRandomDefault,8,random))return @{@"error":@"无法生成会话认证"};NSMutableString *password=[NSMutableString new];const char alphabet[]="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";for(int i=0;i<8;i++)[password appendFormat:@"%c",alphabet[random[i]%62]];
        NSString *grantPath=[Directory() stringByAppendingPathComponent:@"vnc-grants.json"];@synchronized(Owners()){NSData *old=[NSData dataWithContentsOfFile:grantPath];NSMutableDictionary *grants=old?[[NSJSONSerialization JSONObjectWithData:old options:0 error:nil] mutableCopy]:[NSMutableDictionary new];for(NSString *identifier in grants.allKeys)if([grants[identifier][@"expires"] doubleValue]<NSDate.date.timeIntervalSince1970)[grants removeObjectForKey:identifier];grants[owner]=@{@"password":password,@"expires":@(NSDate.date.timeIntervalSince1970+60)};NSData *json=[NSJSONSerialization dataWithJSONObject:grants options:0 error:nil];[json writeToFile:grantPath options:NSDataWritingAtomic error:nil];chmod(grantPath.fileSystemRepresentation,0600);}
        return @{@"backend":@"vnc",@"port":@5907,@"certificate":certificate,@"fingerprint":settings[@"fingerprint"]?:@"",@"password":password};
    }
    if([method hasPrefix:@"terminal."]){NSString *action=[method substringFromIndex:9];if(![@[@"open",@"read",@"write",@"close",@"interrupt"] containsObject:action])return @{@"error":@"未知终端操作"};if([policy[@"root"] boolValue])return PCSendRootRequest(@{@"action":@"terminal",@"operation":action,@"args":args,@"owner":owner},5);return PCTerminalRequest(action,args,owner);}
    if(![method isEqual:@"execute"])return @{@"error":@"未知控制方法"};NSString *tool=args[@"tool"];
    if(![tool isKindOfClass:NSString.class]||![@[@"run_shell",@"read_file",@"write_file",@"list_directory",@"screen_capture",@"screen_tap",@"screen_swipe",@"screen_type",@"screen_home"] containsObject:tool])return @{@"error":@"不允许转发该工具"};
    if([tool hasPrefix:@"screen_"]&&![policy[@"screen"] boolValue])return @{@"error":@"被控设备已关闭远程屏幕操作"};
    PCTools *tools=[PCTools new];tools.workspace=[policy[@"workspace"] isKindOfClass:NSString.class]?policy[@"workspace"]:PCWorkspace();tools.rootEnabled=[policy[@"root"] boolValue];
    tools.screenPermission=policy[@"screen"]?:@NO;
    tools.cancellationCheck=cancel;
    if([tool hasPrefix:@"screen_"]){if([args[@"actor"] isEqual:@"ai"])Presence(owner,@"ai",YES,nil);else if(![tool isEqual:@"screen_capture"])Presence(owner,@"manual",YES,nil);}
    BOOL aiScreen=[tool hasPrefix:@"screen_"]&&[args[@"actor"] isEqual:@"ai"];
    @try {if(aiScreen)PCOverlayPrepareForAIScreen();return [tools execute:tool arguments:args[@"arguments"]];}
    @finally {if(aiScreen)PCOverlayFinishAIScreen([tool isEqual:@"screen_swipe"]?[args[@"arguments"][@"duration"] doubleValue]+.15:.2);}
}
NSDictionary *PCControlExecute(NSString *method, NSDictionary *args, NSString *owner) {return Execute(method,args,owner,nil);}

static void Reply(int fd,int status,NSDictionary *value) {NSData *body=[NSJSONSerialization dataWithJSONObject:value?:@{} options:0 error:nil];NSString *header=[NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n",status,status==200?@"OK":@"Forbidden",(unsigned long)body.length];NSMutableData *out=[[header dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];[out appendData:body];NSUInteger offset=0;while(offset<out.length){ssize_t n=write(fd,(char *)out.bytes+offset,out.length-offset);if(n<=0)break;offset+=(NSUInteger)n;}}
static BOOL WriteStream(int fd,NSData *data) {NSUInteger offset=0;while(offset<data.length){ssize_t n=write(fd,(char *)data.bytes+offset,data.length-offset);if(n<=0)return NO;offset+=(NSUInteger)n;}return YES;}
static void StreamFrames(int fd,NSDictionary *peer,NSDictionary *payload) {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE,0);
    if(![PCControlState()[@"screen"] boolValue]){Reply(fd,403,@{});return;}
    NSData *header=[@"HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];if(!WriteStream(fd,header))return;
    struct timeval timeout={3,0};setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    double fps=MAX(1,MIN(30,[payload[@"args"][@"fps"] doubleValue]?:30));NSTimeInterval next=NSProcessInfo.processInfo.systemUptime;NSUInteger sequence=0,sourceSequence=0;double captureMS=0,encodeMS=0,sendMS=0;NSTimeInterval began=next,nextPolicyCheck=0;
    for(;;){@autoreleasepool{
        NSTimeInterval current=NSProcessInfo.processInfo.systemUptime;
        if(current>=nextPolicyCheck){NSDictionary *policy=PCControlState();if(!PCControlAvailable()||![policy[@"enabled"] boolValue]||![policy[@"screen"] boolValue]||!Peer(peer[@"id"]))break;TouchPeer(peer[@"id"]);nextPolicyCheck=current+0.5;}
        char byte;ssize_t ready=recv(fd,&byte,1,MSG_PEEK|MSG_DONTWAIT);if(ready==0||(ready<0&&errno!=EAGAIN&&errno!=EWOULDBLOCK&&errno!=EINTR))break;
        NSTimeInterval a=NSProcessInfo.processInfo.systemUptime;
        NSMutableDictionary *frame=[PCScreenRequest(@{@"action":@"capture",@"after_sequence":@(sourceSequence)}) mutableCopy];sourceSequence=[frame[@"sequence"] unsignedIntegerValue];frame[@"stream_sequence"]=@(++sequence);NSTimeInterval b=NSProcessInfo.processInfo.systemUptime;
        NSData *encoded=PCControlSealFrame(frame,peer[@"key"],payload[@"id"]);if(!encoded||encoded.length>2*1024*1024)break;
        NSTimeInterval c=NSProcessInfo.processInfo.systemUptime;uint32_t length=htonl((uint32_t)encoded.length);NSMutableData *message=[NSMutableData dataWithBytes:&length length:4];[message appendData:encoded];if(!WriteStream(fd,message))break;NSTimeInterval d=NSProcessInfo.processInfo.systemUptime;captureMS+=(b-a)*1000;encodeMS+=(c-b)*1000;sendMS+=(d-c)*1000;
        if(sequence%120==0){NSDictionary *stats=@{@"frames":@(sequence),@"fps":@(sequence/(d-began)),@"capture_ms":@(captureMS/sequence),@"encode_ms":@(encodeMS/sequence),@"send_ms":@(sendMS/sequence)};NSData *record=[NSJSONSerialization dataWithJSONObject:stats options:0 error:nil];[record writeToFile:[Directory() stringByAppendingPathComponent:@"stream-performance.json"] options:NSDataWritingAtomic error:nil];}
        if(frame[@"error"])break;next=MAX(next+1.0/fps,NSProcessInfo.processInfo.systemUptime);NSTimeInterval delay=next-NSProcessInfo.processInfo.systemUptime;if(fps<30&&delay>0)usleep((useconds_t)(delay*1000000));
    }}
}
static void Serve(int fd,NSString *address,NSMutableDictionary *seen) {
    struct timeval timeout={10,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));timeout.tv_sec=140;setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    NSMutableData *bytes=[NSMutableData new];NSRange boundary;NSData *separator=[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    do{uint8_t buf[2048];ssize_t n=read(fd,buf,sizeof(buf));if(n<=0)return;[bytes appendBytes:buf length:n];boundary=[bytes rangeOfData:separator options:0 range:NSMakeRange(0,bytes.length)];if(boundary.location==NSNotFound&&bytes.length>8192)return;}while(boundary.location==NSNotFound);
    NSString *header=[[NSString alloc] initWithBytes:bytes.bytes length:boundary.location encoding:NSUTF8StringEncoding];if(!header)return;
    NSArray *lines=[header componentsSeparatedByString:@"\r\n"];if([lines.firstObject isEqual:@"GET /info HTTP/1.1"]){NSMutableDictionary *info=[PCPairIdentity() mutableCopy]?:[NSMutableDictionary new];info[@"agentgo"]=@1;info[@"platform"]=@"ios";info[@"enabled"]=PCControlState()[@"enabled"];info[@"available"]=@(PCControlAvailable());Reply(fd,200,info);return;}
    BOOL pairing=[lines.firstObject isEqual:@"POST /pair HTTP/1.1"];if(!PCControlAvailable()){Reply(fd,403,@{@"error":@"设备当前不接收后台连接，请打开 AsterHand"});return;}if(!pairing&&(![lines.firstObject isEqual:@"POST /rpc HTTP/1.1"]||![PCControlState()[@"enabled"] boolValue])){Reply(fd,403,@{});return;}
    NSInteger length=-1;for(NSString *line in lines){NSString *lower=line.lowercaseString;if([lower hasPrefix:@"origin:"]||[lower hasPrefix:@"transfer-encoding:"]){Reply(fd,403,@{});return;}if([lower hasPrefix:@"content-length:"]){if(length!=-1)return;length=[[line substringFromIndex:15] integerValue];}}
    if(length<2||length>(pairing?32768:2*1024*1024))return;NSUInteger start=boundary.location+4;
    while(bytes.length<start+(NSUInteger)length){uint8_t buf[8192];ssize_t n=read(fd,buf,MIN(sizeof(buf),start+(NSUInteger)length-bytes.length));if(n<=0)return;[bytes appendBytes:buf length:n];}
    NSDictionary *packet=[NSJSONSerialization JSONObjectWithData:[bytes subdataWithRange:NSMakeRange(start,(NSUInteger)length)] options:0 error:nil];if(pairing){NSDictionary *r=PCPairHandle(packet,address);Reply(fd,r?200:403,r?:@{});return;}NSDictionary *peer=[packet isKindOfClass:NSDictionary.class]?Peer(packet[@"pair"]):nil;
    if([peer[@"incoming"] isEqual:@NO]){Reply(fd,403,@{});return;}
    NSDictionary *payload=peer?PCControlOpen(packet,peer[@"key"],@"req"):nil;if(!payload){Reply(fd,403,@{});return;}
    NSDictionary *sender=payload[@"args"][@"identity"];
    if([payload[@"method"] isEqual:@"info"]&&[sender isKindOfClass:NSDictionary.class]&&!peer[@"device_id"]){NSData *public=[[NSData alloc] initWithBase64EncodedString:sender[@"public_key"]?:@"" options:0];if(public.length==65&&PCPairIdentityValid(sender)){PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableArray *peers=[s[@"peers"] mutableCopy];for(NSUInteger i=0;i<peers.count;i++){NSMutableDictionary *p=[peers[i] mutableCopy];if([p[@"id"] isEqual:peer[@"id"]]){p[@"device_id"]=sender[@"device_id"];p[@"public_key"]=sender[@"public_key"];peers[i]=p;}}s[@"peers"]=peers;return nil;});}}
    TouchPeer(peer[@"id"]);
    @synchronized(Owners()){[Owners() addObject:peer[@"id"]];}
    @synchronized(seen){NSTimeInterval now=NSDate.date.timeIntervalSince1970;for(NSString *key in seen.allKeys)if(now-[seen[key] doubleValue]>180)[seen removeObjectForKey:key];NSString *key=[NSString stringWithFormat:@"%@:%@",packet[@"pair"],payload[@"id"]];if(seen[key]||seen.count>=4096){Reply(fd,403,@{});return;}seen[key]=@(now);}
    if([payload[@"method"] isEqual:@"stream2"]){StreamFrames(fd,peer,payload);return;}
    NSDictionary *result;
    if([payload[@"method"] isEqual:@"hello"]) {
        NSDictionary *args=payload[@"args"];if(![args isKindOfClass:NSDictionary.class]||![args[@"name"] isKindOfClass:NSString.class]||[args[@"name"] length]>80||[args[@"port"] integerValue]<1||[args[@"port"] integerValue]>65535)result=@{@"error":@"hello 参数无效"};
        else result=PCControlUpdate(^NSDictionary *(NSMutableDictionary *s){NSMutableArray *peers=[s[@"peers"] mutableCopy];for(NSUInteger i=0;i<peers.count;i++){NSMutableDictionary *p=[peers[i] mutableCopy];if([p[@"id"] isEqual:peer[@"id"]]){p[@"name"]=args[@"name"];p[@"host"]=address;p[@"port"]=args[@"port"];peers[i]=p;}}s[@"peers"]=peers;return @{@"ok":@YES,@"name":s[@"name"]};});
    }else result=Execute(payload[@"method"],payload[@"args"],peer[@"id"],^BOOL{if(!PCControlAvailable()||![PCControlState()[@"enabled"] boolValue]||!Peer(peer[@"id"]))return YES;char byte;ssize_t n=recv(fd,&byte,1,MSG_PEEK|MSG_DONTWAIT);return n==0||(n<0&&errno!=EAGAIN&&errno!=EWOULDBLOCK&&errno!=EINTR);});
    if(![PCControlState()[@"enabled"] boolValue]||!Peer(peer[@"id"])){PCTerminalCloseOwner(peer[@"id"]);Reply(fd,403,@{});return;}
    Reply(fd,200,PCControlSeal(peer[@"id"],peer[@"key"],@{@"id":payload[@"id"],@"ts":@(NSDate.date.timeIntervalSince1970),@"result":result?:@{@"error":@"执行失败"}},@"res"));
}

@implementation PCControlStream {
    NSURLSession *_session;NSURLSessionDataTask *_task;NSMutableData *_buffer;NSDictionary *_peer;NSString *_nonce;NSUInteger _sequence;BOOL _stopped,_deliveryScheduled;NSDictionary *_pendingFrame;
}
- (void)start:(NSString *)identifier {
    [self stop];_stopped=NO;_peer=Peer(identifier);_buffer=[NSMutableData new];_sequence=0;_nonce=NSUUID.UUID.UUIDString.lowercaseString;
    NSURLComponents *url=[NSURLComponents new];url.scheme=@"http";url.host=_peer[@"host"];url.port=_peer[@"port"];url.path=@"/rpc";
    NSDictionary *packet=_peer?PCControlSeal(identifier,_peer[@"key"],@{@"id":_nonce,@"ts":@(NSDate.date.timeIntervalSince1970),@"method":@"stream2",@"args":@{@"fps":@30}},@"req"):nil;
    if(!url.URL||!packet){if(self.failed)self.failed(@"设备未配对");return;}
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url.URL];request.HTTPMethod=@"POST";request.HTTPBody=[NSJSONSerialization dataWithJSONObject:packet options:0 error:nil];[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.timeoutIntervalForRequest=15;config.timeoutIntervalForResource=24*60*60;config.connectionProxyDictionary=@{};config.HTTPShouldSetCookies=NO;
    NSOperationQueue *queue=[NSOperationQueue new];queue.maxConcurrentOperationCount=1;_session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:queue];_task=[_session dataTaskWithRequest:request];[_task resume];
}
- (void)stop {_stopped=YES;[_task cancel];[_session invalidateAndCancel];_task=nil;_session=nil;}
- (void)error:(NSString *)message {if(_stopped)return;[self stop];dispatch_async(dispatch_get_main_queue(),^{if(self.failed)self.failed(message);});}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {if(session!=_session||[(NSHTTPURLResponse *)response statusCode]!=200){completionHandler(NSURLSessionResponseCancel);[self error:@"对方未允许实时屏幕"];return;}completionHandler(NSURLSessionResponseAllow);}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if(_stopped||session!=_session)return;[_buffer appendData:data];if(_buffer.length>4*1024*1024){[self error:@"画面缓冲区过大"];return;}
    while(_buffer.length>=4){uint32_t length;memcpy(&length,_buffer.bytes,4);length=ntohl(length);if(length<2||length>2*1024*1024){[self error:@"画面数据无效"];return;}if(_buffer.length<4+length)return;
        NSData *body=[_buffer subdataWithRange:NSMakeRange(4,length)];[_buffer replaceBytesInRange:NSMakeRange(0,4+length) withBytes:NULL length:0];NSDictionary *frame=PCControlOpenFrame(body,_peer[@"key"],_nonce);
        if(!frame||[frame[@"stream_sequence"] unsignedIntegerValue]<=_sequence){[self error:@"画面认证失败"];return;}_sequence=[frame[@"stream_sequence"] unsignedIntegerValue];if(frame[@"error"]){[self error:frame[@"error"]];return;}
        @synchronized(self){_pendingFrame=frame;if(_deliveryScheduled)continue;_deliveryScheduled=YES;}
        dispatch_async(dispatch_get_main_queue(),^{NSDictionary *latest;@synchronized(self){latest=self->_pendingFrame;self->_pendingFrame=nil;self->_deliveryScheduled=NO;}if(!self->_stopped&&self.frame)self.frame(latest);});
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {if(session==_session&&!_stopped)[self error:error.localizedDescription?:@"屏幕连接已结束"];}
@end
int PCRunControlDaemon(void) {
    PCPairIdentity();
    PCTerminalStartMaintenance();
    static dispatch_source_t maintenance;maintenance=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));dispatch_source_set_timer(maintenance,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),5*NSEC_PER_SEC,NSEC_PER_SEC);dispatch_source_set_event_handler(maintenance,^{NSArray *owners;@synchronized(Owners()){owners=Owners().allObjects;}for(NSString *owner in owners)if(![PCControlState()[@"enabled"] boolValue]||!Peer(owner)){PCTerminalCloseOwner(owner);PCSendRootRequest(@{@"action":@"terminal",@"operation":@"close_owner",@"args":@{},@"owner":owner},3);@synchronized(Owners()){[Owners() removeObject:owner];}}});dispatch_resume(maintenance);
    signal(SIGPIPE,SIG_IGN);int server=socket(AF_INET,SOCK_STREAM,0),one=1;setsockopt(server,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));fcntl(server,F_SETFD,FD_CLOEXEC);
    struct sockaddr_in bindAddress={0};bindAddress.sin_family=AF_INET;bindAddress.sin_port=htons(18769);bindAddress.sin_addr.s_addr=htonl(INADDR_ANY);
    if(bind(server,(struct sockaddr *)&bindAddress,sizeof(bindAddress))||listen(server,8)){NSLog(@"AsterHand control listener failed: errno=%d %s",errno,strerror(errno));close(server);return 2;}
    struct sockaddr_in actualAddress={0};socklen_t actualLength=sizeof(actualAddress);if(getsockname(server,(struct sockaddr *)&actualAddress,&actualLength)==0){char local[INET_ADDRSTRLEN]={0};inet_ntop(AF_INET,&actualAddress.sin_addr,local,sizeof(local));NSLog(@"AsterHand control listening on %s:%u",local,ntohs(actualAddress.sin_port));}
    NSMutableDictionary *seen=[NSMutableDictionary new];dispatch_semaphore_t slots=dispatch_semaphore_create(4);
    for(;;){struct sockaddr_in addr;socklen_t length=sizeof(addr);int fd=accept(server,(struct sockaddr *)&addr,&length);if(fd<0)continue;fcntl(fd,F_SETFD,FD_CLOEXEC);int noDelay=1;setsockopt(fd,IPPROTO_TCP,TCP_NODELAY,&noDelay,sizeof(noDelay));if(dispatch_semaphore_wait(slots,DISPATCH_TIME_NOW)!=0){close(fd);continue;}char text[INET_ADDRSTRLEN];inet_ntop(AF_INET,&addr.sin_addr,text,sizeof(text));NSString *address=@(text);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE,0),^{@autoreleasepool{@try{Serve(fd,address,seen);}@catch(NSException *e){Reply(fd,403,@{});}close(fd);dispatch_semaphore_signal(slots);}});
    }
}
