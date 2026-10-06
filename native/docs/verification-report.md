# AInauten Voice: Prüfbericht

Stand: 5. Oktober 2026. **Beta, praktische Gesamtabnahme teilweise offen.**

## Öffentlicher Download

Version **0.1.9, Build 13** für Apple Silicon, macOS 14 als Build-Ziel. Die App ist lokal signiert und nutzt Hardened Runtime, ist jedoch noch nicht Apple-notarisiert. Die Signatur benötigt derzeit eine Ausnahme für Bibliotheksvalidierung.

Der Download enthält den separat signierten Sparkle-Updater, Hilfe, einen aktivierten privaten Fehlerempfang sowie eine deutsche und englische Oberfläche. Automatische Updates sind standardmäßig aktiv; eine ausdrücklich gespeicherte Abschaltung bleibt erhalten. Fehlerberichte werden nur mit Zustimmung gesendet, automatische Fehlerübermittlung bleibt standardmäßig aus. Automatische AI-Reparaturen sind nicht aktiviert.

## Nachweise

- Der aktuelle Quellstand sperrt auch den direkten Lippenlese-Installer im Release. Drei gezielte native Release-Prüfungen bestanden; der alte Installer scheitert nachweislich am neuen Test. Die ungeprüften Forschungs-Abhängigkeiten sind damit nicht aktualisiert oder sicherheitsqualifiziert. Der Fix ist noch nicht im Download enthalten.
- Im aktuellen Quellstand bestätigt die Zwischenablage-Wiederherstellung erst eine zusätzliche Prüfung aller ursprünglichen Datenformate und Einträge. **20 gezielte native Vertragsfälle ohne Fehler**, mit separaten AppKit-Testzwischenablagen und unabhängiger Gegenprüfung. Dieser Fix ist noch nicht im Download 0.1.9, Build 13 enthalten; keine Mikrofon- oder vollständige App-Abnahme daraus abgeleitet.
- Für die letzte Oberflächenänderung wurden **97 gezielt ausgewählte portable Vertragsfälle ohne Fehler** ausgeführt. Das sind ausgewählte Prüfungen, kein vollständiger Apple-XCTest-Lauf und keine Gesamtabnahme.
- Der native Release-Build, die eingebetteten Sprachressourcen, der direkte Oberflächensprachwechsel und die Speicherung der Sprachwahl über einen Neustart wurden geprüft. Diktatsprachen und vorhandene Einstellungen blieben erhalten.
- Native Oberfläche, Modellverarbeitung, Textoptimierung, Wörterbuch, Migration, Zwischenablage und einzelne Einfügeziele wurden in früheren Prüfungen lokal geprüft. Diese Nachweise decken jeweils ihren konkreten Testumfang ab.
- Deutsch, Englisch und Sprachwechsel wurden mit reproduzierbaren Textfällen sowie öffentlichen FLEURS-Sprachaufnahmen geprüft. Die Sprachtests haben auch Fehler ergeben; sie belegen keine durchgehend erfüllten Qualitätsziele.
- Die aktuelle lokale Textoptimierung bestand elf unveränderte Textfälle und zwei Prüfungen mit einem Transkriptadapter. Eine Zitatprüfung nutzte den sicheren Originaltext-Rückfall. Diese Tests verwenden das echte lokale Textmodell, jedoch keine Mikrofonaufnahme oder Spracherkennung; die Einstellungen blieben unverändert.
- Vier aktuelle TextEdit-Prüfungen bestätigten Auswahlersetzung, Einfügen am Cursor, langen Text und die Ablehnung eines gewechselten Ziels in eigenen Testdokumenten. Sie prüfen die Zustellung im Core, keine physische Aufnahme oder vollständige Ziel-App-Matrix.
- Für die Auswahländerung bestanden **83 gezielte Vertragsfälle** und ein weiterer tatsächlicher Lauf aller elf Textfälle sowie beider Pipelineprüfungen.
- Ein isolierter Vergleich der Auswahl im Textmodell umfasste sechs vollständige Läufe und alle elf bisherigen Textfälle. Die Ausgaben blieben identisch. Der Median der gepaarten Fallquotienten sank um rund 15 %; dies ist ein begrenzter Modellzeitvergleich, keine Messung bis zur Einfügung in eine andere App. [Details und Grenzen](formatter-selection-2026-10-05.md).
- Screenshots und Promo-Material zeigen ausschließlich ausdrücklich gekennzeichnete Beispieldaten.
- App-Signatur, DMG-Integrität, öffentlicher Download und signierter Updatekanal wurden für 0.1.9, Build 13 geprüft. Die Offline-Installationsanleitung liegt im DMG.

## Sprachrückmeldung und unpersönlicher Probetest

Das Probediktat zeigt den erkannten Text in der Einrichtung. Es wird nicht automatisch in eine andere App eingefügt. Beispieltexte und Vorschauen verwenden keine persönliche Anrede.

## Offene Grenzen

Keine vollständige praktische Abnahme für alle Mikrofone, Apps, langen Aufnahmen oder macOS-Versionen. macOS 14 ist das Build-Ziel; das aktuelle Paket wurde auf einem neueren macOS geprüft.

Die festgelegten Qualitäts- und Geschwindigkeitsziele sind weiterhin offen. Öffentliche Sprachtests überschreiten in einzelnen Fällen die Grenze von 8 % Wortfehlern und verlieren vereinzelt Namen oder Zahlen. Gemessene Modellverarbeitungszeiten überschreiten die Ziele für optimierte Texte; diese Messungen sind kein Nachweis für die Dauer bis zum tatsächlichen Einfügen in eine andere App. Auch ein durchgelaufener 20-Minuten-Audiofall erfüllte die Qualitätsgrenze nicht. Die Optimierung ersetzt keine inhaltliche Prüfung.

Kompatibles Einfügen verwendet kurz die systemweite Zwischenablage. Es lässt sich unter Datenschutz abschalten. Unklare Zustellung wird nicht automatisch wiederholt, damit kein Text doppelt eingefügt wird.

Lippenlesen ist im Release vorübergehend gesperrt, bis eine signierte und isolierte Laufzeit verfügbar ist. Mikrofondiktate sind davon nicht betroffen. Kameraqualität und deutsche Lippenleseerkennung sind nicht allgemein abgenommen. Forschungsmodelle werden nicht mitgeliefert und unterliegen teilweise nichtkommerziellen Lizenzen.

## Reproduzierbare Prüfungen

```sh
cd native
python3 scripts/portable-checks.py
python3 scripts/check-lip-adapters.py
python3 scripts/run-update-native-checks.py
python3 scripts/check-paragraph-quality.py  # vorhandenes lokales Modell; keine Mikrofonaufnahme
```

Ein vollständiger Swift-/XCTest-Lauf benötigt die passende Apple-Entwicklungsumgebung; portable Vertragsprüfungen ersetzen keine echte Mikrofon-/App-Abnahme. Hinweise zum passenden SDK und weitere Modellprüfungen stehen in der [Entwicklungsanleitung](../README.md). Audio, Benutzerprofile, private Wörterbücher, Rohbelege und lokale Schlüssel sind kein Bestandteil dieses Repositorys.
