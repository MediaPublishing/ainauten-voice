#!/usr/bin/env python3
"""Obtain checksum-pinned embedded llama framework; developer build helper only."""
import datetime, hashlib, pathlib, stat, subprocess, sys, zipfile
root = pathlib.Path(__file__).resolve().parents[1]
archive = root / 'Vendor/llama.zip'
framework = root / 'Vendor/build-apple/llama.xcframework'
sha = '6f7684c7b00bdf13e4766d4a261471e5d6997dcfb3debfdf93afce3c0859942d'
if framework.exists():
    if not archive.exists(): raise SystemExit('Pinned archive missing: framework provenance cannot be verified.')
else:
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists(): subprocess.run(['curl', '-fL', '--retry', '2', 'https://github.com/ggml-org/llama.cpp/releases/download/b11361/llama-b11361-xcframework.zip', '-o', str(archive)], check=True)
digest = hashlib.sha256()
with archive.open('rb') as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b''): digest.update(chunk)
if digest.hexdigest() != sha: raise SystemExit('llama checksum mismatch')
def usable_framework(path):
    mac = path / 'macos-arm64_x86_64/llama.framework'
    return (mac/'Modules/module.modulemap').is_file() and (mac/'Headers').is_dir() and (mac/'llama').is_file()

if not usable_framework(framework):
    if sys.platform != 'darwin': raise SystemExit('Building the native app requires macOS.')
    with zipfile.ZipFile(archive) as z:
        for item in z.infolist():
            member = pathlib.PurePosixPath(item.filename)
            if member.is_absolute() or '..' in member.parts: raise SystemExit('Unsafe archive path')
            if stat.S_ISLNK(item.external_attr >> 16):
                link = pathlib.PurePosixPath(z.read(item).decode('utf-8'))
                target = (archive.parent / member.parent / link).resolve()
                if link.is_absolute() or not target.is_relative_to(archive.parent.resolve()): raise SystemExit('Unsafe archive symlink')
    # zipfile.extractall writes framework symlinks as ordinary files. macOS ditto
    # preserves them. Extract into a fresh location and validate before replacing.
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    staging = archive.parent / ('bootstrap-staging-' + stamp)
    staging.mkdir()
    subprocess.run(['ditto', '-x', '-k', str(archive), str(staging)], check=True)
    prepared = staging / 'build-apple/llama.xcframework'
    for path in staging.rglob('*'):
        if path.is_symlink() and not path.resolve().is_relative_to(staging.resolve()): raise SystemExit('Unsafe extracted symlink')
    if not usable_framework(prepared): raise SystemExit('Extracted llama framework is incomplete.')
    if framework.exists():
        backup = archive.parent / ('bootstrap-backup-' + stamp)
        backup.mkdir()
        framework.rename(backup / framework.name)
    framework.parent.mkdir(parents=True, exist_ok=True)
    prepared.rename(framework)
print('Pinned llama.cpp b11361 verified.')
