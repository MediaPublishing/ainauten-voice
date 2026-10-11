#!/usr/bin/env python3
"""Build the pinned offline language fallback. Never reads user audio or settings."""
import hashlib, pathlib, shutil, subprocess, tarfile, urllib.request
root = pathlib.Path(__file__).resolve().parents[1]
revision = '306c88f4d1286aec1bf96e544632897886af5501'
archive_sha = 'f3585ebf64df3e41b26c45d93bdb38b423ca1de0bf40cc4b6d320254867a75df'
model_revision = '5359861c739e955e79d9a303bcbc70fb988958b1'
model_sha = 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb'
out = root/'Vendor/upstream/speech-fallback'; out.mkdir(parents=True, exist_ok=True)
source = root/'Vendor/upstream/whisper-306c88f4'
archive = out/'source.tar.gz'
def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024*1024), b''): h.update(chunk)
    return h.hexdigest()
if not archive.exists():
    urllib.request.urlretrieve(f'https://codeload.github.com/ggml-org/whisper.cpp/tar.gz/{revision}', archive)
if digest(archive) != archive_sha: raise SystemExit('Whisper source checksum mismatch')
if not source.exists():
    source.mkdir()
    with tarfile.open(archive) as t:
        for member in t.getmembers():
            parts = pathlib.Path(member.name).parts[1:]
            if not parts: continue
            if member.issym() or member.islnk() or '..' in parts: raise SystemExit('Unsafe source archive')
            member.name = str(pathlib.Path(*parts)); t.extract(member, source, filter='data')
model = out/'ggml-small-q5_1.bin'
if not model.exists():
    if shutil.disk_usage(out).free < 190085487 + 768*1024*1024: raise SystemExit('Not enough disk reserve for bounded fallback build')
    partial = out/'model.partial'
    urllib.request.urlretrieve(f'https://huggingface.co/ggerganov/whisper.cpp/resolve/{model_revision}/ggml-small-q5_1.bin', partial)
    if partial.stat().st_size != 190085487 or digest(partial) != model_sha: raise SystemExit('Whisper model checksum mismatch')
    partial.rename(model)
if model.stat().st_size != 190085487 or digest(model) != model_sha: raise SystemExit('Whisper model checksum mismatch')
build = out/'build'
subprocess.run(['cmake','-S',str(root/'SpeechFallback'),'-B',str(build),f'-DWHISPER_SOURCE={source}',
                '-DCMAKE_BUILD_TYPE=Release','-DCMAKE_OSX_ARCHITECTURES=arm64','-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0'],check=True)
subprocess.run(['cmake','--build',str(build),'--target','AInautenSpeechFallback','-j','4'],check=True)
print('Pinned offline speech fallback and 190085487-byte model verified.')
