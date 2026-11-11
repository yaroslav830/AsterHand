"""Build the native Windows client against actual .NET Framework 4.6.2 references."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'desktop/windows'


def windows_icon(dark=False):
    source = ROOT / 'Resources/Icons' / ('AgentGoIconDark1024.png' if dark else 'AgentGoIcon1024.png')
    helper_source = ROOT / 'scripts/WindowsIconBuilder.cs'
    helper = ROOT / '.build-deps/WindowsIconBuilder.exe'
    icon = ROOT / '.build-deps' / ('asterhand-windows-dark.ico' if dark else 'asterhand-windows.ico')
    helper.parent.mkdir(parents=True, exist_ok=True)
    compiler = Path(os.environ.get('WINDIR', r'C:\Windows')) / 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
    if not helper.exists() or helper.stat().st_mtime < helper_source.stat().st_mtime:
        subprocess.run([str(compiler), '/nologo', '/target:exe', '/reference:System.Drawing.dll', '/out:' + str(helper), str(helper_source)], check=True)
    subprocess.run([str(helper), str(source), str(icon)], check=True)
    return icon


def references():
    target = ROOT / '.build-deps/net462/build/.NETFramework/v4.6.2'
    if (target / 'mscorlib.dll').exists():
        return target
    name = 'microsoft.netframework.referenceassemblies.net462.1.0.3.nupkg'
    base = 'https://api.nuget.org/v3-flatcontainer/microsoft.netframework.referenceassemblies.net462/1.0.3/'
    archive = ROOT / '.build-deps' / name
    archive.parent.mkdir(exist_ok=True)
    if not archive.exists():
        urllib.request.urlretrieve(base + name, archive)
    # NuGet's package SHA-512 comes from the official feed, not a third party mirror.
    expected = 'HMn0QQmPYcJsVuKet9WA8IQbBweZvc7US88N39itSRqcn/1XOT/Kao1QiiykxU+vx8k7/zim11cVmKtunju4MA=='
    digest = base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode()
    if digest != expected:
        raise RuntimeError('Pinned .NET reference package SHA-512 mismatch')
    with zipfile.ZipFile(archive) as z:
        if '.signature.p7s' not in z.namelist():
            raise RuntimeError('Unsigned .NET reference package')
        for member in z.infolist():
            path = Path(member.filename)
            if path.is_absolute() or '..' in path.parts:
                raise RuntimeError('Unsafe NuGet member')
        z.extractall(ROOT / '.build-deps/net462')
    (ROOT / '.build-deps/net462-package.json').write_text(json.dumps({'url': base + name, 'sha512': digest}, indent=2), encoding='utf-8')
    return target


def main():
    from sync_design import sync as sync_design
    sync_design()
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT / 'build/windows-native')
    parser.add_argument('--tests', action='store_true')
    parser.add_argument('--skip-test-run', action='store_true', help='Compile the test runner without running it')
    parser.add_argument('--test-runner-only', action='store_true', help='For test-only edits: retain the already built client and rebuild its test runner')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.test_runner_only and (not args.tests or not (output/'AsterHand.exe').is_file()):
        parser.error('--test-runner-only requires --tests and an existing native client')
    release = json.loads((ROOT / 'version.json').read_text(encoding='utf-8'))
    windows_version = release.get('windows_version', release['version'])
    native_version = '.'.join((windows_version.split('.') + ['0', '0'])[:3] + [str(release['build'])])
    generated = output / 'WindowsAssemblyVersion.g.cs'
    generated.write_text('using System.Reflection;\n[assembly: AssemblyVersion("' + native_version + '")]\n'
                         '[assembly: AssemblyFileVersion("' + native_version + '")]\n', encoding='utf-8')
    ref = references()
    compiler = Path(os.environ.get('WINDIR', r'C:\Windows')) / 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
    assemblies = ['mscorlib', 'System', 'System.Core', 'System.Drawing', 'System.Windows.Forms',
                  'System.Web.Extensions', 'System.Security', 'System.Net.Http', 'System.Speech']
    command = [str(compiler), '/nologo', '/noconfig', '/utf8output', '/optimize+', '/warn:4', '/langversion:5',
               '/nostdlib+', '/platform:anycpu32bitpreferred', '/target:winexe',
               '/win32manifest:' + str(SOURCE / 'app.manifest'), '/out:' + str(output / 'AsterHand.exe')]
    command += ['/reference:' + str(ref / (name + '.dll')) for name in assemblies]
    icon = windows_icon()
    dark_icon = windows_icon(True)
    command += ['/win32icon:' + str(icon)]
    for asset in ['localizations.json', 'tools.json', 'screen-tools.json']:
        command += ['/resource:' + str(ROOT / 'Resources' / asset) + ',AsterHand.' + asset]
    command += ['/resource:' + str(ROOT / 'Resources/Icons/AgentGoIcon1024.png') + ',AsterHand.icon.png',
                '/resource:' + str(ROOT / 'Resources/Icons/AgentGoIconDark1024.png') + ',AsterHand.icon-dark.png',
                '/resource:' + str(icon) + ',AsterHand.icon.ico',
                '/resource:' + str(dark_icon) + ',AsterHand.icon-dark.ico']
    command += [str(p) for p in sorted(SOURCE.glob('*.cs')) if not p.name.startswith('NativeTests')]
    command += [str(generated)]
    if not args.test_runner_only:
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            raise SystemExit(result.returncode)
    shutil.copy2(SOURCE / 'AsterHand.exe.config', output)
    resources = output / 'Resources'
    resources.mkdir(exist_ok=True)
    for name in ['localizations.json', 'tools.json', 'screen-tools.json']:
        shutil.copy2(ROOT / 'Resources' / name, resources)
    shutil.copy2(ROOT / 'version.json', output)
    if (SOURCE / 'README.md').exists():
        shutil.copy2(SOURCE / 'README.md', output / '使用说明.md')
    icons = ROOT / 'Resources/Icons'
    png = icons / 'AgentGoIcon1024.png'
    if png:
        shutil.copy2(png, resources / 'icon.png')
    shutil.copy2(icon, resources / 'icon.ico')
    shutil.copy2(icons / 'AgentGoIconDark1024.png', resources / 'icon-dark.png')
    shutil.copy2(dark_icon, resources / 'icon-dark.ico')
    if args.tests:
        test = [command[0]] + [x for x in command[1:] if x.startswith('/') and not x.startswith(('/target:', '/out:', '/platform:', '/win32manifest:'))]
        test += ['/target:exe', '/platform:anycpu32bitpreferred', '/main:AsterHand.NativeTests', '/out:' + str(output / 'AsterHand.Tests.exe')]
        test += [x for x in command[1:] if not x.startswith('/')] + [str(p) for p in sorted(SOURCE.glob('NativeTests*.cs'))]
        result = subprocess.run(test, cwd=ROOT)
        if result.returncode:
            raise SystemExit(result.returncode)
        if not args.skip_test_run:
            subprocess.run([str(output / 'AsterHand.Tests.exe')], cwd=output, check=True)
    manifest = {p.relative_to(output).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(output.rglob('*')) if p.is_file() and p.name != 'SHA256.json'}
    (output / 'SHA256.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Built:', output / 'AsterHand.exe', flush=True)


if __name__ == '__main__':
    main()
