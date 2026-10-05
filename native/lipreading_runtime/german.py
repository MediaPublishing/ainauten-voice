"""German silent visual-speech adapter for the internal research beta.

The adapter deliberately keeps MuAViC/AV-HuBERT out of the app package.  A
checkpoint with research dependencies and weights is installed privately by
the Beta setup. No audio input and no translation fallback are
accepted by this reader.
"""
from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
from typing import Any


class GermanLipReadingUnavailable(RuntimeError):
    """Raised when the separately installed research runtime is unavailable."""


@dataclass(frozen=True)
class GermanReaderConfig:
    root: Path
    checkpoint: Path
    sample_rate: int = 25
    roi_size: int = 96
    max_frames: int = 750
    language: str = "de"


def config_from_environment(root: str | os.PathLike[str] | None = None) -> GermanReaderConfig:
    base = Path(root or os.environ.get(
        "GERMAN_LIP_RESEARCH_ROOT",
        Path.home() / "Library/Application Support/Voice Wispr/LipReading/de",
    )).expanduser()
    # The shared worker passes the LipReading parent; keep language data
    # isolated even when it does not know the per-language subdirectory.
    if base.name != "de" and not (base / "checkpoint_best.pt").exists():
        base = base / "de"
    checkpoint = Path(os.environ.get("GERMAN_LIP_CHECKPOINT", base / "checkpoint_best.pt"))
    return GermanReaderConfig(root=base, checkpoint=checkpoint)


class GermanReader:
    """MuAViC video-only reader.

    ``read`` accepts a T×96×96 numpy-like array (grayscale or RGB).  The
    optional backend is imported lazily, so the native app can report a clear
    unavailable state without importing fairseq or opening a camera.
    """

    def __init__(self, root: str | os.PathLike[str] | None = None, *, backend: Any = None):
        self.config = config_from_environment(root)
        self._backend = backend
        self._ready = backend is not None
        if backend is None and self.config.checkpoint.is_file():
            try:
                try:
                    from .muavic_backend import MuAViCVideoBackend  # type: ignore
                except ImportError:
                    from muavic_backend import MuAViCVideoBackend  # type: ignore
                self._backend = MuAViCVideoBackend(self.config)
                self._backend.warmup()
                self._ready = True
            except (ImportError, OSError, RuntimeError, AssertionError) as exc:
                self._load_error = str(exc)
        elif backend is None:
            self._load_error = f"deutsches MuAViC-Gewicht fehlt: {self.config.checkpoint}"

    @property
    def ready(self) -> bool:
        return self._ready

    def warmup(self) -> None:
        if not self._ready: raise GermanLipReadingUnavailable(getattr(self, "_load_error", "Deutsches Modell fehlt"))
        self._backend.warmup()

    @staticmethod
    def resample(timestamps: list[float], n_frames: int) -> list[int]:
        if not n_frames: return []
        import numpy as np
        times = np.asarray(timestamps, dtype=np.float64)
        ticks = np.arange(times[0], times[-1] + .001, .04)
        indices = np.searchsorted(times, ticks)
        return np.clip(indices, 0, n_frames - 1).tolist()

    def read(self, rois96numpy: Any) -> str:
        if not self._ready or self._backend is None:
            raise GermanLipReadingUnavailable(getattr(self, "_load_error", "deutsches Backend nicht geladen"))
        shape = getattr(rois96numpy, "shape", ())
        if len(shape) != 3 or shape[1:] != (96, 96):
            raise ValueError("read erwartet ROIs mit Form T×96×96")
        if shape[0] < 2:
            raise ValueError("zu kurze Lippenaufnahme")
        if shape[0] > self.config.max_frames:
            raise ValueError("Lippenaufnahme überschreitet 30-Sekunden-Grenze")
        # The backend receives video only.  Passing an audio key is forbidden.
        return str(self._backend.transcribe_video(rois96numpy, language="de", audio=None)).strip()


PROTOCOL = {
    "language": "de",
    "modality": "video",
    "audio": None,
    "input": "T×96×96 numpy ROI frames at 25 fps",
    "output": "UTF-8 German text",
    "translation": False,
    "max_duration_seconds": 30,
    "model_license": "CC-BY-NC-4.0; research-only weights outside public app",
}
