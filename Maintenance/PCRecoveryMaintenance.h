/* Included by PCMaintenance.m after its fixed-path process helpers. */
#include <fcntl.h>
#include <sys/file.h>
#include <sys/sysctl.h>
#include <arpa/inet.h>
#include <sys/socket.h>

static NSArray *RecoveryLabels(void){return @[@"local.agentgo.agent",@"local.agentgo.control",@"local.pocketagent.remote",@"local.pocketagent.root",@"local.pocketagent.screen",@"local.pocketagent.overlay"];}
static NSString *RecoveryDirectory(void){return Physical("/var/mobile/Library/PocketAgentControl");}
static NSString *RecoveryLaunch(void){
#if defined(PC_ROOTHIDE) || defined(PC_ROOTFUL)
    return @"/bin/launchctl"; // Run maps the executable once; never map here too.
#else
    return @"/var/jb/usr/bin/launchctl";
#endif
}
static NSString *RecoveryDaemonDirectory(void){return Physical(PC_JB_EXEC("/Library/LaunchDaemons"));}
static BOOL RecoveryNonce(NSString *value){return [value isKindOfClass:NSString.class]&&value.length==32&&[value rangeOfString:@"[^0-9a-f]" options:NSRegularExpressionSearch].location==NSNotFound;}
static int RecoveryOpenDirectory(NSString *path,uid_t owner){int fd=open(path.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);struct stat st;if(fd<0)return -1;if(fstat(fd,&st)||!S_ISDIR(st.st_mode)||st.st_uid!=owner||(st.st_mode&0022)){close(fd);return -1;}return fd;}
static NSData *RecoveryRead(int directory,const char *name,uid_t owner,mode_t mode,size_t maximum,BOOL fresh,struct stat *identity){
    int fd=openat(directory,name,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);if(fd<0)return nil;struct stat before,after;NSData *result=nil;
    if(!fstat(fd,&before)&&S_ISREG(before.st_mode)&&before.st_uid==owner&&before.st_nlink==1&&(before.st_mode&0777)==mode&&before.st_size>=2&&before.st_size<=(off_t)maximum&&(!fresh||fabs(NSDate.date.timeIntervalSince1970-before.st_mtimespec.tv_sec)<35)){
        NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)before.st_size];size_t offset=0;ssize_t count;
        while(offset<data.length&&(count=read(fd,(char *)data.mutableBytes+offset,data.length-offset))>0)offset+=(size_t)count;
        if(offset==data.length&&!fstat(fd,&after)&&before.st_ino==after.st_ino&&before.st_dev==after.st_dev&&before.st_size==after.st_size&&before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec&&before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec){result=data;if(identity)*identity=before;}
    }close(fd);return result;
}
static BOOL RecoveryAtomic(int directory,const char *name,NSDictionary *value,uid_t owner,mode_t mode){
    NSData *bytes=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];if(!bytes||bytes.length>4*1024*1024)return NO;
    NSString *temporary=[@".asterhand-recovery-" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];int fd=openat(directory,temporary.UTF8String,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW|O_CLOEXEC,0600);if(fd<0)return NO;
    size_t offset=0;ssize_t count;while(offset<bytes.length&&(count=write(fd,(const char *)bytes.bytes+offset,bytes.length-offset))>0)offset+=(size_t)count;
    BOOL ok=offset==bytes.length&&fchown(fd,owner,owner==0?0:501)==0&&fchmod(fd,mode)==0&&fsync(fd)==0;close(fd);
    if(ok)ok=renameat(directory,temporary.UTF8String,directory,name)==0;if(!ok)unlinkat(directory,temporary.UTF8String,0);return ok;
}
static NSDictionary *RecoveryMarker(int directory,struct stat *identity){
    NSData *raw=RecoveryRead(directory,"recovery-request.json",501,0600,1024,YES,identity);id value=raw?[NSJSONSerialization JSONObjectWithData:raw options:0 error:nil]:nil;if(![value isKindOfClass:NSDictionary.class]||[value count]!=3)return nil;
    NSDictionary *request=value;double created=[request[@"created"] isKindOfClass:NSNumber.class]?[request[@"created"] doubleValue]:NAN;double age=NSDate.date.timeIntervalSince1970-created;
    return RecoveryNonce(request[@"nonce"])&&[@[@"restart_services",@"stop_services"] containsObject:request[@"action"]]&&isfinite(created)&&age>=-5&&age<=30?request:nil;
}
static int RecoveryClaim(int directory,NSString *nonce,double now){
    NSData *raw=RecoveryRead(directory,"recovery-ledger.json",0,0600,8192,NO,NULL);NSDictionary *ledger=raw?[NSJSONSerialization JSONObjectWithData:raw options:0 error:nil]:nil;struct stat st;BOOL exists=fstatat(directory,"recovery-ledger.json",&st,AT_SYMLINK_NOFOLLOW)==0;
    if(exists){if(![ledger isKindOfClass:NSDictionary.class]||ledger.count!=2||![ledger[@"last"] isKindOfClass:NSNumber.class]||!isfinite([ledger[@"last"] doubleValue])||![ledger[@"nonces"] isKindOfClass:NSArray.class]||[ledger[@"nonces"] count]>32)return 1;for(id value in ledger[@"nonces"])if(!RecoveryNonce(value))return 1;}
    NSArray *used=ledger[@"nonces"]?:@[];if([used containsObject:nonce]||(ledger&&now-[ledger[@"last"] doubleValue]<10))return 2;NSMutableArray *next=[used mutableCopy];[next addObject:nonce];while(next.count>32)[next removeObjectAtIndex:0];return RecoveryAtomic(directory,"recovery-ledger.json",@{@"last":@(now),@"nonces":next},0,0600)?0:3;
}
static int RecoveryConfigure(void){
    int directory=RecoveryOpenDirectory(RecoveryDaemonDirectory(),0);if(directory<0)return 1;
    // RootHide's launchctl patcher maps these logical absolute paths at bootstrap.
    // Supplying jbroot paths here would apply that mapping twice.
    NSDictionary *job=@{@"Label":@"local.asterhand.recovery",@"UserName":@"root",@"GroupName":@"wheel",@"ProgramArguments":@[@PC_JB_EXEC("/Applications/PocketCodex.app/pocketmaint"),@"recover"],@"RunAtLoad":@NO,@"KeepAlive":@NO,@"WatchPaths":@[@"/var/mobile/Library/PocketAgentControl/recovery-request.json"],@"ThrottleInterval":@10,@"ProcessType":@"Background",@"StandardOutPath":@"/dev/null",@"StandardErrorPath":@"/dev/null"};
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:job format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];if(!data||data.length>8192){close(directory);return 1;}NSString *temp=[@".asterhand-recovery-" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];int fd=openat(directory,temp.UTF8String,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW|O_CLOEXEC,0600);BOOL ok=fd>=0;
    if(ok){size_t offset=0;ssize_t count;while(offset<data.length&&(count=write(fd,(const char *)data.bytes+offset,data.length-offset))>0)offset+=(size_t)count;ok=offset==data.length&&fchown(fd,0,0)==0&&fchmod(fd,0644)==0&&fsync(fd)==0;close(fd);}
    if(ok)ok=renameat(directory,temp.UTF8String,directory,"local.asterhand.recovery.plist")==0;if(!ok)unlinkat(directory,temp.UTF8String,0);close(directory);return ok?0:1;
}
static NSInteger RecoveryAppKind(pid_t pid){
    int mib[3]={CTL_KERN,KERN_PROCARGS2,pid};size_t size=0;if(sysctl(mib,3,NULL,&size,NULL,0)||size<8||size>262144)return 0;char *bytes=calloc(1,size);NSInteger result=0;
    if(bytes&&!sysctl(mib,3,bytes,&size,NULL,0)){int argc=0;memcpy(&argc,bytes,sizeof(argc));char *end=bytes+size,*cursor=bytes+sizeof(argc);if(argc==1)result=1;else if(argc==2){size_t n=strnlen(cursor,(size_t)(end-cursor));cursor+=n;if(cursor<end)cursor++;while(cursor<end&&!*cursor)cursor++;n=strnlen(cursor,(size_t)(end-cursor));cursor+=n;if(cursor<end)cursor++;if(cursor<end){n=strnlen(cursor,(size_t)(end-cursor));if(cursor+n<end){NSString *flag=[[NSString alloc] initWithBytes:cursor length:n encoding:NSUTF8StringEncoding];result=[@[@"--agent-daemon",@"--control-daemon",@"--root-daemon"] containsObject:flag]?2:3;}}}}
    free(bytes);return result;
}
static BOOL RecoveryDaemonArguments(pid_t pid){return RecoveryAppKind(pid)==2;}
static NSArray *RecoveryGUIProcesses(void){
    int bytes=proc_listpids(PROC_ALL_PIDS,0,NULL,0);if(bytes<=0)return @[];pid_t *pids=calloc(1,bytes+4096);int count=proc_listpids(PROC_ALL_PIDS,0,pids,bytes+4096)/(int)sizeof(pid_t);NSMutableArray *found=[NSMutableArray new];NSString *expected=[[App() stringByAppendingPathComponent:@"PocketCodex"] stringByResolvingSymlinksInPath];
    for(int i=0;i<count;i++){char path[PROC_PIDPATHINFO_MAXSIZE]={0};if(pids[i]>1&&proc_pidpath(pids[i],path,sizeof(path))>0&&[[@(path) stringByResolvingSymlinksInPath] isEqual:expected]&&RecoveryAppKind(pids[i])==1)[found addObject:@(pids[i])];}free(pids);return [found sortedArrayUsingSelector:@selector(compare:)];
}
static NSUInteger RecoveryStopServices(void){
    NSString *app=[App() stringByResolvingSymlinksInPath],*prefix=[app stringByAppendingString:@"/"];int bytes=proc_listpids(PROC_ALL_PIDS,0,NULL,0);if(bytes<=0)return 0;pid_t *pids=calloc(1,bytes+4096);int count=proc_listpids(PROC_ALL_PIDS,0,pids,bytes+4096)/(int)sizeof(pid_t);Process *items=calloc(count,sizeof(Process));
    for(int i=0;i<count;i++){struct proc_bsdinfo info;if(pids[i]<=1||pids[i]==getpid()||proc_pidinfo(pids[i],PROC_PIDTBSDINFO,0,&info,sizeof(info))!=sizeof(info))continue;items[i]=(Process){pids[i],info.pbi_ppid,info.pbi_start_tvsec,info.pbi_start_tvusec,NO};char path[PROC_PIDPATHINFO_MAXSIZE]={0};if(proc_pidpath(pids[i],path,sizeof(path))>0){NSString *value=[@(path) stringByResolvingSymlinksInPath];if([value hasPrefix:prefix]&&[[value stringByDeletingLastPathComponent] isEqual:app])items[i].selected=[@[@"pocketoverlay",@"pocketscreen",@"pocketremote"] containsObject:value.lastPathComponent]||([value.lastPathComponent isEqual:@"PocketCodex"]&&RecoveryDaemonArguments(pids[i]));}}
    for(int pass=0;pass<count;pass++){BOOL changed=NO;for(int i=0;i<count;i++)if(items[i].pid&&!items[i].selected)for(int j=0;j<count;j++)if(items[j].selected&&items[i].parent==items[j].pid&&SameProcess(items[j])){items[i].selected=YES;changed=YES;break;}if(!changed)break;}
    NSUInteger selected=0;for(int i=0;i<count;i++)if(items[i].selected&&SameProcess(items[i])){selected++;kill(items[i].pid,SIGTERM);}usleep(300000);for(int i=0;i<count;i++)if(items[i].selected&&SameProcess(items[i]))kill(items[i].pid,SIGKILL);free(items);free(pids);return selected;
}
static BOOL RecoveryCancelPendingTasks(void){
    int directory=RecoveryOpenDirectory(Physical("/var/mobile/Library/AgentGoTasks"),501);if(directory<0)return NO;BOOL ok=YES;double now=NSDate.date.timeIntervalSince1970;NSMutableDictionary *tasks=[NSMutableDictionary new];
    for(NSString *name in @[@"request.json",@"state.json"]){struct stat st;if(fstatat(directory,name.UTF8String,&st,AT_SYMLINK_NOFOLLOW)&&errno==ENOENT)continue;NSData *data=RecoveryRead(directory,name.UTF8String,501,0600,4*1024*1024,NO,NULL);id value=data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil]:nil;if(![value isKindOfClass:NSMutableDictionary.class]){ok=NO;break;}tasks[name]=value;}
    if(ok){NSMutableDictionary *request=tasks[@"request.json"],*state=tasks[@"state.json"];BOOL running=[state[@"running"] boolValue]||[state[@"paused"] boolValue];BOOL queued=request[@"id"]&&![request[@"id"] isEqual:state[@"id"]];
        if(request&&(running||queued)){request[@"cancelled"]=@YES;ok=RecoveryAtomic(directory,"request.json",request,501,0600);}
        if(ok&&running){state[@"cancelled"]=@YES;state[@"running"]=@NO;state[@"paused"]=@NO;state[@"failed"]=@NO;state[@"updated"]=@(now);state[@"revision"]=@([state[@"revision"] unsignedIntegerValue]+1);state[@"status"]=@"任务已停止，正在恢复服务";[state removeObjectForKey:@"question"];ok=RecoveryAtomic(directory,"state.json",state,501,0600);}
    }close(directory);return ok;
}
static BOOL RecoveryJobValid(NSString *label,NSString *file){
    int directory=RecoveryOpenDirectory(RecoveryDaemonDirectory(),0);if(directory<0)return NO;NSData *data=RecoveryRead(directory,file.lastPathComponent.UTF8String,0,0644,16384,NO,NULL);close(directory);NSDictionary *job=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil]:nil;if(![job isKindOfClass:NSDictionary.class]||![job[@"Label"] isEqual:label])return NO;
    NSDictionary *flags=@{@"local.agentgo.agent":@"--agent-daemon",@"local.agentgo.control":@"--control-daemon",@"local.pocketagent.root":@"--root-daemon"};NSString *program=flags[label]?@"PocketCodex":@{@"local.pocketagent.remote":@"pocketremote",@"local.pocketagent.screen":@"pocketscreen",@"local.pocketagent.overlay":@"pocketoverlay"}[label];if(!program)return NO;NSString *path=[App() stringByAppendingPathComponent:program],*logical=[@PC_JB_EXEC("/Applications/PocketCodex.app") stringByAppendingPathComponent:program];NSArray *actual=job[@"ProgramArguments"];NSMutableArray *physical=[NSMutableArray arrayWithObject:path],*virtual=[NSMutableArray arrayWithObject:logical];if(flags[label]){[physical addObject:flags[label]];[virtual addObject:flags[label]];}else if([label isEqual:@"local.pocketagent.remote"]){NSArray *options=@[@"-b",@"0.0.0.0",@"-p",@"5907",@"-n",@"AsterHand iPhone",@"-s",@"0.5",@"-F",@"20",@"-H",@"0",@"-B",@"off",@"-T",@"off",@"-C",@"on",@"-e"];[physical addObjectsFromArray:options];[virtual addObjectsFromArray:options];[physical addObjectsFromArray:@[Physical("/var/mobile/Library/PocketCodexRemote/server.pem"),@"-k",Physical("/var/mobile/Library/PocketCodexRemote/server-key.pem")]];[virtual addObjectsFromArray:@[@"/var/mobile/Library/PocketCodexRemote/server.pem",@"-k",@"/var/mobile/Library/PocketCodexRemote/server-key.pem"]];}if(![actual isKindOfClass:NSArray.class]||actual.count!=physical.count)return NO;for(NSUInteger i=0;i<actual.count;i++)if(![actual[i] isEqual:physical[i]]&&![actual[i] isEqual:virtual[i]])return NO;return YES;
}
static int RecoveryLaunchArguments(NSArray *arguments,double timeout){
    NSMutableArray *strings=[NSMutableArray arrayWithObject:RecoveryLaunch()];[strings addObjectsFromArray:arguments];char **argv=calloc(strings.count+1,sizeof(char *));for(NSUInteger i=0;i<strings.count;i++)argv[i]=(char *)[strings[i] fileSystemRepresentation];int result=Run(argv,timeout);free(argv);return result;
}
static BOOL RecoveryPortOpen(uint16_t port){int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return YES;struct sockaddr_in address={0};address.sin_len=sizeof(address);address.sin_family=AF_INET;address.sin_port=htons(port);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);BOOL open=connect(fd,(struct sockaddr *)&address,sizeof(address))==0;close(fd);return open;}
static int RecoveryRun(void){
    int directory=RecoveryOpenDirectory(RecoveryDirectory(),501);if(directory<0)return 1;struct stat markerIdentity;NSDictionary *request=RecoveryMarker(directory,&markerIdentity);if(!request){close(directory);return 0;}NSString *nonce=request[@"nonce"];int private=RecoveryOpenDirectory(Physical(PC_PRIVILEGED_DIRECTORY),0);if(private<0){close(directory);return 1;}
    int lock=openat(private,"recovery.lock",O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);struct stat st;BOOL locked=lock>=0&&!fstat(lock,&st)&&S_ISREG(st.st_mode)&&st.st_uid==0&&st.st_nlink==1&&(st.st_mode&0777)==0600&&flock(lock,LOCK_EX|LOCK_NB)==0;NSMutableDictionary *result=[@{@"nonce":nonce,@"done":@YES,@"ok":@NO,@"detail":@"恢复请求未通过验证"} mutableCopy];int exitCode=1;
    if(!locked){result[@"detail"]=@"另一项恢复正在运行，请稍后重试";goto finished;}
    {int claim=RecoveryClaim(private,nonce,NSDate.date.timeIntervalSince1970);if(claim){result[@"detail"]=claim==2?@"请求已处理或操作过于频繁，请稍后重新确认":@"恢复记录不可安全读写，未执行任何重启";goto finished;}}
    if(!RecoveryCancelPendingTasks()){result[@"detail"]=@"任务状态不可安全更新，未重启服务";goto finished;}
    if([request[@"action"] isEqual:@"stop_services"]){
        BOOL valid=YES;for(NSString *label in RecoveryLabels()){NSString *file=[RecoveryDaemonDirectory() stringByAppendingPathComponent:[label stringByAppendingString:@".plist"]];if(!RecoveryJobValid(label,file)){valid=NO;break;}}
        if(!valid){result[@"detail"]=@"服务配置无法验证，未关闭服务";goto finished;}
        BOOL stopped=YES;NSMutableArray *services=[NSMutableArray new];for(NSString *label in RecoveryLabels()){NSString *job=[@"system/" stringByAppendingString:label];int code=RecoveryLaunchArguments(@[@"disable",job],3);int unload=RecoveryLaunchArguments(@[@"bootout",job],8);stopped=stopped&&code==0;[services addObject:@{@"label":label,@"disabled":@(code==0),@"unloaded":@(unload==0)}];}
        result[@"owned_service_processes_stopped"]=@(RecoveryStopServices());usleep(2000000);NSUInteger returned=RecoveryStopServices();BOOL portsClosed=!RecoveryPortOpen(18769)&&!RecoveryPortOpen(5907);stopped=stopped&&returned==0&&portsClosed;
        result[@"services"]=services;result[@"returned_processes"]=@(returned);result[@"ports_closed"]=@(portsClosed);result[@"done"]=@YES;result[@"ok"]=@(stopped);result[@"detail"]=stopped?@"服务已关闭，项目和授权已保留":@"部分服务未能关闭，请检查后重试";
        if(stopped){if(RecoveryAtomic(directory,"services-master.json",@{@"enabled":@NO},501,0600))exitCode=0;else{result[@"ok"]=@NO;result[@"detail"]=@"服务已停止，但状态保存失败，请重新开启并检查";}}goto finished;
    }
    result[@"done"]=@NO;result[@"detail"]=@"正在停止任务并恢复服务";result[@"gui_pids_before"]=RecoveryGUIProcesses();RecoveryAtomic(directory,"recovery-result.json",result,501,0600);result[@"owned_service_processes_stopped"]=@(RecoveryStopServices());
    if(!RecoveryCancelPendingTasks()){result[@"done"]=@YES;result[@"detail"]=@"任务状态发生并发变化，请检查后重新确认恢复";goto finished;}
    {NSMutableArray *services=[NSMutableArray new];BOOL all=YES;double until=Now()+95;for(NSString *label in RecoveryLabels()){
        NSString *job=[@"system/" stringByAppendingString:label],*file=[RecoveryDaemonDirectory() stringByAppendingPathComponent:[label stringByAppendingString:@".plist"]],*bootstrapFile=[@PC_JB_EXEC("/Library/LaunchDaemons") stringByAppendingPathComponent:[label stringByAppendingString:@".plist"]];BOOL valid=RecoveryJobValid(label,file);int code=1;if(valid&&Now()<until){RecoveryLaunchArguments(@[@"enable",job],3);code=RecoveryLaunchArguments(@[@"kickstart",@"-k",job],12);if(code&&Now()<until){int bootstrap=RecoveryLaunchArguments(@[@"bootstrap",@"system",bootstrapFile],12);if(bootstrap==0&&Now()<until)code=RecoveryLaunchArguments(@[@"kickstart",@"-k",job],12);}}
        BOOL ready=valid&&code==0;all=all&&ready;[services addObject:@{@"label":label,@"restarted":@(ready),@"exit":@(code)}];result[@"services"]=services;result[@"detail"]=[NSString stringWithFormat:@"正在恢复服务（%lu/%lu）",(unsigned long)services.count,(unsigned long)RecoveryLabels().count];RecoveryAtomic(directory,"recovery-result.json",result,501,0600);
    }result[@"gui_pids_after"]=RecoveryGUIProcesses();if([result[@"gui_pids_before"] count]>0)result[@"gui_process_preserved"]=@([result[@"gui_pids_before"] isEqual:result[@"gui_pids_after"]]);result[@"done"]=@YES;result[@"ok"]=@(all);result[@"detail"]=all?@"所有服务已重启，项目和配对已保留":@"部分服务未能恢复，请查看结果后重试";if(all)RecoveryAtomic(directory,"services-master.json",@{@"enabled":@YES},501,0600);exitCode=all?0:1;}
finished:
    result[@"completed"]=@(NSDate.date.timeIntervalSince1970);RecoveryAtomic(directory,"recovery-result.json",result,501,0600);struct stat current;if(fstatat(directory,"recovery-request.json",&current,AT_SYMLINK_NOFOLLOW)==0&&current.st_ino==markerIdentity.st_ino&&current.st_dev==markerIdentity.st_dev)unlinkat(directory,"recovery-request.json",0);if(lock>=0)close(lock);close(private);close(directory);return exitCode;
}
static int RecoverySelfTest(void){
    int parent=RecoveryOpenDirectory(Physical(PC_PRIVILEGED_DIRECTORY),0);if(parent<0)return 1;NSString *name=[@"recovery-qa-" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];if(mkdirat(parent,name.UTF8String,0700)){close(parent);return 1;}int directory=openat(parent,name.UTF8String,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);NSMutableDictionary *checks=[NSMutableDictionary new];
    @try {
        double now=NSDate.date.timeIntervalSince1970;NSString *nonce=@"0123456789abcdef0123456789abcdef",*next=@"fedcba9876543210fedcba9876543210";NSDictionary *valid=@{@"nonce":nonce,@"created":@(now),@"action":@"restart_services"};
        RecoveryAtomic(directory,"recovery-request.json",valid,501,0600);checks[@"valid_marker"]=@(RecoveryMarker(directory,NULL)!=nil);
        NSMutableDictionary *stop=[valid mutableCopy];stop[@"action"]=@"stop_services";RecoveryAtomic(directory,"recovery-request.json",stop,501,0600);checks[@"valid_stop_marker"]=@(RecoveryMarker(directory,NULL)!=nil);RecoveryAtomic(directory,"recovery-request.json",valid,501,0600);
        fchmodat(directory,"recovery-request.json",0644,0);checks[@"rejects_world_readable_marker"]=@(RecoveryMarker(directory,NULL)==nil);RecoveryAtomic(directory,"recovery-request.json",valid,0,0600);checks[@"rejects_wrong_owner"]=@(RecoveryMarker(directory,NULL)==nil);
        RecoveryAtomic(directory,"target.json",valid,501,0600);unlinkat(directory,"recovery-request.json",0);symlinkat("target.json",directory,"recovery-request.json");checks[@"rejects_symlink"]=@(RecoveryMarker(directory,NULL)==nil);unlinkat(directory,"recovery-request.json",0);linkat(directory,"target.json",directory,"recovery-request.json",0);checks[@"rejects_hardlink"]=@(RecoveryMarker(directory,NULL)==nil);unlinkat(directory,"recovery-request.json",0);unlinkat(directory,"target.json",0);
        NSMutableDictionary *bad=[valid mutableCopy];bad[@"created"]=@(now-31);RecoveryAtomic(directory,"recovery-request.json",bad,501,0600);checks[@"rejects_stale_request"]=@(RecoveryMarker(directory,NULL)==nil);bad[@"created"]=@(now+6);RecoveryAtomic(directory,"recovery-request.json",bad,501,0600);checks[@"rejects_future_request"]=@(RecoveryMarker(directory,NULL)==nil);
        bad=[valid mutableCopy];bad[@"action"]=@"restart_services; id";RecoveryAtomic(directory,"recovery-request.json",bad,501,0600);checks[@"rejects_arbitrary_action"]=@(RecoveryMarker(directory,NULL)==nil);bad=[valid mutableCopy];bad[@"command"]=@"id";RecoveryAtomic(directory,"recovery-request.json",bad,501,0600);checks[@"rejects_extra_command_field"]=@(RecoveryMarker(directory,NULL)==nil);
        bad=[valid mutableCopy];bad[@"nonce"]=@"../../not-a-nonce";RecoveryAtomic(directory,"recovery-request.json",bad,501,0600);checks[@"rejects_invalid_nonce"]=@(RecoveryMarker(directory,NULL)==nil);bad=[valid mutableCopy];bad[@"padding"]=[@"x" stringByPaddingToLength:2048 withString:@"x" startingAtIndex:0];RecoveryAtomic(directory,"recovery-request.json",bad,501,0600);checks[@"rejects_oversize_marker"]=@(RecoveryMarker(directory,NULL)==nil);
        checks[@"claim_once"]=@(RecoveryClaim(directory,nonce,now)==0);checks[@"rejects_nonce_replay"]=@(RecoveryClaim(directory,nonce,now+11)==2);checks[@"rejects_rapid_retry"]=@(RecoveryClaim(directory,next,now+1)==2);checks[@"allows_new_explicit_retry"]=@(RecoveryClaim(directory,next,now+11)==0);RecoveryAtomic(directory,"recovery-ledger.json",@{@"bad":@YES},0,0600);checks[@"rejects_corrupt_ledger"]=@(RecoveryClaim(directory,nonce,now+30)==1);
        checks[@"fixed_service_scope"]=@(RecoveryLabels().count==6&&![RecoveryLabels() containsObject:@"local.asterhand.recovery"]);
        BOOL jobs=YES;for(NSString *label in RecoveryLabels())jobs=jobs&&RecoveryJobValid(label,[RecoveryDaemonDirectory() stringByAppendingPathComponent:[label stringByAppendingString:@".plist"]]);checks[@"installed_fixed_service_arguments_valid"]=@(jobs);
        int launch=RecoveryOpenDirectory(RecoveryDaemonDirectory(),0);NSData *raw=launch>=0?RecoveryRead(launch,"local.asterhand.recovery.plist",0,0644,16384,NO,NULL):nil;if(launch>=0)close(launch);NSDictionary *configuration=raw?[NSPropertyListSerialization propertyListWithData:raw options:NSPropertyListImmutable format:nil error:nil]:nil;NSArray *program=configuration[@"ProgramArguments"],*watch=configuration[@"WatchPaths"];checks[@"installed_recovery_paths_mapped_once"]=@(program.count==2&&([program[0] isEqual:[App() stringByAppendingPathComponent:@"pocketmaint"]]||[program[0] isEqual:@PC_JB_EXEC("/Applications/PocketCodex.app/pocketmaint")])&&watch.count==1&&([watch[0] isEqual:[RecoveryDirectory() stringByAppendingPathComponent:@"recovery-request.json"]]||[watch[0] isEqual:@"/var/mobile/Library/PocketAgentControl/recovery-request.json"]));
    }@catch(NSException *exception){checks[@"fixture_error"]=@NO;}
    for(NSString *file in @[@"recovery-request.json",@"recovery-ledger.json",@"target.json"])unlinkat(directory,file.UTF8String,0);close(directory);unlinkat(parent,name.UTF8String,AT_REMOVEDIR);close(parent);BOOL success=checks.count>0;for(NSNumber *value in checks.allValues)success=success&&value.boolValue;checks[@"success"]=@(success);NSData *json=[NSJSONSerialization dataWithJSONObject:checks options:0 error:nil];puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);return success?0:1;
}
