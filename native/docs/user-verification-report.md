# AInauten Voice: Prüfbericht

**Beta. Die praktische Gesamtabnahme ist noch nicht abgeschlossen.**

Diese Fassung wird mit der App ausgeliefert. Sie enthält keine Diktate, Namen oder lokalen Daten.

## Was geprüft wurde

- Automatisierte Vertragsfälle für Spracherkennung, Textoptimierung, Wörterbuch, Wispr-Flow-Import, Zwischenablage, Kürzel und Verlauf.
- Deutsch, Englisch und Sprachwechsel mit reproduzierbaren synthetischen Fällen und öffentlichen FLEURS-Sprachaufnahmen.
- Deutsche und englische Oberfläche mit direktem Sprachwechsel, unveränderten Diktatsprachen und lokalisierten Menü- und Bedienelementen.
- Native Oberfläche, lokale Modelle und einzelne Einfügeziele auf einem Apple-Silicon-Mac mit macOS 27.
- App-Signatur, eingebettete App im DMG und Download.
- Gebündelte deutsche und englische Sprachdateien ohne Zugriff auf einen Entwicklungsordner; kontrollierter Rückfall bei fehlenden Sprachdateien.
- Geschützte Cloud-Empfängerfreigabe, Grenzen für Einstellungsdateien und Fehlermeldungen, sichere Entwicklungs-Dateinamen.

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
- Die App ist lokal signiert, aber noch nicht von Apple notarisiert. Die lokale Signatur benötigt weiterhin eine Ausnahme für Bibliotheksvalidierung. Eine Apple-Developer-ID-Signatur steht aus.
- Kompatibles Einfügen verwendet kurz die systemweite Zwischenablage. Unter Datenschutz lässt es sich ausschalten; nicht unterstützte Textfelder werden dann nicht automatisch befüllt.
- Lippenlesen ist im Release vorübergehend gesperrt, bis eine signierte und isolierte Laufzeit verfügbar ist. Mikrofondiktate sind davon nicht betroffen.
