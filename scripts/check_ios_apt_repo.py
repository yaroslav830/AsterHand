"""Independently check published APT records, archive hashes and OpenPGP signatures."""
import argparse
import bz2
from email.parser import Parser
import gzip
import hashlib
import json
import lzma
from pathlib import Path
import subprocess
import tempfile
from build_ios_apt_repo import gpg_path, deb_control
from ios_apt_common import dependencies, satisfies


def check(args):
    root = args.site.resolve()
    manifest = json.loads((root/'repository.json').read_text('utf-8'))
    expected = {'rootful':'iphoneos-arm', 'rootless':'iphoneos-arm64', 'roothide':'iphoneos-arm64e'}
    assert manifest['selection'] == 'package-manager-native-dpkg-architecture'
    gpgv = str(args.gpgv)
    checked = 0
    with tempfile.TemporaryDirectory(prefix='asterhand-apt-verify-') as home:
        for environment in ['auto', *expected]:
            folder = root if environment == 'auto' else root/environment
            packages = (folder/'Packages').read_bytes()
            records = [Parser().parsestr(part) for part in packages.decode().strip().split('\n\n')]
            extra = [p for p in manifest.get('dependency_packages',[]) if p['environment']==environment]
            assert len(records) == (3 if environment == 'auto' else 1 + len(extra))
            architectures = {r['Architecture'] for r in records}
            assert architectures == set(expected.values()) if environment == 'auto' else architectures <= {expected[environment],'all'}
            own = [r for r in records if r['Package']=='local.pocketcodex']
            assert len(own) == (3 if environment == 'auto' else 1)
            for record in records:
                if record['Package'] == 'local.pocketcodex': assert record['Version'] == manifest['version']
                filename = record['Filename']
                assert filename.startswith('pool/') and '..' not in Path(filename).parts
                raw = (folder/filename).read_bytes()
                _,control=deb_control(folder/filename)
                for field in ['Package','Version','Architecture','Depends','Pre-Depends']:
                    assert control.get(field,'')==record.get(field,''), (filename,field)
                assert len(raw) == int(record['Size'])
                for field, algorithm in [('MD5sum','md5'),('SHA1','sha1'),('SHA256','sha256'),('SHA512','sha512')]:
                    assert record[field] == hashlib.new(algorithm, raw).hexdigest()
                checked += 1
            if extra:
                byname={r['Package']:r for r in records}
                base=manifest['openssh'][environment]['bootstrap_requirements']
                for record in records:
                    if record['Package']=='local.pocketcodex':continue
                    for alternatives in dependencies(record):
                        assert any(name in base or (name in byname and satisfies(byname[name]['Version'],operator,version))
                                   for name,operator,version in alternatives), (record['Package'],alternatives)
                assert 'openssh' in byname and 'openssh-server' in byname
            for name, decompress in [('Packages.gz',gzip.decompress),('Packages.bz2',bz2.decompress),('Packages.xz',lzma.decompress)]:
                assert decompress((folder/name).read_bytes()) == packages
            release = Parser().parsestr((folder/'Release').read_text('utf-8'))
            for line in release['SHA256'].strip().splitlines():
                digest, size, filename = line.split()
                raw = (folder/filename).read_bytes()
                assert len(raw) == int(size) and hashlib.sha256(raw).hexdigest() == digest
            common = [gpgv,'--homedir',gpg_path(home,gpgv),'--keyring',gpg_path(root/'apt-repository-key.gpg',gpgv),'--status-fd','1']
            for files in [[folder/'Release.gpg',folder/'Release'],[folder/'InRelease']]:
                result = subprocess.run(common+[gpg_path(p,gpgv) for p in files],capture_output=True,text=True,check=True)
                assert 'VALIDSIG '+manifest['signing_fingerprint'] in result.stdout
    assert (root/'.nojekyll').exists()
    assert not list(root.rglob('*.key')) and not list(root.rglob('private-keys-v1.d'))
    assert len({p['sha256'] for p in manifest['variants']}) == 3
    result={'index_package_records_verified':checked,'signature_verifications':8,
            'compression_checks':12,'environment_matches':3,'private_signing_key_in_site':False}
    result['mirrored_dependencies']=len(manifest.get('dependency_packages',[]))
    print(json.dumps(result))
    return result


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('site',type=Path)
    parser.add_argument('--gpgv',default='gpgv')
    check(parser.parse_args())
