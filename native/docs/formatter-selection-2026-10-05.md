# Schnellere Auswahl bei der Textoptimierung

Beta 0.1.9, Build 13 prüft zuerst, ob der wahrscheinlichste Vorschlag des lokalen Textmodells die bestehende Wortschutzgrammatik erfüllt. Bei Ablehnung folgt die vollständige Auswahl wie bisher. Modell, Anweisungen, Grammatik, Validierung und Zeitlimit bleiben unverändert. Es werden keine zusätzlichen Diktatprotokolle erzeugt.

Die Strategie folgt dem [entsprechenden Auswahlpfad der gepinnten llama.cpp-Version b11361](https://github.com/ggml-org/llama.cpp/blob/b11361/common/sampling.cpp). Beide Wege akzeptieren das gewählte Token genau einmal; die Vorprüfung verändert den Grammatikzustand nicht.

## Begrenzter Vergleich

Sechs sequenzielle Läufe, abwechselnd bisherige Auswahl und Kandidat, umfassten je elf unveränderte Textfälle und zwei Pipelineprüfungen. Alle ursprünglichen Prüfungen bestanden; alle vergleichbaren Texte waren identisch. Alle Versuche bleiben enthalten, ohne Wiederholung fehlgeschlagener Messungen oder Ausschluss von Ausreißern.

- Zehn modellpflichtige Fälle, je drei Messungen pro Variante: Median der gepaarten Fallquotienten 0,848, etwa 15 % kürzere Formatierung.
- Gepooltes p95 dieser Modellaufrufe: 6,38 → 3,36 Sekunden.
- Median des langen Absatzfalls: 6,38 → 3,36 Sekunden.

Eine unabhängige native C++-Kontrollprüfung mit dem tatsächlichen Modellwortschatz verglich zwölf sequenzielle Übergänge mit vollständigen Grammatikmasken, erlaubten und abgelehnten Vorschlägen, gleichen Logits, Satzzeichen und echtem Ende-Token. Dies ist ein separater synthetischer Zustandsnachweis, keine Ausführung des Swift-Formatters. Die drei tatsächlichen Swift-Kandidatenläufe nutzten beide Auswahlwege.

Nach der Übernahme bestanden 83 gezielte Vertragsfälle und ein weiterer Lauf der unveränderten elf Textfälle sowie der beiden Pipelineprüfungen. Der Zitatfall nutzte weiterhin den sicheren Originaltext-Rückfall.

## Grenzen

Diese begrenzten Textprüfungen messen weder die Spracherkennung noch Mikrofonaufnahme, Hotkeys oder die Zeit bis zum Einfügen in eine andere App. Sie belegen keine allgemeine p95-Zielerfüllung. Wortfehler und die vollständige praktische Geräte-/App-Abnahme bleiben offen. Rohdaten, Benutzerprofile und private Beispiele werden nicht veröffentlicht.
