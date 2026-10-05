#!/usr/bin/env python3
"""Pinned, resumable private research-runtime installer; never opens a device."""
from __future__ import annotations
import argparse, hashlib, json, os, shutil, subprocess, sys, tarfile, time
from pathlib import Path
from urllib.request import Request, urlopen

PIN = "56d22f8522da62f0e76c33e1e94b9da0183954a6"
DEPS = ["numpy==1.26.4", "opencv-python-headless==4.10.0.84", "mediapipe==0.10.21", "torch==2.4.1"]
MODELS = {
 "models/vsr/model.json":"https://huggingface.co/Amanvir/LRS3_V_WER19.1/resolve/main/model.json",
 "models/vsr/model.pth":"https://huggingface.co/Amanvir/LRS3_V_WER19.1/resolve/main/model.pth",
 "models/lm/model.json":"https://huggingface.co/Amanvir/lm_en_subword/resolve/main/model.json",
 "models/lm/model.pth":"https://huggingface.co/Amanvir/lm_en_subword/resolve/main/model.pth",
 "models/lm/unigram5000.model":"https://github.com/mpc001/auto_avsr/raw/main/spm/unigram/unigram5000.model",
 "models/face_landmarker.task":"https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task",
}
MODEL_SHA = {"models/vsr/model.json":"e062e8c58579f54cb51087e639e674781189809905db4162efe0fe1325356d4f", "models/vsr/model.pth":"e740cef369abeabd0ba2c18e37a0661342e1d94d432d6caa77755a11821d8fe3", "models/lm/model.json":"6e2d2004e4066af3e5a3d74c53b0d648fd53904da07178671d1cbe28a206d548", "models/lm/model.pth":"c75aa39020dec98f432c8689b145d3f4cc407d4daa90a0c64202386c34f83c18", "models/lm/unigram5000.model":"2c1d648ccf5fdce6612ecbea2ffbd1cab5aabc90458781186175c3911c4bdb1e", "models/face_landmarker.task":"64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff"}
SOURCE_URL = "https://codeload.github.com/amywork777/lipflow/tar.gz/56d22f8522da62f0e76c33e1e94b9da0183954a"
SOURCE_SHA = "92ba9653a506e67e61ae24ebe89c35631c8e44a0bc7ed526f9f670f24fa18f6c"

def out(state, **kw):
    print(json.dumps({"state": state, **kw}, separators=(",", ":")), flush=True)

def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""): h.update(block)
    return h.hexdigest()

def checked_download(url, target, expected):
    target = Path(target); target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and digest(target) == expected: return
    if target.exists(): target.rename(target.with_name(target.name + ".invalid-" + str(time.time_ns())))
    part = target.with_name(target.name + ".part")
    if part.exists() and digest(part) == expected:
        part.replace(target); return
    for attempt in range(3):
        try:
            offset = part.stat().st_size if part.exists() else 0
            headers = {"User-Agent": "AInauten-Voice-research-beta"}
            if offset: headers["Range"] = "bytes=" + str(offset) + "-"
            with urlopen(Request(url, headers=headers), timeout=60) as response:
                resumed = offset and response.status == 206
                current = offset if resumed else 0
                total = current + int(response.headers.get("Content-Length", "0"))
                notified = 0.0
                with part.open("ab" if resumed else "wb") as destination:
                    while block := response.read(1024 * 1024):
                        destination.write(block); current += len(block)
                        if time.monotonic() - notified >= .5:
                            out("model_download", current=current, total=total)
                            notified = time.monotonic()
            if digest(part) != expected:
                part.rename(part.with_name(part.name + ".invalid-" + str(time.time_ns())))
                raise RuntimeError("Downloaded model checksum differs from pinned manifest")
            part.replace(target); return
        except Exception:
            if attempt == 2: raise
            time.sleep(.5 * (attempt + 1))

def unpack_verified(archive, destination):
    destination = Path(destination); destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as source:
        members = []
        for item in source.getmembers():
            path = Path(item.name)
            if path.is_absolute() or ".." in path.parts:
                raise RuntimeError("Unsafe path in pinned source archive")
            # Upstream research examples include links. They are unnecessary
            # for inference and are never followed or extracted.
            if item.isfile() or item.isdir(): members.append(item)
        source.extractall(destination, members=members)
    return destination / members[0].name.split("/")[0]

def install_face_source(vendor, full_english=False):
    vendor = Path(vendor); vendor.mkdir(parents=True, exist_ok=True)
    archive = vendor / "lipflow-source.tar.gz"
    checked_download(SOURCE_URL, archive, SOURCE_SHA)
    source = unpack_verified(archive, vendor / ("source-" + PIN))
    face = vendor / "lipflow"; face.mkdir(exist_ok=True)
    for name in ("__init__.py", "face.py", "mean_face.npy") + (("vsr.py", "paths.py", "unigram5000_units.txt") if full_english else ()):
        shutil.copy2(source / "lipflow" / name, face / name)
    if full_english: shutil.copytree(source / "espnet", vendor / "espnet", dirs_exist_ok=True)
    for name in ("LICENSE", "NOTICE"):
        if (source / name).exists(): shutil.copy2(source / name, vendor / ("Lipflow-" + name))
    checked_download(MODELS["models/face_landmarker.task"], vendor / "models/face_landmarker.task", MODEL_SHA["models/face_landmarker.task"])
    out("source_pinned", revision=PIN)

def install_environment(uv, base, resources, python="3.11"):
    base = Path(base); resources = Path(resources); venv = base / ".venv"
    if not (venv / "bin/python").exists():
        subprocess.run([uv, "venv", "--python", python, str(venv)], check=True, stdout=sys.stderr)
    requirements = base / "requirements.lock.txt"
    subprocess.run([uv, "export", "--frozen", "--no-dev", "--no-emit-project", "--directory", str(resources), "--output-file", str(requirements)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([uv, "pip", "install", "--require-hashes", "--python", str(venv / "bin/python"), "-r", str(requirements)], check=True, stdout=sys.stderr)
    return venv

def main():
    parser=argparse.ArgumentParser(); parser.add_argument("--root", required=True); parser.add_argument("--language", choices=("en",), required=True)
    parser.add_argument("--uv", default="uv"); parser.add_argument("--models", action="store_true"); args=parser.parse_args()
    base=Path(args.root).expanduser().resolve() / "en"; base.mkdir(parents=True, exist_ok=True)
    out("start"); install_environment(args.uv, base, Path(__file__).parent)
    vendor=base / "vendor"; install_face_source(vendor, full_english=True)
    if args.models:
        for name, url in MODELS.items():
            checked_download(url, vendor / name, MODEL_SHA[name]); out("model_verified", file=name)
    out("complete", language="en")
if __name__ == "__main__": main()
