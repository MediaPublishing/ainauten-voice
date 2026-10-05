#!/usr/bin/env python3
import os
import sys
import time
import json
import queue
import threading
import subprocess
import urllib.request
from pathlib import Path

# Add project root to path
PROJECT_ROOT = Path(__file__).resolve().parent
sys.path.append(str(PROJECT_ROOT))

import database

# Check if libraries are imported successfully, otherwise alert start script
try:
    import numpy as np
    import sounddevice as sd
    import soundfile as sf
    from pynput import keyboard
    from faster_whisper import WhisperModel
except ImportError as e:
    print(f"Error importing dependencies: {e}. Please run start.sh first.", flush=True)
    sys.exit(1)

# Status definitions
STATUS_IDLE = "bereit"
STATUS_RECORDING = "nimmt auf..."
STATUS_TRANSCRIBING = "transkribiert..."
STATUS_REFINING = "verfeinert (KI)..."
STATUS_PASTING = "fügt ein..."

class LocalWhisperDaemon(threading.Thread):
    def __init__(self):
        super().__init__()
        self.daemon = True  # Terminate thread when main program exits
        self.recording = False
        self.audio_queue = queue.Queue()
        self.stream = None
        self.temp_audio_path = PROJECT_ROOT / "temp_recording.wav"
        
        # Whisper model cache
        self.current_model_name = None
        self.whisper_model = None
        self.hotkeys = None
        
        # Thread locks
        self.lock = threading.Lock()
        
        # Set daemon status to idle initially
        database.set_setting("daemon_status", STATUS_IDLE)
        database.set_setting("daemon_recording", "false")

    def get_whisper_model(self, model_name):
        with self.lock:
            if self.current_model_name != model_name or self.whisper_model is None:
                print(f"[Daemon] Lade Whisper-Modell: {model_name}...", flush=True)
                database.set_setting("daemon_status", f"Lade Whisper {model_name}...")
                
                # CTranslate2 on CPU is optimized and very fast on macOS
                self.whisper_model = WhisperModel(model_name, device="cpu", compute_type="int8")
                self.current_model_name = model_name
                print(f"[Daemon] Whisper-Modell {model_name} geladen.", flush=True)
            return self.whisper_model

    def audio_callback(self, indata, frames, time_info, status):
        if status:
            print(f"[Audio] Status: {status}", flush=True)
        self.audio_queue.put(indata.copy())

    def start_recording(self):
        if self.recording:
            return
        
        print("[Daemon] Starte Aufnahme...", flush=True)
        self.recording = True
        self.audio_queue = queue.Queue()
        
        # Delete temp file if exists
        if self.temp_audio_path.exists():
            try:
                self.temp_audio_path.unlink()
            except Exception:
                pass
                
        database.set_setting("daemon_status", STATUS_RECORDING)
        database.set_setting("daemon_recording", "true")

        self.stream = sd.InputStream(
            samplerate=16000, 
            channels=1, 
            callback=self.audio_callback, 
            dtype='int16'
        )
        self.stream.start()

    def stop_recording(self):
        if not self.recording:
            return None
            
        print("[Daemon] Beende Aufnahme...", flush=True)
        self.recording = False
        
        if self.stream:
            self.stream.stop()
            self.stream.close()
            self.stream = None
            
        database.set_setting("daemon_recording", "false")
        
        # Collect audio chunks
        chunks = []
        while not self.audio_queue.empty():
            chunks.append(self.audio_queue.get())
            
        if chunks:
            full_audio = np.concatenate(chunks, axis=0)
            sf.write(str(self.temp_audio_path), full_audio, 16000)
            duration = len(full_audio) / 16000.0
            print(f"[Daemon] Aufnahme gespeichert. Dauer: {duration:.2f}s", flush=True)
            return duration
        return 0

    def get_active_app(self):
        applescript = """
        tell application "System Events"
            set activeApp to name of first application process whose frontmost is true
            return activeApp
        end tell
        """
        try:
            result = subprocess.check_output(['osascript', '-e', applescript], text=True)
            return result.strip()
        except Exception:
            return "Unbekannte App"

    def inject_text(self, text):
        if not text:
            return
            
        print(f"[Daemon] Füge Text ein: {text[:60]}...", flush=True)
        database.set_setting("daemon_status", STATUS_PASTING)
        
        # macOS Clipboard integration
        # 1. Get original clipboard
        try:
            orig_clipboard = subprocess.check_output(['pbpaste'], text=True)
        except Exception:
            orig_clipboard = ""
            
        # 2. Write new text to clipboard
        pbcopy_proc = subprocess.Popen(['pbcopy'], stdin=subprocess.PIPE, text=True)
        pbcopy_proc.communicate(input=text)
        
        # 3. Simulate Cmd+V keystroke using AppleScript
        applescript = """
        tell application "System Events"
            keystroke "v" using {command down}
        end tell
        """
        subprocess.run(['osascript', '-e', applescript])
        
        # 4. Wait a short moment and restore original clipboard
        time.sleep(0.35)
        pbcopy_proc = subprocess.Popen(['pbcopy'], stdin=subprocess.PIPE, text=True)
        pbcopy_proc.communicate(input=orig_clipboard)

    def refine_text_ollama(self, text, settings):
        if settings.get("ollama_enabled") != "true":
            return text
            
        model = settings.get("ollama_model", "gemma4-obliterated:latest")
        system_prompt = settings.get("system_prompt", "")
        
        print(f"[Daemon] Veredele Text mit Ollama ({model})...", flush=True)
        database.set_setting("daemon_status", STATUS_REFINING)
        
        url = "http://127.0.0.1:11434/api/generate"
        payload = {
            "model": model,
            "prompt": text,
            "system": system_prompt,
            "stream": False
        }
        
        req_data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=req_data,
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        
        try:
            with urllib.request.urlopen(req, timeout=12.0) as response:
                res = json.loads(response.read().decode("utf-8"))
                refined = res.get("response", "").strip()
                if refined:
                    print("[Daemon] Text veredelt.", flush=True)
                    return refined
        except Exception as e:
            print(f"[Daemon] Ollama-Veredelung fehlgeschlagen: {e}. Verwende Roh-Transkript.", flush=True)
            
        return text

    def process_dictation(self, duration):
        if duration < 0.4:
            print("[Daemon] Diktat zu kurz. Überspringe.", flush=True)
            database.set_setting("daemon_status", STATUS_IDLE)
            return

        def worker():
            try:
                active_app = self.get_active_app()
                settings = database.get_settings()
                
                # 1. Transkribieren
                print("[Daemon] Starte Transkription...", flush=True)
                database.set_setting("daemon_status", STATUS_TRANSCRIBING)
                
                model_name = settings.get("whisper_model", "base")
                whisper = self.get_whisper_model(model_name)
                
                custom_vocab = settings.get("custom_vocabulary", "")
                language_setting = settings.get("whisper_language", "auto").strip().lower()
                transcribe_language = None if language_setting in ("", "auto", "detect") else language_setting
                
                # Transkription ausführen
                segments, info = whisper.transcribe(
                    str(self.temp_audio_path),
                    language=transcribe_language,
                    beam_size=5,
                    initial_prompt=custom_vocab if custom_vocab else None
                )
                
                raw_text = "".join([segment.text for segment in segments]).strip()
                print(f"[Daemon] Roh-Transkription: '{raw_text}'", flush=True)
                
                if not raw_text:
                    print("[Daemon] Keine Sprache erkannt.", flush=True)
                    database.set_setting("daemon_status", STATUS_IDLE)
                    return
                
                # 2. Veredeln mit Ollama
                import urllib.request
                refined_text = self.refine_text_ollama(raw_text, settings)
                
                # 3. Einfügen
                self.inject_text(refined_text)
                
                # 4. In Verlauf speichern
                num_words = len(refined_text.split())
                database.add_history_entry(
                    app=active_app,
                    duration=round(duration, 2),
                    num_words=num_words,
                    raw_text=raw_text,
                    refined_text=refined_text
                )
                
                # Temporäre Datei löschen
                try:
                    self.temp_audio_path.unlink()
                except Exception:
                    pass
                    
            except Exception as e:
                print(f"[Daemon] Fehler beim Verarbeiten des Diktats: {e}", flush=True)
            finally:
                database.set_setting("daemon_status", STATUS_IDLE)

        # Im separaten Worker-Thread ausführen, damit der Hotkey-Listener sofort wieder bereit ist!
        threading.Thread(target=worker, daemon=True).start()

    def toggle_recording(self):
        if not self.recording:
            self.start_recording()
        else:
            duration = self.stop_recording()
            if duration:
                self.process_dictation(duration)

    # Thread Haupt-Loop für Hotkey Listener
    def run(self):
        settings = database.get_settings()
        hotkey_str = settings.get("global_hotkey", "option+space")
        
        # Umwandlung für pynput Format
        pynput_hotkey = hotkey_str.replace("option", "<alt>").replace("space", "<space>").replace("ctrl", "<ctrl>").replace("cmd", "<cmd>").replace("shift", "<shift>")
        
        print(f"[Daemon Thread] Starte globalen Hotkey-Listener: {hotkey_str} ({pynput_hotkey})...", flush=True)
        
        def on_hotkey_pressed():
            print(f"[Daemon Thread] Globaler Hotkey {hotkey_str} gedrückt!", flush=True)
            self.toggle_recording()

        try:
            self.hotkeys = keyboard.GlobalHotKeys({
                pynput_hotkey: on_hotkey_pressed
            })
            self.hotkeys.start()
            
            # Warte auf das Ende des Hotkey-Threads, um den Thread aktiv zu halten
            self.hotkeys.join()
        except Exception as e:
            print(f"[Daemon Thread] Schwerer Fehler im globalen Key-Listener: {e}", flush=True)
            database.set_setting("daemon_status", "Fehler")

if __name__ == "__main__":
    # Test-Ausführung direkt
    database.init_db()
    daemon = LocalWhisperDaemon()
    daemon.start()
    daemon.join()
