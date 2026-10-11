# Community-Korrekturen für Beta 0.1.12 (16)

Neun Beiträge wurden zusammen geprüft und integriert: optionaler Wispr-Import (#1), Loslassen kombinierter Kürzel (#2), Ausblenden/Minimieren (#3), gespeicherter Menüleistenmodus (#4), stabilerer Diktatstart (#5), leere WhatsApp-Felder (#6), Frequenzanzeige (#7), Wörterbuch aus letzten Nachrichten (#8) und Leerzeichen am Satzübergang (#9).

Zusätzliche Korrekturen:

- #10: Chromium-Accessibility wird bei jeder Zielerfassung erneut aktiviert. Bis zu sechs Erfassungsversuche warten asynchron höchstens fünfmal 40 ms; ein App-Wechsel oder Abbruch beendet die Erfassung. Das Ziel wird vor Beginn der Aufnahme erfasst. Fokus-, Auswahl- und Readback-Prüfungen bleiben erhalten. Ein nachträgliches Übernehmen irgendeines gerade fokussierten Felds wurde bewusst nicht eingeführt.
- #11: Systemeinstellungen öffnen die PrivacySecurity-Erweiterung mit dem bestehenden TCC-Anker. Ab macOS 27 heißt die Freigabe in der deutschen Oberfläche „Gerätesteuerung und Datenzugriff“. Ältere Systeme behalten ihre bisherigen Beschriftungen. Kamera und Mikrofon verwenden denselben Einstieg mit ihrem jeweiligen Anker.
- Timeout-Wiederherstellung und Modifier-Halten verwenden dieselbe Loslass-Regel. Der neue Freihand-Test enthält das tatsächliche Loslassen des Modifiers.
- Satzabstände werden nicht in Dezimalzahlen oder angefangenen URLs ergänzt.
- Fehlerempfang akzeptiert zusätzlich die gültigen Paare 0.1.11 (15) und 0.1.12 (16); unbekannte und falsch kombinierte Versionen bleiben abgewiesen.

Dieser Abschnitt beschreibt 0.1.12: Die Sprachauswahl wirkte noch nicht auf die Erkennung. Die anschließende Korrektur in 0.1.13 ist unter `speech-language-selection.md` dokumentiert. Keine Behauptung, dass die ursprüngliche Nutzeraufnahme ohne Reproduktion geprüft wurde.

Prüfungen umfassen native Vertragsfälle, echte Event-Tap-Callbacks, deutsche/englische Sprachdateien, den Release-Build und synthetische Berichte. Die Freigabelinks und Einfügekorrekturen ersetzen keine vollständige praktische Hardware-/Ziel-App-Matrix. Apple-Notarisierung und aktive Bibliotheksvalidierung bleiben für die lokal signierte Beta offen.
