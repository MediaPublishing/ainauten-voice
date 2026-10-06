# AInauten Voice: Oberflächensprache Deutsch und Englisch

Status: Spezifikation geprüft und angepasst, Umsetzung am 5. Oktober 2026 für Beta 0.1.7 (Build 11) verifiziert. [Umsetzung und Prüfbelege](ui-localization-2026-10-05.md). Die vollständige praktische Gesamtabnahme der Spracherkennung ist davon getrennt.

## Ziel

Die native Mac-App zeigt ihre Oberfläche auf Deutsch oder Englisch. Standardmäßig übernimmt sie die bevorzugte Sprache von macOS. Nutzer können die Oberflächensprache in der App selbst ändern; die Auswahl bleibt nach einem Neustart erhalten.

Die Sprache der Oberfläche ist unabhängig von den gesprochenen Sprachen. Ein englisches Interface darf weiterhin deutsche Diktate erkennen und optimieren. Ein Sprachwechsel verändert weder Inhalte noch Diktierverhalten.

## Bedienung und Sprachwahl

Eine kompakte Auswahl im bestehenden Einstellungsbereich „Diktieren“, oberhalb der Kürzel und deutlich getrennt von „Welche Sprachen sprichst du?“. Dafür keinen zusätzlichen Navigationspunkt und keinen zusätzlichen Einrichtungsschritt anlegen. Dieselbe Auswahl ist zusätzlich im nativen App-Menü erreichbar, damit offene Wörterbuch- und Fehlerbericht-Entwürfe beim Sprachwechsel erhalten bleiben. Beide Zugänge verwenden dieselbe Präferenz.

| Element | Deutsche Oberfläche | Englische Oberfläche |
| --- | --- | --- |
| Bezeichnung | Oberflächensprache | Interface language |
| Automatische Auswahl | Automatisch (Systemsprache) | Automatic (system language) |
| Deutsche Auswahl | Deutsch | Deutsch |
| Englische Auswahl | English | English |
| Kurzer Hilfetext | Ändert nur die Oberfläche. Deine Diktatsprachen bleiben erhalten. | Changes only the interface. Your dictation languages stay the same. |

Die Sprachnamen „Deutsch“ und „English“ bleiben in ihrer jeweiligen eigenen Sprache. Keine Flaggen für die Oberflächensprache: Englisch und Deutsch gehören jeweils zu mehreren Ländern. Der gesamte Auswahlbereich ist bedienbar, der Tastaturfokus sichtbar und die Auswahl mit VoiceOver verständlich.

Die Auswahl wird unmittelbar übernommen und gespeichert. App-eigene Fenster, Menüs, Hinweise und Tooltips wechseln ohne App-Neustart. Die aktuelle Seite, Scrollposition und ungespeicherte Eingaben bleiben erhalten. Kein zusätzliches Bestätigungsfenster. Falls das Speichern fehlschlägt, bleibt die bisher gespeicherte Auswahl wirksam und die App zeigt einen kurzen verständlichen Hinweis.

## Regeln für die automatische Auswahl

1. Gespeicherte Auswahl `de` oder `en` hat Vorrang vor der Systemsprache.
2. Bei `system` die von macOS für die App gelieferte Reihenfolge bevorzugter Sprachen verwenden. Eine in macOS hinterlegte Sprache für diese App berücksichtigen.
3. Den ersten unterstützten Sprachcode dieser Reihenfolge wählen. Regionale Varianten normalisieren: `de-DE`, `de-CH` und `de-AT` ergeben Deutsch; `en-US` und `en-GB` ergeben Englisch.
4. Wenn keine bevorzugte Sprache unterstützt wird, Englisch verwenden. Beispiel: `[fr-FR, de-DE]` ergibt Deutsch; `[fr-FR, es-ES]` ergibt Englisch.
5. Für neue und bestehende Installationen ohne gespeicherte Auswahl gilt `system`. Unbekannte oder beschädigte Werte werden als `system` behandelt und blockieren den App-Start nicht.
6. Änderungen der macOS-Sprache werden bei automatischer Auswahl spätestens beim nächsten App-Start wirksam. Die manuelle Auswahl bleibt dabei erhalten.

Die Sprachentscheidung darf nicht aus den ausgewählten Diktatsprachen, dem Wörterbuch, Wispr-Flow-Importen oder erkannten Texten abgeleitet werden.

## Übersetzungsumfang

Alle von der App selbst erzeugten Bedienungs- und Rückmeldungstexte werden übersetzt:

- Navigation, Übersicht, Verlauf, Statistik, Diktieren und Einrichtung.
- Wörterbuchoberfläche, Textmodi, Spracheinstellungen und Wispr-Flow-Import samt Ergebnisanzeige.
- Datenschutz, Updates, Beta-Funktionen und Hilfe einschließlich Fehlerbericht-Formular und Kaffee-Link.
- App-Menü und Menüleisten-Menü, Fenster- und Dialogtitel, Schaltflächen, Platzhalter und Bestätigungen.
- Aufnahme-Pill, Ergebnis-Overlay, Statusmeldungen und verständliche Fehlermeldungen.
- Mouse-over-Texte, VoiceOver-Bezeichnungen, Tastennamen wie „Leertaste“/„Space“ und Hinweise zu Berechtigungen.
- App-eigene Mikrofon- und Kamera-Begründungstexte über lokalisierte `InfoPlist.strings`.

Dynamische Werte bleiben erhalten: App-Namen, Versionsnummern, Dateipfade, URLs, Marken, Tastenkombinationen und technische Fehlercodes. Datumswörter wie „Heute“/„Today“ und Monatsnamen folgen der Oberflächensprache. Regionale Zahlen- und Zeitformate sowie die Zeitzone folgen weiterhin den macOS-Einstellungen. Keine fest codierte deutsche Region für die gesamte Oberfläche.

Bestehende Diktate, Originaltexte, Wörterbucheinträge, Ersetzungen, Benutzerbeschreibungen in Fehlerberichten und exportierte Nutzerdaten werden nicht übersetzt. Technische Rohberichte, Logs und der bestehende statische Prüfbericht behalten ihren Originalinhalt; die Bedienung um diese Inhalte wird übersetzt.

Von macOS oder Fremdframeworks verwaltete Dialoge können weiterhin der dort verwendeten Sprache folgen. Das betrifft beispielsweise den Rahmen von Berechtigungsdialogen und Sparkle-Dialoge. Keine globale macOS-Sprache oder fremde Framework-Ressourcen verändern, um die manuelle Auswahl zu erzwingen.

## Technische Umsetzung

Bestehendes SwiftUI/AppKit und Apples Lokalisierungsmechanismen verwenden. Keine neue Bibliothek, kein Übersetzungsdienst und keine Netzwerkverbindung.

### Lokale Präferenz

Eine eigene App-Präferenz `interfaceLanguage` mit den Werten `system`, `de` und `en` in `UserDefaults` speichern. Die vorhandene Bundle-ID und der lokale Datenordner bleiben erhalten. Die Präferenz nicht in die Liste der Erkennungssprachen aufnehmen. Wispr-Flow-Import und dessen Rückgängig-Funktion verändern diese Auswahl nicht. Keine Änderung am Format vorhandener Diktate oder Wörterbücher erforderlich. Die native Präferenz wird gesetzt und unmittelbar zurückgelesen. Bei einer erkennbaren Speicherstörung bleibt die vorherige Auswahl wirksam; ein synchrones Schreiben auf Datenträger wird nicht versprochen.

### Übersetzungsressourcen

Für den vorhandenen SwiftPM-/CLI-Build lokalisierte `de.lproj/Localizable.strings` und `en.lproj/Localizable.strings` einbinden; bei Pluralformen passende `.stringsdict` ergänzen. Englisch ist die vollständige Basissprache. Im App-Bundle beide unterstützten Sprachen deklarieren und lokalisierte `InfoPlist.strings` aufnehmen. Das Paket muss unabhängig vom Arbeitsverzeichnis funktionieren. Die zentrale Schicht liegt in `VoiceWisprCore`; SwiftPM verarbeitet dessen separate `Localization`-Ressourcen mit `.process`. Der Paketierer übernimmt das Ressourcenbundle sowie die beiden `InfoPlist.strings` in das Hauptbundle.

Eine kleine zentrale Lokalisierungsschicht liefert die wirksame Sprache und übernimmt die Übersetzungsauflösung für SwiftUI und AppKit. Explizite manuelle Sprachwahl auch bei Texten außerhalb von SwiftUI berücksichtigen. Stabile semantische Schlüssel verwenden, beispielsweise `navigation.history`, `dictation.ready` und `settings.interfaceLanguage`. Dynamische Werte über lokalisierbare Platzhalter einsetzen; keine Sätze aus einzeln übersetzten Fragmenten zusammensetzen.

Fehlende deutsche Übersetzungen fallen auf die englische Basis zurück und werden bei der Entwicklungsprüfung erkannt. Vollständige Schlüsselabdeckung, passende Platzhalter und Pluralformen sind vor der Abnahme zu prüfen. Im Nutzerinterface keine rohen Übersetzungsschlüssel anzeigen.

### Zustände und bestehende Abläufe

Einige Abläufe vergleichen derzeit deutsche Statusmeldungen direkt, etwa die Rückkehr aus „Keine Sprache erkannt“. Vor der Übersetzung diese betroffenen Vergleiche auf stabile Zustände oder Meldungskennungen umstellen. Sichtbare Texte dürfen keine Bedingungen für Aufnahme, Timer, Hotkey oder Einfügen sein.

App-eigene Menüs beim Sprachwechsel aktualisieren. Aktuelle Rückmeldungen aus ihren Kennungen und Werten neu darstellen. Bestehende app-eigene Diagnosemeldungen dürfen an der UI-Grenze über semantische Ressourcen aufgelöst werden; diese Kompatibilitätsschicht darf nie Nutzerdiktate, Formularbeschreibungen oder Rohberichte übersetzen. Unbekannte Framework-Fehler bleiben als technische Details erhalten. Dabei keine Aufnahme abbrechen, Modelle neu laden, Hotkeys neu aufzeichnen, den Eingabefokus übernehmen oder Text erneut einfügen. Erkennungs-, Optimierungs- und Lippenlese-Prompts bleiben unverändert.

### Betroffene Bereiche im aktuellen Code

- `native/Package.swift`: Sprachressourcen für die App einbinden.
- `native/Resources/Info.plist` und Paketierung: unterstützte Sprachen und Begründungstexte im fertigen Bundle.
- `native/Sources/VoiceWispr/Settings.swift`: kompakte Auswahl und lokalisierte Einstellungsoberfläche.
- `AppModel.swift`, `Pill.swift`, `HistoryViews.swift`, `DictionaryEditor.swift`, `ErrorReportView.swift`, `UpdateSettingsView.swift` und `ReportView.swift`: eigene Beschriftungen und Rückmeldungen.
- An der Grenze zu `VoiceWisprCore`: sichtbare Namen und Meldungen lokalisieren, interne Enum-Werte und gespeicherte Daten stabil halten. Insbesondere `TextStyle.title`, Tastennamen und Fehlerbeschreibungen prüfen.
- `native/scripts/package.py` und vorhandene Bundle-Prüfungen: sicherstellen, dass Sprachressourcen auch im ausgelieferten Paket vorhanden und erreichbar sind.

## Abnahme

| Fall | Erwartetes Ergebnis |
| --- | --- |
| Bestehendes Profil ohne neue Präferenz | Startet mit automatischer Auswahl; alle bisherigen Inhalte und Einstellungen bleiben erhalten. |
| Automatisch, bevorzugt `de-CH` | Deutsche Oberfläche. |
| Automatisch, bevorzugt `en-GB` | Englische Oberfläche. |
| Automatisch, Liste `[fr-FR, de-DE]` | Deutsche Oberfläche. |
| Automatisch, keine unterstützte bevorzugte Sprache | Englische Oberfläche. |
| Deutsch manuell auf englischem Mac | Deutsche App-Oberfläche, auch nach Neustart. |
| English manuell auf deutschem Mac | Englische App-Oberfläche, auch nach Neustart. |
| Zurück zu Automatisch | Erneute Auswahl anhand der bevorzugten macOS-Sprachen. |
| Unbekannter gespeicherter Wert | Startet mit automatischer Auswahl; kein Einstellungs- oder Startfehler. |
| Wechsel bei geöffnetem Wörterbucheintrag oder Fehlerformular | Sprache ändert sich; Seite und ungespeicherte Eingaben bleiben erhalten. |
| Wechsel während Aufnahme oder Verarbeitung | Diktat läuft weiter; kein Modell-Neuladen und kein erneutes Einfügen. |
| Englische Oberfläche, deutsches Diktat | Erkennung und Optimierung bleiben deutsch; Inhalt und Marken wie „AInauten“ bleiben erhalten. |
| Wispr-Flow-Import samt Rückgängig | Oberflächensprache bleibt unverändert. |
| Status „Keine Sprache erkannt“ in beiden Sprachen | Gleicher Zustandswechsel, gleiche Hotkey-Verfügbarkeit und gleiche Pill-Sichtbarkeit. |
| Deutsche Übersetzung fehlt in einer isolierten Testressource | Englischer Ersatztext; kein Schlüssel und kein leeres Bedienelement. |
| Fertiges App-Paket außerhalb des Repos | Beide Sprachen und lokalisierte Berechtigungsbegründungen vorhanden; keine Abhängigkeit von Entwicklungsdateien. |

Gezielte automatisierte Prüfungen für Sprachauflösung, Speicherung, alte Profile, Platzhalter und Schlüsselabdeckung verwenden. Diktierabläufe mit isolierten Beispieldaten in beiden Oberflächensprachen prüfen. Keine echten Diktate oder privaten Wörterbücher als Fixtures verwenden.

Screenshot-QA in Deutsch und Englisch, jeweils hell und dunkel sowie bei Standard- und Mindestfenstergröße. Mindestens Navigation, Einrichtung, Kürzel, Verlauf, Hilfe und Ergebnis-Overlay prüfen. Texte dürfen nicht abgeschnitten werden; größere englische oder deutsche Beschriftungen dürfen die Klickflächen nicht verkleinern. Native Menüs und VoiceOver gesondert prüfen.

Abnahmebeleg: Commit/Dateien, Ergebnis der gezielten Prüfungen, Screenshots und Paketprüfung. Ein grüner Build allein bestätigt noch keine vollständige Lokalisierung.

## Umsetzung in vier Schritten

1. Sprachauflösung, lokale Präferenz und Ressourcenpaket mit gezielten Prüfungen aufbauen.
2. App-Oberfläche, native Menüs und Meldungen übersetzen; betroffene Statusvergleiche von sichtbaren Texten trennen.
3. Bestehende Profile und Diktierabläufe in beiden Sprachen prüfen, Screenshot-QA durchführen.
4. Fertiges App-Paket auf Ressourcenauflösung prüfen und die Umsetzung mit Abnahmebelegen dokumentieren.

## Abgrenzung

Dieser Punkt umfasst ausschließlich Deutsch und Englisch für die native App-Oberfläche. Website, README, Installationsseite und DMG-Anleitung benötigen bei Bedarf einen eigenen Übersetzungspunkt. Keine weiteren Erkennungssprachen, keine automatische Übersetzung von Diktaten, kein erneuter Wispr-Flow-Import und keine Änderung der Freigaben oder Update-Einstellungen.

Technische Referenz: [Apple: Preparing your app’s text for translation](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation).
