"""Download isolated cross-build dependencies; does not change the system PATH."""
import concurrent.futures
import hashlib
import pathlib
import subprocess
import urllib.request
import zipfile
import shutil
import argparse

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEPS = ROOT / '.build-deps'
SDK_COMMIT = '0222fd5413cf4b9af096f37b4621afa2688572f7'

def zig():
    DEPS.mkdir(exist_ok=True)
    archive = DEPS / 'zig.zip'
    if not archive.exists():
        print('Downloading Zig 0.14.1...', flush=True)
        urllib.request.urlretrieve('https://ziglang.org/download/0.14.1/zig-x86_64-windows-0.14.1.zip', archive)
    expected = '554f5378228923ffd558eac35e21af020c73789d87afeabf4bfd16f2e6feed2c'
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise RuntimeError('Zig archive SHA-256 mismatch; remove .build-deps/zig.zip and retry')
    target = DEPS / 'zig-x86_64-windows-0.14.1'
    if not target.exists():
        with zipfile.ZipFile(archive) as z:
            z.extractall(DEPS)
    print('Zig ready', flush=True)

def sdk():
    path = DEPS / 'sdks'
    if not path.exists():
        subprocess.run(['git', 'clone', '--depth', '1', '--filter=blob:none', '--sparse',
                        'https://github.com/theos/sdks.git', str(path)], check=True)
    current = subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()
    if current != SDK_COMMIT:
        subprocess.run(['git', '-C', str(path), 'fetch', '--depth', '1', 'origin', SDK_COMMIT], check=True)
        subprocess.run(['git', '-C', str(path), 'checkout', '--detach', SDK_COMMIT], check=True)
    subprocess.run(['git', '-C', str(path), 'sparse-checkout', 'set', 'iPhoneOS16.5.sdk'], check=True)
    # Git on Windows represents symlinks as tiny text files. Materialize SDK links.
    listing = subprocess.check_output(['git', '-C', str(path), 'ls-files', '--stage', 'iPhoneOS16.5.sdk'], text=True)
    links = {}
    for line in listing.splitlines():
        meta, name = line.split('\t', 1)
        if meta.startswith('120000 '):
            link = path / name
            target = subprocess.check_output(['git', '-C', str(path), 'cat-file', '-p', meta.split()[1]], text=True)
            links[link.resolve()] = (link.parent / target).resolve()
    def materialize(link, seen=None):
        seen = set() if seen is None else seen
        if link in seen:
            raise RuntimeError('Cyclic SDK symlink: ' + str(link))
        seen.add(link)
        target = links[link]
        target.relative_to(path.resolve())
        for parent in reversed(target.parents):
            if parent in links and not parent.is_dir():
                materialize(parent, seen.copy())
        if target in links:
            materialize(target, seen)
        if target.is_dir():
            if link.is_file() and not link.is_symlink():
                link.unlink()  # Only a Git mode-120000 stub inside .build-deps.
            if not link.is_symlink():
                shutil.copytree(target, link, dirs_exist_ok=True)
        elif not link.is_symlink():
            shutil.copyfile(target, link)
    for link in links:
        materialize(link)
    print('SDK ready: ' + subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip(), flush=True)

def signer():
    name = 'apple-codesign-0.29.0-x86_64-pc-windows-msvc.zip'
    base = 'https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F0.29.0/'
    archive = DEPS / name
    if not archive.exists():
        print('Downloading Apple Codesign 0.29.0...', flush=True)
        urllib.request.urlretrieve(base + name, archive)
    checksum = urllib.request.urlopen(base + name + '.sha256', timeout=30).read().decode().split()[0]
    if hashlib.sha256(archive.read_bytes()).hexdigest() != checksum:
        raise RuntimeError('Apple Codesign SHA-256 mismatch')
    with zipfile.ZipFile(archive) as z:
        z.extractall(DEPS / 'codesign')
    print('Signer ready', flush=True)

def roothide():
    archive = DEPS / 'roothide-devkit.zip'
    if not archive.exists():
        urllib.request.urlretrieve('https://github.com/RootHide/libroothide/files/12643716/devkit.zip', archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != '295ce6b7e411aad38738c2965789eb10c7ed244567b9b86b539e226fa6a3dac5':
        raise RuntimeError('RootHide devkit SHA-256 mismatch')
    with zipfile.ZipFile(archive) as z:
        z.extractall(DEPS / 'roothide-devkit')
    name = 'llvm-mingw-20260908-msvcrt-x86_64'
    archive = DEPS / (name + '.zip')
    if not archive.exists():
        print('Downloading LLVM/LLD 23.1.1...', flush=True)
        urllib.request.urlretrieve('https://github.com/mstorsjo/llvm-mingw/releases/download/20260908/' + name + '.zip', archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != '341cc9786b54956467ac19a02fdb00749307eac133da56108f643e4189db810b':
        raise RuntimeError('LLVM/LLD archive SHA-256 mismatch')
    binaries = ('ld.lld.exe', 'libLLVM-23.dll', 'libc++.dll', 'libunwind.dll', 'libwinpthread-1.dll', 'libffi-8.dll')
    with zipfile.ZipFile(archive) as z:
        for binary in binaries:
            z.extract(name + '/bin/' + binary, DEPS)
    shutil.copyfile(DEPS / name / 'bin/ld.lld.exe', DEPS / name / 'bin/lld.exe')
    subprocess.run([str(DEPS / name / 'bin/lld.exe'), '-flavor', 'darwin', '--version'], check=True)
    print('RootHide devkit and Darwin LLD ready', flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--roothide', action='store_true')
    args = parser.parse_args()
    DEPS.mkdir(exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(zig), pool.submit(sdk), pool.submit(signer)]
        if args.roothide:
            futures.append(pool.submit(roothide))
        for future in futures:
            future.result()
