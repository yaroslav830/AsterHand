"""One release version for iOS, Android, Windows and the control skill."""
import argparse
import json
import pathlib
import plistlib
import re
import os
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

def release():
    value = json.loads((ROOT / 'version.json').read_text(encoding='utf-8'))
    if not re.fullmatch(r'\d+\.\d+(?:\.\d+)?', value['version']) or not isinstance(value['build'], int) or value['build'] < 1:
        raise ValueError('Invalid version.json')
    return value

def sync(check=False):
    value = release()
    updates = {}
    if (ROOT / 'Resources/Info.plist').exists():
        path = ROOT / 'Resources/Info.plist'
        info = plistlib.loads(path.read_bytes())
        info.update(CFBundleShortVersionString=value['version'], CFBundleVersion=str(value['build']), MinimumOSVersion='15.0')
        updates[path] = plistlib.dumps(info, sort_keys=False)
    for directory in ('packaging', 'packaging-roothide', 'packaging-rootful'):
        path = ROOT / directory / 'DEBIAN/control'
        if path.exists():
            updates[path] = re.sub(r'(?m)^Version: .*$', 'Version: '+value['version'], path.read_text(encoding='utf-8')).encode('utf-8')
    for relative in ('desktop/package.json','mcp/package.json'):
        path = ROOT / relative
        if path.exists():
            package = json.loads(path.read_text(encoding='utf-8'))
            display = value.get('windows_version',value['version']) if relative=='desktop/package.json' else value['version']
            package['version'] = display if display.count('.') == 2 else display+'.0'
            updates[path] = (json.dumps(package, indent=2, ensure_ascii=False)+'\n').encode('utf-8')
    path = ROOT / 'android/app/build.gradle'
    if path.exists():
        gradle = path.read_text(encoding='utf-8')
        gradle = re.sub(r'(?m)^(\s*versionCode)\s+\d+',lambda match:match[1]+' '+str(value['build']),gradle)
        gradle = re.sub(r"(?m)^(\s*versionName)\s+'[^']+'",lambda match:match[1]+" '"+value['version']+"'",gradle)
        updates[path] = gradle.encode('utf-8')
    for directory in ('skills/asterhand-skill','skills/agentgo-control'):
        path = ROOT / directory / 'version.json'
        if path.parent.exists():updates[path] = (json.dumps(value, indent=2)+'\n').encode('utf-8')
    mismatches = [str(p.relative_to(ROOT)) for p, data in updates.items() if not p.exists() or p.read_bytes().replace(b'\r\n', b'\n') != data.replace(b'\r\n', b'\n')]
    if check and mismatches:
        raise ValueError('Version drift: '+', '.join(mismatches))
    if not check:
        for path, data in updates.items():
            if path.exists() and path.read_bytes() == data:
                continue
            fd, temporary = tempfile.mkstemp(prefix=path.name+'.', dir=path.parent)
            try:
                with os.fdopen(fd, 'wb') as target:
                    target.write(data)
                os.replace(temporary, path)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
    return value

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    print(json.dumps(sync(parser.parse_args().check)))
