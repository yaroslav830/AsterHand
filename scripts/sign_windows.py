import pathlib
import subprocess
import argparse
from ios_build_profile import add_environment_args

ROOT = pathlib.Path(__file__).resolve().parents[1]
SIGNER = ROOT / '.build-deps/codesign/apple-codesign-0.29.0-x86_64-pc-windows-msvc/rcodesign.exe'

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    add_environment_args(parser)
    parser.add_argument('--app',type=pathlib.Path)
    args = parser.parse_args()
    app = ROOT / ('build/roothide/PocketCodex.app' if args.environment == 'roothide' else 'build/rootful/PocketCodex.app' if args.environment == 'rootful' else 'build/PocketCodex.app')
    if args.app:app=args.app.resolve()
    # Scoped rcodesign arguments interpret ':' specially; use a relative plist path.
    flags = ['--entitlements-xml-file', 'entitlements.plist']
    if (app / 'pocketremote').exists(): flags += ['--entitlements-xml-file', 'pocketremote:remote-entitlements.plist']
    if (app / 'pocketscreen').exists(): flags += ['--entitlements-xml-file', 'pocketscreen:remote-entitlements.plist']
    if (app / 'pocketoverlay').exists(): flags += ['--entitlements-xml-file', 'pocketoverlay:overlay-entitlements.plist']
    if (app / 'pocketmaint').exists(): flags += ['--entitlements-xml-file', 'pocketmaint:entitlements.plist']
    subprocess.run([str(SIGNER), 'sign', *flags, '--timestamp-url', 'none', str(app)], cwd=ROOT, check=True)
