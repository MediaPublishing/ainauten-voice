#!/usr/bin/env python3
"""NDJSON stdin/stdout adapter for local, silent English/German lip reading.

The process never opens a camera or microphone. Swift owns capture and sends
JPEG frames. Diagnostics go to stderr; stdout is reserved for the contract.
"""
from __future__ import annotations

import argparse, base64, binascii, importlib, json, os, sys, time, uuid
from dataclasses import dataclass, field
from pathlib import Path
from setup_runtime import MODEL_SHA, digest
from setup_german import MODEL_SHA as GERMAN_MODEL_SHA, VOCAB_SHA

MAX_SECONDS, MAX_FRAMES, MAX_JPEG, MAX_SESSION = 30_000, 750, 150_000, 64 * 1024 * 1024

def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()

def err(session, code, message):
    emit({"type": "error", "session": session, "code": code, "message": message})

def valid_session(value):
    try:
        return str(uuid.UUID(str(value))) == str(value).lower()
    except (ValueError, AttributeError, TypeError):
        return False

@dataclass
class Capture:
    session: str
    started_ms: int
    frames: list[tuple[int, bytes]] = field(default_factory=list)
    bytes: int = 0
    last_ts: int = -1

def verify_models(root: str, language: str) -> None:
    """Only fixed, previously reviewed checkpoints/configs may reach research loaders.

    Older research dependencies must never load arbitrary pickle or Hydra inputs.
    Re-check on every worker start, including an already installed environment.
    """
    base = Path(root) / language
    expected = ({base / "vendor" / name: sha for name, sha in MODEL_SHA.items()}
                if language == "en" else {
                    base / "checkpoint_best.pt": GERMAN_MODEL_SHA,
                    base / "tokenizer.model": VOCAB_SHA,
                    base / "vendor/models/face_landmarker.task": MODEL_SHA["models/face_landmarker.task"],
                })
    for path, sha in expected.items():
        if not path.is_file() or digest(path) != sha:
            raise RuntimeError("model_integrity_failed")

class Reader:
    def __init__(self, root: str, language: str):
        self.root, self.language = os.path.abspath(os.path.expanduser(root)), language
        self.capture: Capture | None = None
        self.reader = None
        sys.path.insert(0, os.path.join(self.root, self.language, "vendor"))

    def _load_reader(self):
        if self.reader is not None: return self.reader
        verify_models(self.root, self.language)
        if self.language != "en":
            try: self.reader = importlib.import_module("german").GermanReader(root=self.root)
            except Exception as e: raise RuntimeError("de_runtime_unavailable") from e
            return self.reader
        try:
            os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
            sys.path.insert(0, os.path.join(self.root, "en", "vendor"))
            from lipflow.vsr import LipReader
            self.reader = LipReader(device="auto", personal=False)
        except Exception as e: raise RuntimeError("en_runtime_unavailable") from e
        return self.reader

    def read_jpegs(self, frames):
        """Decode JPEGs and extract a conservative mouth ROI with MediaPipe."""
        import cv2, numpy as np
        try:
            from lipflow.face import FaceTracker, mouth_rois
            tracker = FaceTracker(os.path.join(self.root, self.language, "vendor", "models", "face_landmarker.task"))
        except Exception as e: raise RuntimeError("face_pipeline_unavailable") from e
        gray, anchors, times = [], [], []
        for ts, raw in frames:
            bgr = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
            if bgr is None: continue
            gray.append(cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)); obs = tracker.detect(bgr, ts)
            anchors.append(obs.anchors if obs else None); times.append(ts / 1000)
        tracker.close(); rois = mouth_rois(gray, anchors)
        if rois is None or len(rois) < 8: raise RuntimeError("no_face")
        idx = self.reader.resample(times, len(rois))
        return self.reader.read(rois[idx])

    def begin(self, msg):
        if self.capture is not None:
            err(msg.get("session"), "duplicate_start", "Eine Sitzung läuft bereits."); return
        session = msg.get("session")
        if not valid_session(session): err(session, "invalid_session", "Ungültige Sitzungskennung."); return
        now = int(msg.get("ts_ms", 0))
        self.capture = Capture(session, now)

    def frame(self, msg):
        c = self.capture; session = msg.get("session")
        if c is None or session != c.session: err(session, "no_session", "Keine passende Sitzung."); return
        try: ts = int(msg["ts_ms"]); raw = base64.b64decode(msg["jpeg"], validate=True)
        except (KeyError, ValueError, binascii.Error): err(session, "invalid_frame", "Ungültiger JPEG-Frame."); return
        if len(raw) > MAX_JPEG: err(session, "frame_too_large", "JPEG überschreitet 150 KB."); return
        if len(c.frames) >= MAX_FRAMES or c.bytes + len(raw) > MAX_SESSION: err(session, "session_limit", "Sitzungslimit erreicht."); return
        if ts < 0 or ts > MAX_SECONDS or ts <= c.last_ts:
            err(session, "invalid_timestamp", "Zeitstempel muss strikt steigen und innerhalb von 30 Sekunden liegen."); return
        c.last_ts = ts
        elapsed = ts - c.started_ms if c.started_ms >= 0 else ts
        if elapsed > MAX_SECONDS: err(session, "timeout", "Maximale Sitzungsdauer erreicht."); return
        c.frames.append((ts, raw)); c.bytes += len(raw)

    def finish(self, msg):
        c = self.capture; session = msg.get("session")
        if c is None or session != c.session: err(session, "no_session", "Keine passende Sitzung."); return
        self.capture = None  # clear before inference; late frames cannot attach
        if len(c.frames) < 8: err(session, "too_few_frames", "Zu wenige Frames für Lippenlesen."); return
        try:
            reader = self._load_reader()
            # Same pinned face alignment for both models; no capture devices.
            result = self.read_jpegs(c.frames)
            text = str(result[0] if isinstance(result, tuple) else result).strip()
            if not text: err(session, "no_face", "Kein verwertbares Gesicht erkannt."); return
            emit({"type": "result", "session": session, "text": text})
        except RuntimeError as e:
            code = str(e) if str(e) in {"no_face", "face_pipeline_unavailable", "en_runtime_unavailable", "de_runtime_unavailable", "model_integrity_failed"} else "inference_failed"
            err(session, code, "Kein verwertbares Gesicht erkannt. Schaue direkt in die Kamera." if code == "no_face" else "Lokale Lippenverarbeitung ist nicht verfügbar.")
        except Exception: err(session, "inference_failed", "Lokale Verarbeitung fehlgeschlagen.")

    def run(self):
        try:
            reader = self._load_reader()
            if hasattr(reader, "warmup"): reader.warmup()
            emit({"type": "ready", "language": self.language})
        except Exception:
            emit({"type": "error", "session": None, "code": "runtime_unavailable", "message": "Lokale Laufzeit oder Gewichte fehlen."})
            return
        while True:
            line = sys.stdin.readline(210_001)
            if not line: break
            if len(line) > 210_000 or not line.endswith("\n"):
                err(None, "line_limit", "Ungültige Nachricht."); return
            try: msg = json.loads(line)
            except json.JSONDecodeError: err(None, "invalid_json", "Ungültiges NDJSON."); continue
            if not isinstance(msg, dict): err(None, "invalid_json", "Ungültiges NDJSON."); continue
            op = msg.get("op")
            if op == "begin": self.begin(msg)
            elif op == "frame": self.frame(msg)
            elif op == "finish": self.finish(msg)
            elif op == "cancel": self.capture = None
            else: err(msg.get("session"), "invalid_op", "Unbekannte Operation.")

def main():
    p = argparse.ArgumentParser(); p.add_argument("--language", choices=("en", "de"), required=True); p.add_argument("--root", required=True)
    a = p.parse_args(); Reader(a.root, a.language).run()
if __name__ == "__main__": main()
