# Startabsturz beim Laden der Sprachdateien

Hotfix 0.1.8, Build 12 korrigiert einen Startabsturz der Version 0.1.7, Build 11. Der gemeldete Stack endet bei `NSBundle.module` über `L10n.bundle`, `L10n.diagnostics` und `AppModel.init`.

## Ursache und Änderung

SwiftPM erzeugt einen Modulzugriff, der neben dem Hauptbundle und anschließend im Entwicklungs-Buildordner sucht. Der Paketierer legt die Sprachdateien korrekt in `Contents/Resources/VoiceWispr_VoiceWisprCore.bundle` ab. Die Sprachschicht verwendete jedoch den generierten Zugriff. Auf dem Entwicklungs-Mac konnte der lokale Buildordner diesen Fehler verdecken; auf einer normalen Installation führte der fehlende Rückfallpfad zu einer Swift-Assertion.

Eine gepackte App lädt ihre Sprachdateien jetzt ausdrücklich aus ihrem Ressourcenordner. Bei fehlenden Dateien liefert die Sprachschicht einen kontrollierten Ersatztext. CLI-/SwiftPM-Prüfungen behalten ihren bisherigen Ressourcenzugriff.

Der tatsächliche Release enthält eine ausschließlich lesende Paketprüfung vor AppModel, Kürzeln und Modellinitialisierung. `--check-bundled-resources` lädt Deutsch, Englisch, Pluralformen, den Diagnosekatalog und das Modellmanifest aus dem App-Paket. Paketierer und Release-Verifikation führen sie vor Annahme des Pakets aus.

## Regression und Grenzen

Der native kontrollierte Test mit nicht verfügbarem Entwickler-Modulzugriff reproduziert die bisherige Assertion sowohl bei vorhandenem App-Katalog als auch bei fehlenden Dateien. Der korrigierte Quellstand besteht beide Fälle. Die vorhandenen sieben Sprach-Vertragsfälle und 753 übereinstimmende englische/deutsche Katalogschlüssel bestehen ebenfalls. Das ist ein CLT-Vertragslauf, kein Apple-XCTest-Lauf.

Eine separate Prüfung des signierten Pakets muss den eingebauten Entwickler-Ressourcenpfad vorübergehend unzugänglich machen und anschließend wiederherstellen. Sie prüft außerdem den verschobenen App-Pfad und die kontrollierte Ablehnung fehlender App-Ressourcen. Diese Ressourcenprüfung ersetzt keinen praktischen M1-/macOS-27.2-, Mikrofon-, Erkennungs- oder Einfügetest.

## Falls Version 0.1.7 nicht mehr startet

Den aktuellen Installer von https://voice.ainauten.com/ herunterladen und die bisherige App ersetzen. Einstellungen, Wörterbuch und Verlauf bleiben erhalten. Eine App, die beim Start abstürzt, kann das automatische Update nicht selbst ausführen.
