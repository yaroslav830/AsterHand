"""Preserve upstream notices and publish source material with mirrored packages."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import tarfile
from sync_ios_apt_upstreams import download


def data_archive(path):
    raw=path.read_bytes(); at=8
    while at<len(raw):
        header=raw[at:at+60]; name=header[:16].decode().strip().rstrip('/')
        size=int(header[48:58]); content=raw[at+60:at+60+size]; at+=60+size+size%2
        if name.startswith('data.tar'): return tarfile.open(fileobj=io.BytesIO(content),mode='r:*')
    raise ValueError('Missing data archive')


def collect(artifacts):
    state=json.loads((artifacts/'dependencies.json').read_text('utf-8'))
    output=artifacts/'third-party'; output.mkdir(parents=True,exist_ok=True)
    entries=[]
    for package in state['packages']:
        with data_archive(artifacts/package['path']) as archive:
            for member in archive.getmembers():
                name=Path(member.name).name
                if member.isfile() and any(token in name.lower() for token in ['copyright','license','copying']):
                    raw=archive.extractfile(member).read()
                    if name.endswith('.zst'):
                        from compression import zstd
                        raw=zstd.decompress(raw);name=name[:-4]
                    target=output/'notices'/(package['environment']+'-'+package['package']+'-'+name)
                    target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
                    entries.append({'package':package['package'],'environment':package['environment'],
                                    'path':target.relative_to(output).as_posix(),'sha256':hashlib.sha256(raw).hexdigest()})
    materials={}
    def add(name,url):materials[name]=url
    for package in state['packages']:
        if package['package']=='openssh-server':
            version=package['version'].split('-')[0]
            if 'p' not in version:version+='p1'
            tag='V_'+version.upper().replace('.','_').replace('P','_P')
            add('OpenSSH-'+version+'-LICENCE.txt','https://raw.githubusercontent.com/openssh/openssh-portable/'+tag+'/LICENCE')
        elif package['package']=='libcrypt2':
            version=package['version'].split('-')[0]
            add('libxcrypt-'+version+'.tar.gz','https://codeload.github.com/besser82/libxcrypt/tar.gz/refs/tags/v'+version)
        elif package['package']=='libpam-modules':
            version=package['version'].split('-')[0]
            add('pam_modules-'+version+'.tar.gz','https://codeload.github.com/ProcursusTeam/pam_modules/tar.gz/refs/tags/'+version)
        elif package['package']=='libssl1.1.1':
            version=package['version'].split('-')[0]
            add('OpenSSL-'+version+'-LICENSE.txt','https://raw.githubusercontent.com/openssl/openssl/OpenSSL_'+version.replace('.','_')+'/LICENSE')
    # Includes the build recipes, patches, source URL definitions and third-party
    # notices used by the original package builders. These archives are offered
    # with the binaries; neither their code nor maintainer scripts are executed.
    add('Procursus-build-recipes.tar.gz','https://codeload.github.com/ProcursusTeam/Procursus/tar.gz/refs/heads/main')
    add('RootHide-build-recipes.tar.gz','https://codeload.github.com/roothide/Procursus-roothide/tar.gz/refs/heads/main')
    for name,url in materials.items():
        destination=output/'sources'/name;destination.parent.mkdir(parents=True,exist_ok=True)
        raw=download(url);destination.write_bytes(raw)
        entries.append({'path':destination.relative_to(output).as_posix(),'upstream_url':url,
                        'size':len(raw),'sha256':hashlib.sha256(raw).hexdigest()})
    heading='''# Third-party software / 第三方软件

OpenSSH and its dependencies retain their original authors, maintainers and licenses. The DEBs are copied unchanged. AsterHand's original-code license terms do not replace these third-party licenses.

OpenSSH 及依赖保留原作者、维护者和许可证；DEB 按原样分发。AsterHand 原创代码的许可声明不适用于这些第三方软件。

Package versions, archive SHA-256 digests and original download URLs are recorded in [upstream-packages.json](../upstream-packages.json). The existing jailbreak bootstrap supplies dpkg, firmware metadata and (for RootHide) roothide itself; this source does not replace those bootstrap components.

The following materials accompany these binaries: embedded copyright/license notices, matching OpenSSH/OpenSSL notices, libxcrypt source archives, PAM module source and upstream build recipes/patches. Individual notices and source archives contain their respective license terms. Source archives are documentation/source material, not packages to install.

| Material | Upstream / package | SHA-256 |
| --- | --- | --- |
'''
    for entry in entries:
        origin=entry.get('upstream_url') or entry.get('environment','')+'/'+entry.get('package','')
        heading+='| ['+entry['path']+']('+entry['path']+') | '+origin+' | `'+entry['sha256']+'` |\n'
    (output/'README.md').write_text(heading,encoding='utf-8')
    (output/'materials.json').write_text(json.dumps(entries,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'third_party_materials':len(entries)}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('artifacts',type=Path)
    collect(parser.parse_args().artifacts)
