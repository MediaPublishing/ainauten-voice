# Weiterdiktieren in allen Sprachen

Lokaler Teststand: 0.1.17, Build 21. Noch kein öffentliches Release; der
veröffentlichte Download bleibt 0.1.16, Build 20.

Nach dem Loslassen darf die nächste Audioaufnahme bereits beginnen, während
die vorherige Aufnahme erkannt, formatiert oder eingefügt wird. Dies gilt für
alle ausgewählten Audiosprachen, einschließlich Schweizerdeutsch. Probe und
Lippenlesen bleiben eigene Abläufe. Die bestehende Sprachwahl, der Stil pro App,
das Wörterbuch und eine ausdrücklich konfigurierte Cloud-Nachbearbeitung werden
für jede Aufnahme festgehalten. Schweizerdeutsch wird weiterhin lokal verarbeitet.

Ergebnisse werden nacheinander in Aufnahmereihenfolge eingefügt. Hat eine neue
Aufnahme das gleiche Textfeld bereits vor der ersten Einfügung erfasst, wird
ihr Ziel ausschließlich anhand der vollständig bestätigten eigenen Einfügung
fortgeschrieben. Dabei müssen Feld, Fenster, vollständiger Text und Cursor exakt
passen. Normale Wortabstände am Satzende bleiben erhalten.

Wird ein Ergebnis während einer weiteren Aufnahme fertig, wartet seine
Einfügung bis zum Ende dieser Aufnahme und bis das Kürzel losgelassen wurde.
Das gilt auch bei freihändiger Aufnahme. Die normale Frist für andere gehaltene
Tasten beginnt erst danach. Während des Wartens bleibt die Zwischenablage
unverändert; vor der Einfügung werden Ziel, Text und Cursor erneut geprüft.

Bei verändertem Text, einer anderen Auswahl, einem anderen Feld, App-Wechsel,
Teiltext, Verarbeitungsfehler oder unklarer Zustellung wird das automatische
Einfügen für die restliche Serie angehalten. Eine unbestätigte Einfügung wird
nicht wiederholt. Fertige Texte bleiben unter **Diktieren → Aufeinanderfolgende
Diktate** verfügbar, auch bei ausgeschaltetem Verlauf. Vor einem manuellen
Einfügen das Zielfeld prüfen, weil ein unbestätigter Text bereits dort stehen kann.
Ein einzelnes nicht versendetes Ergebnis nutzt weiterhin die Wiederherstellungsanzeige.

Die bestehende Begrenzung reserviert höchstens 768 MiB für drei Aufnahme-
Arbeitsstände. Bei voller Warteschlange wird eine neue Aufnahme erst angenommen,
wenn ein Platz frei ist. Audio bleibt im Arbeitsspeicher. Esc verwirft laufende
Aufnahmen und Verarbeitung; fertige Texte bleiben erhalten. Ruhezustand stoppt
die automatische Zustellung. Ein Neustart stellt unverarbeitetes Audio nicht wieder her.

## Prüfen

Die Vertragsprüfungen decken FIFO, Überlappung, Speichergrenzen, Abbruch,
Sprachkonfiguration und das sichere Fortschreiben bestätigter Ziele ab. Der
native TextEdit-Test fügt drei künstliche Texte in dieselbe Auswahl ein und
prüft vollständigen Text, Cursor, unveränderte Zwischenablage sowie ein
angehaltenes Folgediktat nach Cursorwechsel. Tests mit künstlichen Texten
ersetzen keinen gesprochenen Mikrofon-/Kürzeltest in der jeweiligen Ziel-App.

Für den praktischen Test im unveränderten Textfeld einen Satz diktieren und
während seiner Verarbeitung sofort den nächsten aufnehmen. Die Sätze sollen
automatisch in gesprochener Reihenfolge erscheinen. Beim Wechsel des Textfelds
sollen die noch nicht eingefügten Texte zur Wiederherstellung erhalten bleiben.
