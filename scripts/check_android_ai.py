"""Compile and run offline provider, loopback OAuth and Java/Node control fixtures.

Only the pinned org.json JVM test dependency may be fetched; no AI/account requests.
Android SDK 35 and a JDK/Node executable are required, as for the APK build.
"""
from pathlib import Path
import hashlib, os, shutil, subprocess, urllib.request

ROOT=Path(__file__).resolve().parents[1]
SDK=Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME') or r'C:\Users\ylayang\AppData\Local\Android\Sdk')
PLATFORM=SDK/'platforms/android-35/android.jar'
JAR=ROOT/'.build-deps/android-ai-tests/json-20240303.jar'
HASH='3cf6cd6892e32e2b4c1c39e0f52f5248a2f5b37646fdfbb79a66b46b618414ed'
OUT=ROOT/'.private/android-ai-tests'
SOURCE=ROOT/'android/app/src/main/java/com/pocketagent'
TEST=ROOT/'android/tests'

def run(args):
    subprocess.run([str(x) for x in args],cwd=ROOT,check=True)

def main():
    javac,java,node=(shutil.which(x) for x in ('javac','java','node'))
    if not all((javac,java,node)) or not PLATFORM.is_file():raise SystemExit('JDK, Node and Android SDK platform 35 are required')
    if not JAR.is_file():
        JAR.parent.mkdir(parents=True,exist_ok=True)
        data=urllib.request.urlopen('https://repo.maven.apache.org/maven2/org/json/json/20240303/json-20240303.jar',timeout=30).read()
        if hashlib.sha256(data).hexdigest()!=HASH:raise SystemExit('JSON fixture dependency checksum mismatch')
        JAR.write_bytes(data)
    if hashlib.sha256(JAR.read_bytes()).hexdigest()!=HASH:raise SystemExit('JSON fixture dependency checksum mismatch')
    OUT.mkdir(parents=True,exist_ok=True)
    stub=ROOT/'.private/android-ai-test-stubs/com/pocketagent/MainActivity.java'
    stub.parent.mkdir(parents=True,exist_ok=True)
    stub.write_text('package com.pocketagent; final class MainActivity extends android.app.Activity {}\n',encoding='utf-8')
    classpath=os.pathsep.join(map(str,(JAR,PLATFORM)))
    sources=[SOURCE/x for x in ('ProviderClient.java','ChatGPTAuth.java','RemoteControlWire.java','RemoteAgentRequest.java','Vault.java')]
    tests=[TEST/x for x in ('ProviderClientTest.java','ChatGPTCallbackTest.java','RemoteControlWireTest.java','RemoteAgentRequestTest.java')]
    run([javac,'-source','8','-target','8','-encoding','UTF-8','-classpath',classpath,'-d',OUT,*sources,stub,*tests])
    runtime=os.pathsep.join(map(str,(OUT,JAR,PLATFORM)))
    for test in ('ProviderClientTest','ChatGPTCallbackTest','RemoteAgentRequestTest'):
        run([java,'-Dfile.encoding=UTF-8','-cp',runtime,'com.pocketagent.'+test])
    run([node,ROOT/'scripts/check_android_wire.mjs'])
    # Production HTTP code has no runtime Android calls. The other Hub APIs are
    # compiled against narrow test doubles, without replacing any shipped file.
    http_out=ROOT/'.private/android-http-tests'
    http_out.mkdir(parents=True,exist_ok=True)
    hub_stub=ROOT/'.private/android-ai-test-stubs/com/pocketagent/HubDependencies.java'
    hub_stub.write_text('''package com.pocketagent;
import android.content.Context;
import org.json.*;
import java.util.concurrent.atomic.AtomicBoolean;
final class ServiceMaster {static void requireEnabled(Context c){}}
final class AppRemote {static JSONObject request(JSONObject args){throw new UnsupportedOperationException();}}
final class AgentSession {
 interface RemoteExecutor {JSONArray devices() throws Exception; JSONObject execute(String d,String m,JSONObject a) throws Exception;}
 static RemoteExecutor remote;
}
final class PrivilegeManager {
 enum Mode {NORMAL,ADB,ROOT}
 PrivilegeManager(Context c){}
 Mode getMode(){return Mode.NORMAL;}
 void closeOwner(String id){}
 JSONObject terminal(String action,JSONObject args,String owner,Mode mode){throw new UnsupportedOperationException();}
}
final class AgentTools {
 AgentTools(Context c,boolean root){}
 AgentTools(Context c,PrivilegeManager.Mode mode,String work){}
 String workspace(){throw new UnsupportedOperationException();}
 JSONObject execute(String tool,JSONObject args,AtomicBoolean cancel){throw new UnsupportedOperationException();}
}
final class ProjectStore {
 ProjectStore(Context c){}
 JSONObject currentProject(){throw new UnsupportedOperationException();}
}
''',encoding='utf-8')
    run([javac,'-source','8','-target','8','-encoding','UTF-8','-classpath',classpath,'-d',http_out,
         SOURCE/'RemoteControlHub.java',SOURCE/'RemoteControlWire.java',hub_stub,TEST/'RemoteControlHttpTest.java',TEST/'RemoteControlLeaseTest.java'])
    run([java,'-Dfile.encoding=UTF-8','-cp',os.pathsep.join(map(str,(http_out,JAR,PLATFORM))),
         'com.pocketagent.RemoteControlHttpTest'])
    run([java,'-Dfile.encoding=UTF-8','-cp',os.pathsep.join(map(str,(http_out,JAR,PLATFORM))),
         'com.pocketagent.RemoteControlLeaseTest'])

if __name__=='__main__':main()
