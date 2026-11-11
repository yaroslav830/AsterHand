"""Build the signed AsterHand flat APT repository without changing its DEBs."""
import argparse
import bz2
from datetime import datetime, timezone
from email.utils import format_datetime
import gzip
import hashlib
import io
import json
import lzma
from pathlib import Path
import shutil
import subprocess
import tarfile
from ios_apt_common import records, dependencies, satisfies

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = {
    'rootful': ('Rootful', 'iphoneos-arm', '14.0'),
    'rootless': ('Rootless', 'iphoneos-arm64', '15.0'),
    'roothide': ('RootHide', 'iphoneos-arm64e', '15.0'),
}


def deb_control(path):
    raw = path.read_bytes()
    if not raw.startswith(b'!<arch>\n'):
        raise ValueError('Not a Debian ar archive: ' + path.name)
    at = 8
    while at < len(raw):
        header = raw[at:at+60]
        if len(header) != 60 or header[58:60] != b'`\n':
            raise ValueError('Invalid ar header')
        name = header[:16].decode().strip().rstrip('/')
        length = int(header[48:58])
        content = raw[at+60:at+60+length]
        if name.startswith('control.tar'):
            with tarfile.open(fileobj=io.BytesIO(content), mode='r:*') as archive:
                member = next(x for x in archive.getmembers() if x.name.lstrip('./') == 'control')
                text = archive.extractfile(member).read().decode('utf-8').replace('\r\n', '\n').strip()
                return text, records(text)[0]
        at += 60 + length + length % 2
    raise ValueError('Missing Debian control archive')


def gpg_path(value, executable):
    path = str(Path(value).resolve()).replace('\\', '/')
    if 'git/usr/bin/' in str(executable).replace('\\', '/').lower() and len(path) > 2 and path[1] == ':':
        path = '/' + path[0].lower() + path[2:]
    return path


def build(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    base = args.base_url.rstrip('/') + '/'
    packages = []
    sync = json.loads(args.dependencies.read_text('utf-8')) if args.dependencies else None
    if sync:
        args.version, args.build = sync['version'], sync['build']
    for environment, (label, architecture, minimum) in VARIANTS.items():
        path = args.artifacts / ('AsterHand-' + args.version + '-' + label + '.deb')
        control, fields = deb_control(path)
        assert fields['Package'] == 'local.pocketcodex'
        assert fields['Version'] == args.version
        assert fields['Architecture'] == architecture
        assert 'firmware (>= ' + minimum + ')' in fields['Depends']
        if environment == 'roothide':
            assert 'roothide::compatible' in fields.get('Tag', '') and 'roothide' in fields['Depends']
        raw = path.read_bytes()
        hashes = {name: hashlib.new(name, raw).hexdigest() for name in ['md5', 'sha1', 'sha256', 'sha512']}
        extra = '\n'.join([
            'Filename: pool/' + path.name,
            'Size: ' + str(len(raw)),
            'MD5sum: ' + hashes['md5'],
            'SHA1: ' + hashes['sha1'],
            'SHA256: ' + hashes['sha256'],
            'SHA512: ' + hashes['sha512'],
            'Homepage: https://github.com/yaroslav830/AsterHand',
            'Depiction: ' + base + '?environment=' + environment + '#package',
            'Icon: ' + base + 'CydiaIcon.png',
        ])
        packages.append({'environment': environment, 'label': label, 'architecture': architecture,
                         'minimum_ios': minimum, 'filename': path.name, 'version': fields['Version'],
                         'size': len(raw), 'sha256': hashes['sha256'], 'stanza': control + '\n' + extra + '\n\n', 'own': True})
        for destination in [output/'pool'/path.name, output/environment/'pool'/path.name]:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
            assert hashlib.sha256(destination.read_bytes()).hexdigest() == hashes['sha256']

    own_packages = list(packages)
    if sync:
        for package in sync['packages']:
            environment = package['environment']
            path = args.dependencies.parent/package['path']
            control, fields = deb_control(path)
            raw = path.read_bytes()
            assert hashlib.sha256(raw).hexdigest() == package['sha256']
            assert len(raw) == package['size']
            assert fields['Package'] == package['package'] and fields['Version'] == package['version']
            assert fields['Architecture'] in [VARIANTS[environment][1], 'all']
            # Preserve the original DEB and metadata; only repository file/hash
            # fields are added. In particular Architecture: all is never relabeled.
            assert not any(k in fields for k in ['Filename','Size','SHA256','MD5sum'])
            extra = '\n'.join(['Filename: pool/'+package['filename'], 'Size: '+str(len(raw)),
                *[heading+': '+hashlib.new(algorithm,raw).hexdigest() for algorithm,heading in
                  [('md5','MD5sum'),('sha1','SHA1'),('sha256','SHA256'),('sha512','SHA512')]]])
            packages.append({**package,'stanza':control+'\n'+extra+'\n\n','own':False})
            destination = output/environment/'pool'/package['filename']
            destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(path,destination)

    gpg = args.gpg or shutil.which('gpg')
    if not gpg:
        raise ValueError('GnuPG is required; provide --gpg or install gpg.')
    home = args.gpg_home.resolve()
    if home == output or output in home.parents:
        raise ValueError('The private GPG home must stay outside the public site.')
    common = [str(gpg), '--homedir', gpg_path(home, gpg), '--batch', '--yes', '--pinentry-mode', 'loopback']
    listing = subprocess.check_output(common + ['--with-colons', '--list-secret-keys'], text=True)
    fingerprint = args.key or next(line.split(':')[9] for line in listing.splitlines() if line.startswith('fpr:'))
    public_key = subprocess.check_output(common + ['--armor', '--export', fingerprint])
    keyring = subprocess.check_output(common + ['--export', fingerprint])
    (output/'apt-repository-key.asc').write_bytes(public_key)
    (output/'apt-repository-key.gpg').write_bytes(keyring)
    assert b'PRIVATE KEY' not in public_key

    for environment in ['auto', *VARIANTS]:
        directory = output if environment == 'auto' else output/environment
        # A flat unified index cannot isolate environment-specific Architecture:
        # all payloads. Keep its original AsterHand-only behavior. Complete native
        # OpenSSH closures are served by each environment's independent source.
        selected = own_packages if environment == 'auto' else [p for p in packages if p['environment'] == environment]
        index = ''.join(p['stanza'] for p in selected).encode()
        compressed = {'Packages': index, 'Packages.gz': gzip.compress(index, mtime=0),
                      'Packages.bz2': bz2.compress(index), 'Packages.xz': lzma.compress(index)}
        for name, raw in compressed.items():
            (directory/name).write_bytes(raw)
        architectures = ' '.join(dict.fromkeys(p['architecture'] for p in selected))
        release = '\n'.join([
            'Origin: AsterHand', 'Label: AsterHand' + ('' if environment == 'auto' else ' ' + selected[0]['label']),
            'Suite: stable', 'Codename: asterhand', 'Version: ' + args.version,
            'Date: ' + format_datetime(datetime.now(timezone.utc)),
            'Architectures: ' + architectures, 'Components: main',
            'Description: AsterHand iOS - cross-device Root control and local device agents.',
        ]) + '\n'
        for algorithm, heading in [('md5','MD5Sum'), ('sha1','SHA1'), ('sha256','SHA256'), ('sha512','SHA512')]:
            release += heading + ':\n'
            for name, raw in compressed.items():
                release += ' ' + hashlib.new(algorithm, raw).hexdigest() + ' ' + str(len(raw)) + ' ' + name + '\n'
        release_path = directory/'Release'
        release_path.write_bytes(release.encode())
        signing = common + ['--local-user', fingerprint, '--digest-algo', 'SHA256']
        subprocess.run(signing + ['--armor', '--output', gpg_path(directory/'Release.gpg', gpg),
                                  '--detach-sign', gpg_path(release_path, gpg)], check=True, capture_output=True)
        subprocess.run(signing + ['--output', gpg_path(directory/'InRelease', gpg),
                                  '--clearsign', gpg_path(release_path, gpg)], check=True, capture_output=True)
        subprocess.run(common + ['--verify', gpg_path(directory/'Release.gpg', gpg), gpg_path(release_path, gpg)],
                       check=True, capture_output=True)
        assert gzip.decompress((directory/'Packages.gz').read_bytes()) == index
        assert bz2.decompress((directory/'Packages.bz2').read_bytes()) == index
        assert lzma.decompress((directory/'Packages.xz').read_bytes()) == index
        (directory/'CydiaIcon.png').write_bytes((ROOT/'Resources/Icons/AppIcon60x60@3x.png').read_bytes())

    for path in (ROOT/'apt-repo').iterdir():
        if path.suffix in {'.html', '.css', '.js', '.sh', '.md'}:
            shutil.copyfile(path, output/path.name)
    detector = (output/'detect-environment.sh').read_text('utf-8').replace('@VERSION@',args.version)
    (output/'detect-environment.sh').write_bytes(detector.encode())
    (output/'.nojekyll').write_bytes(b'')
    (output/'.gitattributes').write_bytes(b'* -text\n')
    for environment in VARIANTS:
        (output/environment/'index.html').write_text('<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=../?environment=' + environment + '"><a href="../?environment=' + environment + '">AsterHand repository</a>\n', encoding='utf-8')
    public = [{k:v for k,v in p.items() if k not in ['stanza','own']} for p in own_packages]
    manifest = {'version': args.version, 'build': args.build, 'base_url': base,
                'package_id': 'local.pocketcodex', 'signing_fingerprint': fingerprint,
                'variants': public, 'selection': 'package-manager-native-dpkg-architecture'}
    if sync:
        manifest.update({'release':sync['release'],'openssh':sync['lanes'],
                         'dependency_packages':sync['packages'], 'checked_at':sync['checked_at'],
                         'unified_scope':'asterhand-only','dependencies_scope':'environment-specific-sources',
                         'sync_schedule':'Every 6 hours and on stable GitHub Release publication/edit'})
        (output/'upstream-packages.json').write_text(json.dumps(sync,indent=2)+'\n',encoding='utf-8')
        shutil.copytree(args.dependencies.parent/'third-party',output/'third-party',dirs_exist_ok=True)
    (output/'repository.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    (output/'pool/SHA256SUMS.txt').write_text(''.join(p['sha256'] + '  ' + p['filename'] + '\n' for p in own_packages), encoding='utf-8')
    for environment in VARIANTS:
        (output/environment/'pool/SHA256SUMS.txt').write_text(''.join(p['sha256']+'  '+p['filename']+'\n' for p in packages if p['environment']==environment),encoding='utf-8')
    print(json.dumps({'output': str(output), 'packages': len(packages), 'signed_indices': 4,
                      'fingerprint': fingerprint, 'base_url': base}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', type=Path, default=ROOT/'dist')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--base-url', default='https://yaroslav830.github.io/AsterHand/ios-apt/')
    parser.add_argument('--version', default='1.0')
    parser.add_argument('--build', type=int, default=78)
    parser.add_argument('--gpg-home', type=Path, required=True)
    parser.add_argument('--gpg')
    parser.add_argument('--key')
    parser.add_argument('--dependencies',type=Path,help='Verified output of sync_ios_apt_upstreams.py')
    build(parser.parse_args())
