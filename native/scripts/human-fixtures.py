#!/usr/bin/env python3
"""Download public, checksum-pinned FLEURS recordings for local ASR evaluation.
No credentials, dataset code execution, private recordings, or audio upload.
Selection is defined before recognition, independently of model results.
"""
import hashlib
import json
import pathlib
import subprocess
import tarfile
import urllib.request
import wave

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/fixtures/fleurs'
REVISION = '70bb2e84b976b7e960aa89f1c648e09c59f894dd'
BASE = f'https://huggingface.co/datasets/google/fleurs/resolve/{REVISION}/data'
LICENSE = 'https://creativecommons.org/licenses/by/4.0/'


def request(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'VoiceWispr-public-fixture-tests/0.1'}), timeout=60)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def download_language(config):
    with request(f'{BASE}/{config}/test.tsv') as response:
        metadata = response.read(4 * 1024 * 1024)
    rows = {}
    for line in metadata.decode('utf-8').splitlines():
        parts = line.split('\t')
        if len(parts) != 7:
            raise ValueError('Changed FLEURS TSV schema')
        record_id, filename, raw, normalized, _, count, gender = parts
        rows[filename] = {'recordID': int(record_id), 'filename': filename, 'reference': raw, 'normalizedReference': normalized,
                          'declaredSamples': int(count), 'gender': gender, 'config': config, 'split': 'test'}
    pure, mixed = [], []
    with request(f'{BASE}/{config}/audio/test.tar.gz') as response:
        with tarfile.open(fileobj=response, mode='r|gz') as archive:
            for member in archive:
                filename = pathlib.PurePosixPath(member.name).name
                if not member.isfile() or filename not in rows:
                    continue
                row = rows[filename]
                duration = row['declaredSamples'] / 16000
                cohort = pure if len(pure) < 10 and 5 <= duration <= 30 else mixed if len(pure) == 10 and len(mixed) < 10 and 5 <= duration <= 14 else None
                if cohort is None:
                    continue
                if not 44 <= member.size <= 4 * 1024 * 1024:
                    raise ValueError('Unexpected recording size')
                stream = archive.extractfile(member)
                data = stream.read(member.size + 1)
                if len(data) != member.size:
                    raise ValueError('Incomplete recording')
                path = OUT / f'{config}-{"pure" if cohort is pure else "mixed"}-{len(cohort) + 1:02d}.wav'
                original = path.with_suffix('.source.wav')
                # A prior interrupted run may have saved the original float WAV.
                if path.exists() and not original.exists() and path.read_bytes() == data:
                    path.rename(original)
                if original.exists() and original.read_bytes() != data:
                    raise ValueError('Existing fixture differs from pinned source')
                original.write_bytes(data)
                if not path.exists():
                    # FLEURS sources are IEEE float WAVs; the built-in decoder
                    # converts them to standard 16-kHz PCM for deterministic mixing.
                    subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', str(original), str(path)], check=True)
                with wave.open(str(path), 'rb') as audio:
                    if audio.getnchannels() != 1 or audio.getframerate() != 16000 or audio.getsampwidth() != 2 or audio.getnframes() != row['declaredSamples']:
                        raise ValueError('Unexpected source PCM format or sample count')
                cohort.append(dict(row, localAudio=str(path), sha256=sha(path), originalAudioSHA256=sha(original)))
                if len(pure) == len(mixed) == 10:
                    break
    if len(pure) != 10 or len(mixed) != 10:
        raise ValueError('Not enough eligible recordings')
    print(config, '20 public human recordings verified', flush=True)
    return {'metadataSHA256': hashlib.sha256(metadata).hexdigest(), 'pure': pure, 'mixed': mixed}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    languages = {config: download_language(config) for config in ['de_de', 'en_us']}
    cases = []
    for config, data in languages.items():
        for index, row in enumerate(data['pure']):
            cases.append({'id': f'fleurs-{config}-{index + 1:02d}', 'language': 'de' if config == 'de_de' else 'en',
                          'audio': row['localAudio'], 'audioSHA256': row['sha256'], 'reference': row['reference'],
                          'kind': 'short', 'tags': ['public-human-read-speech', 'fleurs-test'], 'styles': ['original', 'cleaned', 'email', 'chat']})
    for index in range(10):
        de, en = languages['de_de']['mixed'][index], languages['en_us']['mixed'][index]
        pair = [de, en] if index % 2 == 0 else [en, de]
        path = OUT / f'mixed-{index + 1:02d}.wav'
        frames = []
        for row in pair:
            with wave.open(row['localAudio'], 'rb') as audio:
                frames.append(audio.readframes(audio.getnframes()))
        with wave.open(str(path), 'wb') as audio:
            audio.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
            audio.writeframes(frames[0] + b'\0' * 32000 + frames[1])
        cases.append({'id': f'fleurs-mixed-{index + 1:02d}', 'language': 'mixed', 'audio': str(path), 'audioSHA256': sha(path),
                      'reference': ' '.join(row['reference'] for row in pair), 'kind': 'short',
                      'tags': ['public-human-read-speech', 'constructed-two-speaker-language-switch', 'one-second-gap'], 'styles': ['original', 'cleaned', 'email', 'chat']})
    source = {'dataset': 'google/fleurs', 'revision': REVISION, 'license': 'cc-by-4.0', 'licenseURL': LICENSE,
              'attribution': 'FLEURS, Conneau et al. (2022), Google and collaborators', 'datasetURL': 'https://huggingface.co/datasets/google/fleurs',
              'selection': 'For each language, first ten archive-order test WAVs of 5–30 s; then ten further WAVs of 5–14 s. No model-based selection.',
              'pcmModification': 'Original IEEE-float WAVs decoded by macOS afconvert to 16-kHz mono signed 16-bit PCM; original and derived SHA256 retained.',
              'mixedModification': 'Two original PCM recordings concatenated in alternating language order with one second of silence; different speakers, not spontaneous bilingual dictation.'}
    manifest = {'source': 'public-human-fleurs', 'humanAcceptance': False, 'publicCorpus': source, 'numberAliases': {},
                'normalizationNotes': 'Strict WER lowercases and removes punctuation; no number or spelling aliases. Public read-speech reference transcripts do not prove personal dictation, microphone, paste, or semantic acceptance.', 'cases': cases}
    (OUT / 'provenance.json').write_text(json.dumps({'source': source, 'languages': languages}, ensure_ascii=False, indent=2) + '\n')
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print('30 defined public human test cases; manual/product acceptance remains false.', flush=True)


if __name__ == '__main__':
    main()
