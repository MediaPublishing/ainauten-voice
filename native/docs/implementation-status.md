# Entwicklungsstand

AInauten Voice ist eine native lokale Diktier-App für macOS und Apple Silicon. Der öffentliche Download ist Beta 0.1.19, Build 26, mit signierten automatischen Updates, Hilfe und aktivem privaten Fehlerempfang. Automatische Fehlerberichte bleiben standardmäßig aus. Lippenlesen ist in diesem Release vorübergehend gesperrt, bis eine signierte und isolierte Laufzeit verfügbar ist. Die vollständige praktische Abnahme und Apple-Notarisierung sind weiterhin offen.

[Prüfstand und offene Grenzen](verification-report.md) · [Entwickeln](../README.md) · [Lizenzen](../Resources/Licenses/NOTICE.md)

Bundle-ID, Modulname und der lokale Datenordner behalten für bestehende Installationen den internen Namen Voice Wispr. Für das Produkt wird AInauten Voice verwendet. Audio bleibt lokal und wird nicht dauerhaft aufgezeichnet; Textverlauf ist lokal und abschaltbar.


Zusätzlicher Entwicklungsstand: Schutzregeln für vollständige Sprachwechsel und Satzzeichen an begrenzten Textkorrekturen sind im Quellcode enthalten. 97 gezielte native Contract-Prüfungen bestehen. Ein vollständig aufgezeichneter Modellvergleich mit 18 Ergebnissen aus drei öffentlichen Kurz-Fixtures bestätigt die gezielten Formatierungskorrekturen in allen drei Wiederholungen. Die unveränderte Spracherkennung verfehlt weiterhin das Wortfehlerziel und einen geschützten Namen. Diese Änderungen sind noch nicht im oben genannten Beta-Download enthalten; daraus folgt keine Abnahme der allgemeinen Erkennungsqualität oder Einfügezeit.

Schweizerdeutsch (Beta): optionale lokale Whisper-Erkennung mit hochdeutscher Ausgabe, direkt in der Sprachauswahl. Eine begrenzte Warteschlange erlaubt weitere Aufnahmen während vorheriger Verarbeitung. Überlappende Ergebnisse werden wie in allen ausgewählten Audiosprachen automatisch in Aufnahme-Reihenfolge im ursprünglichen, unveränderten Textfeld eingefügt. Nach Feld- oder Cursorwechsel bleiben sie zur Wiederherstellung erhalten. Decoder-Wörterbuchhinweise bleiben nach dem fehlgeschlagenen Stille-/Rauschvergleich aus. Die Beta ist kein Nachweis fehlerfreier Dialekterkennung.

Ab Beta 0.1.17 (24): [Weiterdiktieren in allen Audiosprachen](queued-dictation.md) mit automatischer FIFO-Zustellung. Bestätigte eigene Einfügungen schreiben wartende Ziel-Snapshots fort; manuelle Änderungen, Fehler oder unbestätigte Zustellungen halten die automatische Serie an. Gleichwertige Rich-Text-Darstellungen und kurz verzögerte Cursor-Rückmeldungen werden berücksichtigt. 410 Vertragsprüfungen, elf native Einfüge-/Schutzfälle und CI bestehen; der lokale Build 23 wurde praktisch positiv getestet. Das ersetzt keine vollständige Abnahme über alle Ziel-Apps und Geräte.

## Beta 0.1.18 (25): sichere Fokus- und Kürzel-Wiederherstellung

Begrenzte read-only-Fokusprüfung ohne Probezeichen oder Undo bei expliziter Wiederherstellung und im getrennten Kameraablauf. Ungültige Tastatur-Hooks werden unter Erhalt aktiver Gesten ersetzt. Die automatische Diktatwarteschlange mit ihren ursprünglichen Ziel-Snapshots bleibt unverändert. Die bisherige Ausgangsrevision bestand 424 XCTest-, 31 Reporting- und 14 Controller-Prüfungen; die finale Release-Revision wird separat in CI geprüft. Live-Verhalten über alle Apps und Apple-Notarisierung sind damit nicht abgenommen.

## Beta 0.1.19 (26): kompatibles Einfügen und erhaltene Ergebnisse

Rich-Text-Felder ohne direkte Accessibility-Textsetter können bei aktiviertem Standard-Einfügebefehl kompatibel eingefügt werden. Die Prüfung bleibt an dasselbe lesbare, aktivierte Textfeld und seine unveränderte Auswahl gebunden. Verkürzte AXValue-Rückmeldungen werden über den vollständigen Textbereich gelesen; unvollständige Bereichsantworten werden verworfen. Ohne Freigabe der Zwischenablage wird weiterhin kein kompatibler Paste ausgeführt.

Nach gescheiterter Zustellung bleibt der Ergebnistext sichtbar, bis du ihn schließt oder eine neue Aufnahme beginnst. Explizite kurze Statusanzeigen behalten den Countdown. Der Kopierhinweis ist direkt sichtbar.

Prüfstand: 424 Vertragsfälle, acht native Rich-Text-/Queue-Fälle, zehn TextEdit-Fälle und fünf Chrome-Schutzfälle bestanden. Word war auf dem Referenz-Mac nicht installiert; diese Prüfungen ersetzen keinen Live-Nachweis für alle Word-Versionen oder die ursprünglichen Nutzeraufnahmen. Apple-Signierung/Notarisierung bleiben getrennt offen.
