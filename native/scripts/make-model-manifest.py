#!/usr/bin/env python3
"""Build a pinned public model manifest. No personal data is read."""
import hashlib, json, pathlib, urllib.request

root = pathlib.Path(__file__).resolve().parents[1]
specs = [
    ('parakeet', 'FluidInference/parakeet-tdt-0.6b-v3-coreml', '7dd20fe6b1797d35f5e3307e8b1732d9a178edfe'),
    ('qwen', 'unsloth/Qwen3-4B-Instruct-2507-GGUF', 'a06e946bb6b655725eafa393f4a9745d460374c9'),
    ('vad', 'FluidInference/silero-vad-coreml', 'b419383c55c110e2c9271fa6ee0ea83d03c70d96'),
]
files = []
for kind, repo, rev in specs:
    with urllib.request.urlopen(f'https://huggingface.co/api/models/{repo}/revision/{rev}?blobs=true') as r:
        meta = json.load(r)
    for item in meta['siblings']:
        name = item['rfilename']
        selected = (kind == 'qwen' and name == 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf') or (kind == 'parakeet' and (name.split('/')[0] in ['Preprocessor.mlmodelc', 'Encoder.mlmodelc', 'Decoder.mlmodelc', 'JointDecisionv3.mlmodelc'] or name == 'parakeet_vocab.json')) or (kind == 'vad' and name.startswith('silero-vad-unified-256ms-v6.2.1.mlmodelc/'))
        if not selected: continue
        url = f'https://huggingface.co/{repo}/resolve/{rev}/{name}'
        sha = item.get('lfs', {}).get('sha256')
        if sha is None:
            with urllib.request.urlopen(url) as r: sha = hashlib.sha256(r.read()).hexdigest()
        files.append(dict(path=({'parakeet': 'parakeet/', 'vad': 'vad/'}.get(kind, '')) + name, url=url, sha256=sha, size=item['size'], group=kind))
dest = root / 'Sources/VoiceWisprCore/Resources/model-manifest.json'
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(json.dumps(dict(version=1, files=files), indent=2) + '\n')
print(f'{len(files)} files, {sum(f["size"] for f in files):,} bytes')
