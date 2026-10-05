#!/usr/bin/env python3
"""Obtain checksum-pinned embedded llama framework; developer build helper only."""
import hashlib, pathlib, subprocess, zipfile
root = pathlib.Path(__file__).resolve().parents[1]
archive = root / 'Vendor/llama.zip'
framework = root / 'Vendor/build-apple/llama.xcframework'
sha = '6f7684c7b00bdf13e4766d4a261471e5d6997dcfb3debfdf93afce3c0859942d'
if framework.exists():
    if not archive.exists(): raise SystemExit('Pinned archive missing: framework provenance cannot be verified.')
else:
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists(): subprocess.run(['curl', '-fL', '--retry', '2', 'https://github.com/ggml-org/llama.cpp/releases/download/b11361/llama-b11361-xcframework.zip', '-o', str(archive)], check=True)
if hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest() != sha: raise SystemExit('llama checksum mismatch')
if not framework.exists():
    with zipfile.ZipFile(archive) as z:
        for item in z.infolist():
            target = (archive.parent / item.filename).resolve()
            if not target.is_relative_to(archive.parent.resolve()): raise SystemExit('Unsafe archive path')
        z.extractall(archive.parent)
print('Pinned llama.cpp b11361 verified.')
