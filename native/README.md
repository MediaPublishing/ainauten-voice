# AInauten Voice

Native macOS-App im bestehenden LocalWhisper-Projekt. Apple Silicon, macOS 14+. Audio bleibt lokal; Parakeet v3 (FluidAudio) und Qwen3-4B Q4_K_M (eingebettetes llama.cpp). Optionale OpenAI-kompatible Textglättung ist standardmäßig aus.

## Installieren

Das DMG enthält AInauten Voice, eine Applications-Verknüpfung sowie **00 - ZUERST LESEN.html** und eine Textfassung. Die HTML-Anleitung ist eigenständig und offline lesbar. App nach Applications ziehen und von dort öffnen. Der Assistent führt durch Modelle, Wispr-Import, Sprache, Mikrofon/Bedienungshilfen, Probediktat und Wechsel.

Das lokale Paket ist mit einer lokalen Identität oder ad-hoc signiert. Apple Developer ID und Notarisierung sind noch nicht Bestandteil dieser Lieferung. Falls macOS den ersten Start blockiert: **Fertig (Done)** wählen, dann **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen (Open Anyway)** und den Start bestätigen. Die genaue Anleitung mit Hinweisen zu abweichenden Warnungen liegt im DMG und [online](https://voice.ainauten.com/installation.html). Ein Neu-Build kann eine erneute macOS-Freigabe verlangen. Auf macOS 14 wurde das Paket noch nicht praktisch getestet.

`scripts/package.py` und `scripts/package_dmg.py` verwenden dieselbe Anleitung aus `Resources/InstallerGuide`. Mit `python3 scripts/package_dmg.py --app /Pfad/zu/AInauten\ Voice.app` lässt sich ein bestehendes signiertes App-Bundle unverändert neu verpacken, ohne interne Beta-Funktionen in die öffentliche Version zu übernehmen.

## Entwickeln

Command Line Tools mit Swift 6.2+, Python 3 nur für den Paketbau. Endnutzer benötigen keine Entwicklungswerkzeuge und keinen separaten Server.

```sh
python3 scripts/bootstrap.py
swift package resolve
swift build
swift test                  # mit vollständigem Xcode/XCTest
python3 scripts/portable-checks.py  # dieselben Contract-Cases auf CLT-only Macs
python3 scripts/package.py --install
swift run -c release VoiceWisprProbe format-cases docs/fixtures/formatting-contracts.json
python3 scripts/human-fixtures.py  # öffentliche CC-BY-4.0-Sprachaufnahmen
swift run -c release VoiceWisprProbe suite artifacts/fixtures/fleurs/manifest.json 3 --styles=original,cleaned,email,chat
```

`bootstrap.py` prüft die festgelegte llama-XCFramework-Prüfsumme. `Package.resolved` bindet FluidAudio an den geprüften Commit. Modelle sind über ein mitgeliefertes Datei-/SHA256-Verzeichnis gebunden. Die lokale SwiftPM-Mirrorkonfiguration in `.swiftpm` ist nicht Teil des Quellcodes; sie vermeidet auf dem Referenzgerät einen unnötig großen vollständigen Upstream-Clone.

Die lokalen Glättungsfälle sind ausdrücklich synthetische Texte. Die öffentliche FLEURS-Auswahl verwendet einen festen Datenstand; Quell-/PCM-Prüfsummen und CC-BY-4.0-Provenance liegen bei den ignorierten Fixtures. Zehn gemischte Fälle sind zusammengesetzte Lesetexte verschiedener Sprecher, keine spontanen Sprachwechsel. `--settings-dictionary` liest das lokale Wörterbuch ohne Schlüsselbundzugriff und unterdrückt alle Inhaltsfelder im Probe-Receipt. `format-cases` protokolliert nur solche deklarierten Fixtures; die App speichert keine Inhalte in Diagnoseprotokollen. Der optionale lokale Textverlauf ist davon getrennt. Die lokale Glättung ist auf die Wortfolge des aktuellen Abschnitts beschränkt. Bei Diktaten über zehn Minuten prüft der abschließende Abgleich 60-Sekunden-Blöcke mit acht Sekunden akustischem Kontext. Details und weiterhin offene praktische Abnahme stehen im Prüfbericht.

## Sicherheit und Zustellung

Einfügung nur in unveränderte, lesbare AX-Ziele. Bestätigung verlangt kompletten Text-/Cursor-Readback, keine bloße Tastensimulation. Bei Zweifel vollständiges Ergebnisfenster; keine automatische Wiederholung. Zwischenablage wird byteweise gesichert, bei unlesbaren/über 64 MB großen Inhalten nicht verändert; ein neuer Benutzer-Copy gewinnt. macOS stellt keine atomare Fokus-und-Paste-Operation bereit. Verzögerte Einfügeziele können nach dem 1,5-Sekunden-Fenster unklar bleiben.

Einstellungen und Wörterbuch: `~/Library/Application Support/Voice Wispr/settings.json`, atomar, versioniertes Exportformat. API-Schlüssel ausschließlich Keychain. Audio und die fünf letzten Resultate für den Schnellzugriff bleiben im Speicher. Bei eingeschaltetem Verlauf werden Diktattexte zusätzlich lokal in history.sqlite gespeichert; das lässt sich in der App abschalten. SDK-Transkript-Diagnosen und llama-Logs sind deaktiviert. Die App liest den fokussierten Text ausschließlich für lokale Zustellungsprüfung; er wird weder an ein Sprachmodell noch an Cloud gesendet.

## Stand und Nachweise

Siehe `docs/implementation-status.md` und `docs/verification-report.md`. Build-, Contract- und UI-Prüfungen sind getrennt von realem Mikrofon-/Modell-/App-Einfügenachweis. Keine behaupteten Leistungswerte ohne Messung.

Drittlizenzen und Modellkarten: `Resources/Licenses/`.
