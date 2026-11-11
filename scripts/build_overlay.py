"""Build the standalone iOS overlay; no SpringBoard injection is used."""
import pathlib
import subprocess
import sys
import argparse
from ios_build_profile import add_environment_args, profile

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build_windows as base

OUT = ROOT / 'build/overlay'

def main():
    global OUT
    parser=argparse.ArgumentParser();add_environment_args(parser,default='roothide');args=parser.parse_args();target=profile(args)
    OUT=ROOT/'build'/target.helper_directory('overlay')
    OUT.mkdir(parents=True, exist_ok=True)
    base.BUILD = OUT
    (OUT / 'compile.log').write_text('', encoding='utf-8')
    objects = []
    for name in ('PCOverlayUI', 'PCOverlayHost', 'PCScreenEdgeMask', 'PCMessageQueue', 'PCHaptics', 'PCAvailability', 'PCLocalization'):
        obj = OUT / (name + '.o')
        base.run([base.ZIG, 'cc', '-target', target.target, '-isysroot', base.SDK,
            '-iframework', base.SDK / 'System/Library/Frameworks', '-isystem', base.SDK / 'usr/include',
            '-I' + str(ROOT / '.build-deps/roothide-devkit/devkit'), '-I' + str(ROOT / 'Sources'), *target.defines, *target.availability, '-fobjc-arc', '-fblocks',
            '-O2', '-Wno-nullability-completeness', '-c', ROOT / ('Sources' if name in ('PCMessageQueue','PCHaptics','PCAvailability', 'PCLocalization') else 'Overlay') / (name + '.m'), '-o', obj])
        objects.append(obj)
    args = [ROOT / '.build-deps/llvm-mingw-20260908-msvcrt-x86_64/bin/lld.exe',
        '-flavor', 'darwin', '-arch', 'arm64', '-platform_version', 'ios', target.minimum, '16.5',
        '-syslibroot', base.SDK, '-F' + str(base.SDK / 'System/Library/Frameworks'),
        '-F' + str(base.SDK / 'System/Library/PrivateFrameworks'),
        '-L' + str(base.SDK / 'usr/lib'), '-L' + str(ROOT / '.build-deps/roothide-devkit/devkit/roothide'),
        *target.libraries, '-lproc', '-lSystem', '-lobjc', '-headerpad', '0x1000', *objects]
    for name in ('Foundation', 'UIKit', 'CoreFoundation', 'CoreGraphics', 'QuartzCore', 'IOKit',
                 'BackBoardServices', 'GraphicsServices', 'SpringBoardServices'):
        args += ['-framework', name]
    base.run(args + ['-o', OUT / 'pocketoverlay'])
    subprocess.run([str(ROOT / '.build-deps/codesign/apple-codesign-0.29.0-x86_64-pc-windows-msvc/rcodesign.exe'),
        'sign', '--timestamp-url', 'none', '--entitlements-xml-file', 'overlay-entitlements.plist',
        str(OUT / 'pocketoverlay')], cwd=ROOT, check=True)
    print('Standalone overlay compiled and signed')

if __name__ == '__main__':
    main()
