"""Exercise real NSIS install/upgrade/uninstall in uniquely named QA locations."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import uuid
import winreg
from build_windows_installer import build,ROOT

def digest(file): return hashlib.sha256(Path(file).read_bytes()).hexdigest()
def registry(key,name=''):
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,key,0,winreg.KEY_READ|winreg.KEY_WOW64_32KEY) as k:
            return winreg.QueryValueEx(k,name)[0]
    except FileNotFoundError:return None

def production_registration():
    uninstall='Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\AsterHand.Windows'
    alias='Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\AsterHand.exe'
    return {name:registry(uninstall,name) for name in ['DisplayName','DisplayVersion','InstallLocation','UninstallString']}|{'AppPath':registry(alias)}

def main():
    stamp=uuid.uuid4().hex
    app_id='AsterHand.QA.'+stamp
    name='AsterHand-QA-'+stamp
    root=(ROOT/'.private'/('installer-qa-'+stamp)).resolve();root.mkdir(parents=True)
    target=root/'Installed App';profile=root/'User Data'
    setup=root/'QA-Setup.exe';build(setup,app_id,name)
    reg='Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\'+app_id
    app_path='Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\'+app_id+'.exe'
    menu=Path(os.environ['APPDATA'])/'Microsoft/Windows/Start Menu/Programs'/name
    production_before=production_registration()
    report={'appId':app_id,'checks':[],'testedPayloadSha256':digest(ROOT/'dist/AsterHand-Windows.exe'),'userDataRemoved':False}
    def check(value,label):
        if not value:raise RuntimeError(label)
        report['checks'].append(label)
    def install():
        # NSIS /D is last and unquoted by definition, including embedded spaces.
        return subprocess.run(subprocess.list2cmdline([str(setup),'/S'])+' /D='+str(target),timeout=30).returncode
    try:
        check(registry(reg,'InstallLocation') is None,'QA registry starts empty')
        check(install()==0,'Native installer completes without elevation')
        check(digest(target/'AsterHand.exe')==digest(ROOT/'dist/AsterHand-Windows.exe'),'Installed payload SHA-256 matches release')
        check(registry(reg,'InstallLocation')==str(target),'Apps uninstall registration readback')
        check(registry(reg,'UninstallString')=='"'+str(target/'Uninstall.exe')+'"','Quoted uninstall command readback')
        check(registry(app_path)==str(target/'AsterHand.exe'),'App Paths registration readback')
        check((menu/(name+'.lnk')).is_file() and (menu/('卸载 '+name+'.lnk')).is_file(),'Start menu launch and uninstall shortcuts exist')
        app=subprocess.Popen([str(target/'AsterHand.exe'),'--data-dir',str(profile),'--isolated','--port','0'],cwd=target)
        try:
            until=time.monotonic()+10
            while time.monotonic()<until and not (profile/'settings.dat').exists():
                if app.poll() is not None:break
                time.sleep(.15)
            check(app.poll() is None and (profile/'settings.dat').is_file(),'Installed native EXE starts without sidecar resources')
            before=digest(target/'AsterHand.exe')
            check(install()!=0 and digest(target/'AsterHand.exe')==before,'Running app blocks upgrade without changing executable')
        finally:
            if app.poll() is None:app.terminate();app.wait(timeout=10)
        (profile/'preserve.txt').write_text('QA user data retained',encoding='utf-8')
        check(install()==0,'Upgrade succeeds after app exits')
        check((profile/'preserve.txt').read_text(encoding='utf-8')=='QA user data retained','Upgrade preserves user data')
        unknown=target/'user-created.txt';unknown.write_text('Preserve unrelated file',encoding='utf-8')
        subprocess.run([str(target/'Uninstall.exe'),'/S'],timeout=15,check=True)
        until=time.monotonic()+15
        while time.monotonic()<until and (registry(reg,'InstallLocation') is not None or (target/'Uninstall.exe').exists()):time.sleep(.15)
        check(not (target/'AsterHand.exe').exists() and not (target/'Uninstall.exe').exists(),'Native uninstaller removes installed executables including itself')
        check(registry(reg,'InstallLocation') is None and registry(app_path) is None,'Uninstaller removes only its QA registry keys')
        check(not menu.exists(),'Uninstaller cleans its Start menu group')
        check((profile/'settings.dat').exists() and (profile/'preserve.txt').exists(),'Uninstall preserves settings and user data')
        check(unknown.read_text(encoding='utf-8')=='Preserve unrelated file','Uninstall preserves unrelated files in install directory')
        report['productionRegistryChanged']=production_registration()!=production_before
        check(not report['productionRegistryChanged'],'Production registration unchanged after QA install and uninstall')
        report.update(passed=len(report['checks']),failed=0)
    except Exception as error:
        report.update(passed=len(report['checks']),failed=1,error=str(error));raise
    finally:
        out=ROOT/'dist/AsterHand-Windows-installer-test-report.json'
        out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
