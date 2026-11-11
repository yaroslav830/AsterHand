#import "PCScreen.h"
#import "PCPlatform.h"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static BOOL Transfer(int fd, void *bytes, size_t length, BOOL writing) {
    size_t done = 0;
    while (done < length) {
        ssize_t n = writing ? write(fd, (char *)bytes + done, length - done) : read(fd, (char *)bytes + done, length - done);
        if (n <= 0) return NO;
        done += n;
    }
    return YES;
}

NSDictionary *PCScreenRequest(NSDictionary *request) {
    NSString *path = PCRealPath(@"/var/mobile/.pocketagent-screen.sock");
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return @{@"error":@"屏幕服务不可用。"};
    struct timeval timeout = {20, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    if (strlen(path.fileSystemRepresentation) >= sizeof(address.sun_path)) { close(fd); return @{@"error":@"屏幕服务路径无效。"}; }
    strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));
    if (connect(fd, (struct sockaddr *)&address, sizeof(address))) { close(fd); return @{@"error":@"屏幕服务未启动；请检查 AsterHand 安装。"}; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    uint32_t length = htonl((uint32_t)data.length);
    if (!data.length || !Transfer(fd, &length, 4, YES) || !Transfer(fd, (void *)data.bytes, data.length, YES) || !Transfer(fd, &length, 4, NO)) { close(fd); return @{@"error":@"屏幕服务通信失败。"}; }
    length = ntohl(length);
    if (length < 2 || length > 2 * 1024 * 1024) { close(fd); return @{@"error":@"屏幕服务回复大小异常。"}; }
    NSMutableData *reply = [NSMutableData dataWithLength:length];
    BOOL okay = Transfer(fd, reply.mutableBytes, length, NO);
    close(fd);
    if (!okay) return @{@"error":@"屏幕服务回复不完整。"};
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:reply options:0 error:nil];
    return [result isKindOfClass:NSDictionary.class] ? result : @{@"error":@"屏幕服务回复无效。"};
}
