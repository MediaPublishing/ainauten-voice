# AInauten Voice mit einem Agent installieren

Für die normale Nutzung installierst du die veröffentlichte Beta. Du musst den Quellcode nicht kompilieren und brauchst keinen GitHub-Login oder Apple-Developer-Account.

## Voraussetzungen

Mac mit Apple Silicon (M1 oder neuer), macOS 14 oder neuer, mindestens 8 GB RAM; 16 GB empfohlen. Mindestens 8 GB freien Speicher für Modelle und Installation einplanen. Intel-Macs und andere Betriebssysteme werden nicht unterstützt.

## Auftrag an den Agent

> Installiere AInauten Voice auf meinem Mac. Verwende den veröffentlichten Download unter https://voice.ainauten.com/, prüfe seine SHA-256-Prüfsumme und erhalte eine eventuell bestehende Installation samt Einstellungen. Lies die Installationshinweise in diesem Repository. Sage mir danach, welche macOS-Freigaben ich noch selbst bestätigen muss.

## Schritte für den Agent

1. Plattform und vorhandene Installation prüfen. Wenn AInauten Voice oder Voice Wispr läuft, den Nutzer bitten, die App regulär zu beenden. Keine Aufnahme unterbrechen oder Datenordner löschen.
2. Release-Metadaten von `https://voice.ainauten.com/downloads/release.json` laden. Die aktuelle Beta heißt `AInauten-Voice-0.1.1-arm64.dmg`, Version 0.1.1, Build 2. Datei ausschließlich vom zugehörigen HTTPS-Downloadpfad laden. Mit `size` und `sha256` aus den Metadaten vergleichen; zusätzlich die [Prüfsummen](https://voice.ainauten.com/downloads/SHA256SUMS.txt) prüfen. Bei Abweichung abbrechen.
3. DMG-Integrität prüfen, schreibgeschützt einbinden. Das enthaltene Bundle muss `AInauten Voice.app`, Bundle-ID `com.mediapublishing.VoiceWispr` und Version 0.1.1 tragen. Codesignatur prüfen. Eine gültige lokale Signatur bedeutet noch keine Apple-Notarisierung.
4. Eine bestehende App als datiertes Backup aufbewahren. Das neue Bundle nach Programme (`/Applications`, falls beschreibbar, sonst `~/Applications`) kopieren und die Kopie erneut prüfen. Symlinks im Bundle erhalten. Den Datenordner `~/Library/Application Support/Voice Wispr` und vorhandene Schlüsselbunddienste unverändert lassen. Keine doppelt gestarteten Versionen erzeugen. DMG anschließend auswerfen.
5. Dem Nutzer Installationspfad und geprüfte Version nennen. Der Nutzer öffnet die App und bestätigt die unten beschriebenen Freigaben. Die Einrichtung lädt die Modelle einmalig und führt zum Probediktat.

Der Agent kann für Integrität und Bundle-Prüfung die vorhandenen macOS-Werkzeuge `hdiutil`, `codesign` und `plutil` nutzen; zum Kopieren `ditto`. Keine fremden Installationsskripte ausführen und keine Sicherheitsfunktionen umgehen. Ein Downloadvergleich allein ist kein Nachweis für erfolgreiches Diktieren.

## macOS-Freigaben, die der Nutzer bestätigt

Die Beta ist noch nicht Apple-notarisiert. Falls macOS „Apple konnte die App nicht überprüfen“ meldet: **Fertig (Done)** wählen, dann **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen (Open Anyway)** und anschließend **Öffnen (Open)** bestätigen. Die Option erscheint nach dem ersten Öffnungsversuch aus Programme. [Anleitung mit Abbildungen](https://voice.ainauten.com/installation.html); auch offline im DMG unter **00 - ZUERST LESEN.html**.

Danach Mikrofon und Bedienungshilfen für die tatsächlich installierte App erlauben. Bei abweichenden Warnungen über eine beschädigte oder schädliche App stoppen und Ursache prüfen. Keine globalen Sicherheitsregeln abschalten.

## Updates und Entwicklungsbuilds

Der signierte Updatekanal ist eingerichtet, bietet derzeit aber noch kein neues Release an. Der öffentliche Download 0.1.1, Build 2 enthält noch keinen Updater. Für diese Version ist einmalig der nächste updatefähige Installer nötig; danach lässt sich die automatische Suche samt Download in **Einstellungen → Updates** einschalten. Installiert wird beim Beenden/Neustart. Einstellungen, Wörterbuch und Verlauf bleiben erhalten.

Quellcode-Builds sind für Entwickler: siehe [native/README.md](../native/README.md). Sie können noch unveröffentlichte Funktionen enthalten und sind nicht mit der geprüften Download-Beta gleichzusetzen. Die Python-Werkzeuge dienen dem Build; Endnutzer benötigen keinen Python- oder Modellserver.
