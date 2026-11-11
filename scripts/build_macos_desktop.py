"""Build the AsterHand AppKit host and self-contained macOS desktop app.

On macOS the Apple SDK/clang/codesign are used. On Windows --bootstrap
downloads an isolated SDK and uses this repository's Zig/LLD/rcodesign.
No private state, credentials, device logs, or development dependencies enter
the app. ZIP entries explicitly retain Unix executable permissions.
"""
from __future__ import annotations

import argparse
import base64
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import posixpath
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEPS = ROOT / '.build-deps/macos'
NODE_VERSION = '18.20.8'
NODE_HASHES = {
    'x64': 'ed2554677188f4afc0d050ecd8bd56effb2572d6518f8da6d40321ede6698509',
    'arm64': 'bae4965d29d29bd32f96364eefbe3bca576a03e917ddbb70b9330d75f2cacd76',
}
SDK_URL = 'https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX11.3.sdk.tar.xz'
SDK_API = 'https://api.github.com/repos/phracker/MacOSX-SDKs/releases/assets/36307825'
# Pinned release-asset SHA-256. See dependencies.json for recorded source URLs.
SDK_SHA256 = 'cd4f08a75577145b8f05245a2975f7c81401d75e9535dcffbb879ee1deefcbf4'
ARCHES = {'x64': ('x86_64', '10.15'), 'arm64': ('arm64', '11.0')}
FRAMEWORKS = ['Foundation', 'AppKit', 'WebKit', 'ApplicationServices',
              'CoreGraphics', 'ImageIO', 'Security', 'AVFoundation', 'Speech']
MCP_STDIO = ['@modelcontextprotocol/sdk', 'zod', 'ajv', 'ajv-formats',
             'zod-to-json-schema', 'fast-deep-equal', 'fast-uri',
             'json-schema-traverse', 'require-from-string']


def digest(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while block := stream.read(1024 * 1024): result.update(block)
    return result.hexdigest()


def download(urls, output, expected=None, integrity=None):
    output.parent.mkdir(parents=True, exist_ok=True)
    def valid():
        if not output.is_file(): return False
        if expected and digest(output) != expected: return False
        if integrity and base64.b64encode(hashlib.sha512(output.read_bytes()).digest()).decode() != integrity: return False
        return True
    if valid(): return output
    last = None
    for url in urls:
        temporary = output.with_suffix(output.suffix + '.partial')
        try:
            headers = {'User-Agent': 'AsterHand-macOS-builder'}
            if 'api.github.com/' in url:
                headers.update(Accept='application/octet-stream', **{'X-GitHub-Api-Version': '2022-11-28'})
            request = urllib.request.Request(url, headers=headers)
            print('Downloading ' + output.name, flush=True)
            with urllib.request.urlopen(request, timeout=30) as response, temporary.open('wb') as stream:
                shutil.copyfileobj(response, stream)
            if expected and digest(temporary) != expected: raise ValueError('SHA-256 mismatch: ' + output.name)
            if integrity and base64.b64encode(hashlib.sha512(temporary.read_bytes()).digest()).decode() != integrity:
                raise ValueError('SHA-512 integrity mismatch: ' + output.name)
            temporary.replace(output)
            return output
        except Exception as error:
            last = error
            if temporary.exists(): temporary.unlink()
    raise RuntimeError('Download failed: ' + output.name) from last


def extract_sdk(archive, target):
    """Materialize SDK symlinks on Windows without requiring admin privileges."""
    if (target / '.asterhand-sdk-ready').is_file(): return
    if os.name == 'nt' and not str(target).startswith('\\\\?\\'):
        target = Path('\\\\?\\' + str(target.resolve()))
    with tarfile.open(archive, 'r:xz') as source:
        members = {}
        for member in source.getmembers():
            name = PurePosixPath(member.name)
            if name.is_absolute() or '..' in name.parts: raise ValueError('Unsafe SDK path')
            if '/usr/share/' in '/' + str(name) + '/': continue  # manpages contain ':' names invalid on Windows
            members[str(name)] = member
        def resolve_name(name, trail=()):
            if name in members: return name
            if name in trail: raise ValueError('Cyclic SDK alias')
            bits = name.split('/')
            for index in range(len(bits) - 1, 0, -1):
                prefix = '/'.join(bits[:index])
                member = members.get(prefix)
                if member and member.issym():
                    link = posixpath.normpath(posixpath.join(posixpath.dirname(prefix), member.linkname, *bits[index:]))
                    return resolve_name(link, (*trail, name))
            raise ValueError('Missing SDK link target: ' + name)
        def materialize(name, trail=()):
            if name in trail: raise ValueError('Cyclic SDK link')
            member = members[name]
            path = target.parent.joinpath(*PurePosixPath(name).parts)
            if path.exists(): return
            path.resolve().relative_to(target.parent.resolve())
            if member.isdir(): path.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                path.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(member) as stream, path.open('wb') as out: shutil.copyfileobj(stream, out)
            elif member.issym() or member.islnk():
                link = member.linkname if member.islnk() else posixpath.join(posixpath.dirname(name), member.linkname)
                link = posixpath.normpath(link)
                if link.startswith('../') or link.startswith('/'): raise ValueError('Unsafe SDK link')
                link = resolve_name(link)
                materialize(link, (*trail, name))
                origin = target.parent.joinpath(*PurePosixPath(link).parts)
                path.parent.mkdir(parents=True, exist_ok=True)
                if origin.is_dir():
                    if origin in path.parents: return  # Ruby's cyclic ruby/ruby alias is not a compiler input.
                    shutil.copytree(origin, path)
                else: shutil.copyfile(origin, path)
        # Populate directories/files before links to avoid copying incomplete dirs.
        for name, member in members.items():
            if member.isdir() or member.isfile(): materialize(name)
        # Finish nested framework header aliases before copying umbrella
        # Frameworks/Versions/Current directories, so copies are complete.
        for name in sorted(members, key=lambda n: n.count('/'), reverse=True): materialize(name)
    (target / '.asterhand-sdk-ready').write_text('complete\n', encoding='utf-8')


def sdk_path(args):
    if args.sdk: return args.sdk.resolve()
    if sys.platform == 'darwin':
        return Path(subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip())
    sdk = DEPS / 'MacOSX11.3.sdk'
    if not (sdk / '.asterhand-sdk-ready').exists():
        if not args.bootstrap: raise SystemExit('Supply --sdk or use --bootstrap to download the isolated SDK.')
        archive = download([SDK_API, SDK_URL, 'https://gh-proxy.org/' + SDK_URL], DEPS / 'MacOSX11.3.sdk.tar.xz', SDK_SHA256)
        extract_sdk(archive, sdk)
    return sdk


def run(command, log):
    result = subprocess.run([str(v) for v in command], cwd=ROOT, capture_output=True, text=True, errors='replace')
    with log.open('a', encoding='utf-8') as stream:
        stream.write(subprocess.list2cmdline([str(v) for v in command]) + '\n' + result.stdout + result.stderr + '\n')
    if result.returncode:
        print(result.stdout[-12000:] + result.stderr[-12000:])
        raise RuntimeError('Build command failed; see ' + str(log))
    return result.stdout


def compile_host(arch, sdk, output, log):
    cpu, minimum = ARCHES[arch]
    settings = json.loads((sdk / 'SDKSettings.json').read_text(encoding='utf-8'))
    sdk_version = settings['Version']
    source = ROOT / 'desktop/macos/main.m'
    if sys.platform == 'darwin':
        command = ['xcrun', '--sdk', 'macosx', 'clang', '-arch', cpu,
                   '-mmacosx-version-min=' + minimum, '-isysroot', sdk]
    else:
        zig = ROOT / '.build-deps/zig-x86_64-windows-0.14.1/zig.exe'
        if not zig.is_file(): raise SystemExit('First run scripts/bootstrap_windows.py to obtain Zig.')
        command = [zig, 'cc', '-target', ('aarch64' if arch == 'arm64' else cpu) + '-macos.' + minimum,
                   '-isysroot', sdk, '-iframework', sdk / 'System/Library/Frameworks',
                   '-isystem', sdk / 'usr/include']
    common = ['-fobjc-arc', '-fblocks', '-O2', '-Wall', '-Wextra', '-Wno-unused-parameter',
              '-Werror=unguarded-availability', '-Werror=unguarded-availability-new']
    if sys.platform == 'darwin':
        command += common + [source]
        for framework in FRAMEWORKS: command += ['-framework', framework]
        run(command + ['-o', output], log)
    else:
        obj = output.parent / ('host-' + arch + '.o')
        run(command + common + ['-c', source, '-o', obj], log)
        linker = ROOT / '.build-deps/llvm-mingw-20260908-msvcrt-x86_64/bin/lld.exe'
        if not linker.is_file(): raise SystemExit('First run scripts/bootstrap_windows.py --roothide to obtain Darwin LLD.')
        command = [linker, '-flavor', 'darwin', '-arch', cpu, '-platform_version', 'macos', minimum, sdk_version,
                   '-syslibroot', sdk, '-F' + str(sdk / 'System/Library/Frameworks'),
                   '-L' + str(sdk / 'usr/lib'), '-lSystem', '-lobjc', '-headerpad', '0x1000', obj]
        for framework in FRAMEWORKS: command += ['-framework', framework]
        run(command + ['-o', output], log)
        obj.unlink()
    output.chmod(0o755)


def runtime(arch, output):
    name = 'node-v' + NODE_VERSION + '-darwin-' + arch + '.tar.gz'
    archive = download(['https://nodejs.org/dist/v' + NODE_VERSION + '/' + name,
                        'https://repo.huaweicloud.com/nodejs/v' + NODE_VERSION + '/' + name],
                       DEPS / name, NODE_HASHES[arch])
    output.mkdir(parents=True, exist_ok=True)
    prefix = name.removesuffix('.tar.gz')
    with tarfile.open(archive, 'r:gz') as source:
        for relative, target in [('bin/node', 'node'), ('LICENSE', 'LICENSE.node.txt')]:
            with source.extractfile(prefix + '/' + relative) as stream:
                (output / target).write_bytes(stream.read())
    (output / 'node').chmod(0o755)


def npm_package(name, version, integrity, output):
    filename = name.replace('/', '-') + '-' + version + '.tgz'
    stem = name.rsplit('/', 1)[-1]
    url = 'https://registry.npmjs.org/' + name + '/-/' + stem + '-' + version + '.tgz'
    mirror = 'https://registry.npmmirror.com/' + name + '/-/' + stem + '-' + version + '.tgz'
    archive = download([url, mirror], DEPS / 'npm' / filename, integrity=integrity)
    with tarfile.open(archive, 'r:gz') as source:
        for member in source.getmembers():
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != 'package':
                raise ValueError('Unsafe npm archive path')
            if member.isdir(): continue
            if not member.isfile(): raise ValueError('Unexpected npm archive link')
            target = output.joinpath(*path.parts[1:]); target.parent.mkdir(parents=True, exist_ok=True)
            with source.extractfile(member) as stream: target.write_bytes(stream.read())
    return {'name': name, 'version': version, 'integrity': 'sha512-' + integrity, 'url': url}


def package_mcp(backend):
    # Only the stdio import graph is shipped: no HTTP server, oauth/browser or
    # Node >=20 Hono dependency. Every archive is checked against the lockfile.
    import re
    lock = (ROOT / 'mcp/pnpm-lock.yaml').read_text(encoding='utf-8')
    packages = []
    for name in MCP_STDIO:
        pattern = r"^  '?" + re.escape(name) + r"@([^:'\n]+)'?:\n    resolution: \{integrity: sha512-([^}]+)\}"
        match = re.search(pattern, lock, re.M)
        if not match: raise ValueError('Package missing from lockfile: ' + name)
        packages.append((name, match[1], match[2], backend / 'mcp/node_modules' / name))
    with concurrent.futures.ThreadPoolExecutor(6) as pool:
        manifest = list(pool.map(lambda row: npm_package(*row), packages))
    (backend / 'mcp/stdio-dependencies.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')


def copy_backend(destination):
    destination.mkdir(parents=True, exist_ok=True)
    desktop = destination / 'desktop'; desktop.mkdir(exist_ok=True)
    for file in (ROOT / 'desktop').glob('*.mjs'): shutil.copy2(file, desktop / file.name)
    shutil.copy2(ROOT / 'desktop/package.json', desktop)
    shutil.copytree(ROOT / 'desktop/public', desktop / 'public', dirs_exist_ok=True)
    # ws has no mandatory dependencies or native addon. Fetch its exact tarball
    # from the registry and compare the published SHA-512 integrity.
    npm_package('ws', '8.18.3', 'PEIGCY5tSlUt50cqyMXfCzX+oOPqN0vuGqWzbcJ2xvnkzkq46oOpz7dQaTDBdfICb4N14+GARUDw2XV2N4tvzg==', desktop / 'node_modules/ws')
    shutil.copytree(ROOT / 'shared', destination / 'shared', dirs_exist_ok=True)
    resource = destination / 'Resources'; resource.mkdir(exist_ok=True)
    for name in ['localizations.json', 'tools.json', 'screen-tools.json', 'user-guide.json']:
        shutil.copy2(ROOT / 'Resources' / name, resource / name)
    shutil.copytree(ROOT / 'Resources/Guide', resource / 'Guide', dirs_exist_ok=True)
    shutil.copy2(ROOT / 'version.json', destination / 'version.json')
    mcp = destination / 'mcp'; mcp.mkdir(exist_ok=True)
    for name in ['server.mjs', 'package.json', 'pnpm-lock.yaml', 'README.md']:
        shutil.copy2(ROOT / 'mcp' / name, mcp / name)
    package_mcp(destination)
    scripts = destination / 'scripts'; scripts.mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'scripts/install_asterhand_mcp.py', scripts)
    shutil.copy2(ROOT / 'desktop/macos/install-mcp.mjs', scripts / 'install_macos_mcp.mjs')
    shutil.copy2(ROOT / 'desktop/macos/install-skill.mjs', scripts / 'install_macos_skill.mjs')
    for skill in ['asterhand-skill', 'asterhand-control']:
        shutil.copytree(ROOT / 'skills' / skill, destination / 'skills' / skill, dirs_exist_ok=True)
    shutil.copytree(ROOT / 'cli', destination / 'cli', dirs_exist_ok=True)


def create_icns(output):
    # Modern macOS accepts PNG-backed icns entries. A 1024px ic10 image covers
    # Retina Finder/Dock display without an image conversion dependency.
    png = (ROOT / 'Resources/Icons/AgentGoIcon1024.png').read_bytes()
    block = b'ic10' + struct.pack('>I', len(png) + 8) + png
    output.write_bytes(b'icns' + struct.pack('>I', len(block) + 8) + block)


def macho_info(path):
    data = path.read_bytes()
    if data[:4] != b'\xcf\xfa\xed\xfe': raise ValueError('Expected a thin 64-bit Mach-O: ' + str(path))
    cpu, subtype, kind, count, size, flags, reserved = struct.unpack_from('<7I', data, 4)
    result = {'cpu': {0x01000007: 'x86_64', 0x0100000c: 'arm64'}.get(cpu, hex(cpu)), 'signed': False}
    offset = 32
    def version(n): return '.'.join(str(x) for x in ((n >> 16) & 0xffff, (n >> 8) & 255, n & 255))
    for _ in range(count):
        command, length = struct.unpack_from('<II', data, offset)
        if length < 8 or offset + length > len(data): raise ValueError('Malformed Mach-O command')
        if command == 0x32:
            platform, minimum, sdk = struct.unpack_from('<III', data, offset + 8)
            if platform != 1: raise ValueError('Non-macOS Mach-O platform')
            result.update(minimum=version(minimum), sdk=version(sdk))
        elif command == 0x24:
            minimum, sdk = struct.unpack_from('<II', data, offset + 8)
            result.update(minimum=version(minimum), sdk=version(sdk))
        elif command == 0x1d: result['signed'] = True
        offset += length
    if 'minimum' not in result: raise ValueError('Mach-O deployment target missing')
    result.update(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))
    return result


def verify_adhoc_signature(path, info=None, resources=None):
    """Verify CodeDirectory hashes, without claiming Apple trust validation.

    Layout: Apple's xnu/osfmk/kern/cs_blobs.h. rcodesign 0.29's verify
    incorrectly rejects the empty CMS wrapper of an otherwise valid ad-hoc
    signature, so use an independent page/special-slot digest check here.
    """
    data = path.read_bytes()
    count = struct.unpack_from('<I', data, 16)[0]
    offset = 32; signature = None
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 0x1d:
            start, length = struct.unpack_from('<II', data, offset + 8)
            signature = data[start:start + length]
        offset += size
    if signature is None: raise ValueError('Missing code signature: ' + str(path))
    magic, length, count = struct.unpack_from('>III', signature)
    if magic != 0xfade0cc0 or length > len(signature): raise ValueError('Invalid signature SuperBlob')
    blobs = {}
    for index in range(count):
        kind, offset = struct.unpack_from('>II', signature, 12 + index * 8)
        magic, size = struct.unpack_from('>II', signature, offset)
        if size < 8 or offset + size > length: raise ValueError('Invalid signature blob bounds')
        blobs[kind] = signature[offset:offset + size]
    directory = blobs.get(0)
    if not directory or struct.unpack_from('>I', directory)[0] != 0xfade0c02:
        raise ValueError('Missing primary CodeDirectory')
    version, flags, hash_offset, identifier, special_count, code_count, code_limit = struct.unpack_from('>7I', directory, 8)
    hash_size, hash_type, platform, page_log = struct.unpack_from('>4B', directory, 36)
    if not flags & 2: raise ValueError('Expected an explicitly ad-hoc signature')
    algorithm = {1: 'sha1', 2: 'sha256', 3: 'sha256', 4: 'sha384'}.get(hash_type)
    if not algorithm: raise ValueError('Unsupported CodeDirectory hash algorithm')
    def hash_value(value): return hashlib.new(algorithm, value).digest()[:hash_size]
    page_size = 1 << page_log if page_log else code_limit
    if code_limit > len(data) or code_count != (code_limit + page_size - 1) // page_size:
        raise ValueError('Invalid CodeDirectory code range')
    if hash_offset - special_count * hash_size < 0 or hash_offset + code_count * hash_size > len(directory):
        raise ValueError('Invalid CodeDirectory hash table')
    for index in range(code_count):
        actual = hash_value(data[index * page_size:min(code_limit, (index + 1) * page_size)])
        expected = directory[hash_offset + index * hash_size:hash_offset + (index + 1) * hash_size]
        if actual != expected: raise ValueError('Code page digest mismatch: ' + str(path))
    special = {**blobs}
    if info is not None: special[1] = info.read_bytes()
    if resources is not None: special[3] = resources.read_bytes()
    for slot in range(1, special_count + 1):
        expected = directory[hash_offset - slot * hash_size:hash_offset - (slot - 1) * hash_size]
        if expected == b'\x00' * hash_size: continue
        if slot not in special or hash_value(special[slot]) != expected:
            raise ValueError('Special-slot digest mismatch ' + str(slot) + ': ' + str(path))
    signing_identifier = directory[identifier:directory.index(0, identifier)].decode('utf-8')
    return {'ad_hoc': True, 'identifier': signing_identifier, 'identity_stability': 'version-specific ad-hoc identity',
            'hash': algorithm, 'code_pages_verified': code_count,
            'special_slots_verified': special_count, 'cdhash': hashlib.new(algorithm, directory).hexdigest()[:40]}


def verify_resource_seal(app):
    contents = app / 'Contents'
    manifest = plistlib.loads((contents / '_CodeSignature/CodeResources').read_bytes())
    checked = 0
    for name, value in manifest['files2'].items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts: raise ValueError('Unsafe sealed resource path')
        file = contents.joinpath(*relative.parts)
        if 'hash2' in value:
            if hashlib.sha256(file.read_bytes()).digest() != value['hash2']: raise ValueError('Resource seal mismatch: ' + name)
            checked += 1
        elif 'hash' in value:
            if hashlib.sha1(file.read_bytes()).digest() != value['hash']: raise ValueError('Resource seal mismatch: ' + name)
            checked += 1
        else: raise ValueError('Unexpected unverified resource seal: ' + name)
    return checked


def sign(app, log):
    if sys.platform == 'darwin':
        run(['codesign', '--force', '--deep', '--sign', '-', '--timestamp=none', app], log)
        run(['codesign', '--verify', '--deep', '--strict', app], log)
        return {'method': 'Apple codesign ad-hoc; not notarized', 'apple_codesign_verified': True}
    signer = ROOT / '.build-deps/codesign/apple-codesign-0.29.0-x86_64-pc-windows-msvc/rcodesign.exe'
    if not signer.is_file(): raise SystemExit('First run scripts/bootstrap_windows.py for rcodesign.')
    run([signer, 'sign', '--timestamp-url', 'none', app], log)
    contents = app / 'Contents'
    checks = {'host': verify_adhoc_signature(contents / 'MacOS/AsterHand', contents / 'Info.plist', contents / '_CodeSignature/CodeResources'),
              'runtime': verify_adhoc_signature(contents / 'Resources/runtime/node'),
              'resources_verified': verify_resource_seal(app)}
    return {'method': 'rcodesign 0.29.0 ad-hoc; independently verified CodeDirectory and resource digests; not notarized',
            'apple_codesign_verified': False, 'checks': checks,
            'rcodesign_verify_limitation': '0.29.0 verify reports a known false CMS error for ad-hoc signatures; Apple codesign and Gatekeeper require actual macOS verification.'}


def create_zip(app, output):
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=7) as archive:
        for path in sorted(app.rglob('*')):
            relative = path.relative_to(app.parent).as_posix()
            executable = path.name == 'node' or relative == 'AsterHand.app/Contents/MacOS/AsterHand' or path.suffix == '.command'
            mode = 0o755 if path.is_dir() or executable else 0o644
            entry = zipfile.ZipInfo(relative + ('/' if path.is_dir() else ''))
            entry.create_system = 3
            entry.external_attr = ((stat.S_IFDIR if path.is_dir() else stat.S_IFREG) | mode) << 16
            if path.is_dir(): entry.external_attr |= 0x10
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, b'' if path.is_dir() else path.read_bytes())


def main():
    from sync_design import sync as sync_design
    sync_design()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=['all', 'x64', 'arm64'], default='all')
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--bootstrap', action='store_true')
    parser.add_argument('--compile-only', action='store_true')
    parser.add_argument('--skip-sign', action='store_true')
    args = parser.parse_args()
    DEPS.mkdir(parents=True, exist_ok=True)
    sdk = sdk_path(args)
    release = json.loads((ROOT / 'version.json').read_text(encoding='utf-8'))
    version = release.get('macos_version', '0.1')
    build = ROOT / 'build/macos-desktop'; build.mkdir(parents=True, exist_ok=True)
    log = build / 'build.log'; log.write_text('', encoding='utf-8')
    backend = build / 'backend-stage'
    if not args.compile_only:
        if backend.exists():
            backend.resolve().relative_to((ROOT / 'build/macos-desktop').resolve())
            shutil.rmtree(backend)
        copy_backend(backend)
    outputs = []
    for arch in (ARCHES if args.arch == 'all' else [args.arch]):
        cpu, minimum = ARCHES[arch]
        output = build / arch; output.mkdir(exist_ok=True)
        app = output / 'AsterHand.app'
        if app.exists():
            app.resolve().relative_to((ROOT / 'build/macos-desktop').resolve())
            shutil.rmtree(app)
        contents = app / 'Contents'; executable = contents / 'MacOS/AsterHand'
        executable.parent.mkdir(parents=True, exist_ok=True)
        print('Compiling macOS ' + cpu + ' (minimum ' + minimum + ')', flush=True)
        compile_host(arch, sdk, executable, log)
        if args.compile_only:
            print(json.dumps(macho_info(executable), indent=2)); continue
        resources = contents / 'Resources'; resources.mkdir(exist_ok=True)
        shutil.copytree(backend, resources / 'backend')
        runtime(arch, resources / 'runtime')
        create_icns(resources / 'AsterHand.icns')
        shutil.copy2(ROOT / 'Resources/Icons/AgentGoIcon1024.png', resources / 'AsterHandIconLight.png')
        shutil.copy2(ROOT / 'Resources/Icons/AgentGoIconDark1024.png', resources / 'AsterHandIconDark.png')
        info = {'CFBundleDevelopmentRegion': 'en', 'CFBundleDisplayName': 'AsterHand',
                'CFBundleExecutable': 'AsterHand', 'CFBundleIdentifier': 'local.asterhand.mac',
                'CFBundleIconFile': 'AsterHand.icns', 'CFBundleInfoDictionaryVersion': '6.0',
                'CFBundleName': 'AsterHand', 'CFBundlePackageType': 'APPL',
                'CFBundleShortVersionString': version, 'CFBundleVersion': str(release.get('macos_build', release['build'])),
                'LSMinimumSystemVersion': minimum, 'NSHighResolutionCapable': True,
                'NSSupportsAutomaticGraphicsSwitching': True, 'NSRequiresAquaSystemAppearance': False,
                'NSPrincipalClass': 'NSApplication',
                'NSLocalNetworkUsageDescription': 'Discover and connect to your paired AsterHand devices on the local network.',
                'NSMicrophoneUsageDescription': 'Voice input starts only when you choose the microphone button.',
                'NSSpeechRecognitionUsageDescription': 'Convert the voice input you start into a message.',
                'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True, 'NSAllowsArbitraryLoadsInWebContent': True}}
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        for name, script in [('MCP', 'mcp'), ('Skill', 'skill')]:
            command = '#!/bin/bash\nset -euo pipefail\nresources="$(cd "$(dirname "$0")" && pwd)"\nexec "$resources/runtime/node" "$resources/backend/scripts/install_macos_' + script + '.mjs"\n'
            (resources / ('Install Codex ' + name + '.command')).write_text(command, encoding='utf-8', newline='\n')
            (resources / ('Install Codex ' + name + '.command')).chmod(0o755)
        shutil.copy2(ROOT / 'desktop/macos/README.md', resources / 'README.md')
        provenance = {'node': {'version': NODE_VERSION, 'sha256': NODE_HASHES[arch],
                              'url': 'https://nodejs.org/dist/v' + NODE_VERSION + '/node-v' + NODE_VERSION + '-darwin-' + arch + '.tar.gz',
                              'support': 'https://github.com/nodejs/node/blob/v18.20.8/BUILDING.md'},
                      'sdk': {'version': '11.3' if sys.platform != 'darwin' and not args.sdk else 'user-supplied Apple SDK',
                              'url': SDK_URL, 'sha256': SDK_SHA256 if sys.platform != 'darwin' and not args.sdk else None}}
        (resources / 'dependencies.json').write_text(json.dumps(provenance, indent=2) + '\n', encoding='utf-8')
        signing = 'unsigned' if args.skip_sign else sign(app, log)
        audit = {'architecture': cpu, 'minimum_macos': minimum, 'version': version,
                 'macos_build': release.get('macos_build', release['build']), 'host': macho_info(executable),
                 'runtime': macho_info(resources / 'runtime/node'), 'signing': signing,
                 'native_source_sha256': digest(ROOT / 'desktop/macos/main.m'),
                 'backend_file_count': sum(1 for p in (resources / 'backend').rglob('*') if p.is_file()),
                 'validation_boundary': 'Cross-compiled and statically checked. macOS launch, TCC, AI login, screen and device operation require actual Mac validation.',
                 'tcc_upgrade_boundary': 'Ad-hoc identity is specific to this build. A previous macOS permission-list checkmark may belong to an older build; the user may need to remove that entry and add the current application. No TCC database or system trust settings are modified.',
                 'permission_owner_validation': {'expected_scope': 'application',
                                                 'expected_bundle_id': info['CFBundleIdentifier'],
                                                 'expected_pid': 'running GUI process, matching ASTERHAND_PARENT_PID',
                                                 'expected_transport': 'authenticated private AF_UNIX socket',
                                                 'runtime_verified_on_macos': False}}
        audit['permission_value_contract'] = 'true/1 = granted; false/0 = denied; other values and query errors remain unknown. Native GUI emits JSON booleans.'
        for key in ['host', 'runtime']:
            if audit[key]['cpu'] != cpu: raise ValueError('Wrong Mach-O architecture')
            actual = tuple(int(v) for v in audit[key]['minimum'].split('.'))
            allowed = tuple(int(v) for v in (minimum + '.0').split('.')[:3])
            if actual > allowed: raise ValueError('Runtime exceeds deployment target')
            if not args.skip_sign and not audit[key]['signed']: raise ValueError('Missing code signature')
        dist = ROOT / 'dist'; dist.mkdir(exist_ok=True)
        name = 'AsterHand-' + version + '-macOS-' + ('Intel' if arch == 'x64' else 'AppleSilicon')
        archive = dist / (name + '.zip')
        create_zip(app, archive)
        audit.update(archive=str(archive.relative_to(ROOT)), archive_sha256=digest(archive), archive_bytes=archive.stat().st_size)
        (dist / (name + '-report.json')).write_text(json.dumps(audit, indent=2) + '\n', encoding='utf-8')
        outputs.append(audit)
        print('Created ' + str(archive), flush=True)
    print(json.dumps(outputs, indent=2))
    from sync_desktop_packages import sync_after_build
    sync_after_build([ROOT / item['archive'] for item in outputs])


if __name__ == '__main__':
    main()
