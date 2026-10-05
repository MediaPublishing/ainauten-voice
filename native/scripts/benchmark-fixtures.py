#!/usr/bin/env python3
"""Generate labelled synthetic fixtures using installed Apple voices, without a provider.

Source text is reviewable; audio/manifests/results belong in ignored artifacts.
These fixtures check reproducibility and regressions, not human dictation acceptance.
"""
import argparse
import hashlib
import json
import platform
import os
import re
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
    with safe_output(destination) as stream, wave.open(stream, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(16000)
        output.writeframes(unit * copies)
    text = " ".join(segment["text"] for segment in segments)
    return len(unit) * copies / 32000, " ".join([text] * copies)


def safe_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", value):
        raise ValueError("Fixture ID must be a safe filename, max 80 characters")
    return value


def safe_output(destination):
    # Never follow an existing file or symlink; all generated files are new.
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    return os.fdopen(fd, "wb")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--definitions", type=Path, default=ROOT / "docs/fixtures/synthetic-cases.json")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/fixtures")
    args = parser.parse_args()
    definitions = json.loads(args.definitions.read_text())
    ids = [safe_id(case["id"]) for case in definitions["cases"]]
    if len(set(ids)) != len(ids): raise ValueError("Duplicate fixture IDs")
    if args.output.is_symlink(): raise ValueError("Output directory cannot be a symlink")
    args.output.mkdir(parents=True, exist_ok=True)
    args.output = args.output.resolve()
    for identifier in ids:
        destination = args.output / (identifier + ".wav")
        if destination.exists() or destination.is_symlink(): raise ValueError("Fixture output already exists")
    scratch = args.output / "voice-parts"
    if scratch.exists() or scratch.is_symlink(): raise ValueError("Scratch output already exists; use a new output directory")
    scratch.mkdir(mode=0o700)
    manifest = {"source": "synthetic-apple-say", "humanAcceptance": False,
                "generation": {"macOS": platform.mac_ver()[0], "voices": VOICES, "wordsPerMinute": 165,
                               "sampleRate": 16000, "channels": 1, "bitsPerSample": 16, "pauseSeconds": 0.25,
                               "definitionsSHA256": hashlib.sha256(args.definitions.read_bytes()).hexdigest()},
                "normalizationNotes": "Strict WER lowercases and removes punctuation. Canonical WER additionally maps only explicitly defined spoken number aliases. Neither metric validates facts or human audio quality.",
                "numberAliases": definitions["numberAliases"], "cases": []}
    for case in definitions["cases"]:
        destination = args.output / (safe_id(case["id"]) + ".wav")
        if destination.resolve().parent != args.output: raise ValueError("Output escapes fixture directory")
        seconds, reference = synthesize(case["segments"], destination, scratch, case.get("targetSeconds", 0))
        manifest["cases"].append({"id": case["id"], "language": case["language"],
                                  "audio": str(destination.resolve()), "reference": reference,
                                  "audioSHA256": hashlib.sha256(destination.read_bytes()).hexdigest(),
                                  "audioSeconds": seconds, "kind": case.get("kind", "short"),
                                  "tags": case["tags"], "styles": case.get("styles", ["original", "cleaned"])})
        print(f"{case['id']}: {seconds:.2f} s", flush=True)
    path = args.output / "manifest.json"
    with safe_output(path) as stream: stream.write((json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
    print(path.resolve())


if __name__ == "__main__":
    main()
