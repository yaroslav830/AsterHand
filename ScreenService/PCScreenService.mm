#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <CoreMedia/CoreMedia.h>
#import <Accelerate/Accelerate.h>
#import "PCRuntimePaths.h"
#import "PCMemoryBudget.h"
#import "ScreenCapturer.h"
#import "STHIDEventGenerator.h"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <pwd.h>
#include <signal.h>
#include <libproc.h>

int gOrientationFixQuad = 0;
BOOL tvncLoggingEnabled = NO;
BOOL tvncVerboseLoggingEnabled = NO;
@interface STHIDEventGenerator (AsterHandKeyboard)
- (void)_sendIOHIDKeyboardEvent:(uint32_t)page usage:(uint32_t)usage isKeyDown:(bool)down;
@end
@interface ScreenCapturer (AsterHandFramePump)
- (void)onDisplayLink:(CADisplayLink *)link;
@end

static NSString *PCScreenPath(void) {
    const char *path = jbroot("/var/mobile/.pocketagent-screen.sock");
    return path ? [NSString stringWithUTF8String:path] : nil;
}
static BOOL ReadAll(int fd, void *buffer, size_t length) {
    size_t done = 0;
    while (done < length) { ssize_t n = read(fd, (char *)buffer + done, length - done); if (n <= 0) return NO; done += n; }
    return YES;
}
static BOOL WriteAll(int fd, const void *buffer, size_t length) {
    size_t done = 0;
    while (done < length) { ssize_t n = write(fd, (const char *)buffer + done, length - done); if (n <= 0) return NO; done += n; }
    return YES;
}
static NSCondition *sFrameLock;
static NSDictionary *sLatestFrame;
static BOOL sCapturing;
static NSTimeInterval sLastAccess;
static NSUInteger sFrameSequence;
static NSTimeInterval sLastFrameTime;
static NSArray *sClipboardOriginal;
static NSInteger sClipboardChange=-1;
static NSString *sClipboardOwner;
static void RestoreClipboard(NSString *owner){if(!sClipboardOriginal||(owner&&![owner isEqual:sClipboardOwner]))return;UIPasteboard *pasteboard=UIPasteboard.generalPasteboard;if(pasteboard.changeCount==sClipboardChange)pasteboard.items=sClipboardOriginal;sClipboardOriginal=nil;sClipboardOwner=nil;sClipboardChange=-1;}
static void StartContinuousCapture(void) {
    if(sCapturing)return;
    sCapturing=YES;
    [sFrameLock lock];sLatestFrame=nil;[sFrameLock unlock];
    [[ScreenCapturer sharedCapturer] setPreferredFrameRateWithMin:30 preferred:30 max:30];
    [[ScreenCapturer sharedCapturer] forceNextFrameUpdate];
    [[ScreenCapturer sharedCapturer] startCaptureWithFrameHandler:^(CMSampleBufferRef sample) {
        @autoreleasepool {
            NSData *jpeg=nil;CGSize size=CGSizeZero;
            CVImageBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
            if (!buffer) return;
            if (CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) return;
            size = CGSizeMake(CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer));
            CGFloat scale = MIN(1.0, 960.0 / MAX(size.width, size.height));
            CGSize output = CGSizeMake(MAX(1, floor(size.width * scale)), MAX(1, floor(size.height * scale)));
            CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
            CGContextRef scaled = CGBitmapContextCreate(NULL, output.width, output.height, 8, 0, color,
                kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
            if(scaled){vImage_Buffer src={CVPixelBufferGetBaseAddress(buffer),(vImagePixelCount)size.height,(vImagePixelCount)size.width,CVPixelBufferGetBytesPerRow(buffer)};vImage_Buffer dst={CGBitmapContextGetData(scaled),(vImagePixelCount)output.height,(vImagePixelCount)output.width,CGBitmapContextGetBytesPerRow(scaled)};vImageScale_ARGB8888(&src,&dst,NULL,kvImageNoFlags);}
            CGImageRef thumbnail = scaled ? CGBitmapContextCreateImage(scaled) : NULL;
            if (thumbnail) {
                NSMutableData *encoded = [NSMutableData data];
                CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)encoded, CFSTR("public.jpeg"), 1, NULL);
                if (destination) {
                    CGImageDestinationAddImage(destination, thumbnail, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@0.50});
                    if (CGImageDestinationFinalize(destination)) jpeg = [encoded copy];
                    CFRelease(destination);
                }
                CGImageRelease(thumbnail);
            }
            if (scaled) CGContextRelease(scaled);
            CGColorSpaceRelease(color);
            CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);

            if(jpeg.length&&jpeg.length<=1024*1024){
                NSDictionary *frame=@{@"width":@(output.width),@"height":@(output.height),@"native_width":@(size.width),@"native_height":@(size.height),@"sequence":@(++sFrameSequence),@"image_base64":[jpeg base64EncodedStringWithOptions:0]};
                [sFrameLock lock];sLatestFrame=frame;sLastFrameTime=NSProcessInfo.processInfo.systemUptime;[sFrameLock broadcast];[sFrameLock unlock];
            }
        }
    }];
}
static NSDictionary *Capture(NSDictionary *request) {
    [sFrameLock lock];sLastAccess=NSProcessInfo.processInfo.systemUptime;[sFrameLock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{StartContinuousCapture();});
    [sFrameLock lock];NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:6];
    NSUInteger after=[request[@"after_sequence"] unsignedIntegerValue];
    if([request[@"fresh"] boolValue])after=MAX(after,sFrameSequence);
    while(!sLatestFrame||[sLatestFrame[@"sequence"] unsignedIntegerValue]<=after)if(![sFrameLock waitUntilDate:deadline])break;
    NSDictionary *frame=[sLatestFrame[@"sequence"] unsignedIntegerValue]>after?sLatestFrame:nil;[sFrameLock unlock];
    return frame?:@{@"error":@"未能获取新的屏幕画面；请检查屏幕是否唤醒或重试。"};
}
static NSDictionary *Act(NSDictionary *request) {
    NSString *action = request[@"action"];
    if ([action isEqual:@"capture"]) return Capture(request);
    if (![@[@"tap", @"swipe", @"type", @"home", @"clipboard_restore"] containsObject:action]) return @{@"error":@"未知屏幕操作。"};
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSDictionary *result = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            STHIDEventGenerator *hid = [STHIDEventGenerator sharedGenerator];
            // The generator normalizes points by its rendering reference size.
            // Plus/Display Zoom devices can downsample that size to nativeBounds;
            // multiplying by nativeBounds would shift every tap toward the origin.
            NSValue *geometry=[hid valueForKey:@"physicalScreenSize"];
            if(![geometry isKindOfClass:NSValue.class]||strcmp(geometry.objCType,@encode(CGSize))!=0){result=@{@"error":@"无法读取触控参考坐标。"};dispatch_semaphore_signal(done);return;}
            CGSize screen=geometry.CGSizeValue;
            if(!isfinite(screen.width)||!isfinite(screen.height)||screen.width<=0||screen.height<=0){result=@{@"error":@"触控参考尺寸无效。"};dispatch_semaphore_signal(done);return;}
            double x = [request[@"x"] doubleValue], y = [request[@"y"] doubleValue];
            if ([action isEqual:@"clipboard_restore"]) {RestoreClipboard(request[@"clipboard_owner"]);result=@{@"restored_if_unchanged":@YES};}
            else if ([action isEqual:@"home"]) { [hid menuPress]; result = @{@"home":@YES}; }
            else if ([action isEqual:@"type"]) {
                NSString *value = request[@"text"];
                if (![value isKindOfClass:NSString.class] || !value.length || value.length > 2000) result = @{@"error":@"一次只能输入 1 至 2000 个字符。"};
                else {
                    // Paste avoids composition/autocorrection by the current Chinese IME.
                    UIPasteboard *pasteboard=UIPasteboard.generalPasteboard;if(!sClipboardOriginal||pasteboard.changeCount!=sClipboardChange)sClipboardOriginal=pasteboard.items?:@[];
                    pasteboard.string=value;NSInteger change=pasteboard.changeCount;sClipboardChange=change;sClipboardOwner=[request[@"clipboard_owner"] isKindOfClass:NSString.class]?request[@"clipboard_owner"]:@"remote";
                    if([request[@"replace"] boolValue]){[hid _sendIOHIDKeyboardEvent:7 usage:0xe3 isKeyDown:true];[hid keyPress:@"a"];[hid _sendIOHIDKeyboardEvent:7 usage:0xe3 isKeyDown:false];}
                    [hid _sendIOHIDKeyboardEvent:7 usage:0xe3 isKeyDown:true];[hid keyPress:@"v"];[hid _sendIOHIDKeyboardEvent:7 usage:0xe3 isKeyDown:false];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,90*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(sClipboardChange==change)RestoreClipboard(nil);});
                    result=@{@"paste_dispatched":@(value.length),@"verify_on_screen":@YES,@"next_step":@"Capture the screen, handle Allow Paste if shown, and verify the intended text. The task text remains available for the paste confirmation."};
                }
            } else if (!(x >= 0 && x <= 1 && y >= 0 && y <= 1)) result = @{@"error":@"坐标必须在 0 至 1 之间。"};
            else if ([action isEqual:@"tap"]) {
                [hid sendTaps:1 location:CGPointMake(x * screen.width, y * screen.height) numberOfTouches:1 delayBetweenTaps:0.05];
                result = @{@"tapped":@YES};
            }
            else {
                double x2 = [request[@"x2"] doubleValue], y2 = [request[@"y2"] doubleValue];
                double duration = [request[@"duration"] doubleValue];
                if (!(x2 >= 0 && x2 <= 1 && y2 >= 0 && y2 <= 1 && duration >= 0.1 && duration <= 2)) result = @{@"error":@"终点或持续时间无效。"};
                else {CGPoint start=CGPointMake(x*screen.width,y*screen.height),end=CGPointMake(x2*screen.width,y2*screen.height);if(hypot(start.x-end.x,start.y-end.y)<2){[hid touchDown:start];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(duration*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[hid liftUp:end];});}else [hid dragLinearWithStartPoint:start endPoint:end duration:duration]; result = @{@"swiped":@YES}; }
            }
        } @catch (NSException *exception) { result = @{@"error":exception.reason ?: @"触控失败"}; }
        dispatch_semaphore_signal(done);
    });
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 18 * NSEC_PER_SEC))) return @{@"error":@"屏幕操作超时。"};
    return result ?: @{@"error":@"屏幕操作无结果。"};
}
static void HandleClient(int fd) {
    struct timeval timeout = {20, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    uid_t uid = 0; gid_t gid = 0;
    struct passwd *mobile = getpwnam("mobile");
    if (!mobile || getpeereid(fd, &uid, &gid) || uid != mobile->pw_uid) return;
    pid_t pid = 0; socklen_t pidSize = sizeof(pid);
    char clientPath[4096] = {0};
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidSize) || pid <= 0 ||
        proc_pidpath(pid, clientPath, sizeof(clientPath)) <= 0 ||
        ![[NSString stringWithUTF8String:clientPath] hasSuffix:@"/Applications/PocketCodex.app/PocketCodex"]) return;
    uint32_t length = 0;
    if (!ReadAll(fd, &length, 4)) return;
    length = ntohl(length);
    if (length < 2 || length > 8192) return;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (!ReadAll(fd, data.mutableBytes, length)) return;
    NSDictionary *request = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *reply = [request isKindOfClass:NSDictionary.class] ? Act(request) : @{@"error":@"请求格式无效。"};
    NSData *payload = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
    if (payload.length > 2 * 1024 * 1024) payload = [NSJSONSerialization dataWithJSONObject:@{@"error":@"图像过大。"} options:0 error:nil];
    uint32_t count = htonl((uint32_t)payload.length);
    WriteAll(fd, &count, 4); WriteAll(fd, payload.bytes, payload.length);
}
int main(void) {
    if(!PCEnsureServiceMemoryBudget())return 5;
    signal(SIGPIPE, SIG_IGN);
    sFrameLock=[NSCondition new];
    // A standalone launchd process can lose CADisplayLink callbacks after lock or
    // display idle. Pump only when requested capture has stopped producing frames.
    [NSTimer scheduledTimerWithTimeInterval:.05 repeats:YES block:^(NSTimer *timer){
        [sFrameLock lock];double now=NSProcessInfo.processInfo.systemUptime;BOOL needed=sCapturing&&now-sLastAccess<3&&now-sLastFrameTime>.12;[sFrameLock unlock];
        if(needed)[[ScreenCapturer sharedCapturer] onDisplayLink:nil];
    }];
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){
        [sFrameLock lock];BOOL idle=NSProcessInfo.processInfo.systemUptime-sLastAccess>3;[sFrameLock unlock];
        if(sCapturing&&idle){[[ScreenCapturer sharedCapturer] endCapture];sCapturing=NO;[sFrameLock lock];sLatestFrame=nil;[sFrameLock unlock];}
    }];
    NSString *path = PCScreenPath();
    if (!path) return 1;
    unlink(path.fileSystemRepresentation);
    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) return 2;
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    if (strlen(path.fileSystemRepresentation) >= sizeof(address.sun_path)) return 3;
    strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) || chmod(path.fileSystemRepresentation, 0600) || listen(server, 4)) return 4;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (;;) {
            int client = accept(server, NULL, NULL);
            if (client >= 0) { @autoreleasepool { HandleClient(client); } close(client); }
        }
    });
    [[NSRunLoop mainRunLoop] run];
    return 0;
}
