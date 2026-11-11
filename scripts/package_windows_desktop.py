"""Package only the native EXE and a compact validation report."""
from datetime import datetime, timezone
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/windows-native'
DIST = ROOT / 'dist'


def main():
    global BUILD
    parser=argparse.ArgumentParser();parser.add_argument("--build-dir",type=Path,default=BUILD);args=parser.parse_args();BUILD=args.build_dir.resolve()
    tests = json.loads((BUILD / 'native-test-report.json').read_text(encoding='utf-8'))
    interop = json.loads((BUILD / 'native-interop-report.json').read_text(encoding='utf-8'))
    if tests['failed'] or interop['failed']:
        raise SystemExit('Native verification has failures; not packaging.')
    source = BUILD / 'AsterHand.exe'
    binary = source.read_bytes()
    offset = struct.unpack_from('<I', binary, 0x3C)[0]
    if binary[offset:offset+4] != b'PE\0\0':
        raise SystemExit('Not a PE executable')
    optional = offset + 24
    if struct.unpack_from('<H', binary, optional)[0] != 0x10B:
        raise SystemExit('Expected PE32 AnyCPU executable')
    if struct.unpack_from('<H', binary, optional + 68)[0] != 2:
        raise SystemExit('Expected Windows GUI subsystem')
    for text in ['fixture-http-key', 'fixture-secret-key', 'license.yaroslav.fun', 'OnlineLicense', 'AsterHand.NativeTests']:
        if text.encode() in binary or text.encode('utf-16-le') in binary:
            raise SystemExit('Unexpected test/licensing content in release executable: ' + text)
    inspection = subprocess.run([str(BUILD / 'AsterHand.Tests.exe'), '--inspect-package', str(source)],
                                check=True, capture_output=True, text=True, encoding='utf-8')
    metadata = json.loads(inspection.stdout)
    if metadata['hasTestCode'] or metadata['hasLicensing'] or metadata['targetFramework'] != '.NETFramework,Version=v4.6.2':
        raise SystemExit('Unexpected package metadata')
    DIST.mkdir(exist_ok=True)
    target = DIST / 'AsterHand-Windows.exe'
    if target.exists():
        old = ROOT / 'build/windows-native-previous' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        old.mkdir(parents=True, exist_ok=False)
        shutil.copy2(target, old / target.name)
    shutil.copy2(source, target)
    digest = hashlib.sha256(binary).hexdigest()
    if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
        raise SystemExit('Packaged EXE hash mismatch')
    report = {
        'artifact': target.name, 'version': metadata['version'], 'sha256': digest, 'bytes': len(binary),
        'nativeTests': {'passed': tests['passed'], 'failed': 0},
        'protocolInterop': interop,
        'serialNumberFeature': False, 'onlineLicenseRequests': False, 'floatingWindowFeature': False,
        'providers': ['ChatGPT', 'Generic API'], 'modelCatalog': 'account/API discovery; no fixed model versions',
        'package': metadata,
        'verified': ['Current Windows native runtime', 'OAuth callback/token fixtures', 'Generic API local HTTP roundtrip',
                     'Embedded resources'],
        'notVerified': ['Interactive ChatGPT account consent and real plan inference', 'Windows 7 physical/VM runtime',
                        'Physical phone streaming in this run'],
        'uiAutomation': {'completed': False, 'reason': 'Not run during this packaging operation'},
        'timeUtc': datetime.now(timezone.utc).isoformat()
    }
    layouts = []
    for name in ['native-layout-aware.json', 'native-layout-unaware.json']:
        path=BUILD/name
        if path.exists():
            result=json.loads(path.read_text(encoding='utf-8'))
            if not result.get('geometryPassed'):
                raise SystemExit('Layout geometry verification has failures')
            layouts.append(result)
    report['internalLayoutChecks']=layouts
    if layouts:report['verified'].append('Internal DPI layout geometry; not a substitute for live window acceptance')
    live_path=DIST/'AsterHand-Windows-live-login-report.json'
    if live_path.exists():
        live=json.loads(live_path.read_text(encoding='utf-8-sig'))
        if live.get('passed') and live.get('releaseSha256')==digest:
            report['liveChatGPT']=live
            report['verified'].append('Real ChatGPT account: current model catalog and completed native streaming inference')
            report['notVerified'].remove('Interactive ChatGPT account consent and real plan inference')
            report['notVerified'].append('Real account token rotation and remote revocation; fixture checks only')
            if live.get('tokenRefreshAttempted'):
                report['verified'].append('Real ChatGPT account token refresh followed by completed inference')
                report['notVerified'].remove('Real account token rotation and remote revocation; fixture checks only')
                report['notVerified'].append('Real account remote revocation; fixture checks only')
    vm_path=DIST/'AsterHand-Windows-Win7-report.json'
    if vm_path.exists():
        vm=json.loads(vm_path.read_text(encoding='utf-8-sig'))
        if vm.get('passed') and vm.get('releaseSha256')==digest:
            report['win7Runtime']=vm
            report['verified'].append('Windows 7 SP1 x64 VM: native runtime, layout, install/upgrade/uninstall/data retention and Android control')
            report['notVerified'].remove('Windows 7 physical/VM runtime')
            report['notVerified'].append('Windows 7 x86, physical hardware, and real ChatGPT authorization/inference inside Win7')
    phone_reports=[]
    for name in ['AsterHand-Windows-iPhone-LAN-report.json','AsterHand-Windows-Android-LAN-report.json']:
        path=DIST/name
        if path.exists():
            phone=json.loads(path.read_text(encoding='utf-8-sig'))
            if phone.get('passed') and phone.get('releaseSha256')==digest:phone_reports.append(phone)
    if phone_reports:
        report['phoneRuntime']=phone_reports
        report['verified'].append('Physical phone LAN pairing, files, persistent terminal and authenticated screen frames')
        report['notVerified'].remove('Physical phone streaming in this run')
    ui_path=DIST/'AsterHand-Windows-UI-report.json'
    if ui_path.exists():
        ui=json.loads(ui_path.read_text(encoding='utf-8-sig'))
        if ui.get('releaseSha256')==digest:
            report['uiAutomation']={'completedForListedChecks':True,'fullCoverage':False,**ui}
            report['verified'].append('Native Android viewer: rendered frames, mouse tap/swipe and Home; native transport text readback')
    refresh_path=DIST/'AsterHand-Windows-token-refresh-report.json'
    if refresh_path.exists():
        refresh=json.loads(refresh_path.read_text(encoding='utf-8-sig'))
        if refresh.get('passed') and refresh.get('tokenRefreshAttempted'):
            report['realTokenRefreshEarlierInSession']=refresh
            report['verified'].append('Real account token refresh earlier in this session; tested build recorded separately')
            pending='Real account token rotation and remote revocation; fixture checks only'
            if pending in report['notVerified']:
                report['notVerified'].remove(pending)
                report['notVerified'].append('Real account remote revocation; fixture checks only')
    (DIST / 'AsterHand-Windows-test-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    shutil.copy2(ROOT / 'desktop/windows/README.md', DIST / 'AsterHand-Windows-使用说明.txt')
    (DIST / 'AsterHand-Windows-SHA256.txt').write_text(digest + '  ' + target.name + '\n', encoding='utf-8')
    print(json.dumps({'exe': str(target), 'bytes': len(binary), 'sha256': digest}, ensure_ascii=False))
    from sync_desktop_packages import sync_after_build
    sync_after_build([target])


if __name__ == '__main__':
    main()
