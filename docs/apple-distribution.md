# Apple-Distribution ab 0.1.20

Öffentliche Pakete verwenden Developer ID Application, Hardened Runtime, sichere Apple-Zeitstempel und aktive Bibliotheksvalidierung. Alle eingebetteten ausführbaren Komponenten müssen zum freigegebenen Team gehören. Code-Injection-Ausnahmen werden abgewiesen.

App und abschließender DMG-Installer werden jeweils bei Apple eingereicht. Erst nach Accepted, angehängtem Ticket und erfolgreicher Gatekeeper-Prüfung werden die Pakete veröffentlicht. Das Updatepaket enthält die notarisierten App-Daten und verwendet weiterhin die bestehende Sparkle-Updatesignatur. Schlüssel und Zugangsdaten gehören ausschließlich in den lokalen Schlüsselbund.

Prüfungen: `python3 native/scripts/check-distribution-security.py`, `python3 native/scripts/check-installer-guide.py`, `site/release_verification.py` sowie der echte Installations-/Update-Test. Die Notarisierung belegt keine vollständige Kompatibilität mit allen Ziel-Apps und Geräten.
