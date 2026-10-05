# AInauten Voice: Prüfbericht

Stand: 4. Oktober 2026. **Beta, praktische Gesamtabnahme teilweise offen.**

## Öffentlicher Download

Version 0.1.1, Build 2 für Apple Silicon, macOS 14 als Build-Ziel. Lokal signiert, noch nicht Apple-notarisiert. Der aktuelle Entwicklungsstand kann zusätzliche Funktionen enthalten.

## Nachweise

- Für den veröffentlichten App-Stand wurden 243 automatisierte Vertragsfälle geprüft.
- Native Oberfläche, Modellverarbeitung, Textoptimierung, Wörterbuch, Migration, Zwischenablage und einzelne Einfügeziele wurden lokal geprüft.
- Deutsch, Englisch und Sprachwechsel wurden mit reproduzierbaren synthetischen Fällen sowie öffentlichen FLEURS-Sprachaufnahmen geprüft.
- Screenshots und Promo-Material zeigen ausschließlich ausdrücklich gekennzeichnete Beispieldaten.
- App-Signatur, DMG-Integrität und öffentlicher Download wurden geprüft. Die Offline-Installationsanleitung liegt im DMG.

## Sprachrückmeldung und unpersönlicher Probetest

Das Probediktat zeigt den erkannten Text in der Einrichtung. Es wird nicht automatisch in eine andere App eingefügt. Beispieltexte und Vorschauen verwenden keine persönliche Anrede.

## Offene Grenzen

Keine vollständige praktische Abnahme für alle Mikrofone, Apps, langen Aufnahmen, macOS-Versionen oder die festgelegten Geschwindigkeitsziele. Namen und Fachbegriffe können Fehler enthalten. Die Optimierung ersetzt keine inhaltliche Prüfung.

Der Entwicklungsstand enthält einen vorbereiteten, separat signierten Sparkle-Updatekanal und eine ausgeschaltete Forschungs-Beta für Lippenlesen. Beides gehört noch nicht zum öffentlichen Download. Kameraqualität und deutsche Lippenleseerkennung sind nicht allgemein abgenommen. Forschungsmodelle werden nicht mitgeliefert und unterliegen teilweise nichtkommerziellen Lizenzen.

## Neuerer Entwicklungsstand

Der neuere Quellstand enthält einen standardmäßig ausgeschalteten Fehlerbericht-Ausbau. Dafür wurden 265 portable Vertragsfälle sowie 17 lokale JavaScript-Tests geprüft. Lokale Prüfungen sind kein Nachweis für aktivierten öffentlichen Fehlerempfang oder automatische AI-Reparaturen. Diese Funktionen werden noch nicht allgemein ausgeliefert.

## Reproduzierbare Prüfungen

```sh
cd native
python3 scripts/portable-checks.py
python3 scripts/check-lip-adapters.py
python3 scripts/run-update-native-checks.py
```

Ein vollständiger Swift-/XCTest-Lauf benötigt die passende Apple-Entwicklungsumgebung; portable Vertragsprüfungen ersetzen keine echte Mikrofon-/App-Abnahme. Weitere Modellprüfungen sind in der [Entwicklungsanleitung](../README.md) beschrieben. Audio, Benutzerprofile, private Wörterbücher, Rohbelege und lokale Schlüssel sind kein Bestandteil dieses Repositorys.
