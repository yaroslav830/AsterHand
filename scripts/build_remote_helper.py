"""Build the GPL-2.0 TrollVNC screen/control backend for PocketCodex (Windows)."""
import pathlib
import shutil
import subprocess
import sys
import difflib
import argparse
from ios_build_profile import add_environment_args, profile, availability_object

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build_windows as base

REPO = ROOT / '.build-deps/TrollVNC-source'
OUT = ROOT / 'build/remote-helper'
UPSTREAM = 'cfdb737e72977d961eb7d0a8110d2fe1a58551d7'

def materialize():
    listing = subprocess.check_output(['git', '-C', str(REPO), 'ls-files', '--stage'], text=True)
    for line in listing.splitlines():
        meta, name = line.split('\t', 1)
        if not meta.startswith('120000 '):
            continue
        source = REPO / name
        target_name = subprocess.check_output(['git', '-C', str(REPO), 'cat-file', '-p', meta.split()[1]], text=True)
        target = (source.parent / target_name).resolve()
        target.relative_to(REPO.resolve())
        shutil.copyfile(target, source)

def main():
    global OUT
    parser=argparse.ArgumentParser();add_environment_args(parser,default='roothide');args=parser.parse_args();target=profile(args)
    rootless=args.environment != 'roothide'
    OUT=ROOT/'build'/target.helper_directory('remote-helper')
    if not REPO.exists():
        subprocess.run(['git', 'clone', 'https://github.com/owngoal-dev/TrollVNC.git', str(REPO)], check=True)
        subprocess.run(['git', '-C', str(REPO), 'checkout', UPSTREAM], check=True)
    if subprocess.check_output(['git', '-C', str(REPO), 'rev-parse', 'HEAD'], text=True).strip() != UPSTREAM:
        sys.exit('Unexpected TrollVNC revision. Expected ' + UPSTREAM)
    materialize()
    OUT.mkdir(parents=True, exist_ok=True)
    base.BUILD = OUT
    original = (REPO / 'src/trollvncserver.mm').read_text(encoding='utf-8')
    modified = original.replace('#import <sys/socket.h>', '#import <sys/socket.h>\n#import <sys/stat.h>\n#import <spawn.h>\n#import <limits.h>\n#import <signal.h>\n#import <roothide.h>\nextern char **environ;', 1)
    modified = modified.replace('static enum rfbNewClientAction newClientHook(rfbClientPtr cl) {', '''static BOOL pocketRequirePhoneApproval(rfbClientPtr cl) {
    const char *directory = getenv("POCKET_REMOTE_DIRECTORY");
    if (!directory || !*directory) return NO;
    NSString *root = [NSString stringWithUTF8String:directory];
    NSString *host = cl && cl->host ? [NSString stringWithUTF8String:cl->host] : @"Unknown device";
    if (host.length > 96) host = [host substringToIndex:96];
    NSString *settingsPath = [root stringByAppendingPathComponent:@"remote-settings.json"];
    NSData *settingsData = [NSData dataWithContentsOfFile:settingsPath];
    NSDictionary *settings = settingsData ? [NSJSONSerialization JSONObjectWithData:settingsData options:0 error:nil] : @{};
    if ([settings[@"auto_approve"] boolValue]) return YES;
    NSArray *trusted = [settings[@"trusted_hosts"] isKindOfClass:NSArray.class] ? settings[@"trusted_hosts"] : @[];
    if ([trusted containsObject:host]) return YES;
    NSString *requestId = NSUUID.UUID.UUIDString.lowercaseString;
    NSString *requestPath = [root stringByAppendingPathComponent:[@"pending-" stringByAppendingString:requestId]];
    NSString *responsePath = [root stringByAppendingPathComponent:[@"decision-" stringByAppendingString:requestId]];
    NSDictionary *request = @{ @"id": requestId, @"host": host, @"created": @(NSDate.date.timeIntervalSince1970) };
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    if (!requestData || ![requestData writeToFile:requestPath options:NSDataWritingAtomic error:nil]) return NO;
    chmod(requestPath.fileSystemRepresentation, 0600);
    // Bring the consent UI forward even when PocketAgent was not already open.
    const char *uiopen = "/usr/bin/uiopen";
    char *uiargs[] = {(char *)uiopen, (char *)"--bundleid", (char *)"local.pocketcodex", NULL};
    pid_t uiPID = 0;
    posix_spawn(&uiPID, uiopen, NULL, NULL, uiargs, environ);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60.0];
    BOOL allowed = NO;
    while ([deadline timeIntervalSinceNow] > 0) {
        NSData *responseData = [NSData dataWithContentsOfFile:responsePath];
        NSDictionary *response = responseData ? [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil] : nil;
        if ([response[@"id"] isEqual:requestId]) { allowed = [response[@"allow"] boolValue]; break; }
        usleep(150000);
    }
    [[NSFileManager defaultManager] removeItemAtPath:requestPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:responsePath error:nil];
    return allowed;
}

static enum rfbNewClientAction newClientHook(rfbClientPtr cl) {
    // PocketCodex: only authenticated TLS WebSocket clients may reach RFB.
    if (!cl->sslctx || !cl->wsctx) return RFB_CLIENT_REFUSE;''', 1)
    modified = modified.replace('if (!cl->sslctx || !cl->wsctx) return RFB_CLIENT_REFUSE;', '''if (!cl->sslctx || !cl->wsctx) return RFB_CLIENT_REFUSE;
    // Auto-allow enabled or trusted paired computers; otherwise wait for phone approval.
    if (!pocketRequirePhoneApproval(cl)) return RFB_CLIENT_REFUSE;''', 1)
    modified = modified.replace('if (gClipboardEnabled && !gIsClipboardStarted && gClientCount > 0)',
                                'if (false && gClipboardEnabled && !gIsClipboardStarted && gClientCount > 0)', 1)
    modified = modified.replace('static void prepareClipboardManager(void) {', '''static void prepareClipboardManager(void) {
    // PocketCodex accepts explicit client paste, never watches phone clipboard.
    return;''', 1)
    modified = modified.replace('int main(int argc, const char *argv[]) {', '''static char pocketPIDPath[PATH_MAX];
static void pocketRemovePID(void) { if (pocketPIDPath[0]) unlink(pocketPIDPath); }
static void pocketStopSignal(int signalNumber) { (void)signalNumber; pocketRemovePID(); _exit(0); }

int main(int argc, const char *argv[]) {
    // launchd starts this service at install and keeps it alive. Wait for first pairing if needed.
    const char *directory = getenv("POCKET_REMOTE_DIRECTORY");
    fprintf(stderr, "PocketRemote startup directory=%s\\n", directory ? directory : "(unset)"); fflush(stderr);
    if (!directory || !*directory) return 78;
    const char *physicalDirectory = jbroot(directory);
    if (!physicalDirectory) return 78;
    setenv("POCKET_REMOTE_DIRECTORY", physicalDirectory, 1);
    NSString *root = [NSString stringWithUTF8String:physicalDirectory];
    NSString *configPath = [root stringByAppendingPathComponent:@"phone.json"];
    NSString *certPath = [root stringByAppendingPathComponent:@"server.pem"];
    NSString *keyPath = [root stringByAppendingPathComponent:@"server-key.pem"];
    for (int i = 1; i + 1 < argc; i++) {
        if (strcmp(argv[i], "-e") == 0) argv[i + 1] = certPath.fileSystemRepresentation;
        else if (strcmp(argv[i], "-k") == 0) argv[i + 1] = keyPath.fileSystemRepresentation;
    }
    while (true) {
        NSData *pairData = [NSData dataWithContentsOfFile:configPath];
        NSDictionary *pair = pairData ? [NSJSONSerialization JSONObjectWithData:pairData options:0 error:nil] : nil;
        NSString *password = [pair[@"password"] isKindOfClass:NSString.class] ? pair[@"password"] : nil;
        BOOL hasCertificate = [[NSFileManager defaultManager] fileExistsAtPath:certPath];
        BOOL hasPrivateKey = [[NSFileManager defaultManager] fileExistsAtPath:keyPath];
        if (password.length == 8 && hasCertificate && hasPrivateKey) {
            setenv("TROLLVNC_PASSWORD", password.UTF8String, 1);
            fprintf(stderr, "PocketRemote pairing ready; certificate and key found.\\n"); fflush(stderr);
            break;
        }
        fprintf(stderr, "PocketRemote waiting for pairing (config=%d, password_length=%lu, certificate=%d, key=%d).\\n", pairData != nil, (unsigned long)password.length, hasCertificate, hasPrivateKey); fflush(stderr);
        sleep(5);
    }
    snprintf(pocketPIDPath, sizeof(pocketPIDPath), "%s/remote.pid", physicalDirectory);
    FILE *pidFile = fopen(pocketPIDPath, "w");
    if (pidFile) { fprintf(pidFile, "%d\\n", getpid()); fclose(pidFile); chmod(pocketPIDPath, 0600); }
    atexit(pocketRemovePID);''', 1)
    modified = modified.replace('atexit(pocketRemovePID);', 'atexit(pocketRemovePID);\n    signal(SIGTERM, pocketStopSignal);\n    signal(SIGINT, pocketStopSignal);', 1)
    # Authenticate every VNC connection using a short-lived grant obtained over paired RPC.
    auth = (ROOT / 'scripts/remote_identity_auth.inc').read_text(encoding='utf-8')
    modified = modified.replace('static enum rfbNewClientAction newClientHook(rfbClientPtr cl) {', auth + '\nstatic enum rfbNewClientAction newClientHook(rfbClientPtr cl) {', 1)
    modified = modified.replace('    if (!pocketRequirePhoneApproval(cl)) return RFB_CLIENT_REFUSE;', '')
    modified = modified.replace('rfbBool rc = rfbCheckPasswordByList(cl, passwd, len);', 'rfbBool rc = pocketPasswordCheck(cl, passwd, len);', 1)
    modified = modified.replace('    gClientCount++;', '    @synchronized(pocketAuthenticated) { [pocketAuthenticated removeObjectForKey:@(cl->sock)]; }\n    gClientCount++;', 1)
    modified = modified.replace('    NSString *configPath = [root stringByAppendingPathComponent:@"phone.json"];', '    pocketEnsureIdentity(root);\n    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { pocketMonitorClients(); }];\n    NSString *configPath = [root stringByAppendingPathComponent:@"phone.json"];', 1)
    modified=modified.replace('#import <roothide.h>', '#import "PCRuntimePaths.h"').replace('const char *uiopen = "/usr/bin/uiopen";', 'const char *uiopen = PC_JB_EXEC("/usr/bin/uiopen");')
    (OUT / 'trollvncserver.mm').write_text(modified, encoding='utf-8')
    patch_dir = ROOT / 'third_party/TrollVNC'
    patch_dir.mkdir(parents=True, exist_ok=True)
    (patch_dir / 'pocketremote.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True), modified.splitlines(True), fromfile='a/src/trollvncserver.mm', tofile='b/src/trollvncserver.mm')), encoding='utf-8')
    capture_original = (REPO / 'src/ScreenCapturer.mm').read_text(encoding='utf-8')
    capture_modified = capture_original.replace('mScreenSurface = IOSurfaceCreate((__bridge CFDictionaryRef)mRenderProperties);', '''mScreenSurface = IOSurfaceCreate((__bridge CFDictionaryRef)mRenderProperties);
    NSLog(@"PocketRemote capture geometry %dx%d, surface allocated=%d", width, height, mScreenSurface != NULL);''', 1)
    capture_modified = capture_modified.replace('CFRunLoopSourceRef runLoopSource = IOSurfaceAcceleratorGetRunLoopSource(accelerator);', 'CFRunLoopSourceRef runLoopSource = accelerator ? IOSurfaceAcceleratorGetRunLoopSource(accelerator) : NULL;', 1)
    capture_modified = capture_modified.replace('- (BOOL)renderDisplayToScreenSurface:(IOSurfaceRef)dstSurface {', '- (BOOL)renderDisplayToScreenSurface:(IOSurfaceRef)dstSurface {\n    if (!dstSurface) return NO;', 1)
    capture_modified = capture_modified.replace('sDirtyFrameCount = 0; // Force next frame to be treated as dirty',
        'sDirtyFrameCount = -1; // Always differ from a nonnegative dirty-frame count', 1)
    capture_modified = capture_modified.replace('static CFIndex sDirtyFrameCount = 0;', 'static CFIndex sDirtyFrameCount = 0;\nstatic BOOL sForceFrame = NO;', 1)
    capture_modified = capture_modified.replace('if (dirtyFrameCount == sDirtyFrameCount) {', 'if (dirtyFrameCount == sDirtyFrameCount && !sForceFrame) {', 1)
    capture_modified = capture_modified.replace('// Fast ~20ms, sRGB, while the image is GOOD. Recommended.',
        'sForceFrame = NO;\n    // Fast ~20ms, sRGB, while the image is GOOD. Recommended.', 1)
    capture_modified = capture_modified.replace('sDirtyFrameCount = -1; // Always differ from a nonnegative dirty-frame count',
        'sDirtyFrameCount = -1; sForceFrame = YES; // Capture even if dirty count is unchanged or unavailable', 1)
    capture_modified = capture_modified.replace('CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);', 'if (runLoopSource) CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);', 1)
    capture_modified = capture_modified.replace('CARenderServerRenderDisplay(0 /* Main Display */, CFSTR("LCD"), srcSurface, 0, 0);\n    IOSurfaceAcceleratorTransferSurface(accelerator, srcSurface, dstSurface, NULL, NULL, NULL, NULL);', '''if (accelerator && srcSurface) {
        CARenderServerRenderDisplay(0, CFSTR("LCD"), srcSurface, 0, 0);
        IOSurfaceAcceleratorTransferSurface(accelerator, srcSurface, dstSurface, NULL, NULL, NULL, NULL);
    } else {
        // A16/iOS 16 may expose no accelerator runloop source. Render directly.
        CARenderServerRenderDisplay(0, CFSTR("LCD"), dstSurface, 0, 0);
    }''', 1)
    (OUT / 'ScreenCapturer.mm').write_text(capture_modified, encoding='utf-8')
    with (patch_dir / 'pocketremote.patch').open('a', encoding='utf-8') as patch:
        patch.write(''.join(difflib.unified_diff(capture_original.splitlines(True), capture_modified.splitlines(True), fromfile='a/src/ScreenCapturer.mm', tofile='b/src/ScreenCapturer.mm')))
    (OUT / 'compile.log').write_text('', encoding='utf-8')
    common = [base.ZIG, 'c++', '-target', target.target, '-isysroot', base.SDK,
        '-iframework', base.SDK / 'System/Library/Frameworks',
        '-nostdinc++', '-isystem', base.SDK / 'usr/include/c++/v1', '-isystem', base.SDK / 'usr/include',
        '-I' + str(ROOT / '.build-deps/roothide-devkit/devkit'), '-I' + str(ROOT / 'Sources'), *target.defines, *target.availability,
        '-I' + str(REPO / 'include-spi'), '-I' + str(REPO / 'include'), '-I' + str(REPO / 'src'),
        '-fblocks', '-fobjc-arc', '-std=c++20', '-O2', '-Wno-nullability-completeness',
        '-include', ROOT / 'scripts/ios_cxx_compat.h', '-Wno-c99-designator',
        '-Wno-macro-redefined', '-Wno-unknown-warning-option', '-Wno-deprecated-declarations',
        '-DPACKAGE_VERSION="3.2-272"', '-DTHEOS_PACKAGE_SCHEME="'+args.environment+'"']
    objects = []
    for name in ('trollvncserver', 'BulletinManager', 'ClipboardManager', 'ScreenCapturer', 'STHIDEventGenerator', 'OhMyJetsam'):
        src = REPO / 'src' / (name + '.mm')
        if name in ('trollvncserver', 'ScreenCapturer'): src = OUT / (name + '.mm')
        obj = OUT / (name + '.o')
        print('Compiling ' + name, flush=True)
        base.run(common + ['-c', src, '-o', obj])
        objects.append(obj)
    objects.append(availability_object(base,target,OUT))
    args = [ROOT / '.build-deps/llvm-mingw-20260908-msvcrt-x86_64/bin/lld.exe', '-flavor', 'darwin',
        '-arch', 'arm64', '-platform_version', 'ios', target.minimum, '16.5', '-syslibroot', base.SDK,
        '-L' + str(base.SDK / 'usr/lib'), '-L' + str(REPO / 'lib'),
        '-L' + str(ROOT / '.build-deps/roothide-devkit/devkit/roothide'),
        '-F' + str(base.SDK / 'System/Library/Frameworks'),
        '-F' + str(base.SDK / 'System/Library/PrivateFrameworks'),
        '-F' + str(REPO / 'PrivateFrameworks'), '-headerpad', '0x1000',
        *objects, *target.libraries, '-lSystem', '-lobjc', '-lc++', '-lz', '-licucore',
        '-lcrypto', '-llzo2', '-lturbojpeg', '-lpng18', '-lsasl2', '-lssl', '-lvncserver']
    for framework in ('Accelerate', 'CoreGraphics', 'CoreMedia', 'CoreVideo', 'Foundation', 'IOKit',
                      'IOSurface', 'QuartzCore', 'UIKit', 'UserNotifications', 'FrontBoardServices', 'Preferences'):
        args += ['-framework', framework]
    base.run(args + ['-o', OUT / 'pocketremote'])
    print('Remote backend compiled', flush=True)

if __name__ == '__main__':
    main()
