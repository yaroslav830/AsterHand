"""Cross-compile the native iOS app with an isolated Zig/Clang toolchain."""
import pathlib
import subprocess
import sys
import argparse
import plistlib
from ios_build_profile import add_environment_args, profile

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEPS = ROOT / '.build-deps'
SDK = DEPS / 'sdks' / 'iPhoneOS16.5.sdk'
ZIG = DEPS / 'zig-x86_64-windows-0.14.1' / 'zig.exe'
BUILD = ROOT / 'build'
APP = BUILD / 'PocketCodex.app'

def run(args):
    p = subprocess.run([str(x) for x in args], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors='replace')
    log = BUILD / 'compile.log'
    with log.open('a', encoding='utf-8') as f:
        f.write('COMMAND: ' + subprocess.list2cmdline([str(x) for x in args]) + '\n')
        f.write(p.stdout)
    if p.returncode:
        print('Command failed, exit code: ' + str(p.returncode))
        print(p.stdout[-24000:])
        raise SystemExit(p.returncode)
    if p.stdout.strip():
        print(p.stdout[-5000:])

def main():
    from sync_design import sync as sync_design
    sync_design()
    from sync_localizations import sync as sync_localizations
    sync_localizations()
    from sync_version import sync
    from build_login_streams import build
    from build_login_forms import build as build_forms
    sync()
    build()
    build_forms()
    global BUILD, APP
    parser = argparse.ArgumentParser()
    add_environment_args(parser)
    parser.add_argument('--build-dir',type=pathlib.Path)
    args = parser.parse_args()
    target=profile(args)
    if (args.environment == 'roothide'):
        BUILD = ROOT / 'build/roothide'
        APP = BUILD / 'PocketCodex.app'
        for dependency in (DEPS / 'roothide-devkit/devkit/roothide.h', DEPS / 'llvm-mingw-20260908-msvcrt-x86_64/bin/lld.exe'):
            if not dependency.exists():
                sys.exit('First run: python scripts/bootstrap_windows.py --roothide')
    if args.environment == 'rootful':
        BUILD=ROOT/'build/rootful'
        APP=BUILD/'PocketCodex.app'
    if not ZIG.exists() or not SDK.exists():
        sys.exit('First run: python scripts/bootstrap_windows.py')
    if args.build_dir:
        BUILD=args.build_dir.resolve()
        APP=BUILD / 'PocketCodex.app'
    APP.mkdir(parents=True, exist_ok=True)
    (BUILD / 'compile.log').write_text('', encoding='utf-8')
    common = [ZIG, 'cc', '-target', target.target, '-isysroot', SDK,
        '-iframework', SDK / 'System/Library/Frameworks', '-isystem', SDK / 'usr/include',
        *target.defines, *target.availability, '-fblocks', '-O2', '-Wall', '-Wextra', '-Wno-unused-parameter', '-Wno-nullability-completeness',
        '-Wno-macro-redefined', '-Wno-unknown-warning-option', '-ISources']
    if (args.environment == 'roothide'):
        common += ['-I.build-deps/roothide-devkit/devkit']
    objects = []
    for src in sorted((ROOT / 'Sources').glob('*')):
        if src.suffix not in ('.m', '.c'):
            continue
        obj = BUILD / (src.stem + '.o')
        print('Compiling ' + src.name, flush=True)
        run(common + (['-fobjc-arc'] if src.suffix == '.m' else []) + ['-c', src, '-o', obj])
        objects.append(obj)
    print('Linking...', flush=True)
    lld = DEPS / 'llvm-mingw-20260908-msvcrt-x86_64/bin/lld.exe'
    run([lld, '-flavor', 'darwin', '-arch', 'arm64', '-platform_version', 'ios', target.minimum, '16.5',
            '-syslibroot', SDK, '-F' + str(SDK / 'System/Library/Frameworks'), '-L' + str(SDK / 'usr/lib'),
            '-L.build-deps/roothide-devkit/devkit/roothide', *(['-lroothide'] if (args.environment == 'roothide') else []), '-lproc', '-lSystem', '-lobjc',
            '-framework', 'Foundation', '-framework', 'UIKit', '-framework', 'Security', '-framework', 'CoreGraphics', '-framework', 'WebKit', '-framework', 'SafariServices', '-framework', 'PhotosUI', '-framework', 'UniformTypeIdentifiers', '-framework', 'UserNotifications', '-framework', 'AVFoundation', '-framework', 'Speech', '-framework', 'Intents', '-framework', 'IntentsUI', '-framework', 'CallKit',
            '-headerpad', '0x1000', *objects, '-o', APP / 'PocketCodex'])
    import shutil
    for name in ('Info.plist', 'localizations.json', 'user-guide.json', 'tools.json', 'screen-tools.json', 'chatgpt-login-compat.js', 'chatgpt-login-streams.js', 'chatgpt-login-forms.js'):
        shutil.copy2(ROOT / 'Resources' / name, APP / name)
    if (ROOT / 'Resources/Guide').is_dir():
        for old in (APP / 'Guide').glob('*'):
            if old.is_file() and not (ROOT / 'Resources/Guide' / old.name).is_file():
                old.unlink()
        shutil.copytree(ROOT / 'Resources/Guide', APP / 'Guide', dirs_exist_ok=True)
    legacy_config = APP / 'license-config.json'
    if legacy_config.is_file():
        legacy_config.unlink()
    for locale in (ROOT / 'Resources').glob('*.lproj'):
        shutil.copytree(locale, APP / locale.name, dirs_exist_ok=True)
    info = plistlib.loads((APP / 'Info.plist').read_bytes())
    info['MinimumOSVersion'] = target.minimum
    info['AsterHandEnvironment'] = args.environment
    (APP / 'Info.plist').write_bytes(plistlib.dumps(info))
    helper = ROOT / ('build/'+target.helper_directory('remote-helper')+'/pocketremote')
    if not helper.exists(): sys.exit('First run: python scripts/build_remote_helper.py')
    shutil.copy2(helper, APP / 'pocketremote')
    screen = ROOT / ('build/'+target.helper_directory('screen-service')+'/pocketscreen')
    if not screen.exists(): sys.exit('First run: python scripts/build_screen_service.py')
    shutil.copy2(screen, APP / 'pocketscreen')
    overlay = ROOT / ('build/'+target.helper_directory('overlay')+'/pocketoverlay')
    if not overlay.exists(): sys.exit('First run: python scripts/build_overlay.py')
    shutil.copy2(overlay, APP / 'pocketoverlay')
    maintenance=ROOT/'build'/target.helper_directory('maintenance')/'pocketmaint'
    if not maintenance.exists():sys.exit('First run: python scripts/build_maintenance.py --'+args.environment)
    shutil.copy2(maintenance,APP/'pocketmaint')
    for icon in (ROOT / 'Resources/Icons').glob('*.png'):
        shutil.copy2(icon, APP / icon.name)
    shutil.copy2(ROOT / 'third_party/TrollSpeed/LICENSE', APP / 'TrollSpeed-LICENSE.txt')
    shutil.copy2(ROOT / 'third_party/TrollVNC/COPYING', APP / 'TrollVNC-COPYING.txt')
    shutil.copy2(ROOT / 'third_party/web-streams-polyfill/LICENSE', APP / 'web-streams-polyfill-LICENSE.txt')
    shutil.copy2(ROOT / 'third_party/formdata-submitter-polyfill/LICENSE', APP / 'formdata-submitter-polyfill-LICENSE.txt')
    print('Compiled: ' + str(APP))
    print('Signing and packaging are separate: see README.md')

if __name__ == '__main__':
    main()
