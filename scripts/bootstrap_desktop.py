"""Install the pinned local WebSocket dependency and copy the upstream noVNC client."""
import base64
import hashlib
import io
import json
import pathlib
import shutil
import tarfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
target = ROOT / 'desktop/node_modules/ws'
if not (target / 'package.json').exists():
    meta = json.load(urllib.request.urlopen('https://registry.npmjs.org/ws/8.18.3'))
    blob = urllib.request.urlopen(meta['dist']['tarball']).read()
    expected = meta['dist']['integrity'].split('sha512-', 1)[1]
    if base64.b64encode(hashlib.sha512(blob).digest()).decode() != expected: raise ValueError('ws integrity mismatch')
    target.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(blob), mode='r:gz') as archive:
        for member in archive.getmembers():
            path = pathlib.PurePosixPath(member.name)
            if not member.isfile() or path.parts[0] != 'package' or '..' in path.parts: raise ValueError('Unexpected ws archive member')
            output = target.joinpath(*path.parts[1:]); output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(archive.extractfile(member).read())
source = ROOT / '.build-deps/TrollVNC-source/layout/usr/share/trollvnc/webclients/novnc'
for name in ('core', 'vendor'):
    shutil.copytree(source / name, ROOT / 'desktop/public/novnc' / name, dirs_exist_ok=True)
print('Local desktop dependencies ready.')
