"""Independently inspect the .deb, Mach-O target, signature hashes and entitlements."""
import argparse
import hashlib
import io
import json
import pathlib
import plistlib
import struct
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

def require(condition, message):
    if not condition:
        raise ValueError(message)

def read_ar(data):
    require(data[:8] == b'!<arch>\n', 'Not an ar archive')
    offset, entries = 8, {}
    while offset < len(data):
        header = data[offset:offset+60]
        require(len(header) == 60 and header[58:] == b'`\n', 'Invalid ar member')
        name = header[:16].decode('ascii').strip().rstrip('/')
        size = int(header[48:58])
        require(name not in entries and offset+60+size <= len(data), 'Duplicate/truncated ar member')
        entries[name] = data[offset+60:offset+60+size]
        offset += 60+size+(size % 2)
    require(offset == len(data), 'Bad ar alignment')
    return entries

def read_tar(data):
    result = {}
    directories=set()
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        for member in archive.getmembers():
            path = pathlib.PurePosixPath(member.name)
            require(not path.is_absolute() and '..' not in path.parts and (member.isfile() or member.isdir()), 'Unsafe tar member')
            require(member.name not in result, 'Duplicate tar path')
            require(member.uid == 0 and member.gid == 0, 'Package ownership is not root')
            if member.isdir():
                require(member.mode==0o755,'Unexpected package directory mode')
                require(member.name not in directories,'Duplicate tar directory')
                directories.add(member.name)
                continue
            result[member.name] = (archive.extractfile(member).read(), member.mode)
    require(all(any(name.startswith(directory.rstrip('/')+'/') for name in result) for directory in directories),'Unrelated package directory')
    return result

def verify_macho(binary, info_bytes=None, resource_bytes=None, roothide=False, entitlements='entitlements.plist', minimum_ios='15.0'):
    magic, cpu, subtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from('<8I', binary)
    require(magic == 0xfeedfacf and cpu == 0x100000c and subtype == 0, 'Expected generic ARM64 Mach-O')
    require(filetype == 2 and flags & 0x200000, 'Expected PIE executable')
    offset, target, signature, dylibs, entry = 32, None, None, [], False
    symbols=None
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', binary, offset)
        require(size >= 8 and offset+size <= 32+sizeofcmds, 'Bad Mach-O load command')
        if cmd == 0x32:
            target = struct.unpack_from('<III', binary, offset+8)
        elif cmd == 2:
            symbols=struct.unpack_from('<IIII',binary,offset+8)
        elif cmd == 0x1d:
            signature = struct.unpack_from('<II', binary, offset+8)
        elif cmd == 0x80000028:
            entry = True
        elif cmd in (0xc, 0x80000018, 0x8000001f):
            nameoff = struct.unpack_from('<I', binary, offset+8)[0]
            name = binary[offset+nameoff:offset+size].split(b'\0', 1)[0].decode()
            require(name.startswith(('/usr/lib/', '/System/Library/')) or
                    (roothide and name == '@loader_path/.jbroot/usr/lib/libroothide.dylib'), 'Unexpected library: ' + name)
            dylibs.append(name)
        offset += size
    require(offset == 32+sizeofcmds, 'Load command size mismatch')
    if roothide:
        require('@loader_path/.jbroot/usr/lib/libroothide.dylib' in dylibs, 'Missing RootHide runtime dependency')
    parts=[int(x) for x in minimum_ios.split('.')];minimum=(parts[0]<<16)|(parts[1]<<8)
    require(target is not None and target[0] == 2 and target[1] == minimum, 'Expected iOS device, minimum '+minimum_ios)
    if minimum<0x000f0000:
        require(symbols is not None,'Missing symbols for iOS 14 compatibility audit')
        symoff,count,stroff,strsize=symbols
        for index in range(count):
            nameoff,kind,section,description,value=struct.unpack_from('<IBBHQ',binary,symoff+index*16)
            name=binary[stroff+nameoff:stroff+strsize].split(b'\0',1)[0]
            if name==b'_OBJC_CLASS_$_UIButtonConfiguration':
                require(description&0x40,'iOS 15 UIButtonConfiguration must be a weak import')
            if name==b'___isPlatformVersionAtLeast':
                require(section>0,'Missing statically linked availability runtime')
    require(entry and signature is not None, 'Missing entrypoint/signature')
    sigoff, sigsize = signature
    require(sigoff+sigsize <= len(binary), 'Signature out of bounds')
    blob = binary[sigoff:sigoff+sigsize]
    magic, total, count = struct.unpack_from('>III', blob)
    require(magic == 0xfade0cc0 and total <= len(blob), 'Invalid signature superblob')
    slots = {}
    for index in range(count):
        slot, off = struct.unpack_from('>II', blob, 12+index*8)
        _, length = struct.unpack_from('>II', blob, off)
        require(off+length <= total, 'Invalid signature slot bounds')
        slots[slot] = blob[off:off+length]
    require(0 in slots and (entitlements is None or 5 in slots), 'Missing CodeDirectory/entitlements')
    code = slots[0]
    magic, length, version, csflags, hash_offset, ident, special_count, page_count, code_limit = struct.unpack_from('>9I', code)
    hash_size, hash_type, platform, page_exp = struct.unpack_from('>4B', code, 36)
    require(magic == 0xfade0c02 and csflags & 2, 'Expected ad-hoc signature')
    require(hash_type == 2 and hash_size == 32, 'Expected SHA-256 CodeDirectory')
    require(code_limit == sigoff, 'Signature does not cover all code')
    page_size = 1 << page_exp
    require(page_count == (code_limit+page_size-1)//page_size, 'Bad page count')
    for i in range(page_count):
        digest = hashlib.sha256(binary[i*page_size:min((i+1)*page_size, code_limit)]).digest()
        require(digest == code[hash_offset+i*hash_size:hash_offset+(i+1)*hash_size], f'Bad code page {i}')
    special = {slot: data for slot, data in {1: info_bytes, 3: resource_bytes}.items() if data is not None}
    for slot in (2, 5, 7):
        if slot in slots:
            special[slot] = slots[slot]
    for slot, content in special.items():
        require(slot <= special_count, f'Unbound special slot {slot}')
        actual = code[hash_offset-slot*hash_size:hash_offset-(slot-1)*hash_size]
        require(actual == hashlib.sha256(content).digest(), f'Bad special slot {slot}')
    if entitlements is not None:
        ent = plistlib.loads(slots[5][8:])
        expected = plistlib.loads((ROOT / entitlements).read_bytes())
        require(ent == expected, 'Unexpected entitlements')
    return {'architecture': 'arm64', 'platform': 'iOS device', 'minimum_ios': minimum_ios,
            'code_pages_sha256_verified': page_count, 'entitlements_verified': entitlements is not None, 'libraries': dylibs}

def verify(path, roothide=False, rootful=False):
    require(not (roothide and rootful),'Choose one environment')
    native=roothide or rootful
    minimum_ios='14.0' if rootful else '15.0'
    archive = read_ar(path.read_bytes())
    require(set(archive) == {'debian-binary', 'control.tar.gz', 'data.tar.gz'}, 'Unexpected ar members')
    require(archive['debian-binary'] == b'2.0\n', 'Invalid Debian version')
    control = read_tar(archive['control.tar.gz'])
    text = control['control'][0].decode()
    architecture = 'iphoneos-arm64e' if roothide else 'iphoneos-arm' if rootful else 'iphoneos-arm64'
    require(f'Architecture: {architecture}\n' in text and 'Package: local.pocketcodex\n' in text, 'Wrong package identity')
    depends=next((line[9:] for line in text.splitlines() if line.startswith('Depends: ')),'')
    require(any(part.strip()=='openssh' for part in depends.split(',')), 'Missing OpenSSH dependency')
    require('firmware (>= '+minimum_ios+')' in depends, 'Wrong firmware dependency')
    from sync_lifecycle_scripts import scripts as lifecycle_scripts
    environment='roothide' if roothide else 'rootful' if rootful else 'rootless'
    for name,expected_script in lifecycle_scripts(environment).items():
        require(name in control and control[name][1]==0o755 and control[name][0]==expected_script.encode('utf-8'),
                'Unexpected lifecycle script: '+name)
    for script in ('postinst', 'postrm'):
        shebang = b'#!/bin/sh\n' if native else b'#!/var/jb/bin/sh\n'
        require(control[script][1] == 0o755 and control[script][0].startswith(shebang), 'Bad maintainer script')
    if rootful:
        require('/var/jb' not in text and 'roothide' not in depends,'Rootful package depends on another bootstrap')
        for script in ('postinst','postrm'):
            require(b'/var/jb' not in control[script][0], 'Rootful installer contains rootless paths')
        require(b'/var/lib/asterhand' in control['postinst'][0], 'Missing rootful private service directory')
        require('prerm' in control and control['prerm'][1]==0o755 and control['prerm'][0].startswith(b'#!/bin/sh\n'),'Missing rootful service unload script')
    files = read_tar(archive['data.tar.gz'])
    prefix = 'Applications/PocketCodex.app/' if native else 'var/jb/Applications/PocketCodex.app/'
    service_prefix = '' if native else 'var/jb/'
    service_app = '/Applications/PocketCodex.app' if native else '/var/jb/Applications/PocketCodex.app'
    daemon_path = service_prefix+'Library/LaunchDaemons/local.pocketagent.remote.plist'
    root_daemon_path = service_prefix+'Library/LaunchDaemons/local.pocketagent.root.plist'
    screen_daemon_path = service_prefix+'Library/LaunchDaemons/local.pocketagent.screen.plist'
    overlay_daemon_path = service_prefix+'Library/LaunchDaemons/local.pocketagent.overlay.plist'
    control_daemon_path = service_prefix+'Library/LaunchDaemons/local.agentgo.control.plist'
    agent_daemon_path = service_prefix+'Library/LaunchDaemons/local.agentgo.agent.plist'
    recovery_daemon_path = service_prefix+'Library/LaunchDaemons/local.asterhand.recovery.plist'
    allowed_paths = {daemon_path, root_daemon_path, screen_daemon_path, overlay_daemon_path, control_daemon_path, agent_daemon_path, recovery_daemon_path}
    require(all(p.startswith(prefix) or p in allowed_paths for p in files), 'Package writes outside approved application/service paths')
    agent_daemon=plistlib.loads(files[agent_daemon_path][0])
    require(agent_daemon.get('UserName')=='mobile' and agent_daemon.get('KeepAlive') is True and agent_daemon.get('ProgramArguments')==[service_app+'/PocketCodex','--agent-daemon'], 'Unexpected AI service identity')
    require(control_daemon_path in files, 'Missing AsterHand control service')
    control_daemon=plistlib.loads(files[control_daemon_path][0])
    require(control_daemon.get('UserName')=='mobile' and control_daemon.get('ProgramArguments')==[service_app+'/PocketCodex','--control-daemon'], 'Unexpected control service identity')
    require(daemon_path in files and files[daemon_path][1] == 0o644, 'Missing RootHide remote launch daemon')
    daemon = plistlib.loads(files[daemon_path][0])
    require(daemon.get('Label') == 'local.pocketagent.remote' and daemon.get('RunAtLoad') is True and daemon.get('KeepAlive') is True,
            'Remote launch daemon is not configured for automatic persistence')
    require(daemon['ProgramArguments'][0] == service_app+'/pocketremote', 'Unexpected launch daemon executable')
    require(root_daemon_path in files and files[root_daemon_path][1] == 0o644, 'Missing RootHide Root launch daemon')
    root_daemon = plistlib.loads(files[root_daemon_path][0])
    require(root_daemon.get('Label') == 'local.pocketagent.root' and root_daemon.get('UserName') == 'root'
            and root_daemon.get('RunAtLoad') is True and root_daemon.get('KeepAlive') is True,
            'Root launch daemon is not configured for root persistence')
    require(root_daemon['ProgramArguments'] == [service_app+'/PocketCodex', '--root-daemon'],
            'Unexpected Root daemon executable')
    require(screen_daemon_path in files and files[screen_daemon_path][1] == 0o644, 'Missing screen launch daemon')
    screen_daemon = plistlib.loads(files[screen_daemon_path][0])
    require(screen_daemon.get('Label') == 'local.pocketagent.screen' and screen_daemon.get('KeepAlive') is True and screen_daemon.get('UserName') == 'mobile', 'Screen daemon configuration invalid')
    require(overlay_daemon_path in files and files[overlay_daemon_path][1] == 0o644, 'Missing standalone overlay service')
    overlay = plistlib.loads(files[overlay_daemon_path][0])
    require(overlay.get('Label') == 'local.pocketagent.overlay' and overlay.get('UserName') == 'root'
            and overlay.get('KeepAlive') is True and overlay.get('RunAtLoad') is True
            and overlay.get('ProgramArguments') == [service_app+'/pocketoverlay'], 'Overlay service invalid')
    require('prerm' in control and control['prerm'][1]==0o755,'Missing pre-removal script')
    require(b'bootout "system/$label"' in control['prerm'][0], 'Removal must use service identifiers before deleting files')
    require(b'kickstart' not in control['postinst'][0], 'Duplicate service restart slows installation')
    require(overlay.get('EnvironmentVariables', {}).get('_MSSafeMode') == '1', 'Overlay tweak isolation missing')
    require(overlay.get('JetsamProperties',{}).get('MemoryLimit')==256,'Missing bounded overlay keyboard memory budget')
    require(recovery_daemon_path in files and files[recovery_daemon_path][1]==0o644,'Missing root-owned recovery job')
    recovery=plistlib.loads(files[recovery_daemon_path][0])
    expected_recovery={
        'Label':'local.asterhand.recovery','UserName':'root','GroupName':'wheel',
        'ProgramArguments':[service_app+'/pocketmaint','recover'],
        'RunAtLoad':False,'KeepAlive':False,
        'WatchPaths':['/var/mobile/Library/PocketAgentControl/recovery-request.json'],
        'ThrottleInterval':10,'ProcessType':'Background',
        'StandardOutPath':'/dev/null','StandardErrorPath':'/dev/null',
    }
    require(recovery==expected_recovery,'Recovery job must use the fixed helper, marker and bounded launch policy')
    require(type(recovery.get('RunAtLoad')) is bool and type(recovery.get('KeepAlive')) is bool
            and type(recovery.get('ThrottleInterval')) is int,'Recovery launch policy has invalid types')
    get = lambda name: files[prefix+name][0]
    info = plistlib.loads(get('Info.plist'))
    require(info['CFBundleIdentifier'] == 'local.pocketcodex' and info['MinimumOSVersion'] == minimum_ios, 'Wrong app metadata')
    if rootful:require(info.get('AsterHandEnvironment')=='rootful','Wrong app environment')
    require(info.get('CFBundleDisplayName') == 'AsterHand', 'App display name was not updated')
    for key in ('NSMicrophoneUsageDescription','NSSpeechRecognitionUsageDescription','NSSiriUsageDescription'):
        require(isinstance(info.get(key),str) and len(info[key])>10, 'Missing voice privacy description: '+key)
    require(set(info.get('NSUserActivityTypes',[]))=={'local.asterhand.shortcut.'+action for action in ('voice','status','open')}, 'Siri activity declarations invalid')
    require({'audio','voip'} <= set(info.get('UIBackgroundModes',[])), 'Floating voice background modes missing')
    require('asterhand' in info.get('CFBundleURLTypes',[{}])[0].get('CFBundleURLSchemes',[]), 'Voice shortcut URL scheme missing')
    require(info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconFiles'), 'App icon metadata missing')
    for name, size in (('AppIcon60x60@2x.png', 120), ('AppIcon60x60@3x.png', 180), ('AgentGoMark@3x.png', 102)):
        png = get(name)
        require(png.startswith(b'\x89PNG\r\n\x1a\n') and struct.unpack_from('>II', png, 16) == (size, size), 'Invalid icon: ' + name)
        require(png[25] == (6 if name.startswith('AgentGoMark') else 2), 'Invalid icon transparency: ' + name)
    require(files[prefix+'PocketCodex'][1] == 0o755, 'Executable permission missing')
    guide=json.loads(get('user-guide.json'))
    require(guide.get('version')==1 and len(guide.get('steps',[]))==5 and len(guide.get('topics',[]))==10, 'Invalid mobile user guide')
    for entry in guide['steps']+guide['topics']:
        image=entry.get('iosImage')
        if image:
            require(image.startswith('Guide/') and '..' not in image and get(image).startswith(b'\xff\xd8'), 'Missing guide screenshot: '+image)
    require(prefix+'license-config.json' not in files, 'Legacy licensing config must not ship')
    resources_bytes = get('_CodeSignature/CodeResources')
    require(prefix+'chatgpt-login-compat.js' in files and len(get('chatgpt-login-compat.js'))>100,'Missing ChatGPT login compatibility resource')
    require(prefix+'chatgpt-login-streams.js' in files and len(get('chatgpt-login-streams.js'))>10000,'Missing ChatGPT login streams resource')
    require(prefix+'web-streams-polyfill-LICENSE.txt' in files,'Missing login streams license')
    require(prefix+'chatgpt-login-forms.js' in files and len(get('chatgpt-login-forms.js'))>1000,'Missing login forms resource')
    require(prefix+'formdata-submitter-polyfill-LICENSE.txt' in files,'Missing login forms license')
    resources = plistlib.loads(resources_bytes)
    for name, record in resources['files2'].items():
        require('hash2' in record and hashlib.sha256(get(name)).digest() == record['hash2'], 'Bad resource digest: ' + name)
    tools = json.loads(get('tools.json'))
    require({t['name'] for t in tools} == {'run_shell','read_file','write_file','list_directory','list_remote_devices','remote_execute'}, 'Unexpected tool definitions')
    require(len(json.loads(get('screen-tools.json'))) == 5, 'Expected five screen tools')
    result = verify_macho(get('PocketCodex'), get('Info.plist'), resources_bytes, roothide, minimum_ios=minimum_ios)
    if prefix+'pocketremote' in files:
        require(files[prefix+'pocketremote'][1] == 0o755, 'Remote helper permission missing')
        result['remote_helper'] = verify_macho(get('pocketremote'), roothide=roothide, entitlements='remote-entitlements.plist', minimum_ios=minimum_ios)
    require(files[prefix+'pocketscreen'][1] == 0o755, 'Screen helper permission missing')
    result['screen_helper'] = verify_macho(get('pocketscreen'), roothide=roothide, entitlements='remote-entitlements.plist', minimum_ios=minimum_ios)
    require(files[prefix+'pocketoverlay'][1] == 0o755, 'Overlay helper permission missing')
    result['overlay_helper'] = verify_macho(get('pocketoverlay'), roothide=roothide, entitlements='overlay-entitlements.plist', minimum_ios=minimum_ios)
    require(files[prefix+'pocketmaint'][1]==0o755,'Missing maintenance helper')
    result['maintenance_helper']=verify_macho(get('pocketmaint'),roothide=roothide,entitlements='entitlements.plist',minimum_ios=minimum_ios)
    result.update({'package': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                   'installation_paths_verified': True, 'environment': 'RootHide' if roothide else 'rootful' if rootful else 'rootless', 'resource_digests_verified': True,
                   'declared_dependencies': depends, 'openssh_dependency_verified': True, 'recovery_job_verified':True,
                   'recovery_job_requires_marker':True,'launch_jobs':7,
                   'login_compat_resource_verified': True, 'login_forms_resource_verified': True, 'runtime_on_iphone_tested': False, 'live_api_tested': False})
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    from ios_build_profile import add_environment_args
    add_environment_args(parser)
    parser.add_argument('package', nargs='?', type=pathlib.Path, default=ROOT / 'dist/AsterHand-0.8.0-RootHide.deb')
    args = parser.parse_args()
    result = verify(args.package, args.environment=='roothide', args.environment=='rootful')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    args.package.with_suffix('.verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
