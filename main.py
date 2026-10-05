#!/usr/bin/env python3
import os
import sys
import webbrowser
import threading
import time
from pathlib import Path

# Add project root to path
PROJECT_ROOT = Path(__file__).resolve().parent
sys.path.append(str(PROJECT_ROOT))

import database

# Check if libraries are imported successfully, otherwise install
try:
    import rumps
except ImportError:
    print("[Main] rumps-Bibliothek fehlt. Versuche automatische Installation...", flush=True)
    subprocess.run([sys.executable, "-m", "pip", "install", "rumps"])
    import rumps

import daemon
import app

class LocalWhisperMenuBarApp(rumps.App):
    def __init__(self, daemon_instance, flask_instance):
        super().__init__(name="LocalWhisper", title="🎙️", quit_button=None)
        
        self.daemon_instance = daemon_instance
        self.flask_instance = flask_instance
        
        # Build beautiful menu items (Umlauts properly encoded)
        self.menu = [
            rumps.MenuItem("📊 Dashboard öffnen", callback=self.open_dashboard),
            rumps.MenuItem("🎙️ Diktat starten/stoppen", callback=self.toggle_recording),
            None,  # Separator
            rumps.MenuItem("Zustand: Bereit", callback=None),
            None,  # Separator
            rumps.MenuItem("❌ Beenden", callback=self.quit_app)
        ]
        
        # Disable status indicator item so it's read-only
        self.menu["Zustand: Bereit"].state = False
        
        # Create a timer to poll status and update menu icon/labels every second
        self.status_timer = rumps.Timer(self.update_status, 1.0)
        self.status_timer.start()
        
        print("[Main] Native macOS-Menüleiste initialisiert.", flush=True)

    def open_dashboard(self, sender):
        webbrowser.open("http://127.0.0.1:4950")

    def toggle_recording(self, sender):
        if self.daemon_instance:
            self.daemon_instance.toggle_recording()

    def update_status(self, sender):
        # Poll daemon status and active app from SQLite
        status = database.get_setting("daemon_status", "inaktiv")
        recording = database.get_setting("daemon_recording", "false") == "true"
        
        # 1. Update menu item label
        self.menu["Zustand: Bereit"].title = f"Zustand: {status}"
        
        # 2. Dynamic Title / Icon changes in macOS menu bar
        if recording:
            self.title = "🔴 AUFNAHME"
        elif status == "transkribiert...":
            self.title = "⏳ Transkription..."
        elif "verfeinert" in status:
            self.title = "🔮 KI-Glättung..."
        elif status == "fügt ein...":
            self.title = "✍️ Einfügen..."
        else:
            self.title = "🎙️"

    def quit_app(self, sender):
        print("[Main] Beende LocalWhisper...", flush=True)
        # Reset DB status
        database.set_setting("daemon_status", "inaktiv")
        database.set_setting("daemon_recording", "false")
        
        # Gracefully stop flask and hotkey threads (using sys.exit)
        # Rumps clean exit
        rumps.quit_application()
        sys.exit(0)

def main():
    print("=========================================", flush=True)
    print("        LocalWhisper App Launcher        ", flush=True)
    print("=========================================", flush=True)
    
    # 1. Initialize SQLite Database Schema
    database.init_db()
    
    # 2. Start Daemon Thread (Keyboard hotkeys + recording)
    daemon_thread = daemon.LocalWhisperDaemon()
    daemon_thread.start()
    
    # 3. Start Flask Thread (Dashboard server)
    flask_thread = app.FlaskAppThread(daemon_instance=daemon_thread)
    flask_thread.start()
    
    # 4. Start native macOS Menu Bar App
    menu_app = LocalWhisperMenuBarApp(daemon_instance=daemon_thread, flask_instance=flask_thread)
    
    # Start the App event loop (blocking, handles cocoa runloop)
    menu_app.run()

if __name__ == "__main__":
    main()
