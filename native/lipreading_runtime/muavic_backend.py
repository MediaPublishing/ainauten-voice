"""Small adapter around the official MuAViC AV-HuBERT checkpoint.

The heavy fairseq/AV-HuBERT checkout is deliberately optional and private.
This module performs no model fabrication: if the pinned upstream runtime is
not installed it fails with an actionable diagnostic.
"""
from __future__ import annotations
from pathlib import Path
from typing import Any
import argparse
import sys
import importlib


class MuAViCVideoBackend:
    def __init__(self, config: Any):
        self.config = config
        try:
            import torch  # type: ignore
        except ImportError as exc:
            raise RuntimeError("MuAViC benötigt privaten PyTorch/fairseq Runtime") from exc
        self.torch = torch
        if not Path(config.checkpoint).is_file():
            raise RuntimeError(f"Checkpoint fehlt: {config.checkpoint}")
        self._model = None

    def _load(self) -> None:
        if self._model is not None:
            return
        try:
            import numpy as np
            if not hasattr(np, "float"):
                np.float = float  # type: ignore[attr-defined]
            user_dir = self.config.root / "vendor" / "av_hubert"
            sys.path.insert(0, str(user_dir / "fairseq"))
            sys.path.insert(0, str(user_dir / "avhubert"))
            from fairseq import checkpoint_utils  # type: ignore
            # The old upstream mixes relative and absolute imports. Import each
            # registration once in its original absolute namespace, instead of
            # silently accepting a partially imported/duplicate task registry.
            # This pinned research version selects absolute versus relative
            # imports from len(sys.argv), even when embedded as a library.
            # Isolate that compatibility shim to registration; retain the
            # worker's parsed arguments and leave upstream files unchanged.
            arguments = sys.argv
            try:
                sys.argv = arguments[:1]
                for name in ("hubert", "hubert_asr", "hubert_pretraining", "hubert_criterion"):
                    importlib.import_module(name)
            finally:
                sys.argv = arguments
        except ImportError as exc:
            raise RuntimeError(f"privater AV-HuBERT-Import fehlgeschlagen: {exc}") from exc
        state = checkpoint_utils.load_checkpoint_to_cpu(str(self.config.checkpoint))
        state["cfg"]["task"]["modalities"] = ["video"]
        state["cfg"]["task"]["data"] = str(self.config.root)
        state["cfg"]["task"]["label_dir"] = str(self.config.root)
        state["cfg"]["task"]["tokenizer_bpe_model"] = str(self.config.root / "tokenizer.model")
        models, cfg, task = checkpoint_utils.load_model_ensemble_and_task([str(self.config.checkpoint)], state=state)
        self._model, self._cfg, self._task = models[0], cfg, task
        self._model.eval()
        self.torch.set_num_threads(4)
        from fairseq.dataclass.configs import GenerationConfig
        self._generator = task.build_generator([self._model], GenerationConfig(beam=5, max_len_b=150))
        import sentencepiece
        self._tokenizer = sentencepiece.SentencePieceProcessor(model_file=str(self.config.root / "tokenizer.model"))

    def warmup(self) -> None:
        self._load()

    def transcribe_video(self, frames: Any, *, language: str, audio: Any = None) -> str:
        if language != "de" or audio is not None:
            raise ValueError("MuAViC DE akzeptiert ausschließlich language=de und audio=None")
        self._load()
        tensor = self.torch.as_tensor(frames).float()
        if tensor.ndim != 3:
            raise ValueError("video tensor muss T×96×96 sein")
        tensor = (tensor[:, 4:92, 4:92].div(255.0) - 0.421) / 0.165
        sample = {"id": self.torch.tensor([0]), "net_input": {
            "source": {"video": tensor.unsqueeze(0).unsqueeze(1), "audio": None},
            "padding_mask": self.torch.zeros((1, len(frames)), dtype=self.torch.bool)}}
        with self.torch.inference_mode():
            result = self._task.inference_step(self._generator, [self._model], sample)
        if not result or not result[0]: return ""
        dictionary = self._task.target_dictionary
        pieces = dictionary.string(result[0][0]["tokens"].int().cpu(), extra_symbols_to_ignore={dictionary.eos()})
        return self._tokenizer.decode_pieces(pieces.split()).strip()
