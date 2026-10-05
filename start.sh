#!/bin/bash
# --------------------------------------------------
# LocalWhisper Start & Setup Runner
# Manages virtual environment, installs packages with uv,
# runs the background daemon and Flask server, and cleans up.
# --------------------------------------------------

# Set execution directory to script path
cd "$(dirname "$0")"
PROJECT_DIR="$(pwd)"

echo "=================================================="
echo "          Starting LocalWhisper for Mac          "
echo "=================================================="

# 1. Virtual Environment Setup
if [ ! -d ".venv" ]; then
    echo "[Setup] Erstelle virtuelle Umgebung (.venv)..."
    python3 -m venv .venv
fi

echo "[Setup] Aktiviere virtuelle Umgebung..."
source .venv/bin/activate

# 2. Dependency Management via uv
echo "[Setup] Überprüfe und installiere Abhängigkeiten..."
if command -v uv &> /dev/null; then
    # Use blazing-fast uv
    uv pip install --upgrade pip
    uv pip install numpy sounddevice soundfile pynput faster-whisper flask pyautogui pyobjc-core pyobjc-framework-cocoa pyobjc-framework-quartz
else
    # Fallback to standard pip
    pip install --upgrade pip
    pip install numpy sounddevice soundfile pynput faster-whisper flask pyautogui pyobjc-core pyobjc-framework-cocoa pyobjc-framework-quartz
fi

echo "[Setup] Alle Abhängigkeiten sind bereit."

# 3. Starting App Processes
echo "--------------------------------------------------"
echo "[App] Starte Hintergrund-Daemon & Web-Dashboard..."

# Clean up any leftover processes on start
pkill -f "python3 daemon.py" 2>/dev/null
pkill -f "python3 app.py" 2>/dev/null

# Start daemon.py in the background
python3 daemon.py > daemon.log 2>&1 &
DAEMON_PID=$!

# Start app.py in the background
python3 app.py > app.log 2>&1 &
APP_PID=$!

# Handler for graceful shutdown on Ctrl+C
cleanup() {
    echo ""
    echo "--------------------------------------------------"
    echo "[App] Fahre LocalWhisper herunter..."
    kill $DAEMON_PID 2>/dev/null
    kill $APP_PID 2>/dev/null
    # Reset status in DB
    python3 -c "import database; database.set_setting('daemon_status', 'inaktiv')" 2>/dev/null
    echo "[App] LocalWhisper erfolgreich beendet."
    exit 0
}

trap cleanup SIGINT SIGTERM

# 4. Open browser to dashboard
sleep 1.5
echo "[App] Öffne Dashboard im Webbrowser..."
open "http://127.0.0.1:4950"

echo "[App] LocalWhisper läuft im Hintergrund!"
echo "-> Drücke global Option+Leertaste zum Diktieren."
echo "-> Öffne das Dashboard: http://127.0.0.1:4950"
echo "-> Drücke CTRL+C in diesem Terminal, um die App zu beenden."
echo "--------------------------------------------------"

# Wait for background processes to keep terminal open
wait $APP_PID
