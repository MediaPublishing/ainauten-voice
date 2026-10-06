# Sicherheitsnachprüfung: Bibliotheken, Zwischenablage, Apple-Verteilung

Der zu Beginn dieser Nachprüfung veröffentlichte Download 0.1.10 (14) und die damalige Installation waren lokal signiert und nicht Apple-notarisiert. Sie enthalten die Ausnahme für Bibliotheksvalidierung. Die folgenden Änderungen sind Quellcode-Korrekturen für den nächsten Kandidaten; ein Git-Push ersetzt diesen Download nicht.

## Zwischenablage

Automatisches Einfügen und automatisches Kopieren eines Wiederherstellungsergebnisses verwenden die systemweite Zwischenablage nur mit `clipboardCompatibility == true`. Neue Profile und ältere Profile ohne diesen Schlüssel sind standardmäßig ausgeschaltet. Eine ausdrücklich gespeicherte Freigabe bleibt erhalten. Der Standard des Zustellungs-API ist ebenfalls ausgeschaltet. Die Datenschutzseite erklärt das lokale Mitlesen durch andere Apps auf Deutsch und Englisch.

TextEdit unterstützt die bestehende direkte Einfügung über Bedienungshilfen. Andere Felder können mit ausgeschalteter Kompatibilitätsoption das Ergebnis nur in der App erhalten. Explizites Kopieren bleibt möglich. Es gibt keine sichere allgemeine macOS-Zwischenablage ausschließlich für diese App; die Kompatibilitätsoption ist deshalb eine bewusste Abwägung zwischen Datenschutz und Unterstützung weiterer Textfelder.

## Signierung und Notarisierung

Im Apple-Verteilungsweg werden Pakete, Update-Archive und Website-Release-Builds ohne Apple Developer ID Application, Hardened Runtime, aktive Bibliotheksvalidierung und überprüfte Notarisierung abgewiesen. Alle tatsächlichen Mach-O-Dateien im Bundle müssen mit derselben Apple-Team-ID signiert sein. Debugging- und Code-Injection-Ausnahmen sind für die Verteilung gesperrt. Die bestehende Publisher-Pin-Prüfung bleibt zusätzlich erhalten.

`package.py` verlangt im öffentlichen Modus ein bestehendes `--notary-profile`. Der Ablauf signiert die verschachtelten Komponenten mit sicherem Zeitstempel, notarisiert die App, verlangt Apples Status `Accepted`, heftet das Ticket an und überprüft es. Anschließend wird die finale DMG separat signiert, eingereicht, angeheftet und geprüft. Update-Archive entstehen erst aus der so geprüften App. Fehlende Zugangsdaten oder abgelehnte Einreichungen sind kein Erfolg; die Artefakte bleiben zur Diagnose erhalten.

Lokale Entwicklung muss ausdrücklich `--development` verwenden. Die lokale Ausnahme ist nur dafür erhalten und passiert weder den öffentlichen Update- noch den Website-Verifizierer. Die Ausnahme einfach zu entfernen würde beim bisherigen lokalen Zertifikat die eingebundenen Frameworks am Laden hindern; sie ist damit noch nicht im bereits veröffentlichten Build behoben.

### Noch erforderliche Apple-Einrichtung

Auf diesem Mac wurde nur die vorhandene lokale Identität gefunden, keine gültige Developer ID Application. Für die tatsächliche Auslieferung fehlen deshalb ein gültiges Apple-Zertifikat mit privatem Schlüssel und ein genehmigtes Notarytool-Schlüsselbundprofil. Keine Identität, Mitgliedschaft oder Zugangsdaten wurden angelegt.

Nach der separat freigegebenen Einrichtung müssen der öffentliche Publisher-Fingerprint und die lokale Signaturauswahl auf dieselbe überprüfte Apple-Identität umgestellt werden. Der Sparkle-Updateschlüssel bleibt erhalten. Der Signaturwechsel kann eine erneute Bestätigung der macOS-Freigaben verlangen und benötigt einen echten Upgrade-Test.

```sh
# Vorhandene, freigegebene Apple-Identität und Notarytool-Profil erforderlich.
python3 native/scripts/package.py --notary-profile ainauten-voice-notary \
  --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk

# Ausschließlich lokales Testpaket; keine öffentliche Verteilung.
python3 native/scripts/package.py --development \
  --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

Apple beschreibt [Bibliotheksvalidierung](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation) und den [Notarisierungsablauf](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). Eigene Nachweise liegen lokal unter `native/artifacts/receipts/peter-security-20261006/`. Die Modellqualität, physische Einfüge-Latenz, weitere Geräte und die früheren optionalen Abhängigkeitsbefunde bleiben gesondert offen. Diese gezielte AI-gestützte Nachprüfung ersetzt keinen professionellen Sicherheitsaudit.

## Prüfung des tatsächlich veröffentlichten Pakets

Installer und Update-Archiv für 0.1.10 (14) wurden erneut heruntergeladen und geprüft. Die 168 Bundle-Einträge stimmen einschließlich Dateiinhalten, Dateimodi und internen Links überein. Die Ed25519-Signaturen des Update-Archivs und des Appcasts sind mit dem öffentlichen Updateschlüssel gültig; dafür wurde kein privater Schlüssel gelesen. Diese Updatesignaturen ersetzen keine Apple Developer ID oder Notarisierung.

Das tatsächliche Paket verwendet weiterhin die lokale Signatur ohne Apple-Team-ID, enthält `com.apple.security.cs.disable-library-validation = true` und hat weder ein angeheftetes App- noch DMG-Notarisierungsticket. Der veröffentlichte Quellstand enthält weiterhin die eingeschaltete Zwischenablage-Voreinstellung. Eine neue Veröffentlichung bleibt deshalb gesperrt, bis die Apple-Voraussetzungen erfüllt sind.

Der Release-Prüfer fordert die Entitlements jetzt ausdrücklich als XML an; aktuelle macOS-Versionen liefern sonst eine Textdarstellung, die kein Property List Parser lesen kann. Zwölf gezielte Regressionstests prüfen diesen Pfad einschließlich des echten lokalen Bundles. Für den vorherigen Sicherheitscommit waren keine GitHub-Check-Runs oder Commit-Statusmeldungen vorhanden; ein erfolgreicher lokaler Test ist kein CI-Nachweis.

## Freigegebenes Zwischenrelease 0.1.11 (15)

Auf ausdrücklichen Betreiberauftrag wird die nicht notarisierte Beta weitergeführt, während die Apple-Einrichtung aussteht. Dafür ist `--local-beta` in Paket-, Update- und Website-Build ausdrücklich erforderlich. Das Bundle trägt den signierten Modus `local-beta`. Der getrennte Apple-Verteilungsweg und seine Prüfungen bleiben unverändert streng. Ad-hoc-, Debug- und Entwicklungsbuilds sind keine Beta-Releases.

Die Beta prüft weiterhin den vorhandenen Publisher-Fingerprint, alle tatsächlichen Mach-O-Dateien, Hardened Runtime, Bundle-Identität und interne Links. Nur die bestehende Bibliotheksvalidierungs-Ausnahme des Hauptprogramms ist erlaubt; weitere Code-Injection-Ausnahmen und solche Ausnahmen in verschachtelten Komponenten werden abgewiesen. Dieser Paketnachweis verhindert keine Code-Injection zur Laufzeit und ersetzt keine aktive Apple-Bibliotheksvalidierung.

Die automatische Zwischenablage-Nutzung ist im ausgelieferten Quellstand standardmäßig aus. Eine vorher ausdrücklich gespeicherte Aktivierung bleibt erhalten. Bibliotheksvalidierung und Apple-Notarisierung bleiben in diesem Zwischenrelease offen; Website, README, Nutzerprüfbericht und Release-Hinweise benennen dies.
