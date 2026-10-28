# AInauten Voice: Prüfbericht

**Beta. Die praktische Gesamtabnahme ist noch nicht abgeschlossen.**

Diese Fassung wird mit der App ausgeliefert. Sie enthält keine Diktate, Namen oder lokalen Daten.

## Was geprüft wurde

- Kompatibles Einfügen in isolierte Rich-Text-Editoren ohne direkte Accessibility-Textsetter, vollständiges Lesen bei verkürztem AXValue und drei Einfügungen in Reihenfolge. Schreibgeschützte, deaktivierte und sichere Browserfelder sowie Feldwechsel werden weiterhin abgewiesen.
- Nicht eingefügter Text bleibt im Ergebnisfenster sichtbar. Der Hinweis zum manuellen Einfügen ist direkt sichtbar. Word-spezifisches Live-Verhalten bleibt unbestätigt, da Word auf dem Referenzgerät nicht installiert war.

- Begrenzte Fokus-Wiederherstellung ohne Probezeichen oder Rückgängig-Tastenkürzel, Schutz bei Zielwechsel und Abbruch sowie Erhalt von Gesten beim Ersetzen eines ungültigen Tastatur-Hooks. Getrennte Regressionen für widerrufene Zustellungsfreigaben; keine vollständige Live-Abnahme aller Apps.
- Schweizerdeutsch-Beta mit lokalem Modell und begrenzter Aufnahme-Warteschlange. Getrennte Tests für Akustik und Queue-Verhalten; kein Nachweis fehlerfreier Dialekterkennung.
- Weiterdiktieren in allen ausgewählten Audiosprachen mit automatischer Einfügung in Aufnahme-Reihenfolge. Native Prüfungen für überlappende Aufnahmen, gleichwertige Rich-Text-Darstellung, verzögerte Cursor-Rückmeldung sowie Schutz nach Feldwechsel, Cursorwechsel und Abbruch. Ein lokaler praktischer Nutzertest war positiv; keine vollständige Abnahme aller Ziel-Apps.
- Automatisierte Vertragsfälle für Spracherkennung, Textoptimierung, Wörterbuch, Wispr-Flow-Import, Zwischenablage, Kürzel und Verlauf.
- Deutsch, Englisch und Sprachwechsel mit reproduzierbaren synthetischen Fällen und öffentlichen FLEURS-Sprachaufnahmen.
- Deutsche und englische Oberfläche mit direktem Sprachwechsel, unveränderten Diktatsprachen und lokalisierten Menü- und Bedienelementen.
- Native Oberfläche, lokale Modelle und einzelne Einfügeziele auf einem Apple-Silicon-Mac mit macOS 27.
- Schnellere lokale Textoptimierung mit unveränderten Wortschutzregeln und identischen Ausgaben in elf Textfällen eines sechsfachen Vergleichs; kein allgemeiner Geschwindigkeitsnachweis.
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
- Kompatibles Einfügen verwendet kurz die systemweite Zwischenablage. Die Option ist bei neuen Installationen eingeschaltet und lässt sich unter Datenschutz ausschalten. Andere lokale Apps können den kurzzeitig abgelegten Text lesen. Gespeicherte Einstellungen bleiben erhalten; ohne die Option werden nicht direkt unterstützte Textfelder nicht automatisch befüllt.
- Lippenlesen ist im Release vorübergehend gesperrt, bis eine signierte und isolierte Laufzeit verfügbar ist. Mikrofondiktate sind davon nicht betroffen.
