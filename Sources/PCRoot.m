#import "PCRoot.h"
#import "PCPlatform.h"
#import "PCTools.h"
#import "PCTerminal.h"
#import "PCRootPermission.h"
#import "PCNetworkPermission.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <pwd.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <poll.h>
#include <time.h>

extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

static NSString *PCRootDirectory(void) { return PCPrivilegedDirectory(); }
static NSString *PCRootSocket(void) { return [PCRootDirectory() stringByAppendingPathComponent:@"root.sock"]; }
static NSString *PCRootMarker(void) { return [PCRootDirectory() stringByAppendingPathComponent:@"enabled"]; }

static BOOL PCReadAll(int fd, void *bytes, size_t length) {
    size_t offset = 0;
    while (offset < length) {
        ssize_t count = read(fd, (char *)bytes + offset, length - offset);
        if (count > 0) offset += (size_t)count;
        else if (count < 0 && errno == EINTR) continue;
        else return NO;
    }
    return YES;
}
static BOOL PCWriteAll(int fd, const void *bytes, size_t length) {
    size_t offset = 0;
    while (offset < length) {
        ssize_t count = write(fd, (const char *)bytes + offset, length - offset);
        if (count > 0) offset += (size_t)count;
        else if (count < 0 && errno == EINTR) continue;
        else return NO;
    }
    return YES;
}
static BOOL PCReadPacket(int fd, NSMutableData **data) {
    uint32_t length = 0;
    if (!PCReadAll(fd, &length, sizeof(length))) return NO;
    length = ntohl(length);
    if (!length || length > 512 * 1024) return NO;
    NSMutableData *body = [NSMutableData dataWithLength:length];
    if (!PCReadAll(fd, body.mutableBytes, length)) return NO;
    *data = body;
    return YES;
}
static BOOL PCWritePacket(int fd, NSData *data) {
    if (!data.length || data.length > 512 * 1024) return NO;
    uint32_t length = htonl((uint32_t)data.length);
    return PCWriteAll(fd, &length, sizeof(length)) && PCWriteAll(fd, data.bytes, data.length);
}
static void PCSetSocketTimeout(int fd, NSTimeInterval seconds) {
    struct timeval tv = {(long)seconds, (int)((seconds - (long)seconds) * 1000000)};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
}

static NSTimeInterval PCMonotonicTime(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec / 1e9;
}
static BOOL PCReadCancellable(int fd, void *bytes, size_t length, NSTimeInterval deadline, BOOL (^cancelled)(void)) {
    size_t offset = 0;
    while (offset < length) {
        if ((cancelled && cancelled()) || PCMonotonicTime() >= deadline) return NO;
        struct pollfd descriptor = {fd, POLLIN, 0};
        int ready = poll(&descriptor, 1, 100);
        if (!ready || (ready < 0 && errno == EINTR)) continue;
        if (ready < 0) return NO;
        ssize_t count = read(fd, (char *)bytes + offset, length - offset);
        if (count > 0) offset += (size_t)count;
        else if (count < 0 && errno == EINTR) continue;
        else return NO;
    }
    return YES;
}

NSDictionary *PCSendRootRequest(NSDictionary *request, NSTimeInterval timeout) {
    return PCSendRootRequestWithCancellation(request, timeout, nil);
}
NSDictionary *PCSendRootRequestWithCancellation(NSDictionary *request, NSTimeInterval timeout, BOOL (^cancelled)(void)) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return @{@"error": @"无法创建 Root 服务连接。"};
    PCSetSocketTimeout(fd, timeout);
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    NSString *path = PCRootSocket();
    if (strlen(path.fileSystemRepresentation) >= sizeof(address.sun_path)) { close(fd); return @{@"error": @"Root 服务路径过长。"}; }
    strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) { close(fd); return @{@"error": @"Root 服务未运行；请在 RootHide 中重新安装或检查 AsterHand。"}; }
    NSData *body = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    if (!body || !PCWritePacket(fd, body)) { close(fd); return @{@"error": @"向 Root 服务发送请求失败。"}; }
    NSTimeInterval deadline = PCMonotonicTime() + timeout;
    uint32_t length = 0;
    BOOL okay = PCReadCancellable(fd, &length, sizeof(length), deadline, cancelled);
    length = ntohl(length);
    okay = okay && length > 0 && length <= 512 * 1024;
    NSMutableData *reply = okay ? [NSMutableData dataWithLength:length] : nil;
    if (okay) okay = PCReadCancellable(fd, reply.mutableBytes, length, deadline, cancelled);
    close(fd);
    if (cancelled && cancelled()) return @{@"error": @"任务已停止。"};
    if (!okay) return @{@"error": @"Root 服务未返回结果或操作已超时。"};
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:reply options:0 error:nil];
    return [result isKindOfClass:NSDictionary.class] ? result : @{@"error": @"Root 服务返回无效结果。"};
}

static BOOL PCTrustedClient(int fd) {
    uid_t uid = 0; gid_t gid = 0;
    struct passwd *mobile = getpwnam("mobile");
    if (!mobile || getpeereid(fd, &uid, &gid) != 0 || uid != mobile->pw_uid) return NO;
    pid_t pid = 0; socklen_t size = sizeof(pid);
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) != 0 || pid <= 0) return NO;
    char path[4096] = {0};
    if (proc_pidpath(pid, path, sizeof(path)) <= 0) return NO;
    NSString *expected=PCJailbreakExecutable(@"/Applications/PocketCodex.app/PocketCodex");
    return [[[NSString stringWithUTF8String:path] stringByResolvingSymlinksInPath] isEqual:[expected stringByResolvingSymlinksInPath]];
}
static NSDictionary *PCHandleRootRequest(NSDictionary *request, int client) {
    NSString *action = [request[@"action"] isKindOfClass:NSString.class] ? request[@"action"] : @"";
    if([action isEqual:@"network_status"])return PCNetworkPermissionRead();
    if([action isEqual:@"network_grant"])return PCNetworkPermissionApply(request[@"mode"]);
    if ([action isEqual:@"set_enabled"]) {
        if (![request[@"enabled"] isKindOfClass:NSNumber.class]) return @{@"error": @"Root 开关参数无效。"};
        NSString *marker = PCRootMarker();
        if ([request[@"enabled"] boolValue]) {
            int fd = open(marker.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
            if (fd < 0) return @{@"error": @"无法启用 Root 服务。"};
            fchmod(fd, 0600); close(fd);
        } else {
            PCTerminalCloseOwner(@"*");
            if (unlink(marker.fileSystemRepresentation) != 0 && errno != ENOENT) return @{@"error": @"无法关闭 Root 服务。"};
        }
        return @{@"enabled": @([request[@"enabled"] boolValue])};
    }
    if ([action isEqual:@"status"]) return @{@"enabled": @(access(PCRootMarker().fileSystemRepresentation, F_OK) == 0)};
    if ([action isEqual:@"terminal"]) {
        if ([request[@"operation"] isEqual:@"close_owner"]&&[request[@"owner"] isKindOfClass:NSString.class]){PCTerminalCloseOwner(request[@"owner"]);return @{@"closed":@YES};}
        if (access(PCRootMarker().fileSystemRepresentation,F_OK)!=0) return @{@"error":@"Root 开关已关闭"};
        if (![request[@"operation"] isKindOfClass:NSString.class]||![request[@"owner"] isKindOfClass:NSString.class]||![request[@"args"] isKindOfClass:NSDictionary.class])return @{@"error":@"终端请求无效"};
        return PCTerminalRequest(request[@"operation"],request[@"args"],request[@"owner"]);
    }
    BOOL once = [action isEqual:@"execute_once"];
    if (![action isEqual:@"execute"] && !once) return @{@"error": @"未知 Root 请求。"};
    if (!once && access(PCRootMarker().fileSystemRepresentation, F_OK) != 0) return @{@"error": @"Root 开关已关闭。"};
    NSString *name = [request[@"name"] isKindOfClass:NSString.class] ? request[@"name"] : @"";
    if (![@[@"run_shell", @"read_file", @"write_file", @"list_directory"] containsObject:name]) return @{@"error": @"未知 Root 工具。"};
    NSDictionary *args = [request[@"args"] isKindOfClass:NSDictionary.class] ? request[@"args"] : nil;
    NSString *workspace = [request[@"workspace"] isKindOfClass:NSString.class] ? request[@"workspace"] : nil;
    if (!args || !workspace.isAbsolutePath || workspace.length > 4096) return @{@"error": @"Root 工具参数无效。"};
    if (once) {
        static NSMutableDictionary *used;
        if (!used) used = [NSMutableDictionary new];
        if (!PCRootOperationValid(name, args) || !PCRootOnceClaim(request, used, NSDate.date.timeIntervalSince1970)) return @{@"error":@"本次 Root 授权无效、已过期或已使用。"};
    }
    PCTools *tools = [PCTools new];
    tools.workspace = workspace;
    // Closing the app-side connection cancels a running shell process group.
    tools.cancellationCheck = ^BOOL {
        char byte;
        ssize_t count = recv(client, &byte, 1, MSG_PEEK | MSG_DONTWAIT);
        return count == 0 || (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR);
    };
    return [tools execute:name arguments:args];
}

int PCRunRootDaemon(void) {
    if (geteuid() != 0) return 1;
    signal(SIGPIPE, SIG_IGN);
    NSString *directory = PCRootDirectory();
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0711} error:nil]) return 2;
    chown(directory.fileSystemRepresentation, 0, 0);
    chmod(directory.fileSystemRepresentation, 0711);
    NSString *path = PCRootSocket();
    unlink(path.fileSystemRepresentation);
    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) return 3;
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    if (strlen(path.fileSystemRepresentation) >= sizeof(address.sun_path)) { close(server); return 4; }
    strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0) { close(server); return 5; }
    struct passwd *mobile = getpwnam("mobile");
    if (!mobile || chown(path.fileSystemRepresentation, mobile->pw_uid, mobile->pw_gid) != 0 || chmod(path.fileSystemRepresentation, 0600) != 0 || listen(server, 4) != 0) { close(server); return 6; }
    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client < 0) { if (errno == EINTR) continue; break; }
        PCSetSocketTimeout(client, 125);
        @autoreleasepool {
            NSDictionary *result = @{@"error": @"Root 请求无效或来源未授权。"};
            NSMutableData *body = nil;
            if (PCTrustedClient(client) && PCReadPacket(client, &body)) {
                NSDictionary *request = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
                if ([request isKindOfClass:NSDictionary.class]) result = PCHandleRootRequest(request, client);
            }
            NSData *reply = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
            if (reply) PCWritePacket(client, reply);
        }
        close(client);
    }
    close(server);
    return 7;
}
