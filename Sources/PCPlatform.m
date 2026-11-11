#import "PCPlatform.h"
#import "PCRuntimePaths.h"
#ifdef PC_ROOTHIDE
#include <roothide.h>
#endif

BOOL PCIsRootHide(void) {
#ifdef PC_ROOTHIDE
    return YES;
#else
    return NO;
#endif
}
BOOL PCIsRootful(void) {
#ifdef PC_ROOTFUL
    return YES;
#else
    return NO;
#endif
}
NSString *PCPrivilegedDirectory(void) { return PCRealPath(@PC_PRIVILEGED_DIRECTORY); }
NSString *PCEnvironmentName(void) {return PCIsRootHide()?@"RootHide":PCIsRootful()?@"rootful":@"Dopamine rootless";}

NSString *PCRealPath(NSString *path) {
#ifdef PC_ROOTHIDE
    const char *value = jbroot(path.fileSystemRepresentation);
    return value ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:value length:strlen(value)] : nil;
#else
    return path;
#endif
}

NSString *PCVirtualPath(NSString *path) {
#ifdef PC_ROOTHIDE
    const char *value = rootfs(path.fileSystemRepresentation);
    return value ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:value length:strlen(value)] : nil;
#else
    return path;
#endif
}

NSString *PCShellPath(void) {
    return PCJailbreakExecutable(@"/bin/sh");
}

NSString *PCJailbreakExecutable(NSString *path) {
    return PCIsRootHide() ? PCRealPath(path) : PCIsRootful()?path:[@"/var/jb" stringByAppendingString:path];
}

NSString *PCPathExplanation(void) {
    if (PCIsRootful()) return @"传统 rootful 越狱：命令使用 /bin、/usr/bin、/sbin 和 /usr/sbin；文件绝对路径以原始 iOS 文件系统为根。不要使用 /var/jb 或 RootHide 的 /rootfs 前缀。";
    if (PCIsRootHide()) return @"RootHide：工作目录和文件工具的绝对路径均以 jbroot 为根；访问原始 iOS 文件请使用 /rootfs 前缀，例如 /rootfs/var/mobile。shell 同样使用 jbroot 路径。不要使用 /var/jb。";
    return @"普通 Dopamine rootless：越狱命令位于 /var/jb，文件路径以原始 iOS 文件系统为根。";
}
