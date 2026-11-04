# AInauten Voice mit einem Agent installieren

Für die normale Nutzung installierst du die veröffentlichte Beta. Du musst den Quellcode nicht kompilieren und brauchst keinen GitHub-Login oder Apple-Developer-Account.

## Voraussetzungen

Mac mit Apple Silicon (M1 oder neuer), macOS 14 oder neuer, mindestens 8 GB RAM; 16 GB empfohlen. Mindestens 8 GB freien Speicher für Modelle und Installation einplanen. Intel-Macs und andere Betriebssysteme werden nicht unterstützt.

## Auftrag an den Agent

> Installiere AInauten Voice auf meinem Mac. Verwende den veröffentlichten Download unter https://voice.ainauten.com/, prüfe seine SHA-256-Prüfsumme und erhalte eine eventuell bestehende Installation samt Einstellungen. Lies die Installationshinweise in diesem Repository. Sage mir danach, welche macOS-Freigaben ich noch selbst bestätigen muss.

## Schritte für den Agent

1. Plattform und vorhandene Installation prüfen. Wenn AInauten Voice läuft, den Nutzer bitten, die App regulär zu beenden. Keine Aufnahme unterbrechen oder Datenordner löschen.
2. Release-Metadaten von `https://voice.ainauten.com/downloads/release.json` laden. Verwende `filename`, `version` und `build` aus diesen Metadaten; keine alte Versionsnummer fest im Installationsskript hinterlegen. Datei ausschließlich vom zugehörigen HTTPS-Downloadpfad laden. Mit `size` und `sha256` aus den Metadaten vergleichen; zusätzlich die [Prüfsummen](https://voice.ainauten.com/downloads/SHA256SUMS.txt) prüfen. Bei Abweichung abbrechen.
3. DMG-Integrität prüfen, schreibgeschützt einbinden. Das enthaltene Bundle muss `AInauten Voice.app`, Bundle-ID `com.mediapublishing.VoiceWispr` und die Version aus den aktuellen Release-Metadaten tragen. Codesignatur prüfen. Eine gültige lokale Signatur bedeutet noch keine Apple-Notarisierung.
4. Eine bestehende App als datiertes Backup aufbewahren. Das neue Bundle nach Programme (`/Applications`, falls beschreibbar, sonst `~/Applications`) kopieren und die Kopie erneut prüfen. Symlinks im Bundle erhalten. Den Datenordner `~/Library/Application Support/Voice Wispr` und vorhandene Schlüsselbunddienste unverändert lassen. Keine doppelt gestarteten Versionen erzeugen. DMG anschließend auswerfen.
5. Dem Nutzer Installationspfad und geprüfte Version nennen. Der Nutzer öffnet die App und bestätigt die unten beschriebenen Freigaben. Die Einrichtung lädt die Modelle einmalig und führt zum Probediktat.

Der Agent kann für Integrität und Bundle-Prüfung die vorhandenen macOS-Werkzeuge `hdiutil`, `codesign` und `plutil` nutzen; zum Kopieren `ditto`. Keine fremden Installationsskripte ausführen und keine Sicherheitsfunktionen umgehen. Ein Downloadvergleich allein ist kein Nachweis für erfolgreiches Diktieren.

## macOS-Freigaben, die der Nutzer bestätigt

Die aktuelle Version ist mit Apple Developer ID signiert und Apple-notarisiert. Öffne die App aus Programme und bestätige gegebenenfalls den üblichen ersten Start einer heruntergeladenen App. Prüfe mit `spctl --assess --type execute` und `xcrun stapler validate`, dass die konkrete App zugelassen ist. Bei einer unerwarteten Sicherheitswarnung die Herkunft und Signatur prüfen, statt eine Ausnahme anzulegen. [Installationsanleitung](https://voice.ainauten.com/installation.html).

Danach Mikrofon und Bedienungshilfen für die tatsächlich installierte App erlauben. Bei abweichenden Warnungen über eine beschädigte oder schädliche App stoppen und Ursache prüfen. Keine globalen Sicherheitsregeln abschalten.

## Kompatibles Einfügen

Bei neuen Installationen ab 0.1.14 ist kompatibles Einfügen eingeschaltet. Dafür liegt diktierter Text kurz in der systemweiten Zwischenablage; andere lokale Apps können ihn dort lesen. Der vorherige Inhalt wird wiederhergestellt, solange keine neuere Kopieraktion erfolgt. Unter **Einstellungen → Datenschutz** kannst du die Option ausschalten. Gespeicherte Einstellungen bleiben erhalten, auch eine frühere Abschaltung oder ein älteres Profil ohne Freigabe. Ohne die Option werden nicht direkt unterstützte Textfelder nicht automatisch befüllt. Ein Agent darf eine vorhandene Wahl nicht still ändern.

## Updates und Entwicklungsbuilds

Der öffentliche Download **0.1.20, Build 27** enthält den signierten Updater. Automatische Suche und Downloads sind für neue Installationen standardmäßig aktiv; ein ausdrücklich gespeichertes Nein bleibt erhalten. Die App prüft täglich, installiert beim Beenden und unterbricht laufende Diktate nicht. Unter **Einstellungen → Updates** lassen sich die Automatik ausschalten und Updates sofort prüfen. Einstellungen, Wörterbuch und Verlauf bleiben erhalten.

Apps ohne Updater, insbesondere die frühere Beta 0.1.1, Build 2, benötigen einmalig den aktuellen Installer. Ein Git-Push oder eine Änderung der Website allein verteilt kein Update; dafür wird ein geprüftes App-Paket im signierten Kanal veröffentlicht. App und Installer durchlaufen vor der Veröffentlichung Apples Notarisierung.

Quellcode-Builds sind für Entwickler: siehe [native/README.md](../native/README.md). Sie können noch unveröffentlichte Funktionen enthalten und sind nicht mit der geprüften Download-Beta gleichzusetzen. Die Python-Werkzeuge dienen dem Build; Endnutzer benötigen keinen Python- oder Modellserver.
