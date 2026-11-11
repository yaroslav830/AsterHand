#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "PCRuntimePaths.h"
#include <libproc.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <signal.h>
#include <spawn.h>
#include <unistd.h>
#include <time.h>
#include <math.h>
#include <grp.h>
extern char **environ;

static NSString *Physical(const char *path){return @(jbroot(path));}
static NSString *App(void){return Physical(PC_JB_EXEC("/Applications/PocketCodex.app"));}
static double Now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static int Run(char **args,double timeout){
    double start=Now();pid_t pid=0;posix_spawnattr_t attr;posix_spawnattr_init(&attr);posix_spawnattr_setflags(&attr,POSIX_SPAWN_SETPGROUP);posix_spawnattr_setpgroup(&attr,0);
    NSString *executable=Physical(args[0]);
    int error=posix_spawn(&pid,executable.fileSystemRepresentation,NULL,&attr,args,environ);posix_spawnattr_destroy(&attr);if(error){fprintf(stderr,"AsterHand maintenance: spawn error=%d %s\n",error,args[0]);return error;}
    int status=0;while(waitpid(pid,&status,WNOHANG)==0){if(Now()-start>timeout){kill(-pid,SIGTERM);usleep(100000);kill(-pid,SIGKILL);waitpid(pid,&status,0);fprintf(stderr,"AsterHand maintenance: timeout %.2fs %s\n",Now()-start,args[0]);return 124;}usleep(20000);}
    int result=WIFEXITED(status)?WEXITSTATUS(status):128+WTERMSIG(status);fprintf(stderr,"AsterHand maintenance: %.2fs exit=%d %s\n",Now()-start,result,args[0]);return result;
}
typedef struct {pid_t pid,parent;uint64_t sec,usec;BOOL selected;} Process;
static BOOL SameProcess(Process p){struct proc_bsdinfo info;return proc_pidinfo(p.pid,PROC_PIDTBSDINFO,0,&info,sizeof(info))==sizeof(info)&&info.pbi_start_tvsec==p.sec&&info.pbi_start_tvusec==p.usec;}
static int Stop(BOOL dry){
    NSString *app=[App() stringByResolvingSymlinksInPath],*prefix=[app stringByAppendingString:@"/"];NSArray *names=@[@"PocketCodex",@"pocketoverlay",@"pocketscreen",@"pocketremote"];
    int bytes=proc_listpids(PROC_ALL_PIDS,0,NULL,0);if(bytes<=0)return 1;pid_t *pids=calloc(1,bytes+4096);int count=proc_listpids(PROC_ALL_PIDS,0,pids,bytes+4096)/(int)sizeof(pid_t);Process *items=calloc(count,sizeof(Process));
    for(int i=0;i<count;i++){
        struct proc_bsdinfo info;if(pids[i]<=1||pids[i]==getpid()||proc_pidinfo(pids[i],PROC_PIDTBSDINFO,0,&info,sizeof(info))!=sizeof(info))continue;
        items[i]=(Process){pids[i],info.pbi_ppid,info.pbi_start_tvsec,info.pbi_start_tvusec,NO};char path[PROC_PIDPATHINFO_MAXSIZE]={0};
        if(proc_pidpath(pids[i],path,sizeof(path))>0){NSString *value=[@(path) stringByResolvingSymlinksInPath];items[i].selected=[value hasPrefix:prefix]&&[names containsObject:value.lastPathComponent]&&[[value stringByDeletingLastPathComponent] isEqual:app];}
    }
    // Include only descendants of our exact executables, never processes that
    // merely share a name. Start timestamps protect against PID reuse.
    for(int pass=0;pass<count;pass++){BOOL changed=NO;for(int i=0;i<count;i++)if(items[i].pid&&!items[i].selected)for(int j=0;j<count;j++)if(items[j].selected&&items[i].parent==items[j].pid){items[i].selected=YES;changed=YES;break;}if(!changed)break;}
    int selected=0;for(int i=0;i<count;i++)if(items[i].selected&&SameProcess(items[i])){selected++;if(!dry)kill(items[i].pid,SIGTERM);}
    if(!dry){double until=Now()+.8;while(Now()<until){BOOL alive=NO;for(int i=0;i<count;i++)if(items[i].selected&&SameProcess(items[i]))alive=YES;if(!alive)break;usleep(20000);}for(int i=0;i<count;i++)if(items[i].selected&&SameProcess(items[i]))kill(items[i].pid,SIGKILL);}
    printf("owned_processes=%d dry_run=%d\n",selected,dry);free(items);free(pids);return 0;
}
static BOOL Remove(NSString *path){struct stat info;if(lstat(path.fileSystemRepresentation,&info)&&errno==ENOENT)return YES;NSError *error=nil;BOOL ok=[NSFileManager.defaultManager removeItemAtPath:path error:&error];if(!ok)fprintf(stderr,"AsterHand cleanup: %s: %s\n",path.UTF8String,error.localizedDescription.UTF8String);return ok;}
static NSDictionary *ReadJSON(NSString *path){NSData *bytes=[NSData dataWithContentsOfFile:path];id value=bytes.length<4*1024*1024?[NSJSONSerialization JSONObjectWithData:bytes?:[NSData data] options:0 error:nil]:nil;return [value isKindOfClass:NSDictionary.class]?value:@{};}
static int MobileCleanup(BOOL inspect){
    NSDictionary *query=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"local.pocketcodex.api",(__bridge id)kSecAttrAccessGroup:@"local.pocketcodex"};
    if(inspect){NSMutableDictionary *q=[query mutableCopy];q[(__bridge id)kSecReturnAttributes]=@YES;q[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitAll;CFTypeRef result=NULL;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)q,&result);id items=CFBridgingRelease(result);printf("credential_items=%lu status=%d\n",(unsigned long)([items isKindOfClass:NSArray.class]?[items count]:0),(int)status);return status==errSecSuccess||status==errSecItemNotFound?0:1;}
    OSStatus status=SecItemDelete((__bridge CFDictionaryRef)query);[NSUserDefaults.standardUserDefaults removePersistentDomainForName:@"local.pocketcodex"];[NSUserDefaults.standardUserDefaults synchronize];
    printf("credentials_removed=%d\n",status==errSecSuccess||status==errSecItemNotFound);return status==errSecSuccess||status==errSecItemNotFound?0:1;
}
static int Cleanup(void){
    NSDictionary *choice=ReadJSON(Physical("/var/mobile/Library/PocketAgentControl/uninstall-choice.json"));BOOL fresh=[choice[@"created"] isKindOfClass:NSNumber.class]&&fabs(NSDate.date.timeIntervalSince1970-[choice[@"created"] doubleValue])<86400;
    BOOL projects=fresh&&[choice[@"delete_projects"] isEqual:@YES],files=fresh&&[choice[@"delete_files"] isEqual:@YES];
    NSString *support=Physical("/var/mobile/Library/Application Support/PocketAgent");NSDictionary *store=ReadJSON([support stringByAppendingPathComponent:@"projects.json"]);NSMutableSet *workspaces=[NSMutableSet setWithObject:@"/var/mobile/Documents/PocketCodex"];
    for(NSDictionary *project in [store[@"projects"] isKindOfClass:NSArray.class]?store[@"projects"]:@[])if([project[@"workspace"] isKindOfClass:NSString.class])[workspaces addObject:project[@"workspace"]];
    NSString *documents=[Physical("/var/mobile/Documents") stringByResolvingSymlinksInPath];BOOL ok=YES;NSUInteger removed=0,protected=0;
    if(files)for(NSString *workspace in workspaces){NSString *physical=Physical(workspace.fileSystemRepresentation),*resolved=[physical stringByResolvingSymlinksInPath];if(![resolved hasPrefix:[documents stringByAppendingString:@"/"]]){protected++;continue;}if([NSFileManager.defaultManager fileExistsAtPath:resolved]){ok=Remove(resolved)&&ok;removed++;}}
    if(projects)ok=Remove(support)&&ok;
    NSString *helper=[App() stringByAppendingPathComponent:@"pocketmaint"];char *args[]={(char *)helper.fileSystemRepresentation,"mobile-cleanup",NULL};int mobile=Run(args,10);ok=mobile==0&&ok;
    for(NSString *relative in @[@"/var/mobile/Library/PocketCodexRemote",@"/var/mobile/Library/PocketAgentControl",@"/var/mobile/Library/AgentGoControl",@"/var/mobile/Library/AgentGoTasks",@"/var/mobile/Library/Preferences/local.pocketcodex.plist",@"/var/mobile/Library/Caches/local.pocketcodex",@"/var/mobile/Library/Logs/AsterHand",@"/var/mobile/Library/WebKit/local.pocketcodex",@"/var/mobile/Library/Saved Application State/local.pocketcodex.savedState",@"/var/mobile/Library/Cookies/local.pocketcodex.binarycookies",@"/var/mobile/.pocketagent-screen.sock"])ok=Remove(Physical(relative.fileSystemRepresentation))&&ok;
    NSString *private=Physical(PC_PRIVILEGED_DIRECTORY);
#ifdef PC_ROOTHIDE
    for(NSString *name in @[@"root.sock",@"enabled",@"asterhand-overlay.lock",@"recovery.lock",@"recovery-ledger.json"])ok=Remove([private stringByAppendingPathComponent:name])&&ok;
    rmdir(private.fileSystemRepresentation);
#else
    ok=Remove(private)&&ok;
#endif
    printf("cleanup_projects=%d cleanup_files=%d workspaces_removed=%lu external_workspaces_preserved=%lu\n",projects,files,(unsigned long)removed,(unsigned long)protected);return ok?0:1;
}
#include "PCRecoveryMaintenance.h"
int main(int argc,char **argv){
    if(argc<2)return 64;
    BOOL mobile=strcmp(argv[1],"mobile-cleanup")==0||strcmp(argv[1],"mobile-inspect")==0;
    if(mobile&&geteuid()==0){gid_t group=501;if(setgroups(1,&group)||setgid(501)||setuid(501))return 77;setenv("HOME",jbroot("/var/mobile"),1);}
    if(!mobile&&geteuid()!=0)return 77;
    @autoreleasepool {
        if(mobile)return MobileCleanup(strcmp(argv[1],"mobile-inspect")==0);
        if(argc==2&&strcmp(argv[1],"recover-configure")==0)return RecoveryConfigure();
        if(argc==2&&strcmp(argv[1],"recover")==0)return RecoveryRun();
        if(argc==2&&strcmp(argv[1],"recover-selftest")==0)return RecoverySelfTest();
        if(strcmp(argv[1],"stop")==0)return Stop(NO);
        if(strcmp(argv[1],"inspect")==0)return Stop(YES);
        if(strcmp(argv[1],"cleanup")==0)return Cleanup();
        if(strcmp(argv[1],"run")==0&&argc>=5){double timeout=atof(argv[2]);if(timeout<1||timeout>120||argv[3][0]!='/')return 64;return Run(argv+3,timeout);}
    }
    return 64;
}
