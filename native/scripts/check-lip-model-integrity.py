#!/usr/bin/env python3
"""No camera/models: enforce rejection before any third-party research import."""
from pathlib import Path
import hashlib, importlib.util, sys, tempfile
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'lipreading_runtime'))
import worker
checks = 0
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    for language in ['en', 'de']:
        try: worker.Reader(str(base), language)._load_reader()
        except RuntimeError as error: assert str(error) == 'model_integrity_failed'
        else: raise AssertionError('Missing models reached a research loader')
        checks += 1
    original = worker.MODEL_SHA
    file = base / 'en/vendor/models/model.pth'; file.parent.mkdir(parents=True)
    file.write_bytes(b'reviewed synthetic checkpoint')
    worker.MODEL_SHA = {'models/model.pth': hashlib.sha256(file.read_bytes()).hexdigest()}
    worker.verify_models(str(base), 'en'); checks += 1
    file.write_bytes(b'tampered synthetic checkpoint')
    try: worker.Reader(str(base), 'en')._load_reader()
    except RuntimeError as error: assert str(error) == 'model_integrity_failed'
    else: raise AssertionError('Tampered model reached a research loader')
    checks += 1
    worker.MODEL_SHA = original
print(f'MODEL INTEGRITY PASS: {checks} checks; no research loader, model download or device access')
