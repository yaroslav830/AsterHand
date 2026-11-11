"""Package an already signed .app as an environment-specific Debian archive (stdlib only)."""
import argparse
import gzip
import hashlib
import io
import json
import pathlib
import plistlib
import subprocess
import tarfile
from ios_build_profile import add_environment_args

ROOT = pathlib.Path(__file__).resolve().parents[1]

def tar_bytes(items):
    memory = io.BytesIO()
    with tarfile.open(fileobj=memory, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        directories=set()
        for name, _, _ in items:
            directories.update(str(parent) for parent in pathlib.PurePosixPath(name).parents if str(parent) != '.')
        for name in sorted(directories,key=lambda value:(value.count('/'),value)):
            info=tarfile.TarInfo(name+'/');info.type=tarfile.DIRTYPE;info.mode=0o755
            info.uid=info.gid=0;info.uname=info.gname='root';info.mtime=0
            archive.addfile(info)
        for name, contents, mode in items:
            info = tarfile.TarInfo(name)
            info.size = len(contents)
            info.mode = mode
            info.uid = info.gid = 0
            info.uname = info.gname = 'root'
            info.mtime = 0
            archive.addfile(info, io.BytesIO(contents))
    return gzip.compress(memory.getvalue(), mtime=0)

def ar_bytes(items):
    result = bytearray(b'!<arch>\n')
    for name, content in items:
        header = f'{name + "/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(content):<10}`\n'.encode('ascii')
        assert len(header) == 60
        result.extend(header)
        result.extend(content)
        if len(content) % 2:
            result.extend(b'\n')
    return bytes(result)

def package(app, output, roothide=False, rootful=False):
    if roothide and rootful:raise ValueError("Choose one jailbreak environment")
    native=roothide or rootful
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    executable = app / info['CFBundleExecutable']
    # Independent structural and signature verification is performed by verify_artifact.py.
    if not executable.is_file() or not (app / '_CodeSignature/CodeResources').is_file():
        raise RuntimeError('A signed app bundle is required. Sign before packaging.')
    expected='14.0' if rootful else '15.0'
    if info.get('MinimumOSVersion')!=expected:raise ValueError('Wrong minimum iOS for package environment')
    if info.get('AsterHandEnvironment') not in (None,'roothide' if roothide else 'rootful' if rootful else 'rootless'):raise ValueError('App environment does not match package')
    data = []
    for path in sorted(app.rglob('*')):
        if path.is_file():
            mode = 0o755 if path == executable or path.name in ('pocketremote', 'pocketscreen', 'pocketoverlay','pocketpty','pocketmaint') else 0o644
            prefix = 'Applications/PocketCodex.app/' if native else 'var/jb/Applications/PocketCodex.app/'
            data.append((prefix + path.relative_to(app).as_posix(), path.read_bytes(), mode))
    for name in ('local.pocketagent.remote','local.pocketagent.root','local.pocketagent.screen','local.pocketagent.overlay','local.agentgo.agent','local.agentgo.control','local.asterhand.recovery'):
        contents=(ROOT / 'packaging-roothide' / (name+'.plist')).read_bytes()
        if not native:
            contents=contents.replace(b'/Applications/PocketCodex.app/',b'/var/jb/Applications/PocketCodex.app/').replace(b'/var/pr/',b'/var/jb/var/agentgo/')
        data.append((('' if native else 'var/jb/')+'Library/LaunchDaemons/'+name+'.plist',contents,0o644))
    control_dir = ROOT / ('packaging-roothide/DEBIAN' if roothide else 'packaging-rootful/DEBIAN' if rootful else 'packaging/DEBIAN')
    control_names=['control','postinst','postrm','prerm']
    control = [(name, (control_dir / name).read_bytes().replace(b'\r\n', b'\n'),
                0o644 if name == 'control' else 0o755) for name in control_names]
    import re
    version = info['CFBundleShortVersionString']
    control = [(name,re.sub(rb'(?m)^Version: .*$',('Version: '+version).encode(),data) if name=='control' else data,mode) for name,data,mode in control]
    result = ar_bytes([('debian-binary', b'2.0\n'), ('control.tar.gz', tar_bytes(control)), ('data.tar.gz', tar_bytes(data))])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(result)
    sha = hashlib.sha256(result).hexdigest()
    (output.parent / (output.name + '.sha256')).write_text(sha + '  ' + output.name + '\n', encoding='utf-8')
    print(f'Packaged {output.name}: {len(result)} bytes; SHA-256 {sha}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=pathlib.Path, default=ROOT / 'build/PocketCodex.app')
    add_environment_args(parser)
    parser.add_argument('--out', type=pathlib.Path)
    args = parser.parse_args()
    version = plistlib.loads((args.app / 'Info.plist').read_bytes())['CFBundleShortVersionString']
    output = args.out or ROOT / ('dist/AsterHand-' + version + ('-RootHide' if args.environment == 'roothide' else '-Rootful' if args.environment == 'rootful' else '-Rootless') + '.deb')
    package(args.app, output, args.environment == 'roothide', args.environment == 'rootful')
