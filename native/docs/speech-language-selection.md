# Diktatsprachen ab Beta 0.1.13 (17)

Die App übernimmt die ausgewählten Diktatsprachen zu Beginn jeder Aufnahme. Die Sprache der Oberfläche bleibt davon getrennt.

Parakeet v3 erkennt die Sprache automatisch und bietet in der gepinnten FluidAudio-Version keinen Schalter für eine feste Sprache. Die App kontrolliert deshalb erkennbare Sprachabweichungen. Bei nur Deutsch werden klar englische Sätze und ungewählte kyrillische/griechische Schrift lokal aus dem Originalaudio mit Whisper und der festen Sprache de erneut erkannt. Text wird nicht übersetzt. Bleibt das Ergebnis außerhalb der Auswahl, wird es nicht automatisch eingefügt; die App zeigt eine verständliche Meldung.

Bei Deutsch plus Englisch werden klar englisch erkannte Sätze akustisch mit Whisper im Auto-Modus gegengeprüft. Echte englische Diktate bleiben zulässig. Andere ausgewählte Sprachen bleiben zulässig. Bei mehreren Sprachen nutzt die Zweiterkennung ihre automatische Spracherkennung; die Ausgabe muss weiterhin zur Auswahl passen. Kurze Namen, Zahlen, URLs und Fachbegriffe werden nicht aufgrund eines einzelnen Wortes verworfen. Eine perfekte Erkennung jedes mehrdeutigen Einzelworts wird nicht garantiert.

Der mitgelieferte Whisper-small-q5_1-Helper und das Modell sind auf Version und Prüfsumme gepinnt. Der Helper ist statisch gegen System-Frameworks gelinkt und separat mit der bestehenden App-Identität signiert. Audio läuft über Pipes im RAM. Es gibt keine Audio-/Transkriptdateien, Netzwerkübertragung oder SDK-Logs. Das Modell vergrößert den Installer um ungefähr 190 MB und braucht keinen neuen Modell-Download nach Installation. Die Zweiterkennung läuft nur bei auffälligen Ergebnissen; sie kann zusätzliche Verarbeitungszeit benötigen.

Abbruch und Sitzungstrennung schützen neue Aufnahmen vor alten Resultaten. Der Helper hat ein Zeitlimit von 90 Sekunden und eine begrenzte Ausgabe; unvollständige oder nicht passende Resultate werden nicht automatisch eingefügt. Wortzeitstempel werden geprüft und auf das ursprüngliche Audiofenster bezogen. Die bestehende Behandlung unvollständiger längerer Diktate bleibt erhalten.

Prüfnachweise liegen in den lokalen Release-Receipts. Öffentliche FLEURS-Leseaufnahmen und gekennzeichnete synthetische Beispiele sind Referenzprüfungen, keine Behauptung einer Abnahme mit Retos ursprünglicher Aufnahme. Die lokal signierte Beta bleibt noch nicht Apple-notarisiert; Bibliotheksvalidierung ist ein separates offenes Thema.
