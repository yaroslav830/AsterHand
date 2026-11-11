"""Mirror successful local release packages into an explicitly enabled desktop folder."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
FOLDERS = ("Windows", "macOS", "Linux", "Android", "iOS")
PATTERNS = (
    ("windows-installer", "Windows", "AsterHand-Windows-Setup.exe"),
    ("windows-portable", "Windows", "AsterHand-Windows.exe"),
    ("mac-intel", "macOS", "AsterHand-*-macOS-Intel.zip"),
    ("mac-arm64", "macOS", "AsterHand-*-macOS-AppleSilicon.zip"),
    ("linux-amd64", "Linux", "AsterHand-*-linux-amd64.deb"),
    ("linux-arm64", "Linux", "AsterHand-*-linux-arm64.deb"),
    ("linux-x64-portable", "Linux", "AsterHand-*-linux-x64.tar.gz"),
    ("linux-arm64-portable", "Linux", "AsterHand-*-linux-arm64.tar.gz"),
    ("android", "Android", "AsterHand-*-Android.apk"),
    ("ios-rootful", "iOS", "AsterHand-*-Rootful.deb"),
    ("ios-rootless", "iOS", "AsterHand-*-Rootless.deb"),
    ("ios-roothide", "iOS", "AsterHand-*-RootHide.deb"),
)
MANIFEST = "安装包清单.json"


def sha256(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def atomic_text(path, text):
    data = text.encode("utf-8")
    if path.exists() and path.read_bytes() == data:
        return
    fd, temporary = tempfile.mkstemp(prefix=".asterhand-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def json_text(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


@contextmanager
def sync_lock(root):
    private = root / ".private"
    private.mkdir(exist_ok=True)
    with (private / "desktop-packages.lock").open("a+b") as stream:
        stream.seek(0)
        if not stream.read(1):
            stream.write(b"0")
            stream.flush()
        deadline = time.monotonic() + 30
        while True:
            try:
                stream.seek(0)
                if os.name == "nt":
                    import msvcrt
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except (OSError, BlockingIOError):
                if time.monotonic() >= deadline:
                    raise TimeoutError("Desktop package sync is busy")
                time.sleep(0.1)
        try:
            yield
        finally:
            if os.name == "nt":
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream, fcntl.LOCK_UN)


def managed_path(destination, relative):
    relative = Path(relative)
    if relative.is_absolute() or ".." in relative.parts or len(relative.parts) != 2 or relative.parts[0] not in FOLDERS:
        raise ValueError("Invalid managed package path")
    path = destination / relative
    if destination.is_symlink() or path.parent.is_symlink() or path.is_symlink():
        raise ValueError("Package folder must not be redirected by a symbolic link")
    if not path.resolve().is_relative_to(destination.resolve()):
        raise ValueError("Package destination escapes the configured folder")
    return path


def copy_verified(source, target, expected):
    fd, temporary = tempfile.mkstemp(prefix=".asterhand-", suffix=".tmp", dir=target.parent)
    os.close(fd)
    temporary = Path(temporary)
    try:
        before = source.stat()
        shutil.copyfile(source, temporary)
        observed = sha256(temporary)
        after = source.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns) or observed != expected:
            raise RuntimeError("Source package changed while copying: " + source.name)
        os.replace(temporary, target)
        if sha256(target) != expected:
            raise RuntimeError("Desktop copy verification failed: " + target.name)
    finally:
        temporary.unlink(missing_ok=True)


def select_packages(dist):
    for key, folder, pattern in PATTERNS:
        candidates = [p for p in dist.glob(pattern) if p.is_file() and not p.is_symlink()]
        if not candidates:
            continue
        def rank(path):
            match = re.match(r"AsterHand-(\d+(?:\.\d+)*)-", path.name)
            version = tuple(map(int, match[1].split("."))) if match else (0,)
            return version, path.stat().st_mtime_ns
        yield key, folder, max(candidates, key=rank)


def sync_packages(root=ROOT, only=None):
    root = Path(root).resolve()
    config = root / ".private/desktop-packages.json"
    if os.environ.get("ASTERHAND_NO_DESKTOP_SYNC") == "1" or not config.is_file():
        return {"enabled": False}
    with sync_lock(root):
        settings = json.loads(config.read_text(encoding="utf-8"))
        if not settings.get("enabled"):
            return {"enabled": False}
        destination = Path(settings["destination"])
        if not destination.is_absolute() or len(destination.parts) < 3 or destination.is_symlink():
            raise ValueError("Choose a normal absolute package folder")
        destination.mkdir(parents=True, exist_ok=True)
        manifest_path = destination / MANIFEST
        old = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
        if old and old.get("managedBy") != "AsterHand desktop package sync":
            raise ValueError("Existing package manifest belongs to a different application")
        entries = {item["id"]: item for item in old.get("packages", [])}
        selected = {Path(p).resolve() for p in only} if only is not None else None
        copied, stale = [], []
        for key, folder, source in select_packages(root / "dist"):
            if selected is not None and source.resolve() not in selected:
                continue
            relative = folder + "/" + source.name
            target = managed_path(destination, relative)
            target.parent.mkdir(exist_ok=True)
            digest = sha256(source)
            previous = entries.get(key)
            if previous and previous["file"] != relative:
                stale.append(previous)
            if not target.exists() or sha256(target) != digest:
                copy_verified(source, target, digest)
                copied.append(relative)
            entries[key] = {"id": key, "platform": folder, "file": relative,
                            "bytes": source.stat().st_size, "sha256": digest,
                            "sourceModifiedUtc": datetime.fromtimestamp(source.stat().st_mtime, timezone.utc).isoformat()}
        packages = sorted(entries.values(), key=lambda item: (FOLDERS.index(item["platform"]), item["file"]))
        manifest = {"managedBy": "AsterHand desktop package sync", "schema": 1,
                    "source": "Latest local build output (dist)", "packages": packages}
        if old.get("packages") == packages:
            manifest["updatedAtUtc"] = old.get("updatedAtUtc", datetime.now(timezone.utc).isoformat())
        else:
            manifest["updatedAtUtc"] = datetime.now(timezone.utc).isoformat()
        atomic_text(manifest_path, json_text(manifest))
        atomic_text(destination / "SHA256SUMS.txt", "".join(item["sha256"] + "  " + item["file"] + "\n" for item in packages))
        cloud_note = ("\n云盘副本：" + settings["cloudUrl"] +
                      "\n云盘每小时检查更新；需要这台电脑联网、Codex 自动任务运行且浏览器登录有效。\n") if settings.get("cloudUrl") else ""
        atomic_text(destination / "使用说明.txt",
            "AsterHand 最新安装包\n\n"
            "Windows：安装版与便携版 EXE。\nmacOS：Intel 与 Apple 芯片 ZIP。\n"
            "Linux：amd64、arm64 DEB 与便携版。\nAndroid：APK。\n"
            "iOS：Rootful、Rootless、RootHide DEB，请按越狱环境选择。\n\n"
            "来源为这台电脑的最新本机构建产物；不同平台保留各自最近构建的版本。\n"
            "成功构建新包后自动同步，无需手动复制。这里不自动安装或运行软件。\n"
            "安装包清单.json 和 SHA256SUMS.txt 记录大小、构建文件时间及校验值。\n"
            "手动同步：在 AsterHand 工作区运行 python scripts/sync_desktop_packages.py\n"
            "暂停桌面自动同步：python scripts/sync_desktop_packages.py --disable\n" + cloud_note)
        # Remove only an unchanged old file explicitly owned by our previous manifest.
        for item in stale:
            path = managed_path(destination, item["file"])
            if path.exists() and sha256(path) == item["sha256"]:
                path.unlink()
        return {"enabled": True, "destination": str(destination), "packages": len(packages),
                "copied": copied, "unchanged": len(packages) - len(copied)}


def sync_after_build(artifacts):
    """Optional per-workspace integration; no configuration means no desktop writes."""
    try:
        result = sync_packages(only=artifacts)
        if result.get("enabled"):
            print("Desktop packages: " + json.dumps(result, ensure_ascii=False))
    except Exception as error:
        print("Desktop package sync failed; build output is intact: " + str(error), file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configure", type=Path, help="Enable syncing to this exact folder")
    parser.add_argument("--disable", action="store_true")
    args = parser.parse_args()
    config = ROOT / ".private/desktop-packages.json"
    if args.configure:
        target = args.configure.resolve()
        if len(target.parts) < 3 or target.is_symlink():
            parser.error("Choose a normal absolute folder")
        if target.exists() and any(target.iterdir()) and not (target / MANIFEST).is_file():
            parser.error("The selected folder is not empty and is not managed by AsterHand")
        config.parent.mkdir(exist_ok=True)
        atomic_text(config, json_text({"enabled": True, "destination": str(target)}))
    if args.disable and config.exists():
        settings = json.loads(config.read_text(encoding="utf-8"))
        settings["enabled"] = False
        atomic_text(config, json_text(settings))
    print(json.dumps(sync_packages(), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
