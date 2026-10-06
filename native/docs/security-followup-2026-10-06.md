# Sicherheitsnachprüfung: Bibliotheken, Zwischenablage, Apple-Verteilung

Der öffentliche Download 0.1.10 (14) und die bisher installierte App sind weiterhin lokal signiert und nicht Apple-notarisiert. Sie enthalten die Ausnahme für Bibliotheksvalidierung. Die folgenden Änderungen sind Quellcode-Korrekturen für den nächsten Kandidaten; ein Git-Push ersetzt diesen Download nicht.

## Zwischenablage

Automatisches Einfügen und automatisches Kopieren eines Wiederherstellungsergebnisses verwenden die systemweite Zwischenablage nur mit `clipboardCompatibility == true`. Neue Profile und ältere Profile ohne diesen Schlüssel sind standardmäßig ausgeschaltet. Eine ausdrücklich gespeicherte Freigabe bleibt erhalten. Der Standard des Zustellungs-API ist ebenfalls ausgeschaltet. Die Datenschutzseite erklärt das lokale Mitlesen durch andere Apps auf Deutsch und Englisch.

TextEdit unterstützt die bestehende direkte Einfügung über Bedienungshilfen. Andere Felder können mit ausgeschalteter Kompatibilitätsoption das Ergebnis nur in der App erhalten. Explizites Kopieren bleibt möglich. Es gibt keine sichere allgemeine macOS-Zwischenablage ausschließlich für diese App; die Kompatibilitätsoption ist deshalb eine bewusste Abwägung zwischen Datenschutz und Unterstützung weiterer Textfelder.

## Signierung und Notarisierung

Neue öffentliche Pakete, Update-Archive und Website-Release-Builds werden ohne Apple Developer ID Application, Hardened Runtime, aktive Bibliotheksvalidierung und überprüfte Notarisierung abgewiesen. Alle tatsächlichen Mach-O-Dateien im Bundle müssen mit derselben Apple-Team-ID signiert sein. Debugging- und Code-Injection-Ausnahmen sind für die Verteilung gesperrt. Die bestehende Publisher-Pin-Prüfung bleibt zusätzlich erhalten.

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
