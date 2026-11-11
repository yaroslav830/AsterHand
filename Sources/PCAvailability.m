#import <Foundation/Foundation.h>
#include <stdint.h>

// The standalone lld build does not link compiler-rt's availability object.
// Supply its iOS-device ABI using the actual system version, never the SDK or
// deployment target. Foundation's version API predates the iOS 14 floor.
int32_t __isPlatformVersionAtLeast(uint32_t platform,uint32_t major,uint32_t minor,uint32_t patch) {
    if(platform!=2)return 0;
    static NSOperatingSystemVersion version;static dispatch_once_t once;
    dispatch_once(&once,^{version=NSProcessInfo.processInfo.operatingSystemVersion;});
    if(version.majorVersion!=major)return version.majorVersion>major;
    if(version.minorVersion!=minor)return version.minorVersion>minor;
    return version.patchVersion>=patch;
}
