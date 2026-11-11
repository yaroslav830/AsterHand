"""Download the latest complete stable AsterHand Release and native OpenSSH closure.

Only downloads and reads packages. It never installs them or runs their scripts.
All upstream identity/layout checks finish before a site can be deployed.
"""
import argparse
import bz2
from datetime import datetime, timezone
import hashlib
import json
import lzma
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from build_ios_apt_repo import VARIANTS, deb_control, gpg_path
from ios_apt_common import records, dependency_closure, version_compare

ROOT = Path(__file__).resolve().parents[1]
USER_AGENT = 'Debian APT-HTTP/1.3 (2.6.0) AsterHand-Repository-Sync/1.0'


def download(url, limit=100_000_000):
    if not url.startswith('https://'):
        raise ValueError('HTTPS is required: ' + url)
    headers = {'User-Agent': USER_AGENT}
    # The ephemeral Actions token is sent only to the GitHub API, never upstreams.
    if urllib.parse.urlsplit(url).netloc == 'api.github.com' and os.environ.get('GITHUB_TOKEN'):
        headers['Authorization'] = 'Bearer ' + os.environ['GITHUB_TOKEN']
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as response:
                data = response.read(limit + 1)
                if len(data) > limit: raise ValueError('Download exceeds limit: ' + url)
                if not response.url.startswith('https://'): raise ValueError('Insecure redirect')
                return data
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            if isinstance(error,urllib.error.HTTPError) and error.code not in [429,500,502,503,504]: raise
            if attempt == 2: raise
            time.sleep(attempt + 1)


def get_json(url):
    return json.loads(download(url))


def relative_url(base, path):
    value = PurePosixPath(path)
    if value.is_absolute() or '..' in value.parts or urllib.parse.urlsplit(path).scheme or '\\' in path:
        raise ValueError('Invalid upstream filename: ' + path)
    return base.rstrip('/') + '/' + urllib.parse.quote(str(value), safe='/@:+')


def validate_archive(path, metadata, architecture):
    raw = path.read_bytes()
    if len(raw) != int(metadata['Size']) or hashlib.sha256(raw).hexdigest() != metadata['SHA256']:
        raise ValueError('Archive hash/size mismatch: ' + path.name)
    _, fields = deb_control(path)
    for name in ['Package', 'Version', 'Architecture']:
        if fields[name] != metadata[name]: raise ValueError('Archive control mismatch: ' + name)
    if fields['Architecture'] not in [architecture, 'all']:
        raise ValueError('Foreign package architecture: ' + path.name)
    # Index dependency declarations must describe the actual preserved DEB.
    for name in ['Depends', 'Pre-Depends', 'Conflicts', 'Provides']:
        if fields.get(name, '') != metadata.get(name, ''):
            raise ValueError('Archive dependency mismatch: ' + path.name + ': ' + name)
    return fields


def index_for_lane(name, config, gpgv, github_commit=None):
    provenance = {'label': config['label']}
    if config.get('github_repository'):
        # Pin Release, index and package bytes to one upstream GitHub tree. The
        # key published in RootHide's inherited keyring does not sign this repo.
        repo = config['github_repository']
        commit = github_commit or get_json('https://api.github.com/repos/' + repo + '/commits/main')['sha']
        if not re.fullmatch('[a-f0-9]{40}',commit): raise ValueError('Invalid GitHub commit')
        base = 'https://raw.githubusercontent.com/' + repo + '/' + commit + '/' + config['github_path']
        provenance.update({'authentication': 'github-https-immutable-commit', 'github_commit': commit,
                           'source': 'https://github.com/' + repo + '/tree/' + commit + '/' + config['github_path']})
    else:
        base = config['base_url']
        provenance.update({'authentication': 'openpgp-signed-release', 'fingerprint': config['fingerprint'], 'source': base})
    suite = base + config['suite']
    release = download(suite + 'Release')
    if config.get('keyring'):
        signature = download(suite + 'Release.gpg')
        with tempfile.TemporaryDirectory(prefix='asterhand-upstream-') as temp:
            home = Path(temp)
            (home/'Release').write_bytes(release); (home/'Release.gpg').write_bytes(signature)
            result = subprocess.run([gpgv, '--homedir', gpg_path(home,gpgv), '--keyring',
                gpg_path(ROOT/'apt-repo'/config['keyring'],gpgv), '--status-fd', '1',
                gpg_path(home/'Release.gpg',gpgv), gpg_path(home/'Release',gpgv)],
                capture_output=True, text=True, check=True)
            if 'VALIDSIG ' + config['fingerprint'] not in result.stdout: raise ValueError('Unexpected upstream signer')
    metadata = records(release.decode())[0]
    packed = download(suite + config['index'])
    algorithm = 'sha256' if 'SHA256' in metadata else 'md5'
    field = 'SHA256' if algorithm == 'sha256' else 'MD5Sum'
    digest, size, _ = next(line.split() for line in metadata[field].strip().splitlines() if line.split()[-1] == config['index'])
    if len(packed) != int(size) or hashlib.new(algorithm,packed).hexdigest() != digest:
        raise ValueError('Upstream index differs from Release: ' + name)
    content = bz2.decompress(packed) if config['index'].endswith('.bz2') else lzma.decompress(packed)
    provenance.update({'index_url': suite + config['index'], 'index_sha256': hashlib.sha256(content).hexdigest(),
                       'release_sha256': hashlib.sha256(release).hexdigest()})
    return records(content.decode()), base, provenance


def sync(args):
    config = json.loads((ROOT/'apt-repo/upstreams.json').read_text('utf-8'))
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    release = json.loads(args.release_json.read_text('utf-8')) if args.release_json else get_json('https://api.github.com/repos/' + config['github_repository'] + '/releases/latest')
    if release.get('draft') or release.get('prerelease'): raise ValueError('A stable published release is required')
    assets = release['assets']
    checksums = next((a for a in assets if a['name'] == 'SHA256SUMS.txt'), None)
    sums = {}
    if checksums:
        for line in download(checksums['browser_download_url']).decode().splitlines():
            parts = line.split()
            if len(parts) == 2 and re.fullmatch('[a-fA-F0-9]{64}',parts[0]): sums[parts[1].lstrip('*')] = parts[0].lower()
    variants, version = [], None
    for lane, (label, architecture, minimum) in VARIANTS.items():
        matches = [a for a in assets if re.fullmatch(r'AsterHand-[A-Za-z0-9.+~_-]+-' + label + r'\.deb', a['name'])]
        if len(matches) != 1: raise ValueError('Latest release needs exactly one ' + label + ' DEB')
        asset = matches[0]; name = asset['name']
        digest = asset.get('digest') or ('sha256:' + sums[name] if name in sums else '')
        if not re.fullmatch('sha256:[a-fA-F0-9]{64}', digest): raise ValueError('Release SHA-256 missing: ' + name)
        raw = download(asset['browser_download_url'])
        if len(raw) != asset['size'] or hashlib.sha256(raw).hexdigest() != digest[7:].lower():
            raise ValueError('Release checksum mismatch: ' + name)
        target = output/name; target.write_bytes(raw)
        _, fields = deb_control(target)
        if fields['Package'] != 'local.pocketcodex' or fields['Architecture'] != architecture:
            raise ValueError('Unexpected AsterHand identity/environment')
        if version is not None and fields['Version'] != version: raise ValueError('Mixed AsterHand versions')
        version = fields['Version']
        if 'firmware (>= ' + minimum + ')' not in fields['Depends']: raise ValueError('Unexpected firmware target')
        if name != 'AsterHand-' + version + '-' + label + '.deb': raise ValueError('Asset filename/version mismatch')
        if lane == 'roothide' and 'roothide::compatible' not in fields.get('Tag',''): raise ValueError('RootHide tag missing')
        variants.append({'environment':lane,'filename':name,'sha256':digest[7:],'asset_id':asset['id']})
    if args.previous_manifest:
        previous = json.loads(args.previous_manifest.read_text('utf-8'))
        comparison = version_compare(version, previous['version'])
        if comparison < 0: raise ValueError('Refusing to downgrade published AsterHand')
        if comparison == 0:
            for new, old in zip(variants, previous['variants']):
                if new['environment'] != old['environment'] or new['sha256'] != old['sha256']:
                    raise ValueError('A published DEB version must not be replaced with different bytes; bump its Version')
    mirrored, lanes = [], {}
    for lane, lane_config in config['lanes'].items():
        architecture = VARIANTS[lane][1]
        catalogue, base, provenance = index_for_lane(lane, lane_config, args.gpgv,args.roothide_commit if lane=='roothide' else None)
        selected, external = dependency_closure(catalogue, architecture, ['openssh'], lane_config['external'])
        for record in selected:
            source_url = relative_url(base, record['Filename'])
            # Content-addressed local name avoids collisions and makes changed
            # same-version upstream payloads distinguishable in provenance.
            filename = lane + '-' + record['SHA256'][:16] + '-' + PurePosixPath(record['Filename']).name
            destination = output/'dependencies'/filename
            destination.parent.mkdir(parents=True, exist_ok=True)
            if not destination.exists() or hashlib.sha256(destination.read_bytes()).hexdigest() != record['SHA256']:
                destination.write_bytes(download(source_url))
            fields = validate_archive(destination,record,architecture)
            mirrored.append({'environment':lane,'path':'dependencies/'+filename,'filename':filename,
                'package':fields['Package'],'version':fields['Version'],'architecture':fields['Architecture'],
                'sha256':record['SHA256'],'size':int(record['Size']),'upstream_url':source_url,
                'upstream_filename':record['Filename']})
        lanes[lane] = {'provenance':provenance,'bootstrap_requirements':external,
                       'packages':len(selected),'openssh_server_version':next(r['Version'] for r in selected if r['Package']=='openssh-server')}
        print(lane + ': ' + str(len(selected)) + ' OpenSSH packages/dependencies verified')
    build = re.search(r'\bbuild\s*[:#]?\s*(\d+)\b', release.get('name','')+' '+release.get('body',''), re.I)
    state = {'version':version,'build':int(build[1]) if build else None,
        'release':{'tag':release['tag_name'],'url':release['html_url'],'id':release['id'],'published_at':release['published_at']},
        'variants':variants,'packages':mirrored,'lanes':lanes,'checked_at':datetime.now(timezone.utc).isoformat()}
    (output/'dependencies.json').write_text(json.dumps(state,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'version':version,'release':release['tag_name'],'mirrored_dependencies':len(mirrored)}))
    return state


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--gpgv',default='gpgv')
    parser.add_argument('--previous-manifest',type=Path)
    parser.add_argument('--release-json',type=Path,help='Optional GitHub API snapshot for local builds without an API token')
    parser.add_argument('--roothide-commit',help='Optional exact upstream GitHub snapshot for reproducible local builds')
    sync(parser.parse_args())
