"""Regression checks for bootstrap mixups and missing install dependencies."""
from dataclasses import dataclass
from pathlib import Path
import copy,gzip,io,plistlib,tarfile
from package_app import ar_bytes,tar_bytes
from verify_artifact import read_ar,read_tar,verify
from sync_version import release

@dataclass
class Archive:
    name:str
    data:bytes
    def read_bytes(self):return self.data

def packed(name,control,files):
    return Archive(name,ar_bytes([('debian-binary',b'2.0\n'),('control.tar.gz',tar_bytes([(n,d,m) for n,(d,m) in control.items()])),('data.tar.gz',tar_bytes([(n,d,m) for n,(d,m) in files.items()]))]))

def recovery_rejections(path,control,files,roothide,rootful):
    prefix='' if roothide or rootful else 'var/jb/'
    target=prefix+'Library/LaunchDaemons/local.asterhand.recovery.plist'
    original=plistlib.loads(files[target][0]);checks=0
    mutations=[
        ('arbitrary-command','ProgramArguments',['/bin/sh','-c','echo unsafe']),
        ('dangerous-watch-path','WatchPaths',['/var/mobile']),
        ('multiple-watch-paths','WatchPaths',original['WatchPaths']+['/etc']),
        ('persistent-recovery','KeepAlive',True),
        ('automatic-recovery','RunAtLoad',True),
        ('wrong-user','UserName','mobile'),('wrong-group','GroupName','mobile'),
        ('missing-rate-bound','ThrottleInterval',0),('wrong-process-type','ProcessType','Interactive'),
        ('symlinkable-log','StandardOutPath','/var/mobile/Library/PocketAgentControl/recovery.log'),
        ('non-boolean-keepalive','KeepAlive',0),('non-integer-throttle','ThrottleInterval',10.0),
        ('unsafe-extra-launch-property','StartInterval',1),
    ]
    for label,key,value in mutations:
        altered=dict(original);altered[key]=value;changed=dict(files);changed[target]=(plistlib.dumps(altered),0o644)
        try:verify(packed(path.name,control,changed),roothide,rootful)
        except ValueError:checks+=1
        else:raise AssertionError(path.name+' accepted '+label)
    for label,mode in [('writable-recovery-job',0o666),('executable-recovery-job',0o755)]:
        changed=dict(files);changed[target]=(files[target][0],mode)
        try:verify(packed(path.name,control,changed),roothide,rootful)
        except ValueError:checks+=1
        else:raise AssertionError(path.name+' accepted '+label)
    changed=dict(files);del changed[target]
    try:verify(packed(path.name,control,changed),roothide,rootful)
    except ValueError:checks+=1
    else:raise AssertionError(path.name+' accepted missing recovery job')
    changed=dict(control);changed['postinst']=(control['postinst'][0].replace(b'"$maint" recover-configure',b'"$maint" skipped-recovery-configure'),0o755)
    try:verify(packed(path.name,changed,files),roothide,rootful)
    except ValueError:checks+=1
    else:raise AssertionError(path.name+' accepted missing recovery installation')
    # Mutate just this TarInfo ownership; keep all signed files and every other entry unchanged.
    raw=read_ar(packed(path.name,control,files).read_bytes());memory=io.BytesIO()
    with tarfile.open(fileobj=io.BytesIO(raw['data.tar.gz']),mode='r:gz') as source,tarfile.open(fileobj=memory,mode='w',format=tarfile.USTAR_FORMAT) as destination:
        for member in source:
            entry=copy.copy(member)
            if entry.name==target:entry.uid=501;entry.uname='mobile'
            destination.addfile(entry,source.extractfile(member) if member.isfile() else None)
    raw['data.tar.gz']=gzip.compress(memory.getvalue(),mtime=0)
    try:verify(Archive(path.name,ar_bytes(list(raw.items()))),roothide,rootful)
    except ValueError:checks+=1
    else:raise AssertionError(path.name+' accepted mobile-owned root recovery job')
    return checks

def main():
    root=Path(__file__).resolve().parents[1];version=release()['version'];reports=[]
    for suffix,roothide,rootful in [('Rootful',False,True),('RootHide',True,False),('Rootless',False,False)]:
        path=root/'dist'/f'AsterHand-{version}-{suffix}.deb';report=verify(path,roothide,rootful)
        members=read_ar(path.read_bytes());control=read_tar(members['control.tar.gz']);original=control['control'][0]
        for label,before,after in [('missing-openssh',b', openssh',b''),('wrong-firmware',b'firmware (>= '+report['minimum_ios'].encode()+b')',b'firmware (>= 13.0)'),('wrong-bootstrap-architecture',b'Architecture: '+(b'iphoneos-arm64e' if roothide else b'iphoneos-arm' if rootful else b'iphoneos-arm64')+b'\n',b'Architecture: all\n')]:
            altered=original.replace(before,after);assert altered!=original
            changed=dict(control);changed['control']=(altered,control['control'][1]);payload=ar_bytes([('debian-binary',members['debian-binary']),('control.tar.gz',tar_bytes([(name,data,mode) for name,(data,mode) in changed.items()])),('data.tar.gz',members['data.tar.gz'])])
            try:verify(Archive(path.name,payload),roothide,rootful)
            except ValueError:pass
            else:raise AssertionError(suffix+' accepted '+label)
        required=['chatgpt-login-compat.js','chatgpt-login-streams.js','web-streams-polyfill-LICENSE.txt','chatgpt-login-forms.js','formdata-submitter-polyfill-LICENSE.txt']
        for resource in required:
            files=read_tar(members['data.tar.gz']);missing=[name for name in files if name.endswith('/PocketCodex.app/'+resource)];assert len(missing)==1
            del files[missing[0]]
            payload=ar_bytes([('debian-binary',members['debian-binary']),('control.tar.gz',members['control.tar.gz']),('data.tar.gz',tar_bytes([(name,data,mode) for name,(data,mode) in files.items()]))])
            try:verify(Archive(path.name,payload),roothide,rootful)
            except ValueError:pass
            else:raise AssertionError(suffix+' accepted missing '+resource)
        recovery_checks=recovery_rejections(path,control,read_tar(members['data.tar.gz']),roothide,rootful)
        reports.append({'package':path.name,'minimum_ios':report['minimum_ios'],'dependency_and_architecture_rejections':3,'missing_login_resource_rejected':True,'required_login_resource_checks':len(required),'recovery_security_rejections':recovery_checks,'launch_jobs':7,'signed_programs':5})
    print(reports)
if __name__=='__main__':main()
