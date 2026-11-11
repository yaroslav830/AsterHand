"""Build the local-only screen capture and HID tool service."""
import pathlib
import subprocess
import sys
import argparse
from ios_build_profile import add_environment_args, profile, availability_object

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build_windows as base

REPO = ROOT / '.build-deps/TrollVNC-source'
OUT = ROOT / 'build/screen-service'

def main():
    global OUT
    parser=argparse.ArgumentParser();add_environment_args(parser,default='roothide');args=parser.parse_args();target=profile(args)
    OUT=ROOT/'build'/target.helper_directory('screen-service')
    OUT.mkdir(parents=True, exist_ok=True)
    base.BUILD = OUT
    (OUT / 'compile.log').write_text('', encoding='utf-8')
    common = [base.ZIG, 'c++', '-target', target.target, '-isysroot', base.SDK,
        '-iframework', base.SDK / 'System/Library/Frameworks', '-nostdinc++',
        '-isystem', base.SDK / 'usr/include/c++/v1', '-isystem', base.SDK / 'usr/include',
        '-I' + str(ROOT / '.build-deps/roothide-devkit/devkit'), '-I' + str(ROOT / 'Sources'), *target.defines, *target.availability,
        '-I' + str(REPO / 'include-spi'), '-I' + str(REPO / 'include'), '-I' + str(REPO / 'src'),
        '-fblocks', '-fobjc-arc', '-std=c++20', '-O2', '-Wno-nullability-completeness',
        '-include', ROOT / 'scripts/ios_cxx_compat.h', '-Wno-c99-designator',
        '-Wno-macro-redefined', '-Wno-unknown-warning-option', '-Wno-deprecated-declarations',
        '-DTHEOS_PACKAGE_SCHEME="'+args.environment+'"']
    capture_source=(ROOT / ('build/'+target.helper_directory('remote-helper')+'/ScreenCapturer.mm')).read_text(encoding='utf-8')
    capture_source=capture_source.replace('- (BOOL)updateDisplay:(CADisplayLink *)displayLink {','- (BOOL)updateDisplay:(CADisplayLink *)displayLink {\n    [self forceNextFrameUpdate];',1)
    capture_source=capture_source.replace('CMTimeMakeWithSeconds(link.duration, timescale)','CMTimeMakeWithSeconds(link ? link.duration : 1.0/30, timescale)').replace('CMTimeMakeWithSeconds(link.timestamp, timescale)','CMTimeMakeWithSeconds(link ? link.timestamp : CACurrentMediaTime(), timescale)')
    (OUT / 'ScreenCapturer.mm').write_text(capture_source,encoding='utf-8')
    sources = [ROOT / 'ScreenService/PCScreenService.mm', OUT / 'ScreenCapturer.mm',
               REPO / 'src/STHIDEventGenerator.mm', REPO / 'src/OhMyJetsam.mm', ROOT / 'Sources/PCMemoryBudget.m']
    objects = []
    for source in sources:
        obj = OUT / (source.stem + '.o')
        flags=[arg for arg in common if source.suffix != '.m' or arg != '-std=c++20']
        base.run(flags + ['-c', source, '-o', obj])
        objects.append(obj)
    objects.append(availability_object(base,target,OUT))
    link = [ROOT / '.build-deps/llvm-mingw-20260908-msvcrt-x86_64/bin/lld.exe',
        '-flavor', 'darwin', '-arch', 'arm64', '-platform_version', 'ios', target.minimum, '16.5',
        '-syslibroot', base.SDK, '-L' + str(base.SDK / 'usr/lib'),
        '-L' + str(ROOT / '.build-deps/roothide-devkit/devkit/roothide'),
        '-F' + str(base.SDK / 'System/Library/Frameworks'),
        '-F' + str(base.SDK / 'System/Library/PrivateFrameworks'),
        '-F' + str(REPO / 'PrivateFrameworks'), '-headerpad', '0x1000',
        *objects, *target.libraries, '-lSystem', '-lobjc', '-lc++']
    for framework in ('Accelerate','CoreGraphics', 'CoreMedia', 'CoreVideo', 'Foundation', 'ImageIO', 'IOKit',
                      'IOSurface', 'QuartzCore', 'UIKit'):
        link += ['-framework', framework]
    base.run(link + ['-o', OUT / 'pocketscreen'])
    print('Screen tool service compiled')

if __name__ == '__main__':
    main()
