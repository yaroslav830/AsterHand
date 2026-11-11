#import "PCDiscovery.h"
#import "PCPairing.h"
#import "PCControl.h"
#import "PCDirectedPairing.h"
#include <ifaddrs.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

NSDictionary *PCDiscoveryDecodeJSON(NSData *data) {
    if(data.length>=65536)return nil;NSData *separator=[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];NSRange split=[data rangeOfData:separator options:0 range:NSMakeRange(0,data.length)];if(split.location==NSNotFound)return nil;
    NSString *header=[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0,split.location)] encoding:NSASCIIStringEncoding];if(![header hasPrefix:@"HTTP/1.1 200 "]&&![header hasPrefix:@"HTTP/1.0 200 "])return nil;
    NSData *body=[data subdataWithRange:NSMakeRange(NSMaxRange(split),data.length-NSMaxRange(split))];NSString *transfer=nil,*length=nil;
    for(NSString *line in [header componentsSeparatedByString:@"\r\n"]){NSRange colon=[line rangeOfString:@":"];if(colon.location==NSNotFound)continue;NSString *name=[[line substringToIndex:colon.location] lowercaseString],*value=[[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if([name isEqual:@"transfer-encoding"])transfer=value.lowercaseString;if([name isEqual:@"content-length"])length=value;}
    if(transfer){if(![transfer isEqual:@"chunked"])return nil;NSMutableData *decoded=[NSMutableData new];NSUInteger offset=0;NSData *newline=[@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];
        for(;;){NSRange end=[body rangeOfData:newline options:0 range:NSMakeRange(offset,body.length-offset)];if(end.location==NSNotFound||end.location-offset>128)return nil;NSString *line=[[NSString alloc] initWithData:[body subdataWithRange:NSMakeRange(offset,end.location-offset)] encoding:NSASCIIStringEncoding];NSString *hex=[line componentsSeparatedByString:@";"].firstObject;if(!hex.length||[hex rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location!=NSNotFound)return nil;
            unsigned long long size=0;NSScanner *scanner=[NSScanner scannerWithString:hex];if(![scanner scanHexLongLong:&size]||!scanner.isAtEnd)return nil;offset=NSMaxRange(end);if(size>65536||size>body.length-offset||body.length-offset-size<2)return nil;
            const uint8_t *bytes=body.bytes;if(bytes[offset+size]!='\r'||bytes[offset+size+1]!='\n')return nil;if(size==0){body=decoded;break;}[decoded appendData:[body subdataWithRange:NSMakeRange(offset,(NSUInteger)size)]];offset+=(NSUInteger)size+2;
        }
    }else if(length){NSScanner *scanner=[NSScanner scannerWithString:length];unsigned long long size=0;if(![scanner scanUnsignedLongLong:&size]||!scanner.isAtEnd||size!=body.length)return nil;}
    id value=[NSJSONSerialization JSONObjectWithData:body options:0 error:nil];return [value isKindOfClass:NSDictionary.class]?value:nil;
}

// A socket per live probe, not an NSURLSession per address. Binding to the LAN
// interface keeps local discovery off HTTP proxies and VPN default routes.
static NSDictionary *Probe(NSString *host, unsigned int interface, int *failure) {
    int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0){*failure=errno;return nil;}
    int one=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
    if(setsockopt(fd,IPPROTO_IP,IP_BOUND_IF,&interface,sizeof(interface))<0){*failure=errno;close(fd);return nil;}
    fcntl(fd,F_SETFD,FD_CLOEXEC);fcntl(fd,F_SETFL,O_NONBLOCK);
    struct sockaddr_in target={0};target.sin_family=AF_INET;target.sin_port=htons(18769);
    if(inet_pton(AF_INET,host.UTF8String,&target.sin_addr)!=1){close(fd);return nil;}
    int result=connect(fd,(struct sockaddr *)&target,sizeof(target));
    if(result<0&&errno!=EINPROGRESS){*failure=errno;close(fd);return nil;}
    struct pollfd ready={fd,POLLOUT,0};int error=0;socklen_t length=sizeof(error);
    int polled=poll(&ready,1,1000);if(polled<=0||getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&length)<0||error){*failure=polled==0?ETIMEDOUT:(error?:errno);close(fd);return nil;}
    fcntl(fd,F_SETFL,0);struct timeval timeout={1,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    NSData *request=[[NSString stringWithFormat:@"GET /info HTTP/1.1\r\nHost: %@:18769\r\nConnection: close\r\n\r\n",host] dataUsingEncoding:NSASCIIStringEncoding];
    NSUInteger sent=0;while(sent<request.length){ssize_t n=write(fd,(const char *)request.bytes+sent,request.length-sent);if(n<=0){close(fd);return nil;}sent+=(NSUInteger)n;}
    NSMutableData *data=[NSMutableData new];char buffer[4096];double until=NSProcessInfo.processInfo.systemUptime+1.5;
    while(data.length<65536&&NSProcessInfo.processInfo.systemUptime<until){ssize_t n=read(fd,buffer,MIN(sizeof(buffer),65536-data.length));if(n<=0)break;[data appendBytes:buffer length:n];}
    close(fd);NSDictionary *value=PCDiscoveryDecodeJSON(data);
    if(![value isKindOfClass:NSDictionary.class]||![value[@"agentgo"] isEqual:@1]||![value[@"pairing"] isEqual:@2]||!PCPairIdentityValid(value)||![value[@"name"] isKindOfClass:NSString.class]||[value[@"name"] length]>80||[value[@"port"] integerValue]!=18769)return nil;
    NSMutableDictionary *device=[value mutableCopy];device[@"host"]=host;return device;
}

NSDictionary *PCDiscoveryProbeHost(NSString *host,NSString *expectedDeviceID,NSError **error){
    uint32_t target=0;NSString *failure=nil;int code=EINVAL;unsigned int interface=0;
    if(![host isKindOfClass:NSString.class]||![expectedDeviceID isKindOfClass:NSString.class]||!PCDirectedPairingInput(host.UTF8String,expectedDeviceID.UTF8String,&target))failure=@"请输入规范的局域网 IPv4 和完整设备标识。";
    if(!failure){struct ifaddrs *list=NULL;if(getifaddrs(&list)==0){for(struct ifaddrs *p=list;p;p=p->ifa_next){if(!p->ifa_addr||!p->ifa_netmask||p->ifa_addr->sa_family!=AF_INET||!(p->ifa_flags&IFF_UP)||!(p->ifa_flags&IFF_RUNNING)||(p->ifa_flags&IFF_LOOPBACK))continue;NSString *name=@(p->ifa_name);if(![name hasPrefix:@"en"]&&![name hasPrefix:@"bridge"])continue;uint32_t local=ntohl(((struct sockaddr_in *)p->ifa_addr)->sin_addr.s_addr),mask=ntohl(((struct sockaddr_in *)p->ifa_netmask)->sin_addr.s_addr),base=local&mask;if((target&mask)!=base||target==local||target==base||target==(base|~mask))continue;unsigned int candidate=if_nametoindex(p->ifa_name);if(candidate){interface=candidate;if([name isEqual:@"en0"])break;}}freeifaddrs(list);}if(!interface)failure=@"目标不在当前已连接的局域网接口中，未发出请求。";}
    NSDictionary *remote=nil;if(!failure){remote=Probe(host,interface,&code);if(!remote)failure=@"目标设备未响应，请检查 AsterHand 服务与网络权限。";else if(![remote[@"device_id"] isEqual:expectedDeviceID]){remote=nil;failure=@"设备标识与预期不一致，未发出配对申请。";}}
    if(failure&&error)*error=[NSError errorWithDomain:@"AsterHand.DirectedPairing" code:code userInfo:@{NSLocalizedDescriptionKey:failure}];return remote;
}

NSDictionary *PCDiscoveryRun(void (^progress)(NSArray *,NSString *)) {
    NSMutableArray *networks=[NSMutableArray new],*targets=[NSMutableArray new];NSMutableSet *local=[NSMutableSet new],*seen=[NSMutableSet new];struct ifaddrs *list=NULL;
    if(getifaddrs(&list)==0){for(struct ifaddrs *p=list;p;p=p->ifa_next){if(!p->ifa_addr||p->ifa_addr->sa_family!=AF_INET||!p->ifa_netmask||!(p->ifa_flags&IFF_UP)||!(p->ifa_flags&IFF_RUNNING)||(p->ifa_flags&IFF_LOOPBACK))continue;
        NSString *name=@(p->ifa_name);if(![name hasPrefix:@"en"]&&![name hasPrefix:@"bridge"])continue;
        uint32_t ip=ntohl(((struct sockaddr_in *)p->ifa_addr)->sin_addr.s_addr),mask=ntohl(((struct sockaddr_in *)p->ifa_netmask)->sin_addr.s_addr);char ipText[INET_ADDRSTRLEN];inet_ntop(AF_INET,&((struct sockaddr_in *)p->ifa_addr)->sin_addr,ipText,sizeof(ipText));[local addObject:@(ipText)];
        if((ip&0xffff0000)==0xa9fe0000)continue;
        uint64_t size=(uint64_t)(~mask)+1;if(size<4)continue;
        // Bound unusually wide networks to the current /24. Normal LANs up to
        // /20 are searched, closest /24 first, within an overall time budget.
        if(size>4096){mask=0xffffff00;size=256;}
        [networks addObject:@{@"interface":name,@"index":@(if_nametoindex(p->ifa_name)),@"ip":@(ip),@"mask":@(mask),@"size":@(size)}];
    }freeifaddrs(list);}
    NSDictionary *state=PCControlState();
    for(NSDictionary *network in networks){uint32_t ip=[network[@"ip"] unsignedIntValue],mask=[network[@"mask"] unsignedIntValue],base=ip&mask;NSUInteger size=[network[@"size"] unsignedIntegerValue];NSMutableArray *addresses=[NSMutableArray new];
        for(NSDictionary *peer in state[@"peers"]){struct in_addr addr;if([peer[@"host"] isKindOfClass:NSString.class]&&inet_pton(AF_INET,[peer[@"host"] UTF8String],&addr)==1&&(ntohl(addr.s_addr)&mask)==base)[addresses addObject:@(ntohl(addr.s_addr))];}
        for(NSUInteger pass=0;pass<2;pass++)for(uint32_t n=1;n<size-1;n++){uint32_t address=base+n;if(((address&0xffffff00)==(ip&0xffffff00))==(pass==0))[addresses addObject:@(address)];}
        for(NSNumber *address in addresses){struct in_addr a={htonl(address.unsignedIntValue)};char text[INET_ADDRSTRLEN];inet_ntop(AF_INET,&a,text,sizeof(text));NSString *host=@(text);if([local containsObject:host]||[seen containsObject:host])continue;[seen addObject:host];[targets addObject:@{@"host":host,@"index":network[@"index"]}];}
    }
    NSMutableDictionary *devices=[NSMutableDictionary new],*networkErrors=[NSMutableDictionary new];NSObject *lock=[NSObject new];__block NSUInteger cursor=0,completed=0,denied=0;__block double nextUpdate=0;double start=NSProcessInfo.processInfo.systemUptime;NSString *own=PCPairIdentity()[@"device_id"];
    NSOperationQueue *queue=[NSOperationQueue new];queue.maxConcurrentOperationCount=48;
    for(NSUInteger worker=0;worker<MIN((NSUInteger)48,targets.count);worker++)[queue addOperationWithBlock:^{for(;;){@autoreleasepool{NSDictionary *target;@synchronized(lock){if(cursor>=targets.count||NSProcessInfo.processInfo.systemUptime-start>14)break;target=targets[cursor++];}
        int error=0;NSDictionary *result=Probe(target[@"host"],[target[@"index"] unsignedIntValue],&error);
        @synchronized(lock){completed++;if(error){NSString *key=@(strerror(error));networkErrors[key]=@([networkErrors[key] unsignedIntegerValue]+1);}if(error==EACCES||error==EPERM)denied++;BOOL added=result&&![result[@"device_id"] isEqual:own];if(added)devices[result[@"device_id"]]=result;double now=NSProcessInfo.processInfo.systemUptime;
            if(progress&&(added||now>=nextUpdate)){nextUpdate=now+.4;progress([devices.allValues copy],[NSString stringWithFormat:@"正在搜索 · %lu/%lu",(unsigned long)completed,(unsigned long)targets.count]);}
        }
    }}}];[queue waitUntilAllOperationsAreFinished];
    NSArray *found=[devices.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedStandardCompare:b[@"name"]];}];
    BOOL blockedRoutes=completed>0&&[networkErrors[@(strerror(EHOSTUNREACH))] unsignedIntegerValue]==completed&&NSProcessInfo.processInfo.systemUptime-start<1;
    NSString *message=!networks.count?@"请先连接 Wi-Fi 或局域网":!found.count&&(denied||blockedRoutes)?@"本机无法访问局域网，请检查设置中的网络授权和系统本地网络权限":found.count?@"选择设备发送连接申请":@"未发现设备，请确认对方在线且处于同一局域网";
    NSDictionary *report=@{@"devices":found,@"status":message,@"interfaces":networks,@"attempted":@(completed),@"total":@(targets.count),@"denied":@(denied),@"network_errors":networkErrors,@"seconds":@(NSProcessInfo.processInfo.systemUptime-start)};if(progress)progress(found,message);return report;
}
