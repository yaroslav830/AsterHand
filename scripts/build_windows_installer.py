"""Build a per-user native NSIS installer, without installing build tools globally."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile
from build_windows_desktop import windows_icon

ROOT=Path(__file__).resolve().parents[1]
URL='https://downloads.sourceforge.net/project/nsis/NSIS%203/3.13/nsis-3.13.zip'
SHA256='ba63dffc4410ee89193e1cb5a41989991bd77c61068da17e3156d136b7b0b3d8'

def compiler():
    archive=ROOT/'.build-deps/nsis-3.13.zip'
    archive.parent.mkdir(parents=True,exist_ok=True)
    if not archive.exists():
        subprocess.run(['curl.exe','-L','--fail','--max-time','120','-o',str(archive),URL],check=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA256:
        raise RuntimeError('NSIS compiler archive SHA-256 mismatch')
    target=ROOT/'.build-deps/nsis/nsis-3.13/makensis.exe'
    if not target.exists():
        with zipfile.ZipFile(archive) as z:
            for item in z.infolist():
                if '..' in Path(item.filename).parts or Path(item.filename).is_absolute():
                    raise RuntimeError('Unsafe compiler archive member')
            z.extractall(ROOT/'.build-deps/nsis')
    return target

def build(output,app_id='AsterHand.Windows',name='AsterHand',payload=None):
    output=Path(output).resolve();output.parent.mkdir(parents=True,exist_ok=True)
    default_payload=payload is None
    payload=ROOT/'dist/AsterHand-Windows.exe' if default_payload else Path(payload).resolve(strict=True)
    icon=windows_icon()
    release=json.loads((ROOT/'version.json').read_text(encoding='utf-8'))
    version='.'.join((release.get('windows_version',release['version']).split('.')+['0','0'])[:3]+[str(release['build'])])
    command=[str(compiler()),'/INPUTCHARSET','UTF8','/V2',
             '/DVERSION='+version,'/DOUTPUT='+str(output),'/DAPP_ID='+app_id,'/DAPP_NAME='+name,
             '/DAPP_ALIAS='+('AsterHand.exe' if app_id=='AsterHand.Windows' else app_id+'.exe'),
             '/DPAYLOAD='+str(payload),
             '/DREADME='+str(ROOT/'desktop/windows/README.md'),
             '/DREADME_ZH='+str(ROOT/'desktop/windows/README.zh-CN.md'),
             '/DICON='+str(icon),str(ROOT/'packaging-windows/AsterHand.nsi')]
    subprocess.run(command,cwd=ROOT,check=True)
    metadata={'file':output.name,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'bytes':output.stat().st_size,'version':version,
              'nativeInstaller':True,'scope':'current user','requiresAdministrator':False,
              'languages':['en','zh-CN'],'fallbackLanguage':'en','readmeFiles':['README.md','README.zh-CN.md'],
              'minimumRuntime':'.NET Framework 4.6.2','windowsTarget':'Windows 7 SP1 or newer; see runtime test report for verified systems',
              'payloadSha256':hashlib.sha256(payload.read_bytes()).hexdigest(),
              'uninstallRegistryKey':'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\'+app_id,
              'preservesUserDataOnUninstall':True}
    if output==ROOT/'dist/AsterHand-Windows-Setup.exe' and app_id=='AsterHand.Windows':
        (output.parent/'AsterHand-Windows-installer.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        (output.parent/'AsterHand-Windows-SHA256.txt').write_text(metadata['payloadSha256']+'  AsterHand-Windows.exe\n'+metadata['sha256']+'  '+output.name+'\n',encoding='utf-8')
    if default_payload:
        from sync_desktop_packages import sync_after_build
        sync_after_build([output, output.parent / 'AsterHand-Windows.exe'])
    return metadata

if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--output',type=Path,default=ROOT/'dist/AsterHand-Windows-Setup.exe')
    p.add_argument('--payload',type=Path,help='Use an explicitly staged portable executable without syncing desktop packages')
    a=p.parse_args()
    print(json.dumps(build(a.output,payload=a.payload),ensure_ascii=False))
