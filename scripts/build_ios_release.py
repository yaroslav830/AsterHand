"""Build, sign, package and verify one complete iOS environment on Windows."""
import argparse
import pathlib
import subprocess
import sys
from ios_build_profile import add_environment_args
from sync_version import sync

ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser();add_environment_args(parser);args=parser.parse_args()
    release=sync();environment=args.environment;flag='--'+environment
    app=ROOT/'build'/f'{environment}-{release["version"]}'/'PocketCodex.app'
    suffix={'rootful':'Rootful','rootless':'Rootless','roothide':'RootHide'}[environment]
    package=ROOT/'dist'/f'AsterHand-{release["version"]}-{suffix}.deb'
    steps=[('build_remote_helper.py',[flag]),('build_screen_service.py',[flag]),('build_overlay.py',[flag]),('build_maintenance.py',[flag]),
        ('build_windows.py',[flag,'--build-dir',str(app.parent)]),('sign_windows.py',[flag,'--app',str(app)]),
        ('package_app.py',[flag,'--app',str(app)]),('verify_artifact.py',[flag,str(package)])]
    for script,arguments in steps:
        print('Running '+script+' '+flag,flush=True)
        subprocess.run([sys.executable,'-X','utf8',str(ROOT/'scripts'/script),*arguments],cwd=ROOT,check=True)
    print(str(package))
    from sync_desktop_packages import sync_after_build
    sync_after_build([package])
if __name__=='__main__':main()
