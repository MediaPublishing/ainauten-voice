# AInauten Voice: Installation und Entwicklung

Dieses Repository ist öffentlich. Quellcode einsehen ist ohne GitHub-Anmeldung möglich. Der eigene App-Code hat derzeit keine Open-Source-Lizenz; Lizenzen der Abhängigkeiten gelten separat.

## Wenn der Nutzer die App installieren möchte

Lies [docs/agent-installation.md](docs/agent-installation.md). Verwende für die normale Installation den veröffentlichten DMG-Download von https://voice.ainauten.com/, nicht einen Entwicklungsbuild. Prüfe die veröffentlichten SHA-256-Metadaten vor dem Kopieren. Erhalte vorhandene App und Einstellungen. Bestätige keinen Erfolg, bevor das installierte Bundle geprüft wurde.

Mikrofon, Bedienungshilfen und die erste macOS-Startbestätigung erfordern eine bewusste Nutzeraktion. Keine Gatekeeper-, Quarantäne- oder TCC-Schutzmechanismen abschalten. Keine neuen Signaturidentitäten oder Cloud-Zugänge für eine normale Installation anlegen. Kamerafunktionen und automatische Fehlerübermittlung bleiben standardmäßig aus.

## Wenn der Nutzer entwickeln möchte

Die native App liegt in `native/`, die Downloadseite in `site/`, der Fehlerempfang in `reporting/`. Lies `native/README.md` und `native/docs/implementation-status.md`. Bewahre Bundle-ID `com.mediapublishing.VoiceWispr`, Modul `VoiceWispr`, Datenordner `~/Library/Application Support/Voice Wispr` und bestehende Schlüsselbunddienste.

Prüfungen: `python3 native/scripts/portable-checks.py`; echte Swift-/XCTest-Tests benötigen die passende Apple-Entwicklungsumgebung. Nach Codeänderungen gezielt prüfen. Nie fremde Änderungen zurücksetzen oder private Diktate, Wörterbücher, Profile, Audio, Schlüssel, `.local/`, Modellgewichte oder generierte App-Pakete committen. Screenshots zeigen ausschließlich gekennzeichnete Beispieldaten.

Entwicklungsstand und öffentlicher Download sind getrennt: Der Download 0.1.4, Build 8 enthält den signierten Updater. Automatische Updates sind standardmäßig aktiv; eine ausdrücklich gespeicherte Abschaltung bleibt erhalten. Ältere Apps ohne Updater benötigen einmalig den aktuellen Installer. Forschungsmodelle bleiben außerhalb des Downloads. Der private Fehlerempfang ist aktiv; automatische Meldungen und AI-Bearbeitung bleiben aus. Ein Git-Push allein verteilt kein App-Update.
