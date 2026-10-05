# LocalWhisper

LocalWhisper is a local macOS dictation app. It records speech from the microphone, transcribes it with `faster-whisper`, optionally refines the text through a local Ollama model, stores the dictation history in SQLite, and inserts the final text into the active app.

The project is intentionally local-first. Runtime data such as dictation history, raw transcript text, refined text, temporary audio, logs, model files, and packaged builds must not be committed.

## Architecture

LocalWhisper has three main parts:

- `daemon.py`: records audio, listens for the global hotkey, runs Whisper transcription, calls local Ollama refinement when enabled, injects text via clipboard/AppleScript, and writes history.
- `app.py`: runs a Flask server on `127.0.0.1:4950`, serves the web dashboard, and exposes local API endpoints for status, history, settings, and record toggling.
- `LocalWhisper.swift`: native macOS status bar app and SwiftUI interface. In app-bundle mode it launches the bundled Python backend; in development mode it runs `.venv/bin/python3 main.py` when available.

Supporting files:

- `database.py`: SQLite schema and settings/history helpers. Runtime DB path is `local_whisper.db` in dev and `~/Library/Application Support/LocalWhisper/local_whisper.db` inside the packaged app.
- `web/`: Flask-served dashboard for dictation history, settings, and manual record toggle.
- `start.sh` and `LocalWhisper.command`: development launcher.
- `build_app.py`: macOS packaging script using PyInstaller, `swiftc`, and `hdiutil`.
- `Info.plist`, `AppIcon.icns`, `LocalWhisper*.spec`: app bundle and PyInstaller configuration.

## Dependencies

Runtime dependencies are currently declared in `start.sh`, not in a lockfile:

- Python 3 with `venv`
- `numpy`
- `sounddevice`
- `soundfile`
- `pynput`
- `faster-whisper`
- `flask`
- `pyautogui`
- `pyobjc-core`
- `pyobjc-framework-cocoa`
- `pyobjc-framework-quartz`
- Optional: `uv` for faster dependency installation
- Optional: Ollama on `127.0.0.1:11434` for local text refinement

Build dependencies:

- PyInstaller
- `rumps`
- Xcode command line tools (`xcrun`, `swiftc`)
- `hdiutil`

## Run Locally

Development launcher:

```bash
./start.sh
```

Or from Finder:

```bash
open LocalWhisper.command
```

`start.sh` creates `.venv/` if missing, installs dependencies, starts `daemon.py` and `app.py`, writes runtime logs, and opens:

```text
http://127.0.0.1:4950
```

The default dictation shortcut is `Option+Space`.

Important: `start.sh` installs dependencies if they are missing, so it is network-capable. For offline verification, do not run it unless dependencies are already present and network access is explicitly allowed.

## Build

Package the native macOS app and DMG:

```bash
python3 build_app.py
```

The build script recreates generated build output under:

```text
build/
dist/
dmg_temp/
```

Do not run the build script during a no-deletion/no-move baseline pass. It deliberately removes and rebuilds generated folders.

## Local Data And Privacy

Never commit:

- `local_whisper.db` or any `*.db` / `*.sqlite*`
- `daemon.log`, `app.log`, or other `*.log`
- temporary audio such as `*.wav`, `*.mp3`, `*.m4a`
- model weights such as `*.gguf`, `*.bin`, `*.mlmodel*`, or `models/`
- `.venv/`, `build/`, `dist/`, `__pycache__/`, `.DS_Store`

`database.py` stores dictation history with `raw_text` and `refined_text`. Treat runtime databases and logs as potentially personal transcript data.

Current privacy caveat: `web/index.html` references Google Fonts and FontAwesome CDN assets. The core transcription path is local, but the web dashboard can make external asset requests if loaded with network access. Vendor or remove these assets in a future privacy-hardening pass if strict offline UI behavior is required.

## Offline Checks

Use lightweight checks that do not run real audio or call external services:

```bash
bash -n start.sh
bash -n LocalWhisper.command
plutil -lint Info.plist
node --check web/app.js
xcrun swiftc -parse-as-library -typecheck LocalWhisper.swift
```

For Python syntax checks without writing bytecode into the repo, compile to `/tmp`:

```bash
python3 - <<'PY'
import py_compile
from pathlib import Path

for path in ["main.py", "app.py", "daemon.py", "database.py", "build_app.py"]:
    py_compile.compile(path, cfile=f"/tmp/localwhisper-{Path(path).stem}.pyc", doraise=True)
print("python syntax ok")
PY
```

These checks validate syntax/type parsing only. They do not verify microphone permissions, global hotkeys, AppleScript paste permissions, Whisper model availability, Ollama model availability, or packaged-app runtime behavior.
