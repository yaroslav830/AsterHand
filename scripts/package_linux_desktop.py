"""Build self-contained Linux desktop tar.gz and Debian packages on any host.

No global package manager, WSL, container, public upload, or shell invocation is used.
Electron runtime digests were read from the upstream GitHub release asset API.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import shutil
import struct
import tarfile
import tempfile
import urllib.error
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "desktop/linux"
DIST = ROOT / "dist"
CACHE = ROOT / ".build-deps/electron-linux"
ELECTRON_VERSION = "45.2.1"
RUNTIME_SHA256 = {
    "x64": "616efc1ae4784af1a4f3f0e8774e73e7030e7bd1708da9d09bcf543dfa499beb",
    "arm64": "e04e635e7312f4b361664e18319aefddbcaaebfdee9c8d9a521e520aa8d385bb",
}
EPOCH = 1793664000  # 2026-11-03 00:00 UTC; stable archive member timestamps.
SOURCE_SUFFIXES = {".mjs", ".cjs", ".js", ".css", ".html", ".json", ".svg", ".png", ".jpg", ".jpeg", ".webp", ".md", ".sh"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def runtime(arch: str, mirror: str | None) -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    name = f"electron-v{ELECTRON_VERSION}-linux-{arch}.zip"
    target = CACHE / name
    if target.exists() and sha256(target) == RUNTIME_SHA256[arch]:
        return target
    bases = [mirror] if mirror else [f"https://github.com/electron/electron/releases/download/v{ELECTRON_VERSION}", f"https://npmmirror.com/mirrors/electron/{ELECTRON_VERSION}"]
    failures = []
    for base in bases:
        url = base.rstrip("/") + "/" + name
        temp = target.with_suffix(".zip.partial")
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "AsterHand-Linux-Packager/0.1"})
            print(f"Downloading {name} from {url}", flush=True)
            with urllib.request.urlopen(request, timeout=90) as response, temp.open("wb") as out:
                shutil.copyfileobj(response, out, 1024 * 1024)
            observed = sha256(temp)
            if observed != RUNTIME_SHA256[arch]:
                raise ValueError(f"SHA-256 mismatch for {name}: expected {RUNTIME_SHA256[arch]}, observed {observed}")
            temp.replace(target)
            return target
        except (OSError, ValueError) as error:
            failures.append(f"{url}: {error}")
            temp.unlink(missing_ok=True)
    raise RuntimeError("Cannot obtain a verified Electron runtime:\n" + "\n".join(failures))


def source_files() -> list[Path]:
    required = ["main.mjs", "preload.cjs", "host.mjs", "platform.mjs", "service.mjs", "store.mjs", "ai.mjs", "public/index.html", "public/app.js", "public/app.css"]
    for name in required:
        if not (SOURCE / name).is_file():
            raise RuntimeError(f"Linux application is incomplete: desktop/linux/{name} is missing")
    files = []
    for directory in (SOURCE, ROOT / "shared", ROOT / "Resources"):
        for file in sorted(directory.rglob("*")):
            relative = file.relative_to(ROOT)
            if any(part in {"node_modules", ".git", ".private", "build", "dist", "__pycache__"} for part in relative.parts):
                continue
            if file.is_symlink():
                raise RuntimeError(f"Symlinks are not permitted in application sources: {relative}")
            if file.is_file() and file.suffix.lower() in SOURCE_SUFFIXES and "package-lock" not in file.name:
                files.append(file)
    files.extend(sorted((ROOT / "desktop").glob("control-*.mjs")))
    if (ROOT / "desktop/macos-control.mjs").exists():
        files.append(ROOT / "desktop/macos-control.mjs")
    files.append(ROOT / "version.json")
    return sorted(set(files))


def copy_sources(stage: Path, files: list[Path], version: str) -> list[dict]:
    app = stage / "resources/app"
    app.mkdir(parents=True, exist_ok=True)
    manifest = []
    for file in files:
        relative = file.relative_to(ROOT)
        target = app / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(file, target)
        manifest.append({"path": relative.as_posix(), "sha256": sha256(target), "bytes": target.stat().st_size})
    package = {"name": "asterhand-linux", "productName": "AsterHand", "version": version, "private": True, "type": "module", "main": "desktop/linux/main.mjs", "license": "UNLICENSED"}
    (app / "package.json").write_text(json.dumps(package, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (app / "source-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def extract_runtime(archive: Path, stage: Path, arch: str) -> None:
    with zipfile.ZipFile(archive) as source:
        for member in source.infolist():
            relative = PurePosixPath(member.filename)
            if relative.is_absolute() or ".." in relative.parts or "\\" in member.filename:
                raise RuntimeError("Unsafe Electron runtime archive member")
            target = stage.joinpath(*relative.parts)
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            if (member.external_attr >> 16) & 0o170000 == 0o120000:
                raise RuntimeError("Unexpected runtime symlink")
            target.parent.mkdir(parents=True, exist_ok=True)
            with source.open(member) as src, target.open("wb") as out:
                shutil.copyfileobj(src, out)
    binary = stage / "electron"
    header = binary.read_bytes()[:64]
    expected_machine = 62 if arch == "x64" else 183
    if header[:5] != b"\x7fELF\x02" or struct.unpack_from("<H", header, 18)[0] != expected_machine:
        raise RuntimeError("Electron runtime does not contain the expected Linux ELF architecture")
    binary.rename(stage / "asterhand")
    (stage / "resources/default_app.asar").unlink(missing_ok=True)


def member_filter(info: tarfile.TarInfo) -> tarfile.TarInfo:
    info.uid = info.gid = 0
    info.uname = info.gname = "root"
    info.mtime = EPOCH
    if info.isdir():
        info.mode = 0o755
    elif Path(info.name).name in {"asterhand", "chrome-sandbox", "chrome_crashpad_handler", "launch.sh", "postinst", "postrm"}:
        info.mode = 0o755
    else:
        info.mode = 0o644
    return info


def tar_bytes(directory: Path, prefix: str = "") -> bytes:
    out = io.BytesIO()
    with gzip.GzipFile(fileobj=out, mode="wb", mtime=EPOCH, compresslevel=6) as compressed, tarfile.open(fileobj=compressed, mode="w") as archive:
        if prefix:
            archive.add(directory, arcname=prefix, filter=member_filter, recursive=False)
        for file in sorted(directory.rglob("*")):
            if file.is_file() or file.is_dir():
                name = str(PurePosixPath(prefix) / file.relative_to(directory).as_posix())
                archive.add(file, arcname=name, filter=member_filter, recursive=False)
    return out.getvalue()


def ar_member(stream, name: str, payload: bytes) -> None:
    header = f"{name + '/':<16}{EPOCH:<12}{0:<6}{0:<6}{'100644':<8}{len(payload):<10}`\n".encode("ascii")
    if len(header) != 60:
        raise RuntimeError("Invalid Debian ar header")
    stream.write(header)
    stream.write(payload)
    if len(payload) % 2:
        stream.write(b"\n")


def build_deb(stage: Path, target: Path, arch: str, version: str, scratch: Path) -> dict:
    data = scratch / "deb-data"
    package_root = data / "opt/asterhand"
    package_root.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(stage, package_root)
    apps = data / "usr/share/applications"
    apps.mkdir(parents=True)
    shutil.copyfile(SOURCE / "packaging/asterhand.desktop", apps / "asterhand.desktop")
    icons = data / "usr/share/icons/hicolor/scalable/apps"
    icons.mkdir(parents=True)
    shutil.copyfile(ROOT / "Resources/AgentGoIcon.svg", icons / "asterhand.svg")
    bin_dir = data / "usr/bin"
    bin_dir.mkdir(parents=True)
    (bin_dir / "asterhand").write_text('#!/bin/sh\nexec /opt/asterhand/asterhand "$@"\n', encoding="utf-8", newline="\n")
    controls = scratch / "deb-control"
    controls.mkdir()
    installed = sum(file.stat().st_size for file in data.rglob("*") if file.is_file()) // 1024
    control = f"""Package: asterhand
Version: {version}
Architecture: {'amd64' if arch == 'x64' else 'arm64'}
Maintainer: AsterHand <noreply@localhost>
Section: utils
Priority: optional
Installed-Size: {installed}
Depends: libc6 (>= 2.31), libgtk-3-0 | libgtk-4-1, libnss3, libxss1, libasound2t64 | libasound2, libgbm1, libx11-6, libxcb1, libxcomposite1, libxdamage1, libxrandr2, libdrm2
Recommends: xdotool, xdg-desktop-portal, xdg-desktop-portal-gtk, fonts-noto-color-emoji
Description: AsterHand AI workspace and paired device control
 Linux desktop client with AI conversations, projects, files, terminals,
 encrypted device pairing, screen sharing, and permission-based tools.
"""
    (controls / "control").write_text(control, encoding="utf-8", newline="\n")
    for name in ("postinst", "postrm"):
        shutil.copyfile(SOURCE / "packaging" / name, controls / name)
    md5 = []
    for file in sorted(data.rglob("*")):
        if file.is_file():
            md5.append(hashlib.md5(file.read_bytes(), usedforsecurity=False).hexdigest() + "  " + file.relative_to(data).as_posix())
    (controls / "md5sums").write_text("\n".join(md5) + "\n", encoding="utf-8")
    with target.open("wb") as out:
        out.write(b"!<arch>\n")
        ar_member(out, "debian-binary", b"2.0\n")
        ar_member(out, "control.tar.gz", tar_bytes(controls))
        ar_member(out, "data.tar.gz", tar_bytes(data))
    return {"architecture": "amd64" if arch == "x64" else "arm64", "installedKiB": installed}


def inspect_application(archive: tarfile.TarFile, prefix: str, arch: str) -> dict:
    entries = archive.getmembers()
    members = {member.name: member for member in entries}
    if len(members) != len(entries):
        raise RuntimeError("Duplicate archive paths are not permitted")
    for name, member in members.items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts or member.issym() or member.islnk():
            raise RuntimeError("Unsafe release archive path")
    main = prefix + "/resources/app/desktop/linux/main.mjs"
    binary = prefix + "/asterhand"
    if main not in members or binary not in members or not (members[binary].mode & 0o111):
        raise RuntimeError("Packaged archive is missing its executable or app entry point")
    if any(".private" in name.split("/") or "node_modules" in name.split("/") for name in members):
        raise RuntimeError("Private/development files found in release archive")
    with archive.extractfile(binary) as executable:
        header = executable.read(64)
    if header[:5] != b"\x7fELF\x02" or struct.unpack_from("<H", header, 18)[0] != (62 if arch == "x64" else 183):
        raise RuntimeError("Packaged executable has the wrong architecture")
    manifest_name = prefix + "/resources/app/source-manifest.json"
    manifest = json.loads(archive.extractfile(manifest_name).read())
    for item in manifest:
        with archive.extractfile(prefix + "/resources/app/" + item["path"]) as source:
            observed = hashlib.sha256(source.read()).hexdigest()
        if observed != item["sha256"]:
            raise RuntimeError("Packaged source manifest mismatch: " + item["path"])
    return {"members": len(members), "executableMode": oct(members[binary].mode), "entryPoint": main, "verifiedSourceFiles": len(manifest), "elfArchitecture": arch}


def inspect_tar(target: Path, prefix: str, arch: str) -> dict:
    with tarfile.open(target, "r:gz") as archive:
        return inspect_application(archive, prefix, arch)


def inspect_deb(target: Path, arch: str) -> dict:
    with target.open("rb") as source:
        if source.read(8) != b"!<arch>\n":
            raise RuntimeError("Invalid Debian archive signature")
        parts = {}
        while header := source.read(60):
            if len(header) != 60 or header[-2:] != b"`\n":
                raise RuntimeError("Invalid Debian ar member")
            name = header[:16].decode("ascii").strip().rstrip("/")
            size = int(header[48:58])
            if name in parts:
                raise RuntimeError("Duplicate Debian member")
            parts[name] = source.read(size)
            if len(parts[name]) != size:
                raise RuntimeError("Truncated Debian archive")
            if size % 2:
                source.read(1)
    if set(parts) != {"debian-binary", "control.tar.gz", "data.tar.gz"} or parts["debian-binary"] != b"2.0\n":
        raise RuntimeError("Missing Debian package members")
    with tarfile.open(fileobj=io.BytesIO(parts["control.tar.gz"]), mode="r:gz") as control:
        metadata = control.extractfile("control").read().decode()
        architecture = "amd64" if arch == "x64" else "arm64"
        if f"Architecture: {architecture}\n" not in metadata:
            raise RuntimeError("Debian package architecture mismatch")
        for name in ("postinst", "postrm"):
            if control.getmember(name).mode != 0o755:
                raise RuntimeError("Debian maintenance script is not executable")
        md5 = dict(line.split("  ", 1)[::-1] for line in control.extractfile("md5sums").read().decode().splitlines())
    with tarfile.open(fileobj=io.BytesIO(parts["data.tar.gz"]), mode="r:gz") as data:
        installed = {member.name: member for member in data.getmembers()}
        required_directories = {"opt", "opt/asterhand", "usr", "usr/bin", "usr/share", "usr/share/applications", "usr/share/icons", "usr/share/icons/hicolor", "usr/share/icons/hicolor/scalable", "usr/share/icons/hicolor/scalable/apps"}
        for name in required_directories:
            if name not in installed or not installed[name].isdir():
                raise RuntimeError("Debian package is missing a required directory entry: " + name)
        seen_directories = set()
        for name, member in installed.items():
            for parent in PurePosixPath(name).parents:
                if parent == PurePosixPath("."):
                    continue
                parent_name = parent.as_posix()
                if parent_name not in seen_directories:
                    raise RuntimeError("Debian package cannot create a parent directory before its child: " + parent_name)
            if member.isdir():
                seen_directories.add(name)
        result = inspect_application(data, "opt/asterhand", arch)
        for name, expected in md5.items():
            with data.extractfile(name) as file:
                observed = hashlib.md5(file.read(), usedforsecurity=False).hexdigest()
            if observed != expected:
                raise RuntimeError("Debian installed-file checksum mismatch: " + name)
        if data.getmember("usr/bin/asterhand").mode != 0o755 or data.getmember("usr/share/applications/asterhand.desktop").mode != 0o644:
            raise RuntimeError("Invalid Linux launcher permissions")
    return {**result, "architecture": architecture, "verifiedInstalledFiles": len(md5), "verifiedDirectoryEntries": sum(member.isdir() for member in installed.values()), "maintenanceScriptMode": "0o755"}


def build(arch: str, mirror: str | None, version: str) -> dict:
    archive = runtime(arch, mirror)
    files = source_files()
    DIST.mkdir(exist_ok=True)
    build_dir = ROOT / "build/linux-desktop"
    build_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f"{arch}-", dir=build_dir) as temp:
        scratch = Path(temp)
        stage = scratch / "app"
        stage.mkdir()
        extract_runtime(archive, stage, arch)
        manifest = copy_sources(stage, files, version)
        manifest_digest = sha256(stage / "resources/app/source-manifest.json")
        shutil.copyfile(SOURCE / "packaging/launch.sh", stage / "launch.sh")
        shutil.copyfile(SOURCE / "README.md", stage / "README.zh-CN.md")
        prefix = f"AsterHand-{version}-linux-{arch}"
        portable = DIST / f"{prefix}.tar.gz"
        portable.write_bytes(tar_bytes(stage, prefix))
        inspection = inspect_tar(portable, prefix, arch)
        deb = DIST / f"AsterHand-{version}-linux-{'amd64' if arch == 'x64' else 'arm64'}.deb"
        deb_info = build_deb(stage, deb, arch, version, scratch)
        deb_inspection = inspect_deb(deb, arch)
    artifacts = [{"name": file.name, "bytes": file.stat().st_size, "sha256": sha256(file)} for file in (portable, deb)]
    return {"arch": arch, "electronVersion": ELECTRON_VERSION, "electronArchiveSHA256": RUNTIME_SHA256[arch], "sourceFiles": len(manifest), "sourceManifestSHA256": manifest_digest, "artifacts": artifacts, "portableInspection": inspection, "deb": deb_info, "debInspection": deb_inspection}


def main() -> None:
    from sync_design import sync as sync_design
    sync_design()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=["x64", "arm64", "all"], default="x64")
    parser.add_argument("--mirror", help="Explicit Electron archive base URL; SHA-256 is always verified")
    parser.add_argument("--download-only", action="store_true")
    args = parser.parse_args()
    arches = ["x64", "arm64"] if args.arch == "all" else [args.arch]
    if args.download_only:
        for arch in arches:
            print(json.dumps({"arch": arch, "runtime": str(runtime(arch, args.mirror)), "sha256": RUNTIME_SHA256[arch]}), flush=True)
        return
    version = json.loads((SOURCE / "package.json").read_text(encoding="utf-8"))["version"]
    builds = []
    for arch in arches:
        result = build(arch, args.mirror, version)
        builds.append(result)
        print(json.dumps(result, ensure_ascii=False), flush=True)
    if len({result["sourceManifestSHA256"] for result in builds}) != 1:
        raise RuntimeError("Application sources changed between architecture builds. Re-run after source edits have finished; these packages must not be presented as a matched release.")
    report = {"version": version, "createdAtUtc": datetime.now(timezone.utc).isoformat(), "builds": builds,
              "verified": ["Pinned upstream Electron release digest", "ELF architecture", "Archive entry point and executable modes", "Allowlisted application source tree"],
              "notVerifiedByPackaging": ["Linux desktop launch", "Interactive ChatGPT account consent or paid inference", "Physical device screen/control", "Wayland portal interaction"],
              "runtimeVerificationReport": "AsterHand-Linux-VM-test-report.json",
              "runtimeVerificationBoundary": "Packaging verifies archives and architecture only. See the separate Ubuntu x86_64/XFCE/X11 VM report for actual runtime results; packaging does not verify physical devices, arm64 launch, real ChatGPT consent/inference, or Wayland portal interaction."}
    (DIST / "AsterHand-Linux-package-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    audit = {result["arch"]: {"sourceManifestSHA256": result["sourceManifestSHA256"], "artifacts": result["artifacts"], "portable": result["portableInspection"], "deb": result["debInspection"]} for result in builds}
    (DIST / "AsterHand-Linux-package-audit.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    sums = "".join(f"{artifact['sha256']}  {artifact['name']}\n" for result in builds for artifact in result["artifacts"])
    (DIST / "AsterHand-Linux-SHA256.txt").write_text(sums, encoding="utf-8")
    from sync_desktop_packages import sync_after_build
    sync_after_build([DIST / artifact["name"] for result in builds for artifact in result["artifacts"]])


if __name__ == "__main__":
    main()
