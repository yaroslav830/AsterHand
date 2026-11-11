#import "PCOAuthListener.h"
#import "PCSupport.h"
#import "PCOAuthTrace.h"
#import "PCLocalization.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <poll.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static NSString *EscapeHTML(NSString *text){
    return [[[[[text stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"] stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"] stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"] stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"] stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
}
static NSString *CallbackHTML(BOOL accepted){
    NSString *content=accepted?[NSString stringWithFormat:@"<h2>%@</h2><p>%@</p><a href='asterhand://open'>%@</a>",EscapeHTML(PCLocalized(@"正在验证登录授权…")),EscapeHTML(PCLocalized(@"完成后会自动返回应用。若未返回，可点击下方按钮。")),EscapeHTML(PCLocalized(@"返回 AsterHand"))]:[NSString stringWithFormat:@"<p>%@</p>",EscapeHTML(PCLocalized(@"此请求不是当前登录回调，请继续原来的授权流程。"))];
    return [NSString stringWithFormat:@"<!doctype html><html lang='%@'><meta charset=utf-8><meta name=viewport content='width=device-width'><title>AsterHand</title><style>body{font:18px system-ui;padding:32px}a{display:inline-block;margin-top:20px}</style>%@</html>",PCResolvedUILanguage(),content];
}
static void Respond(int fd,int code,NSString *body){
    NSData *data=[body dataUsingEncoding:NSUTF8StringEncoding];NSString *header=[NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\n\r\n",code,code==200?@"OK":@"Bad Request",(unsigned long)data.length];
    NSMutableData *packet=[[header dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];[packet appendData:data];const char *bytes=packet.bytes;NSUInteger offset=0;
    while(offset<packet.length){ssize_t written=send(fd,bytes+offset,packet.length-offset,0);if(written>0)offset+=(NSUInteger)written;else if(errno!=EINTR)break;}
}
static NSDictionary *Parse(NSString *header,NSURL *redirect,NSString *state){
    NSArray *lines=[header componentsSeparatedByString:@"\r\n"],*first=[lines.firstObject componentsSeparatedByString:@" "];
    if(first.count!=3||![first[0] isEqual:@"GET"])return nil;
    NSString *target=first[1];if(![target hasPrefix:@"/"]||[target hasPrefix:@"//"])return nil;
    NSURLComponents *url=[NSURLComponents componentsWithString:target];if(url.scheme||url.host||url.fragment||![url.path isEqual:redirect.path])return nil;
    NSString *host=nil;for(NSString *line in lines){NSRange colon=[line rangeOfString:@":"];if(colon.location!=NSNotFound&&[[line substringToIndex:colon.location].lowercaseString isEqual:@"host"]){if(host)return nil;host=[[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];}}
    if(![host isEqual:[NSString stringWithFormat:@"%@:%@",redirect.host,redirect.port]])return nil;
    NSMutableDictionary *values=[NSMutableDictionary new];for(NSURLQueryItem *item in url.queryItems){if(values[item.name])return nil;if(item.value)values[item.name]=item.value;}
    if(![values[@"state"] isEqual:state]||(![values[@"code"] length]&&![values[@"error"] length]))return nil;
    return values;
}
BOOL PCOAuthDeliverCallbackURL(NSURL *url,NSURL *redirect,NSString *state,NSError **error){
    if(![url.scheme isEqual:redirect.scheme]||![url.host isEqual:@"127.0.0.1"]||![url.host isEqual:redirect.host]||![url.port isEqual:redirect.port]||![url.path isEqual:redirect.path]||url.fragment||url.user||url.password){if(error)*error=PCError(@"登录回调地址不匹配。");return NO;}
    NSURLComponents *parts=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];NSString *request=[NSString stringWithFormat:@"GET %@?%@ HTTP/1.1\r\nHost: %@:%@\r\nConnection: close\r\n\r\n",parts.percentEncodedPath,parts.percentEncodedQuery?:@"",redirect.host,redirect.port];
    if(!Parse(request,redirect,state)){if(error)*error=PCError(@"登录回调身份校验失败，请重新开始。");return NO;}
    int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0){if(error)*error=PCError(@"无法转交本机登录回调。");return NO;}
    struct sockaddr_in addr={0};addr.sin_len=sizeof(addr);addr.sin_family=AF_INET;addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);addr.sin_port=htons(redirect.port.unsignedShortValue);struct timeval timeout={3,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));int noPipe=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noPipe,sizeof(noPipe));
    BOOL ok=connect(fd,(struct sockaddr *)&addr,sizeof(addr))==0;NSData *data=[request dataUsingEncoding:NSUTF8StringEncoding];size_t offset=0;
    while(ok&&offset<data.length){ssize_t count=send(fd,(const char *)data.bytes+offset,data.length-offset,0);if(count>0)offset+=(size_t)count;else if(errno!=EINTR)ok=NO;}
    char reply[64]={0};size_t received=0;while(ok&&received<13){ssize_t count=recv(fd,reply+received,sizeof(reply)-received-1,0);if(count>0)received+=(size_t)count;else if(errno!=EINTR)ok=NO;}close(fd);ok=ok&&received>=13&&strncmp(reply,"HTTP/1.1 200 ",13)==0;
    if(!ok&&error)*error=PCError(@"本机登录回调未就绪，请重新开始登录。");return ok;
}
NSDictionary *PCOAuthWaitForCallback(int listener,NSURL *redirect,NSString *state,NSTimeInterval timeout,NSError **error){
    double deadline=NSProcessInfo.processInfo.systemUptime+timeout;
    while(NSProcessInfo.processInfo.systemUptime<deadline){
        struct pollfd ready={listener,POLLIN,0};int result=poll(&ready,1,250);
        if(result<0&&errno==EINTR)continue;
        if(result<0||(ready.revents&(POLLERR|POLLHUP|POLLNVAL))){if(error)*error=PCError(@"登录已取消或本机回调已关闭。");return nil;}
        if(!result)continue;
        int client=accept(listener,NULL,NULL);if(client<0){if(errno==EINTR)continue;if(error)*error=PCError(@"无法接收本机登录回调，请重试。");return nil;}
        int noPipe=1;setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&noPipe,sizeof(noPipe));struct timeval ioTimeout={2,0};setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&ioTimeout,sizeof(ioTimeout));setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&ioTimeout,sizeof(ioTimeout));
        char buffer[32769]={0};size_t used=0;double readDeadline=MIN(deadline,NSProcessInfo.processInfo.systemUptime+3);
        while(used<sizeof(buffer)-1&&NSProcessInfo.processInfo.systemUptime<readDeadline){
            ssize_t count=recv(client,buffer+used,sizeof(buffer)-used-1,0);if(count>0){used+=(size_t)count;buffer[used]=0;if(strstr(buffer,"\r\n\r\n"))break;}else if(count<0&&errno==EINTR)continue;else break;
        }
        NSString *header=strstr(buffer,"\r\n\r\n")?[[NSString alloc] initWithBytes:buffer length:used encoding:NSUTF8StringEncoding]:nil;
        NSString *method=[[header componentsSeparatedByString:@" "] firstObject];
        PCOAuthTrace([method isEqual:@"GET"]?@"callback_request_get":([method isEqual:@"OPTIONS"]?@"callback_request_options":([method isEqual:@"POST"]?@"callback_request_post":@"callback_preconnect_or_other")));
        NSDictionary *values=header?Parse(header,redirect,state):nil;
        PCOAuthTrace(values?@"callback_validated":@"callback_request_ignored");
        if(values){Respond(client,200,CallbackHTML(YES));close(client);return values;}
        if(used)Respond(client,400,CallbackHTML(NO));
        close(client); // Speculative preconnects, favicons and stale callbacks do not consume the attempt.
    }
    if(error)*error=PCError(@"登录已超过 10 分钟，请重新开始。");return nil;
}
NSDictionary *PCOAuthListenerSelfTest(void){
    int server=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in addr={0};addr.sin_len=sizeof(addr);addr.sin_family=AF_INET;addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(server<0||bind(server,(struct sockaddr *)&addr,sizeof(addr))||listen(server,8)){if(server>=0)close(server);return @{@"oauth_callback_preconnect_and_fragmented_request":@NO};}
    socklen_t length=sizeof(addr);getsockname(server,(struct sockaddr *)&addr,&length);NSString *host=[NSString stringWithFormat:@"127.0.0.1:%u",ntohs(addr.sin_port)];NSURL *redirect=[NSURL URLWithString:[@"http://" stringByAppendingFormat:@"%@/auth/callback",host]];
    __block BOOL complete=NO;dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSArray *requests=@[@"",[NSString stringWithFormat:@"GET /favicon.ico HTTP/1.1\r\nHost: %@\r\n\r\n",host],[NSString stringWithFormat:@"GET /auth/callback?state=wrong&code=fixture HTTP/1.1\r\nHost: %@\r\n\r\n",host],[NSString stringWithFormat:@"GET /auth/callback?state=fixture-state&code=fixture-code HTTP/1.1\r\nHost: %@\r\n\r\n",host]];
        for(NSString *request in requests){int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0||connect(fd,(struct sockaddr *)&addr,sizeof(addr))){if(fd>=0)close(fd);break;}struct timeval limit={2,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&limit,sizeof(limit));int noPipe=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noPipe,sizeof(noPipe));NSData *data=[request dataUsingEncoding:NSUTF8StringEncoding];if(data.length){NSUInteger half=data.length/2;send(fd,data.bytes,half,0);usleep(10000);send(fd,(const char *)data.bytes+half,data.length-half,0);char response[1024];recv(fd,response,sizeof(response),0);}close(fd);}
        complete=YES;dispatch_semaphore_signal(done);
    });
    NSError *failure=nil;NSDictionary *values=PCOAuthWaitForCallback(server,redirect,@"fixture-state",5,&failure);close(server);dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC));
    NSString *prefix=[NSString stringWithFormat:@"GET /auth/callback?state=fixture-state&code=fixture&state=wrong HTTP/1.1\r\nHost: %@\r\n\r\n",host];
    BOOL foreign=!PCOAuthDeliverCallbackURL([NSURL URLWithString:@"https://example.invalid/auth/callback?code=fixture&state=fixture-state"],redirect,@"fixture-state",nil);
    int bridgeServer=socket(AF_INET,SOCK_STREAM,0);addr.sin_port=0;BOOL bridgeReady=bridgeServer>=0&&bind(bridgeServer,(struct sockaddr *)&addr,sizeof(addr))==0&&listen(bridgeServer,4)==0;__block BOOL delivered=NO;NSDictionary *bridgeValue=nil;
    if(bridgeReady){getsockname(bridgeServer,(struct sockaddr *)&addr,&length);NSURL *bridgeRedirect=[NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/auth/callback",ntohs(addr.sin_port)]];dispatch_semaphore_t bridgeDone=dispatch_semaphore_create(0);dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{delivered=PCOAuthDeliverCallbackURL([NSURL URLWithString:[bridgeRedirect.absoluteString stringByAppendingString:@"?state=bridge-state&code=bridge-fixture"]],bridgeRedirect,@"bridge-state",nil);dispatch_semaphore_signal(bridgeDone);});bridgeValue=PCOAuthWaitForCallback(bridgeServer,bridgeRedirect,@"bridge-state",5,nil);dispatch_semaphore_wait(bridgeDone,dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC));}
    if(bridgeServer>=0)close(bridgeServer);
    return @{@"oauth_callback_preconnect_and_fragmented_request":@(complete&&!failure&&[values[@"code"] isEqual:@"fixture-code"]),@"oauth_callback_rejects_duplicate_state":@(!Parse(prefix,redirect,@"fixture-state")),@"oauth_callback_rejects_wrong_host":@(!Parse(@"GET /auth/callback?state=fixture-state&code=fixture HTTP/1.1\r\nHost: example.invalid\r\n\r\n",redirect,@"fixture-state")),@"oauth_callback_bridge_rejects_foreign_target":@(foreign),@"oauth_callback_native_bridge_roundtrip":@(delivered&&[bridgeValue[@"code"] isEqual:@"bridge-fixture"])};
}
