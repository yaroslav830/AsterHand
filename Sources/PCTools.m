#import "PCTools.h"
#import "PCSupport.h"
#import "PCProcess.h"
#import "PCPlatform.h"
#import "PCRoot.h"
#import "PCScreen.h"
#import "PCControl.h"
#import <sys/stat.h>
#import <sys/utsname.h>
#import <unistd.h>
#import <errno.h>
#import <fcntl.h>
#import <limits.h>

static int cancelled(void *context) {
    PCTools *tools = (__bridge PCTools *)context;
    return tools.cancelled || (tools.cancellationCheck && tools.cancellationCheck());
}

@implementation PCTools

- (NSDictionary *)failure:(NSString *)reason { return @{@"error": reason ?: @"操作失败"}; }

- (NSString *)path:(id)value {
    if (![value isKindOfClass:NSString.class] || ![value length] || [value rangeOfString:@"\0"].location != NSNotFound) return nil;
    NSString *path = [value isAbsolutePath] ? value : [self.workspace stringByAppendingPathComponent:value];
    return PCRealPath([path stringByStandardizingPath]);
}

- (NSDictionary *)diagnostics {
    struct utsname u;
    uname(&u);
    NSString *shellPath = PCShellPath();
    NSString *shell = shellPath && access(shellPath.fileSystemRepresentation, X_OK) == 0 ? shellPath : @"";
    return @{@"device": @(u.machine), @"kernel": @(u.release), @"uid": @(getuid()), @"euid": @(geteuid()),
             @"environment": PCEnvironmentName(),
             @"jailbreak_root_present": @([[NSFileManager defaultManager] fileExistsAtPath:(PCIsRootHide()||PCIsRootful()) ? PCRealPath(@"/") : @"/var/jb"]),
             @"physical_workspace": PCRealPath(self.workspace ?: PCWorkspace()),
             @"path_rules": PCPathExplanation(),
             @"shell": shell, @"workspace": self.workspace ?: PCWorkspace(),
             @"note": self.rootEnabled ? @"Root 开关已开启；经确认的文件和命令工具通过本机 Root 服务执行。" : @"本地命令以当前 App 用户运行；Root 开关关闭。文件工具和 shell 未被限制在工作目录内。"};
}

- (NSDictionary *)execute:(NSString *)name arguments:(NSDictionary *)args {
    if (self.cancelled) return [self failure:@"任务已停止"];
    if (![args isKindOfClass:NSDictionary.class]) return [self failure:@"工具参数必须是对象"];
    if ([name isEqual:@"list_remote_devices"]) {
        NSMutableArray *peers=[NSMutableArray new];for(NSDictionary *p in PCControlState()[@"peers"])if([p[@"host"] length]&&![p[@"incoming"] boolValue])[peers addObject:@{@"id":p[@"id"],@"name":p[@"name"],@"host":p[@"host"]}];return @{@"devices":peers};
    }
    if ([name isEqual:@"remote_execute"]) {
        if (![args[@"device_id"] isKindOfClass:NSString.class]||![args[@"tool"] isKindOfClass:NSString.class]||![args[@"arguments_json"] isKindOfClass:NSString.class])return [self failure:@"远端参数无效"];
        NSDictionary *a=[NSJSONSerialization JSONObjectWithData:[args[@"arguments_json"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (![a isKindOfClass:NSDictionary.class])return [self failure:@"arguments_json 必须为 JSON 对象"];
        return PCControlRequest(args[@"device_id"],@"execute",@{@"tool":args[@"tool"],@"arguments":a,@"actor":@"ai"},^BOOL{return self.cancelled;});
    }
    if ([name hasPrefix:@"screen_"]) {
        if (!(self.screenPermission ? self.screenPermission.boolValue : [NSUserDefaults.standardUserDefaults boolForKey:@"aiScreenEnabled"])) return [self failure:@"AI 屏幕操作开关已关闭。"];
        NSString *action = @{ @"screen_capture":@"capture", @"screen_tap":@"tap", @"screen_swipe":@"swipe", @"screen_type":@"type", @"screen_home":@"home" }[name];
        if (!action) return [self failure:@"未知屏幕工具。"];
        NSMutableDictionary *request = [args mutableCopy];
        request[@"action"] = action;
        if([action isEqual:@"capture"])request[@"fresh"]=@YES;
        return PCScreenRequest(request);
    }
    if (self.rootEnabled) return PCSendRootRequestWithCancellation(@{@"action":@"execute", @"name":name ?: @"", @"args":args,
        @"workspace":self.workspace ?: PCWorkspace()}, 125, ^BOOL { return cancelled((__bridge void *)self); });
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([name isEqual:@"run_shell"]) {
        if (![args[@"command"] isKindOfClass:NSString.class] || ![args[@"timeout_seconds"] isKindOfClass:NSNumber.class]) return [self failure:@"command / timeout_seconds 类型错误"];
        NSString *command = [args[@"command"] stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
        if (!command.length || command.length > 32768 || [command rangeOfString:@"\0"].location != NSNotFound) return [self failure:@"命令为空、包含 NUL 或过长"];
        NSString *shell = PCShellPath();
        if (!shell || access(shell.fileSystemRepresentation, X_OK) != 0) return [self failure:@"找不到当前越狱环境的 shell。请确认已越狱，且安装了 dash。"];
        double timeout = MAX(1, MIN(120, [args[@"timeout_seconds"] doubleValue]));
        PCProcessResult r = PCRunShell(shell.fileSystemRepresentation, command.UTF8String, self.workspace.UTF8String,
                                      timeout, 65536, cancelled, (__bridge void *)self);
        NSData *bytes = [NSData dataWithBytes:r.output ?: "" length:r.output_length];
        NSString *output = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
        if (!output) output = [[NSString alloc] initWithData:bytes encoding:NSISOLatin1StringEncoding] ?: @"";
        NSDictionary *result = @{@"output": PCRedact(output), @"exit_code": @(r.exit_code),
            @"spawn_error": r.spawn_error ? @(strerror(r.spawn_error)) : @"", @"timed_out": @(r.timed_out),
            @"cancelled": @(r.cancelled), @"truncated": @(r.truncated)};
        PCFreeProcessResult(&r);
        return result;
    }
    NSString *path = [self path:args[@"path"]];
    if (!path) return [self failure:@"path 必须是非空路径，不能包含 NUL"];
    NSError *error = nil;
    if ([name isEqual:@"list_directory"]) {
        NSArray *entries = [fm contentsOfDirectoryAtPath:path error:&error];
        if (!entries) return [self failure:error.localizedDescription];
        entries = [entries sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger count = entries.count;
        if (count > 200) entries = [entries subarrayWithRange:NSMakeRange(0, 200)];
        return @{@"path": PCVirtualPath(path), @"entries": entries, @"total": @(count), @"truncated": @(count > 200)};
    }
    if ([name isEqual:@"read_file"]) {
        if (![args[@"offset"] isKindOfClass:NSNumber.class] || [args[@"offset"] longLongValue] < 0) return [self failure:@"offset 必须是非负整数字节偏移"];
        int fd = open(path.UTF8String, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) return [self failure:@(strerror(errno))];
        struct stat st;
        if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) { close(fd); return [self failure:@"只能读取普通文件"]; }
        off_t offset = [args[@"offset"] longLongValue];
        char buffer[49152];
        ssize_t count = pread(fd, buffer, sizeof(buffer), offset);
        close(fd);
        if (count < 0) return [self failure:@(strerror(errno))];
        /* Avoid cutting a UTF-8 scalar at the end of a bounded chunk. */
        ssize_t used = count;
        NSString *text = nil;
        for (int trim = 0; trim < 4 && used >= 0; trim++, used--) {
            text = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)used encoding:NSUTF8StringEncoding];
            if (text) break;
        }
        if (!text || (count > 0 && used == 0) || (used != count && offset + count >= st.st_size)) return [self failure:@"不是完整 UTF-8 文本，或 offset 位于字符中间；请使用 shell 查看二进制文件。"];
        return @{@"path": PCVirtualPath(path), @"text": PCRedact(text), @"next_offset": @(offset + used),
                 @"size": @(st.st_size), @"truncated": @(offset + used < st.st_size)};
    }
    if ([name isEqual:@"write_file"]) {
        if (![args[@"content"] isKindOfClass:NSString.class]) return [self failure:@"content 必须是字符串"];
        NSData *data = [args[@"content"] dataUsingEncoding:NSUTF8StringEncoding];
        if (data.length > 262144) return [self failure:@"单次写入最多 256 KiB"];
        /* Resolve parent symlinks so the approval and reported target are clear. */
        NSString *parent = [[path stringByDeletingLastPathComponent] stringByResolvingSymlinksInPath];
        path = [parent stringByAppendingPathComponent:path.lastPathComponent];
        struct stat st;
        BOOL exists = lstat(path.UTF8String, &st) == 0;
        if (!exists && errno != ENOENT) return [self failure:@(strerror(errno))];
        if (exists && (!S_ISREG(st.st_mode) || st.st_nlink > 1)) return [self failure:@"不覆盖符号链接、硬链接或非普通文件"];
        NSString *backup = @"";
        if (exists) {
            /* Backup beside the target preserves its original access boundary. */
            backup = [path stringByAppendingFormat:@".pocketbackup-%@", NSUUID.UUID.UUIDString];
            if (![fm copyItemAtPath:path toPath:backup error:&error]) return [self failure:[@"备份失败：" stringByAppendingString:error.localizedDescription]];
        }
        if (self.cancelled) return [self failure:@"已停止；未写入目标文件"];
        /* Stage with restrictive permissions; never expose a new world-readable file. */
        NSString *temp = [parent stringByAppendingPathComponent:[@".pocketcodex-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        int fd = open(temp.UTF8String, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
        if (fd < 0) return [self failure:@(strerror(errno))];
        const char *bytes = data.bytes;
        size_t written = 0;
        int failed = 0;
        while (written < data.length) {
            ssize_t n = write(fd, bytes + written, data.length - written);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) { failed = errno ?: EIO; break; }
            written += n;
        }
        if (!failed && fsync(fd) != 0) failed = errno;
        if (!failed && geteuid()==0) {
            struct stat ownership={0},workspaceOwner={0};
            NSString *ownedWorkspace=[PCRealPath(self.workspace?:PCWorkspace()) stringByResolvingSymlinksInPath];
            BOOL projectFile=[path hasPrefix:[ownedWorkspace stringByAppendingString:@"/"]]&&stat(ownedWorkspace.fileSystemRepresentation,&workspaceOwner)==0;
            if(projectFile)ownership=workspaceOwner;else if(exists)ownership=st;else if(stat(parent.fileSystemRepresentation,&ownership)!=0)failed=errno;
            if (!failed && fchown(fd,ownership.st_uid,ownership.st_gid)!=0) failed=errno;
        }
        if (!failed && exists && fchmod(fd, st.st_mode & 0777) != 0) failed = errno;
        close(fd);
        if (!failed && self.cancelled) failed = ECANCELED;
        /* Do not overwrite a target that was externally replaced after backup. */
        struct stat current;
        if (!failed) {
            int found = lstat(path.UTF8String, &current);
            if (exists && (found != 0 || current.st_dev != st.st_dev || current.st_ino != st.st_ino ||
                current.st_size != st.st_size || current.st_mtimespec.tv_sec != st.st_mtimespec.tv_sec ||
                current.st_mtimespec.tv_nsec != st.st_mtimespec.tv_nsec)) failed = EBUSY;
            if (!exists && (found == 0 || errno != ENOENT)) failed = EBUSY;
        }
        if (!failed && rename(temp.UTF8String, path.UTF8String) != 0) failed = errno;
        if (failed) { unlink(temp.UTF8String); return [self failure:@(strerror(failed))]; }
        return @{@"path": PCVirtualPath(path), @"bytes_written": @(data.length), @"backup": backup.length ? PCVirtualPath(backup) : @"",
                 @"note": @"原子替换已完成；原文件的扩展属性和 ACL 未复制到新文件。"};
    }
    return [self failure:@"未知工具"];
}
@end
