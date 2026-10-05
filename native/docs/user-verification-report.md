# AInauten Voice: Prüfbericht

**Beta. Die praktische Gesamtabnahme ist noch nicht abgeschlossen.**

Diese Fassung wird mit der App ausgeliefert. Sie enthält keine Diktate, Namen oder lokalen Daten.

## Was geprüft wurde

- Automatisierte Vertragsfälle für Spracherkennung, Textoptimierung, Wörterbuch, Wispr-Flow-Import, Zwischenablage, Kürzel und Verlauf.
- Deutsch, Englisch und Sprachwechsel mit reproduzierbaren synthetischen Fällen und öffentlichen FLEURS-Sprachaufnahmen.
- Native Oberfläche, lokale Modelle und einzelne Einfügeziele auf einem Apple-Silicon-Mac mit macOS 27.
- App-Signatur, DMG-Integrität und Download.

## Was lokal bleibt

- Audio wird nur im Arbeitsspeicher verarbeitet.
- Einstellungen, Wörterbuch und Verlauf liegen auf deinem Mac, API-Schlüssel im macOS-Schlüsselbund.
- Verbindungen nach außen:
  - der einmalige Modell-Download;
  - die Updateprüfung;
  - die Cloud-Optimierung, nur wenn du sie ausdrücklich einschaltest;
  - Fehlerberichte, nur nach deiner Zustimmung.

## Offene Grenzen

- Keine vollständige praktische Abnahme für alle Mikrofone, Apps, langen Aufnahmen und macOS-Versionen.
- macOS 14 ist das Build-Ziel, getestet wurde bisher auf neueren Versionen.
- Namen und Fachbegriffe können Fehler enthalten. Die Optimierung ersetzt keine inhaltliche Prüfung.
- Die App ist lokal signiert, aber noch nicht von Apple notarisiert.
- Forschungsfunktionen wie Lippenlesen sind ausgeschaltet und nicht Teil der Abnahme.
