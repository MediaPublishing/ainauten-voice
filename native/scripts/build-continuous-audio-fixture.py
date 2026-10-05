#!/usr/bin/env python3
"""Compose one exactly 20-minute public PCM fixture; never run speech models.
Fixed source order and whole utterances only. References and source hashes stay
unchanged. This stress fixture cannot establish microphone or semantic acceptance.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import wave


SOURCE_IDS = ['fleurs-balanced-de-10', 'fleurs-balanced-en-10', 'fleurs-balanced-mixed-10',
              'fleurs-balanced-de-09', 'fleurs-balanced-en-05']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True, help='Existing pinned balanced FLEURS manifest.')
    parser.add_argument('--output-dir', type=Path, default=root / 'artifacts/fixtures/fleurs/continuous')
    args = parser.parse_args()
    out = args.output_dir.resolve()
    if not out.is_relative_to((root / 'artifacts').resolve()):
        parser.error('output-dir must be inside native/artifacts')
    if out.exists():
        parser.error('output-dir already exists; preserve the earlier fixture')
    original = json.loads(args.manifest.read_text())
    corpus = original.get('publicCorpus', {})
    if original.get('source') != 'public-human-fleurs' or original.get('humanAcceptance') is not False or (
        corpus.get('dataset'), corpus.get('revision'), corpus.get('license')) != (
            'google/fleurs', '70bb2e84b976b7e960aa89f1c648e09c59f894dd', 'cc-by-4.0'):
        parser.error('requires the pinned public corpus, never private recordings')
    available = {case['id']: case for case in original['cases']}
    chunks, intervals, provenance, references = [], [], [], []
    offset = 0
    for identifier in SOURCE_IDS:
        case = available.get(identifier)
        if case is None:
            parser.error('missing fixed source: ' + identifier)
        path = Path(case['audio'])
        if sha(path) != case['audioSHA256']:
            parser.error('source checksum changed: ' + identifier)
        with wave.open(str(path), 'rb') as audio:
            if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getcomptype()) != (1, 2, 16_000, 'NONE'):
                parser.error('requires unchanged mono16-bit16kHz PCM: ' + identifier)
            frames = audio.getnframes()
            pcm = audio.readframes(frames)
        if len(pcm) != frames * 2 or frames != round(case['audioSeconds'] * 16_000):
            parser.error('source frame/duration mismatch: ' + identifier)
        source_intervals = case['sourceIntervals']
        previous_end = 0
        for interval in source_intervals:
            if interval['sampleStart'] != previous_end or not interval['sampleStart'] < interval['sampleEnd'] <= frames:
                parser.error('source interval gap/overlap mismatch: ' + identifier)
            previous_end = interval['sampleEnd'] + interval['gapAfterSamples']
            intervals.append({**interval, 'sampleStart': offset + interval['sampleStart'],
                              'sampleEnd': offset + interval['sampleEnd'], 'compositeSourceID': identifier})
        if previous_end != frames or ' '.join(item['reference'] for item in source_intervals) != case['reference']:
            parser.error('source intervals/reference incomplete: ' + identifier)
        chunks.append(pcm)
        references.append(case['reference'])
        provenance.append({'id': identifier, 'audioSHA256': case['audioSHA256'], 'sourceSampleCount': frames,
                           'compositeSampleStart': offset, 'compositeSampleEnd': offset + frames,
                           'referenceSHA256': hashlib.sha256(case['reference'].encode()).hexdigest()})
        offset += frames
    if offset != 20 * 60 * 16_000:
        parser.error('fixed whole sources do not total exactly20 minutes')
    out.mkdir(parents=True)
    audio_path = out / 'fleurs-continuous-20m.wav'
    with wave.open(str(audio_path), 'wb') as audio:
        audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(16_000)
        for chunk in chunks:
            audio.writeframesraw(chunk)
    with wave.open(str(audio_path), 'rb') as audio:
        assert audio.getnframes() == offset
        assert audio.readframes(offset) == b''.join(chunks)
    fixture = {'id': 'fleurs-continuous-20m', 'language': 'mixed', 'kind': 'long',
               'audio': str(audio_path), 'audioSHA256': sha(audio_path), 'audioSeconds': 1200,
               'reference': ' '.join(references), 'sourceIntervals': intervals, 'styles': ['original'],
               'tags': ['public-human-read-speech', 'fixed-whole-source-order', 'exactly20-minute-continuity-stress',
                        'different-and-repeated-speakers', 'not-spontaneous-bilingual-or-microphone-input']}
    manifest = {**original, 'cases': [fixture], 'continuityFixture': {
        'sourceIDs': SOURCE_IDS, 'selection': 'Fixed whole300+300+300+240+60-second source order; no model-based selection.',
        'modification': 'Unchanged source PCM concatenated; no extra gaps, gain, fades, leading/trailing silence, slicing or time stretch.',
        'sourceManifestSHA256': sha(args.manifest), 'provenance': provenance,
        'acceptance': 'Prepared PCM continuity stress only; no recognition, semantic, microphone, physical hotkey or OS-delivery evidence.'}}
    manifest_path = out / 'manifest.json'
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    receipt = {'builtAt': datetime.now(timezone.utc).isoformat(), 'sourceIDs': SOURCE_IDS,
               'audioSHA256': fixture['audioSHA256'], 'manifestSHA256': sha(manifest_path),
               'samples': offset, 'audioSeconds': 1200, 'sourcePCMByteEqual': True,
               'completeSourceIntervals': len(intervals), 'referencesChanged': False, 'modelsLoaded': False,
               'scope': 'Prepared public exactly20-minute fixture. No pipeline/model/microphone/OS acceptance.'}
    (out / 'build-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt))


if __name__ == '__main__':
    main()
