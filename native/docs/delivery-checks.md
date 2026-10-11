# Einfügen in echte lokale Textfelder prüfen

Die Tests verwenden ausschließlich neu angelegte synthetische Dokumente und eigene Browser-Tabs. Bestehende Bedienungshilfenfreigabe ist erforderlich. Testfenster werden geschlossen und die zuvor aktive App wieder aktiviert; Testdateien bleiben erhalten. Zwischenablageformate werden nur im RAM gesichert, nicht protokolliert.

Im Ordner `native`:

```sh
python3 scripts/check-textedit-delivery.py --include-fullscreen
python3 scripts/check-comet-delivery.py --include-negatives
python3 scripts/check-protected-delivery.py
python3 scripts/portable-checks.py --only DeliveryToleranceTests.swift --only DeliveryFeedbackTests.swift --only ClipboardTests.swift
```

Comet muss installiert sein. Die Browserprüfungen starten ausschließlich einen lokalen Server auf 127.0.0.1 und öffnen eindeutige eigene Testseiten. Sie verwenden keine Website-Accounts und senden keine Nachrichten.

Geprüfter Quellcodeumfang am 5. Oktober 2026: fünf TextEdit-Fälle inklusive Vollbild, 14 Comet-Fälle inklusive sechs kontrollierter Abweichungen und fünf geschützte Controls. Lange vollständige Browser-Pastes werden über den gesamten ursprünglichen Textmarkerbereich bestätigt; geänderte/unvollständige Ergebnisse bleiben unsicher. Readonly, deaktivierte Controls, Passwortfelder und sichere Eingabe werden vor einem Paste abgewiesen. Ein synthetischer Paste hinterlässt keine gehaltene Command-Taste. Die 21 ergänzenden Verträge laufen mit einem CLT-Adapter; das ist kein Apple-XCTest-Lauf.

Diese Einfügekorrekturen sind im veröffentlichten Installer 0.1.5 (Build 9) enthalten. Der vorherige Installer 0.1.4 (Build 8) enthielt sie noch nicht. Die Fälle belegen keine physische Hotkey-/Mikrofon-/Aufnahme-Pill-/Recovery-Fenster-/gesamte OS-/p95-Abnahme und keine bessere Spracherkennung. Öffentliche Audiotests zeigen weiterhin Fehler bei Begriffen und Zahlen; die gesamte praktische Abnahme bleibt offen.


Diese Einfüge-Fixes werden mit Beta **0.1.5, Build 9** ausgeliefert. Der öffentliche Download, der signierte Updatekanal und die lokale Installation wurden separat auf denselben Build geprüft. Einstellungen und Verlauf bleiben erhalten. Die vollständige Sprach- und Hardwareabnahme bleibt offen.

Für die Regression am leeren WhatsApp-Nachrichtenfeld WhatsApp mit einem leeren Composer im Vordergrund vorbereiten und `swift run VoiceWisprProbe whatsapp-empty-focus-check` ausführen. Der lesende Test verlangt den ursprünglichen Fehlerzustand: `AXValue` liefert `noValue`, während `AXNumberOfCharacters` ausdrücklich 0 meldet. Er prüft die erfolgreiche Zielerfassung samt unverändertem Fokus, liest keine Nachrichten und verändert weder Feld noch Zwischenablage. Er startet keine Aufnahme und fügt keinen Text ein. Fehlende oder unlesbare Zeichenanzahlen gelten weiterhin nicht als leeres Feld. Tatsächliches Einfügen und Erhalt bestehender Entwürfe werden separat in der lokalen App geprüft.

Am 7. Oktober 2026 scheiterte dieser Test am selben leeren WhatsApp-Feld ohne Korrektur und bestand mit Korrektur. 60 gezielte Contract-Prüfungen zu Zustellung, Fehlerfeedback, Migration und Zwischenablage bestanden. Nach Austausch und Neustart des lokal signierten Dev-Builds bestätigte die lokale Nutzerprüfung das automatische Einfügen eines echten Diktats in WhatsApp. Das belegt den beobachteten leeren Composer; bestehende Entwürfe und weitere WhatsApp-Zustände bleiben eigene Prüfungen.
