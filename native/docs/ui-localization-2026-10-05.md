# Deutsche und englische Oberfläche

Beta 0.1.7 (Build 11) ergänzt Deutsch und Englisch für die native App. Die [Spezifikation](ui-localization-spec.md) wurde vor der Umsetzung präzisiert: Ressourcen werden im SwiftPM-Bundle mitgeliefert, bestehende app-eigene Diagnosemeldungen an der UI-Grenze übersetzt und Sprachwechsel von offenen Entwürfen auch über das native App-Menü ermöglicht.

## Bedienung

Unter **Einstellungen → Diktieren → Oberflächensprache** stehen **Automatisch (Systemsprache)**, **Deutsch** und **English** bereit. Dieselbe Auswahl findest du im nativen App-Menü. Sie wirkt sofort und bleibt nach einem Neustart erhalten. Automatisch verwendet die erste unterstützte bevorzugte macOS-Sprache, bei keiner passenden Sprache Englisch.

Die Auswahl wird getrennt von den Diktateinstellungen gespeichert. Gesprochene Sprachen, Kürzel, Wörterbuch, Verlauf, eigene Texte und Erkennungs-/Optimierungs-Prompts bleiben erhalten. Native Menüs, eigene Meldungen und Bedienhilfen wechseln mit der Oberfläche; technische Rohberichte und externe Dokumentation bleiben im Original.

## Verifikation am 5. Oktober 2026

- 753 übereinstimmende englische/deutsche Ressourcenschlüssel einschließlich Platzhalter- und Pluralprüfung.
- 97 gezielte Vertragsfälle, 0 Fehler: Sprachauflösung, Speicherung/Rollback, fehlende Übersetzung, Wörterbuch-/Importgrenzen, Probediktat, Hotkey-/Feedbackzustände und Verarbeitung. Dies sind portable Swift-Vertragsprüfungen, kein Apple-XCTest-Lauf.
- Native Debug- und Release-Builds mit kompatiblem macOS SDK 26.5 und SwiftPM.
- Echte isolierte App-Vorschauen in Deutsch/Englisch, hell/dunkel und Standard-/kleiner Fenstergröße: Navigation, Einrichtung, Probediktat, Kürzel, Verlauf, Statistik, Wörterbuch, Hilfe und Ergebnisfenster. Screenshots wurden inline in der UI-Prüfung betrachtet; keine separaten Screenshotdateien werden als Beleg behauptet.
- Live-Sprachwechsel mit unveränderter Seite und unveränderten Diktatsprachen. Offene synthetische Wörterbuch- und Fehlerberichtentwürfe bleiben beim Wechsel über das App-Menü erhalten.
- Separater Prover und unabhängiger Release-Checker bestätigen die Umsetzung. Beide Sprachressourcen und lokalisierten Berechtigungsbegründungen sind im fertigen Bundle enthalten. Signatur und eingebettete App im DMG wurden geprüft.
- Lokale Installation mit erhaltener App-Identität; vorhandene Einstellungen, Wörterbuch und Verlauf wurden gesichert und inhaltlich unverändert geprüft.

Ein bestehender Grenzwertfehler bei Wörterbuch-Ersetzungen wurde im Zuge der Prüfung korrigiert: Editor, CSV, Wispr-Flow-Import und Speicherung verwenden dieselbe 16-KB-Grenze. Einzelne zu große Wispr-Einträge werden gezählt und übersprungen.

## Grenzen

Keine neue akustische Modellabnahme, kein echter Mikrofon-/Kamera-/Fehlerberichtversand in dieser Sprachprüfung. Apple-Notarisierung und die vollständige Gesamtabnahme bleiben offen; die lokale Signatur benötigt weiterhin eine Bibliotheksvalidierungs-Ausnahme. Lippenlesen bleibt im Release gesperrt. Website, Installeranleitung und technische Rohberichte wurden nicht als englische Oberfläche übersetzt.
