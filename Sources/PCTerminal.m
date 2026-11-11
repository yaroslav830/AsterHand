#import "PCTerminal.h"
#import "PCPlatform.h"
#import "PCRuntimePaths.h"
#import "PCSupport.h"
#include <spawn.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>

@interface PCCommandSession : NSObject
@property pid_t pid;
@property int input;
@property int output;
@property BOOL ended;
@property NSUInteger base;
@property NSTimeInterval used;
@property(copy) NSString *owner;
@property(strong) NSMutableData *buffer;
@end
@implementation PCCommandSession
- (void)dealloc {
    if (_pid>1) {pid_t pid=_pid;kill(-pid,SIGKILL);kill(pid,SIGKILL);if(waitpid(pid,NULL,WNOHANG)==0)dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{for(int i=0;i<100;i++){if(waitpid(pid,NULL,WNOHANG)!=0)break;usleep(10000);}});}
    if(_input>=0)close(_input);if(_output>=0)close(_output);
}
@end
static NSMutableDictionary *Sessions(void) {static NSMutableDictionary *items;static dispatch_once_t once;dispatch_once(&once,^{items=[NSMutableDictionary new];});return items;}
void PCTerminalStartMaintenance(void) {
    static dispatch_source_t timer;static dispatch_once_t once;dispatch_once(&once,^{timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,NSEC_PER_SEC/10);dispatch_source_set_event_handler(timer,^{@synchronized(Sessions()){NSTimeInterval now=NSDate.date.timeIntervalSince1970;for(NSString *key in Sessions().allKeys)if(now-[(PCCommandSession *)Sessions()[key] used]>1200)[Sessions() removeObjectForKey:key];}});dispatch_resume(timer);});
}
void PCTerminalCloseOwner(NSString *owner) { @synchronized(Sessions()) {for(NSString *key in Sessions().allKeys)if([owner isEqual:@"*"]||[[(PCCommandSession *)Sessions()[key] owner] isEqual:owner])[Sessions() removeObjectForKey:key];} }
NSDictionary *PCTerminalRequest(NSString *action, NSDictionary *args, NSString *owner) {
    PCTerminalStartMaintenance();
    @synchronized(Sessions()) {
        NSTimeInterval now=NSDate.date.timeIntervalSince1970;
        for(NSString *key in Sessions().allKeys)if(now-[(PCCommandSession *)Sessions()[key] used]>1200)[Sessions() removeObjectForKey:key];
        if([action isEqual:@"open"]) {
            if(Sessions().count>=8)return @{@"error":@"终端会话数量已达上限"};
            int inFD[2],outFD[2];if(pipe(inFD))return @{@"error":@"无法创建终端输入"};if(pipe(outFD)){close(inFD[0]);close(inFD[1]);return @{@"error":@"无法创建终端输出"};}
            for(int i=0;i<2;i++){fcntl(inFD[i],F_SETFD,FD_CLOEXEC);fcntl(outFD[i],F_SETFD,FD_CLOEXEC);}
            posix_spawn_file_actions_t a;posix_spawn_file_actions_init(&a);
            posix_spawn_file_actions_adddup2(&a,inFD[0],0);posix_spawn_file_actions_adddup2(&a,outFD[1],1);posix_spawn_file_actions_adddup2(&a,outFD[1],2);
            for(int i=0;i<2;i++){posix_spawn_file_actions_addclose(&a,inFD[i]);posix_spawn_file_actions_addclose(&a,outFD[i]);}
            NSString *shell=PCShellPath();NSString *cwd=[args[@"cwd"] isKindOfClass:NSString.class]?args[@"cwd"]:PCWorkspace();
            if(!cwd.isAbsolutePath||cwd.length>4096){posix_spawn_file_actions_destroy(&a);for(int i=0;i<2;i++){close(inFD[i]);close(outFD[i]);}return @{@"error":@"工作目录无效"};}
            char *argv[]={(char *)shell.fileSystemRepresentation,"-c","cd -- \"$1\" && exec \"$2\" -s","agentgo",(char *)PCRealPath(cwd).fileSystemRepresentation,(char *)shell.fileSystemRepresentation,NULL};
            char *env[]={PC_PROCESS_PATH,"HOME=/var/mobile","LANG=en_US.UTF-8","_MSSafeMode=1","_SafeMode=1","DISABLE_TWEAKS=1",NULL};
            posix_spawnattr_t attr;posix_spawnattr_init(&attr);sigset_t empty;sigemptyset(&empty);posix_spawnattr_setsigmask(&attr,&empty);posix_spawnattr_setpgroup(&attr,0);posix_spawnattr_setflags(&attr,POSIX_SPAWN_SETPGROUP|POSIX_SPAWN_SETSIGMASK);
            pid_t pid=0;int status=shell?posix_spawn(&pid,shell.fileSystemRepresentation,&a,&attr,argv,env):ENOENT;posix_spawnattr_destroy(&attr);
            posix_spawn_file_actions_destroy(&a);close(inFD[0]);close(outFD[1]);
            if(status){close(inFD[1]);close(outFD[0]);return @{@"error":@(strerror(status))};}
            fcntl(inFD[1],F_SETFL,O_NONBLOCK);fcntl(outFD[0],F_SETFL,O_NONBLOCK);
            PCCommandSession *s=[PCCommandSession new];s.pid=pid;s.input=inFD[1];s.output=outFD[0];s.owner=owner;s.buffer=[NSMutableData new];s.used=now;
            NSString *identifier=NSUUID.UUID.UUIDString.lowercaseString;Sessions()[identifier]=s;
            return @{@"session":identifier,@"mode":@"persistent-command-shell",@"uid":@(geteuid())};
        }
        NSString *identifier=[args[@"session"] isKindOfClass:NSString.class]?args[@"session"]:@"";
        PCCommandSession *s=Sessions()[identifier];if(!s||![s.owner isEqual:owner])return @{@"error":@"终端不存在或已过期"};s.used=now;
        if([action isEqual:@"close"]){[Sessions() removeObjectForKey:identifier];return @{@"closed":@YES};}
        if([action isEqual:@"interrupt"]){[Sessions() removeObjectForKey:identifier];return @{@"interrupted":@YES,@"ended":@YES};}
        if([action isEqual:@"write"]){NSData *bytes=[args[@"text"] isKindOfClass:NSString.class]?[args[@"text"] dataUsingEncoding:NSUTF8StringEncoding]:nil;if(!bytes||bytes.length>32768||s.ended)return @{@"error":@"输入无效或终端已结束"};ssize_t count=write(s.input,bytes.bytes,bytes.length);return count==(ssize_t)bytes.length?@{@"written":@YES}:@{@"error":@"终端忙，请减少输入；部分内容可能已写入"};}
        if(![action isEqual:@"read"])return @{@"error":@"未知终端操作"};
        char buf[8192];ssize_t count;NSUInteger drained=0;
        while(drained<262144&&(count=read(s.output,buf,sizeof(buf)))>0){[s.buffer appendBytes:buf length:count];drained+=(NSUInteger)count;}
        if(s.buffer.length>262144){NSUInteger drop=s.buffer.length-262144;[s.buffer replaceBytesInRange:NSMakeRange(0,drop) withBytes:NULL length:0];s.base+=drop;}
        int result=0;if(!s.ended&&waitpid(s.pid,&result,WNOHANG)==s.pid){kill(-s.pid,SIGKILL);s.ended=YES;s.pid=0;}
        NSUInteger offset=[args[@"offset"] unsignedIntegerValue],start=offset>s.base?MIN(offset-s.base,s.buffer.length):0;
        NSData *out=[s.buffer subdataWithRange:NSMakeRange(start,s.buffer.length-start)];
        NSString *text=[[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding]?:[[NSString alloc] initWithData:out encoding:NSISOLatin1StringEncoding]?:@"";
        return @{@"output":text,@"next_offset":@(s.base+s.buffer.length),@"truncated":@(offset<s.base),@"ended":@(s.ended)};
    }
}
