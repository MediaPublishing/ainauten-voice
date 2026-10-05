#!/usr/bin/env python3
"""Generate labelled synthetic fixtures using installed Apple voices, without a provider.

Source text is reviewable; audio/manifests/results belong in ignored artifacts.
These fixtures check reproducibility and regressions, not human dictation acceptance.
"""
import argparse
import hashlib
import json
import platform
import subprocess
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VOICES = {"de": "Anna (German (Germany))", "en": "Daniel (English (UK))"}


def synthesize(segments, destination, scratch, target_seconds=0):
    chunks = []
    for index, segment in enumerate(segments):
        audio = scratch / f"part-{index}.wav"
        subprocess.run(["/usr/bin/say", "-v", VOICES[segment["language"]], "-r", "165",
                        "--file-format=WAVE", "--data-format=LEI16@16000", "-o", str(audio),
                        segment["text"]], check=True, stdout=subprocess.DEVNULL)
        with wave.open(str(audio), "rb") as source:
            if (source.getnchannels(), source.getsampwidth(), source.getframerate()) != (1, 2, 16000):
                raise RuntimeError("Voice generated an unexpected audio format")
            chunks.append(source.readframes(source.getnframes()) + bytes(16000 * 2 // 4))
    unit = b"".join(chunks)
    copies = max(1, int(target_seconds * 32000 / len(unit)) + 1) if target_seconds else 1
    with wave.open(str(destination), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(16000)
        output.writeframes(unit * copies)
    text = " ".join(segment["text"] for segment in segments)
    return len(unit) * copies / 32000, " ".join([text] * copies)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--definitions", type=Path, default=ROOT / "docs/fixtures/synthetic-cases.json")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/fixtures")
    args = parser.parse_args()
    definitions = json.loads(args.definitions.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    scratch = args.output / "voice-parts"
    scratch.mkdir(exist_ok=True)
    manifest = {"source": "synthetic-apple-say", "humanAcceptance": False,
                "generation": {"macOS": platform.mac_ver()[0], "voices": VOICES, "wordsPerMinute": 165,
                               "sampleRate": 16000, "channels": 1, "bitsPerSample": 16, "pauseSeconds": 0.25,
                               "definitionsSHA256": hashlib.sha256(args.definitions.read_bytes()).hexdigest()},
                "normalizationNotes": "Strict WER lowercases and removes punctuation. Canonical WER additionally maps only explicitly defined spoken number aliases. Neither metric validates facts or human audio quality.",
                "numberAliases": definitions["numberAliases"], "cases": []}
    for case in definitions["cases"]:
        destination = args.output / f"{case['id']}.wav"
        seconds, reference = synthesize(case["segments"], destination, scratch, case.get("targetSeconds", 0))
        manifest["cases"].append({"id": case["id"], "language": case["language"],
                                  "audio": str(destination.resolve()), "reference": reference,
                                  "audioSHA256": hashlib.sha256(destination.read_bytes()).hexdigest(),
                                  "audioSeconds": seconds, "kind": case.get("kind", "short"),
                                  "tags": case["tags"], "styles": case.get("styles", ["original", "cleaned"])})
        print(f"{case['id']}: {seconds:.2f} s", flush=True)
    path = args.output / "manifest.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(path.resolve())


if __name__ == "__main__":
    main()
