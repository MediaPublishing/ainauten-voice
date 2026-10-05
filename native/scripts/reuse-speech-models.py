#!/usr/bin/env python3
"""Reuse only byte-verified model files; APFS cloning avoids duplicate disk blocks."""
import hashlib, json, pathlib, subprocess, urllib.request
root=pathlib.Path(__file__).resolve().parents[1]
manifest=json.loads((root/'Sources/VoiceWisprCore/Resources/model-manifest.json').read_text())
source=pathlib.Path.home()/'Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml'
target=pathlib.Path.home()/'Library/Application Support/Voice Wispr/Models'
reused=0; fetched=0
for f in manifest['files']:
    if f['group']!='parakeet':continue
    old=source/f['path'].removeprefix('parakeet/')
    new=target/f['path'];new.parent.mkdir(parents=True,exist_ok=True)
    if not new.exists():
        if old.exists() and hashlib.file_digest(old.open('rb'),'sha256').hexdigest()==f['sha256']:
            subprocess.run(['cp','-c',str(old),str(new)],check=True);reused+=1
        else:
            with urllib.request.urlopen(f['url'],timeout=60) as response,new.open('wb') as out:
                while data:=response.read(1024*1024):out.write(data)
            fetched+=1
    if hashlib.file_digest(new.open('rb'),'sha256').hexdigest()!=f['sha256']:raise SystemExit('Checksum mismatch: '+f['path'])
    pathlib.Path(str(new)+'.verified').write_text(f['sha256'])
print(f'Speech model verified: {reused} APFS clones, {fetched} pinned downloads.')
