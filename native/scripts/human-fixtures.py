#!/usr/bin/env python3
"""Download public, checksum-pinned FLEURS recordings for local ASR evaluation.
No credentials, dataset code execution, private recordings, or audio upload.
Selection is defined before recognition, independently of model results.
"""
import argparse
import hashlib
import itertools
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


def cached_sources(directory):
    provenance = json.loads((directory / 'provenance.json').read_text())
    source = provenance['source']
    if (source['dataset'], source['revision'], source['license']) != ('google/fleurs', REVISION, 'cc-by-4.0'):
        raise ValueError('Balanced fixtures require the existing pinned public FLEURS corpus')
    pools = {}
    for config in ['de_de', 'en_us']:
        rows = provenance['languages'][config]['pure'] + provenance['languages'][config]['mixed']
        if len(rows) != 20 or len({row['filename'] for row in rows}) != 20:
            raise ValueError('Expected twenty distinct previously selected sources per language')
        for row in rows:
            path = pathlib.Path(row['localAudio'])
            original = path.with_suffix('.source.wav')
            if sha(path) != row['sha256'] or sha(original) != row['originalAudioSHA256']:
                raise ValueError('Cached source checksum changed')
            with wave.open(str(path), 'rb') as audio:
                if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getnframes()) != (1, 2, 16000, row['declaredSamples']):
                    raise ValueError('Cached PCM dimensions changed')
        pools[config] = rows
    return source, pools


def whole_sentences_for_duration(pool, seconds, rotation):
    """Choose on duration/order only; fill exact length with 250–750ms interior gaps."""
    target = seconds * 16000
    ordered = pool[rotation:] + pool[:rotation]
    # Fixed ascending combinations make the 60s selection reproducible, without
    # ASR output, trimming words or adding a latency-improving tail of silence.
    if seconds == 60:
        for count in range(3, 11):
            for indices in itertools.combinations(range(len(ordered)), count):
                rows = [ordered[index] for index in indices]
                if len({row['config'] for row in pool}) > 1 and len({row['config'] for row in rows}) < 2:
                    continue
                gap_samples = target - sum(row['declaredSamples'] for row in rows)
                if (count - 1) * 4000 <= gap_samples <= (count - 1) * 12000:
                    return rows
        raise ValueError('No full-sentence 60s composition within the fixed gap bounds')
    rows, spoken, cursor = [], 0, 0
    while True:
        fitting = next((offset for offset in range(len(ordered))
                        if spoken + ordered[(cursor + offset) % len(ordered)]['declaredSamples'] + 4000 * len(rows) <= target), None)
        if fitting is None:
            break
        index = (cursor + fitting) % len(ordered)
        row = ordered[index]
        rows.append(row); spoken += row['declaredSamples']; cursor = index + 1
    gaps = len(rows) - 1
    if gaps < 1 or not gaps * 4000 <= target - spoken <= gaps * 12000:
        raise ValueError('Long composition needs a gap outside the declared bounds')
    return rows


def compose_pcm(path, rows, seconds=None, fixed_gap_samples=None):
    spoken = sum(row['declaredSamples'] for row in rows)
    count = len(rows) - 1
    total_gaps = seconds * 16000 - spoken if seconds is not None else count * (fixed_gap_samples or 0)
    quotient, remainder = divmod(total_gaps, count) if count else (0, 0)
    gap_lengths = [quotient + (index < remainder) for index in range(count)]
    if seconds is not None and not all(4000 <= gap <= 12000 for gap in gap_lengths):
        raise ValueError('Composition gap must be 250–750ms')
    chunks, intervals, position = [], [], 0
    for index, row in enumerate(rows):
        with wave.open(row['localAudio'], 'rb') as audio:
            pcm = audio.readframes(audio.getnframes())
        chunks.append(pcm)
        end = position + row['declaredSamples']
        gap = gap_lengths[index] if index < count else 0
        intervals.append({'config': row['config'], 'filename': row['filename'], 'recordID': row['recordID'],
                          'audioSHA256': row['sha256'], 'originalAudioSHA256': row['originalAudioSHA256'],
                          'sampleStart': position, 'sampleEnd': end, 'gapAfterSamples': gap, 'reference': row['reference']})
        if gap:
            chunks.append(b'\0' * (gap * 2))
        position = end + gap
    if seconds is not None and position != seconds * 16000:
        raise ValueError('Exact composite duration mismatch')
    if path.exists():
        with wave.open(str(path), 'rb') as audio:
            if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getnframes()) != (1, 2, 16000, position) or audio.readframes(position) != b''.join(chunks):
                raise ValueError('Refusing to replace a different existing fixture')
    else:
        with wave.open(str(path), 'wb') as audio:
            audio.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
            audio.writeframes(b''.join(chunks))
    return intervals, position / 16000


def balanced(directory, output):
    source, pools = cached_sources(directory)
    output.mkdir(parents=True, exist_ok=True)
    configurations = {'de': pools['de_de'], 'en': pools['en_us'],
                      'mixed': [row for pair in zip(pools['de_de'], pools['en_us']) for row in pair]}
    cases = []
    for language, pool in configurations.items():
        selections = []
        for index in range(4):
            if language == 'mixed':
                rows = [pools['de_de'][10 + index], pools['en_us'][10 + index]]
                if index % 2:
                    rows.reverse()
            else:
                rows = [pool[index]]
            selections.append(('short', rows, None, 16000))
        for rotation in [4, 7, 10]:
            selections.append(('medium', whole_sentences_for_duration(pool, 60, rotation), 60, None))
        for index, seconds in enumerate([180, 240, 300]):
            selections.append(('long', whole_sentences_for_duration(pool, seconds, 3 + index * 5), seconds, None))
        for index, (kind, rows, seconds, fixed_gap) in enumerate(selections, 1):
            identity = f'fleurs-balanced-{language}-{index:02d}'
            path = output / f'{identity}.wav'
            intervals, duration = compose_pcm(path, rows, seconds, fixed_gap)
            if kind == 'short' and not 5 <= duration <= 30:
                raise ValueError('Short composite outside the approved duration range')
            cases.append({'id': identity, 'language': language, 'kind': kind, 'audio': str(path.resolve()),
                          'audioSHA256': sha(path), 'reference': ' '.join(row['reference'] for row in rows),
                          'audioSeconds': duration, 'sourceIntervals': intervals,
                          'tags': ['public-human-read-speech', 'fixed-selection-before-asr', 'no-added-leading-or-trailing-silence'] +
                                  (['constructed-multiple-speakers', 'not-spontaneous-dictation'] if len(rows) > 1 else ['unchanged-source-utterance']),
                          'styles': ['original', 'cleaned']})
    source = dict(source, balancedSelection='Per language: first four short cases; three exact 60s compositions; 180/240/300s whole-sentence compositions. Duration and fixed source order only; no model-based selection.',
                  composition='Complete original PCM utterances in order, gaps of 250–750ms between long/medium sources; old one-second gap for short bilingual pairs. No added leading/trailing silence, resampling, time stretch, fades or gain. Different/repeated speakers and statements: stress fixtures, not spontaneous long dictation.')
    manifest = {'source': 'public-human-fleurs', 'humanAcceptance': False, 'publicCorpus': source, 'numberAliases': {},
                'normalizationNotes': 'Strict WER only lowercases and removes punctuation; no number/spelling aliases. Entire reference utterances retained. Composite public read-speech is not personal dictation, microphone, hotkey, OS delivery or semantic acceptance.', 'cases': cases}
    encoded = json.dumps(manifest, ensure_ascii=False, indent=2) + '\n'
    path = output / 'manifest.json'
    if path.exists() and path.read_text() != encoded:
        raise ValueError('Refusing to replace a different existing manifest')
    path.write_text(encoded)
    print('30 balanced public cases: 10 per language, 12 short / 9 exact 60s / 9 long. Human/product acceptance remains false.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--balanced', action='store_true', help='Compose balanced duration cases from previously verified public sources; no download')
    parser.add_argument('--source-directory', type=pathlib.Path, default=OUT, help='Existing pinned source cache for --balanced')
    parser.add_argument('--output', type=pathlib.Path, help='Balanced output directory; existing differing files are never overwritten')
    args = parser.parse_args()
    if args.balanced:
        balanced(args.source_directory, args.output or OUT / 'balanced')
        return
    if args.output or args.source_directory != OUT:
        parser.error('--output/--source-directory require --balanced')
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
