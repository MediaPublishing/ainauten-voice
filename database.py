import sqlite3
import os
import sys
from pathlib import Path

def get_db_path() -> Path:
    # If compiled with PyInstaller or running inside an app bundle
    if hasattr(sys, '_MEIPASS') or 'LocalWhisper.app' in __file__:
        app_support = Path.home() / "Library" / "Application Support" / "LocalWhisper"
        app_support.mkdir(parents=True, exist_ok=True)
        return app_support / "local_whisper.db"
    return Path(__file__).resolve().parent / "local_whisper.db"

DB_PATH = get_db_path()

OLD_DEFAULT_PROMPT = (
    "Du bist ein intelligenter Schreibassistent für Diktate. "
    "Korrigiere die Grammatik, füge Satzzeichen hinzu und formatiere den folgenden Text auf Deutsch. "
    "Verwende immer die korrekten deutschen Umlaute (ä, ö, ü, ß). "
    "Entferne Füllwörter wie 'ähm', 'äh', 'ja', 'so'. "
    "WENN der Text konkrete Formatierungsanweisungen enthält (z. B. 'Format: Liste', 'mach daraus Stichpunkte', 'schreibe eine E-Mail'), wende diese an. "
    "Gib AUSSCHLIESSLICH den finalen korrigierten Text aus und absolut keinen anderen Kommentar oder Einleitung."
)

MULTILINGUAL_DEFAULT_PROMPT = (
    "Du bist ein intelligenter Schreibassistent für Diktate auf Deutsch und Englisch. "
    "Erkenne die Sprache des Rohtexts und antworte in derselben Sprache. "
    "Bei deutschem Text: Verwende Hochdeutsch mit korrekten Umlauten (ä, ö, ü) und ß. "
    "Bei englischem Text: Verwende natürliches, klares Englisch. "
    "Korrigiere Grammatik, Satzzeichen und offensichtliche Transkriptionsfehler, ohne die Aussage zu verändern. "
    "Entferne Füllwörter wie 'ähm', 'äh', 'um', 'uh', 'you know' und 'like', sofern sie keine Bedeutung tragen. "
    "WENN der Text konkrete Formatierungsanweisungen enthält (z. B. 'Format: Liste', 'turn this into bullets', 'schreibe eine E-Mail'), wende diese an. "
    "Gib AUSSCHLIESSLICH den finalen korrigierten Text aus und absolut keinen Kommentar oder eine Einleitung."
)

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Historie-Tabelle
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        app TEXT,
        duration REAL,
        num_words INTEGER,
        raw_text TEXT,
        refined_text TEXT,
        is_archived INTEGER DEFAULT 0
    )
    """)
    
    # Einstellungen-Tabelle
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
    )
    """)
    
    # Standard-Einstellungen einfügen, falls nicht vorhanden
    default_settings = {
        "whisper_model": "base",
        "whisper_language": "auto",
        "ollama_enabled": "true",
        "ollama_model": "gemma4-obliterated:latest",
        "system_prompt": MULTILINGUAL_DEFAULT_PROMPT,
        "custom_vocabulary": "",
        "global_hotkey": "option+space"
    }
    
    for key, val in default_settings.items():
        cursor.execute("INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)", (key, val))

    cursor.execute("SELECT value FROM settings WHERE key = 'system_prompt'")
    row = cursor.fetchone()
    if row and row[0] == OLD_DEFAULT_PROMPT:
        cursor.execute(
            "UPDATE settings SET value = ? WHERE key = 'system_prompt'",
            (MULTILINGUAL_DEFAULT_PROMPT,)
        )
        
    conn.commit()
    conn.close()

def get_settings():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT key, value FROM settings")
    rows = cursor.fetchall()
    conn.close()
    return {row["key"]: row["value"] for row in rows}

def get_setting(key, default=None):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT value FROM settings WHERE key = ?", (key,))
    row = cursor.fetchone()
    conn.close()
    return row["value"] if row else default

def set_setting(key, value):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", (key, str(value)))
    conn.commit()
    conn.close()

def add_history_entry(app, duration, num_words, raw_text, refined_text):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("""
    INSERT INTO history (app, duration, num_words, raw_text, refined_text)
    VALUES (?, ?, ?, ?, ?)
    """, (app, duration, num_words, raw_text, refined_text))
    conn.commit()
    row_id = cursor.lastrowid
    conn.close()
    return row_id

def get_history(limit=100, query=None):
    conn = get_db_connection()
    cursor = conn.cursor()
    if query:
        cursor.execute("""
        SELECT id, timestamp, app, duration, num_words, raw_text, refined_text, is_archived
        FROM history
        WHERE is_archived = 0 AND (raw_text LIKE ? OR refined_text LIKE ? OR app LIKE ?)
        ORDER BY timestamp DESC
        LIMIT ?
        """, (f"%{query}%", f"%{query}%", f"%{query}%", limit))
    else:
        cursor.execute("""
        SELECT id, timestamp, app, duration, num_words, raw_text, refined_text, is_archived
        FROM history
        WHERE is_archived = 0
        ORDER BY timestamp DESC
        LIMIT ?
        """, (limit,))
    rows = cursor.fetchall()
    conn.close()
    return [dict(row) for row in rows]

def delete_history_entry(entry_id):
    conn = get_db_connection()
    cursor = conn.cursor()
    # We soft-delete by setting is_archived = 1, to preserve history but hide it from the standard view
    cursor.execute("UPDATE history SET is_archived = 1 WHERE id = ?", (entry_id,))
    conn.commit()
    conn.close()

# Datenbank initialisieren bei Import
init_db()
