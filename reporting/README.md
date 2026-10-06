# Optionaler privater Fehlereingang

Der private Fehlerempfang ist ab Beta 0.1.4, Build 8 aktiviert und bis zur privaten GitHub-Inbox mit synthetischen Berichten geprüft. Automatische Meldungen bleiben standardmäßig aus; manuelle Meldungen benötigen eine sichtbare Vorschau und ausdrückliche Zustimmung. Audio, Diktate, Wörterbuch, Zwischenablage, Pfade und Gerätekennungen gehören nicht zum technischen Bericht.

Der Collector validiert ein begrenztes Schema, bestätigt erst nach Speicherung und sendet technische Angaben ausschließlich an eine private GitHub-Inbox. Freiwillige Beschreibung und Kontakt bleiben im privaten Eingang mit 30-Tage-Aufbewahrung. Unklarer Ausgang eines Issue-Versuchs führt nicht zu einem blinden zweiten Versuch. Authentisierung und Infrastruktur sind Betreibersache; kein GitHub-Schlüssel liegt im Client oder Quellcode. Die öffentliche Quellcode-Freigabe macht die separate Fehler-Inbox nicht öffentlich.

`worker.mjs`, `wrangler.toml` und die Tests dokumentieren die Implementierung. Die Betreiberkonfiguration ist aktiviert; ohne die separat provisionierten serverseitigen Secrets bleibt sie geschlossen. Für einen eigenen Betreiberbetrieb sind eigene private Infrastruktur, gesonderte eng begrenzte Schlüssel und eine geprüfte Datenschutz-/Zustimmungsoberfläche erforderlich. Nicht für eine normale App-Installation deployen.

Prüfen: `node --test reporting/tests.mjs reporting/automation/tests.mjs` aus dem Repository-Root. Lokale Tests nutzen synthetische Angaben und keine produktiven Schlüssel. Die [Analysevorlage](automation/README.md) läuft nicht als Hintergrundjob.

Der Collector akzeptiert nur freigegebene Version-/Build-Paare. Die Liste enthält auch 0.1.7 (11), 0.1.8 (12) und 0.1.9 (13). Die Vertragsprüfung liest zusätzlich die aktuelle App-Version aus `native/Resources/Info.plist` und schlägt fehl, wenn sie vom Collector abgewiesen würde. Bei einem neuen App-Release müssen Freigabeliste und Collector vor der Auslieferung mit aktualisiert werden; unbekannte oder falsch kombinierte Versionen bleiben gesperrt.
