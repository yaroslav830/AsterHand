"""Build the local Android development APK, preserving app ID and signing key."""
from __future__ import annotations
import argparse,hashlib,json,os,shutil,subprocess,tempfile,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];APP=ROOT/'android/app'
SDK=Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME') or r'C:\Users\ylayang\AppData\Local\Android\Sdk')
TOOLS=SDK/'build-tools/35.0.0';PLATFORM=SDK/'platforms/android-35/android.jar'
KEYSTORE=ROOT/'.build-deps/android-debug.keystore';PASSWORD='pocketagent-debug-only'
def tool(name):
 for ext in ('.bat','.exe','') if os.name=='nt' else ('',):
  p=TOOLS/(name+ext)
  if p.exists():return str(p)
 raise SystemExit('Android SDK tool missing: '+name)
def run(args,capture=False):
 p=subprocess.run([str(a) for a in args],cwd=ROOT,check=True,text=True,encoding='utf-8',errors='replace',stdout=subprocess.PIPE if capture else None,stderr=subprocess.STDOUT if capture else None);return p.stdout or ''
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--out',type=Path,help='Write the signed APK to a separate output path.')
 args=parser.parse_args()
 from sync_design import sync as sync_design
 sync_design()
 from sync_localizations import sync as sync_localizations
 sync_localizations()
 release=json.loads((ROOT/'version.json').read_text(encoding='utf-8'));out=args.out or ROOT/'dist'/f'AsterHand-{release["version"]}-Android.apk'
 for p in [PLATFORM,APP/'src/main/AndroidManifest.xml']:
  if not p.exists():raise SystemExit('Required input missing: '+str(p))
 javac,keytool=shutil.which('javac'),shutil.which('keytool')
 if not javac or not keytool:raise SystemExit('JDK 17 required.')
 out=out.resolve();out.parent.mkdir(parents=True,exist_ok=True);KEYSTORE.parent.mkdir(exist_ok=True)
 if not KEYSTORE.exists():run([keytool,'-genkeypair','-keystore',KEYSTORE,'-storepass',PASSWORD,'-keypass',PASSWORD,'-alias','pocketagent-debug','-keyalg','RSA','-keysize','2048','-validity','10000','-dname','CN=PocketAgent Local Debug'])
 with tempfile.TemporaryDirectory(prefix='asterhand-android-') as temporary:
  temp=Path(temporary);classes=temp/'classes';dex=temp/'dex';generated=temp/'generated'
  for p in [classes,dex,generated]:p.mkdir()
  resources=temp/'resources.zip';unsigned=temp/'unsigned.apk'
  staged=temp/'inputs';staged.mkdir();shutil.copytree(APP/'src/main/res',staged/'res');shutil.copytree(APP/'src/main/assets',staged/'assets');shutil.copytree(APP/'src/main/java',staged/'java');shutil.copy2(APP/'src/main/AndroidManifest.xml',staged/'AndroidManifest.xml')
  run([tool('aapt2'),'compile','--dir',staged/'res','-o',resources])
  run([tool('aapt2'),'link','-o',unsigned,'--manifest',staged/'AndroidManifest.xml','-I',PLATFORM,'-A',staged/'assets','--java',generated,'--min-sdk-version','23','--target-sdk-version','35','--version-code',release['build'],'--version-name',release['version'],resources])
  sources=sorted((staged/'java').rglob('*.java'))+sorted(generated.rglob('*.java'));source_args=temp/'sources.txt';source_args.write_text('\n'.join('"'+str(p).replace('\\','/')+'"' for p in sources),encoding='utf-8')
  run([javac,'-source','8','-target','8','-encoding','UTF-8','-classpath',PLATFORM,'-d',classes,'@'+str(source_args)])
  jar=temp/'classes.jar';run([shutil.which('jar') or 'jar','cf',jar,'-C',classes,'.']);run([tool('d8'),'--min-api','23','--lib',PLATFORM,'--output',dex,jar])
  merged=temp/'merged.apk'
  with zipfile.ZipFile(unsigned) as source,zipfile.ZipFile(merged,'w',compression=zipfile.ZIP_DEFLATED) as destination:
   for info in source.infolist():destination.writestr(info,source.read(info.filename))
   for p in dex.glob('*.dex'):destination.write(p,p.name,compress_type=zipfile.ZIP_STORED)
  aligned=temp/'aligned.apk';run([tool('zipalign'),'-f','4',merged,aligned]);run([tool('apksigner'),'sign','--ks',KEYSTORE,'--ks-key-alias','pocketagent-debug','--ks-pass','pass:'+PASSWORD,'--key-pass','pass:'+PASSWORD,'--out',out,aligned])
  verify=run([tool('apksigner'),'verify','--verbose','--print-certs',out],True)
  with zipfile.ZipFile(out) as z:
   assert all(n in z.namelist() for n in ['AndroidManifest.xml','classes.dex','assets/ui/index.html','assets/ui/app.js','assets/ui/user-guide.js','assets/ui/style.css','assets/ui/mark.png']);assert not any('.private' in n or '.keystore' in n for n in z.namelist())
   assert 'assets/license-config.json' not in z.namelist(), 'Legacy licensing config must not ship'
   guide=json.loads((ROOT/'Resources/user-guide.json').read_text('utf-8'))
   for entry in guide['steps']+guide['topics']:
    if entry.get('androidImage'):assert z.read('assets/ui/'+entry['androidImage'])==(ROOT/'Resources/Guide'/Path(entry['androidImage']).name).read_bytes()
  report={'app':out.name,**release,'minimum_android_api':23,'target_android_api':35,'development_debuggable':True,'debug_signed':True,'application_id':'com.pocketagent','sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'required_assets_verified':True,'source_files':len(sources),'apksigner':verify.strip()};out.with_suffix('.build.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('Built and verified '+str(out)+' ('+str(out.stat().st_size)+' bytes)')
 from sync_desktop_packages import sync_after_build
 sync_after_build([out])
if __name__=='__main__':main()
