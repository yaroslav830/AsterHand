#!/usr/bin/env python3
"""Build a separate, same-signed native diagnostic APK; never installs or unlocks a device."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,tempfile,zipfile
ROOT=Path(__file__).resolve().parents[1]
SDK=Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME') or r'C:\Users\ylayang\AppData\Local\Android\Sdk')
PLATFORM=SDK/'platforms/android-35/android.jar'
TOOLS=SDK/'build-tools/35.0.0'
KEY=ROOT/'.build-deps/android-debug.keystore'

def tool(name):
    for ext in ('.bat','.exe',''):
        path=TOOLS/(name+ext)
        if path.exists():return str(path)
    raise SystemExit('Missing Android SDK tool: '+name)
def run(args):
    p=subprocess.run([str(x) for x in args],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
    if p.returncode:print(p.stdout);raise SystemExit(p.returncode)
    return p.stdout

def main():
    if not KEY.exists() or not PLATFORM.exists():raise SystemExit('Build the target application first, using its existing SDK and development signing key.')
    javac=shutil.which('javac');jar=shutil.which('jar')
    if not javac or not jar:raise SystemExit('A JDK with javac and jar is required.')
    release=json.loads((ROOT/'version.json').read_text(encoding='utf-8'))
    out=ROOT/'dist'/('AsterHand-'+release['version']+'-android-tests.apk');out.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='asterhand-android-tests-') as directory:
        temp=Path(directory);target=temp/'target-classes';tests=temp/'test-classes';dex=temp/'dex'
        for path in (target,tests,dex):path.mkdir()
        # Target classes are compilation inputs only, never packaged into the test APK.
        sources=sorted((ROOT/'android/app/src/main/java').rglob('*.java'))
        run([javac,'-source','8','-target','8','-encoding','UTF-8','-classpath',PLATFORM,'-d',target,*sources])
        testsources=sorted((ROOT/'android/tests/src').rglob('*.java'))
        run([javac,'-source','8','-target','8','-encoding','UTF-8','-classpath',str(PLATFORM)+os.pathsep+str(target),'-d',tests,*testsources])
        testjar=temp/'tests.jar';run([jar,'cf',testjar,'-C',tests,'.'])
        run([tool('d8'),'--min-api','23','--lib',PLATFORM,'--classpath',target,'--output',dex,testjar])
        unsigned=temp/'unsigned.apk'
        run([tool('aapt2'),'link','-o',unsigned,'--manifest',ROOT/'android/tests/AndroidManifest.xml','-I',PLATFORM,'--min-sdk-version','23','--target-sdk-version','35','--version-code',str(release['build']),'--version-name',release['version']])
        merged=temp/'merged.apk'
        with zipfile.ZipFile(unsigned) as original,zipfile.ZipFile(merged,'w',compression=zipfile.ZIP_DEFLATED) as apk:
            for entry in original.infolist():apk.writestr(entry,original.read(entry.filename))
            apk.write(dex/'classes.dex','classes.dex',compress_type=zipfile.ZIP_STORED)
        aligned=temp/'aligned.apk';run([tool('zipalign'),'-f','4',merged,aligned])
        run([tool('apksigner'),'sign','--ks',KEY,'--ks-key-alias','pocketagent-debug','--ks-pass','pass:pocketagent-debug-only','--key-pass','pass:pocketagent-debug-only','--out',out,aligned])
        verify=run([tool('apksigner'),'verify','--verbose','--print-certs',out])
    report={'apk':out.name,'version':release['version'],'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'target_package':'com.pocketagent','minimum_api':23,'target_api':35,'same_existing_debug_key':True,'test_only':True,'device_tested':False,'signature_verification':verify.strip()}
    (ROOT/'dist'/('AsterHand-'+release['version']+'-android-tests-build.json')).write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='signature_verification'},ensure_ascii=False))
if __name__=='__main__':main()
