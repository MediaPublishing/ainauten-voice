#!/usr/bin/env python3
import os
import sys
import json
import urllib.request
import threading
from pathlib import Path
from flask import Flask, jsonify, request, send_from_directory

# Add project root to path
PROJECT_ROOT = Path(__file__).resolve().parent
sys.path.append(str(PROJECT_ROOT))

import database

def get_static_folder():
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, 'web')
    return os.path.join(str(PROJECT_ROOT), 'web')

app = Flask(__name__, static_folder=get_static_folder(), static_url_path="")
_daemon_instance = None  # Global variable to avoid naming clashes with module app

# Route: Serve index.html as main page
@app.route("/")
def index():
    return send_from_directory(app.static_folder, "index.html")

# API: Status abrufen
@app.route("/api/status", methods=["GET"])
def get_status():
    daemon_status = database.get_setting("daemon_status", "inaktiv")
    daemon_recording = database.get_setting("daemon_recording", "false") == "true"
    
    # Ollama-Verbindung prüfen & installierte Modelle abrufen
    ollama_running = False
    ollama_models = []
    try:
        req = urllib.request.Request("http://127.0.0.1:11434/api/tags")
        with urllib.request.urlopen(req, timeout=1.2) as response:
            data = json.loads(response.read().decode("utf-8"))
            ollama_running = True
            ollama_models = [m["name"] for m in data.get("models", [])]
    except Exception:
        pass
        
    return jsonify({
        "daemon_status": daemon_status,
        "daemon_recording": daemon_recording,
        "ollama_running": ollama_running,
        "ollama_models": ollama_models,
        "active_hotkey": database.get_setting("global_hotkey", "option+space")
    })

# API: Verlauf abrufen (mit Suche)
@app.route("/api/history", methods=["GET"])
def get_history_api():
    query = request.args.get("q", "").strip()
    limit = int(request.args.get("limit", 50))
    history_entries = database.get_history(limit=limit, query=query if query else None)
    return jsonify({"history": history_entries})

# API: Einstellungen abrufen
@app.route("/api/settings", methods=["GET"])
def get_settings_api():
    settings = database.get_settings()
    return jsonify(settings)

# API: Einstellungen speichern
@app.route("/api/settings", methods=["POST"])
def save_settings_api():
    data = request.json
    if not data:
        return jsonify({"error": "Keine Daten übergeben"}), 400
        
    for key, val in data.items():
        database.set_setting(key, val)
        
    return jsonify({"success": True, "settings": database.get_settings()})

# API: Eintrag löschen (Soft-Delete)
@app.route("/api/delete/<int:entry_id>", methods=["POST"])
def delete_entry(entry_id):
    database.delete_history_entry(entry_id)
    return jsonify({"success": True})

# API: Diktat per Web-UI triggern (In-Prozess Direktaufruf!)
@app.route("/api/record/toggle", methods=["POST"])
def trigger_record():
    global _daemon_instance
    if _daemon_instance:
        # Toggle recording directly in process!
        _daemon_instance.toggle_recording()
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Daemon ist nicht initialisiert"})

# Flask Thread Kapselung
class FlaskAppThread(threading.Thread):
    def __init__(self, daemon_instance=None):
        super().__init__()
        self.daemon = True  # Terminate thread when main program exits
        self.daemon_instance = daemon_instance
        global _daemon_instance
        _daemon_instance = daemon_instance

    def run(self):
        # Mute Werkzeug logger for clean terminal output
        import logging
        log = logging.getLogger('werkzeug')
        log.setLevel(logging.ERROR)
        
        print("[App Thread] Starte Flask Webserver auf Port 4950...", flush=True)
        # Run Flask server locally
        app.run(host="127.0.0.1", port=4950, debug=False, use_reloader=False)

if __name__ == "__main__":
    # Test execution when run directly
    database.init_db()
    server = FlaskAppThread()
    server.start()
    server.join()
