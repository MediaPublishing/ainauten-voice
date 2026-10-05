# AInauten Voice: Produktgestaltung

Register: product. Referenz: Wispr Flow, kompakte dunkle Pill unten mittig über dem Dock. SF-Systemschrift, zurückhaltende monochrome Oberfläche. SwiftUI und AppKit als native Komponenten; SF Symbols als Icons.

Die Pill aktiviert das App-Fenster nicht. Im Ruhezustand bleibt sie unsichtbar; der Hotkey startet das Diktat. Aufnahme mit echtem Pegel, Stopp und Abbrechen. Verarbeitung mit Spinner, Erfolg mit Haken, Fehler mit zugänglicher Erklärung. Reduzierte Bewegung respektieren. Die Pill folgt dem Bildschirm der Ziel-App und funktioniert auf Spaces einschließlich Vollbild.

Einrichtung: Sprache, Importvorschau, Modelle, Berechtigungen, Probediktat, Wechsel. Sichtbare nächste Aktion pro Schritt. Native Einstellungen folgen hellem/dunklem Systemmodus; Tastatur und VoiceOver vollständig nutzbar. Prüfflächen: 640×560 und 960×720.

Keine Werbekarten, erfundenen Kennzahlen, werblichen Gradienten oder dekorativen Illustrationen. Nutzungskennzahlen sind zulässig, wenn sie aus tatsächlichen Diktaten berechnet werden. Schriftgröße mindestens 12 pt, klare Fokusindikatoren, Status nicht allein durch Farbe. Kompaktes Ergebnis-Popover mit vollständigem auswählbarem Text bei fehlgeschlagenem oder nicht ausgeführtem Einfügen; neue vollständige Ergebnisse werden dabei automatisch kopiert. Bereits übermittelte, aber nicht bestätigte Eingaben erhalten nur einen kurzen Symbolhinweis und bleiben im Menü erreichbar. Frühere Ergebnisse und Teiltexte nur durch eine bewusste Aktion kopieren.

Auswahl und Tastaturfokus sind getrennt: Seitenwahl erhält eine dezente Fläche. Zusätzliche Fokusrahmen an Seitenleiste und Symbolknöpfen erscheinen erst beim Navigieren mit Tab/Pfeiltasten und verschwinden bei einem Mausklick. Tastaturbedienung, Escape und VoiceOver bleiben nutzbar. Der Prüfbericht verwendet lokal gerenderten, durchgehend auswählbaren Rich Text mit Überschriften, Hervorhebungen, Listen, Code und Tabellen; keine sichtbaren Markdown-Markierungen.

Screenshot-Prüfung aller Zustände und unabhängige UI-/Fehlerfall-Reviews vor Abnahme. Technischer Build-Erfolg ersetzt keine visuelle oder funktionale Abnahme.

Die ruhende Pill misst 52 × 24 Punkte, Aufnahme 118 × 28, Verarbeitung 96 × 28. Status und Hotkey erscheinen als Tooltip und VoiceOver-Label statt als dauerhafte Beschriftung. Ergebnisse bleiben über das Menü zugänglich; Fehler öffnen sie weiterhin per Pill.

Das Probediktat stoppt nach zwei Sekunden Sprechpause (frühestens nach drei Sekunden) und spätestens nach 15 Sekunden. Ein vollständiges erkanntes Ergebnis bestätigt den Teststatus und die Einrichtung automatisch. Das Fenster und der aktuelle Schritt bleiben offen; der erkannte Text steht dort auswählbar mit Kopierknopf. Nur eine bewusste Weiter-Aktion wechselt die Seite. Neue Versuche ersetzen die vorherige Anzeige, Fehler und Abbruch zeigen keine alten Erfolgstexte. Fehlende Bedienungshilfen pausieren Hotkey und Einfügen, erzwingen aber kein neues Probediktat. Der Wispr-Wechsel ist unabhängig vom Probediktat erreichbar und startet einen bereits beendeten Wechsel nicht erneut.

## Korrekturen nach Nutzerfeedback

Sprachen als adaptive anklickbare Elemente, ausgewählte Sprachen in einer eigenen oberen Gruppe. Weitere Sprachen werden bei Bedarf aufgeklappt; mindestens eine bleibt gewählt. Die Seitenleiste zeigt genau einen ausgewählten Eintrag. Tastaturfokus verwendet den gesamten Eintrag; Mausklicks wechseln die Auswahl ohne zusätzlichen Rahmen. Die Wispr-Vorschau unterscheidet Laden, Fehler und echte Werte, bietet erneutes Prüfen und zeigt daneben den lokal gespeicherten Stand. UI-Vorschau ist ausschließlich in Debug-Builds verfügbar.

## Bedienung nach Praxistest am 3. Oktober 2026

Die reguläre Mac-App besitzt ein eigenes Dock-Icon. Die Pill bleibt nicht aktivierend. Bereit, Laden, offene Schritte und ausgeschaltete Kürzel erscheinen nicht als dauerhafte Pill; Einstellungen und Status bleiben über Dock und Menüleiste erreichbar. Das Pausezeichen wird nicht mehr für Einrichtung oder fehlende Freigaben verwendet.

Der gesamte Seitenleisteneintrag, jede Sprachkachel und die gesamte Aufklappzeile reagieren auf Klicks. Flaggen ergänzen ausgeschriebene Sprachnamen, ersetzen sie aber nicht. Die Sprachliste zeigt ausschließlich die angebotenen Sprachen, ohne zusätzlichen Dialekthinweis.

Ein erfolgreicher Import zeigt ein sichtbares Ergebnis und führt im Assistenten zu den Modellen weiter. Im separaten Bereich steht „Zum Diktieren“ beziehungsweise „Einrichtung fortsetzen“. Die aktuellen Halte-, freihändigen, Abbruch-, Kopier- und Einfügekürzel stehen mit verständlichen Aktionsnamen in den Einstellungen. „Tastenkürzel aktiv“ ersetzt den unklaren Pausenschalter.

Die Freigabeseite bietet ein ziehbares Element der tatsächlich laufenden App, den vollständigen Pfad und eine Finder-Aktion. Sie erklärt, dass Backup-Versionen nicht die aktuelle App sind. Der Prüfbericht öffnet innerhalb des Einstellungsfensters. Der Probetest nennt einen Beispielsatz, zeigt Aufnahmezeit und Pegel und stoppt automatisch. Ein gespeicherter Erfolg bleibt nach Neustart erhalten.

Der Probetest verwendet den unpersönlichen Beispielsatz „Dies ist ein kurzer Test der Spracherkennung.“ Entwicklungsprüfungen mit Audiodateien nennen die Datei und bei den bekannten deutschen/englischen Fixtures deren Sprache. Sie erklären ausdrücklich, dass das Mikrofon aus bleibt, und verwenden „Testaudio starten/auswerten“ statt Mikrofon-Beschriftungen. Solche Dateitests sind im Release nicht verfügbar.


## Kompakte Einstellungen nach Nutzerfeedback

Der Textmodus heißt „Optimiert“, auch Modell- und Cloud-Beschriftungen verwenden Textoptimierung. Der gespeicherte Formatbezeichner cleaned bleibt rückwärtskompatibel. Das Fenster startet mit 1120 × 860 Punkten, begrenzt auf die nutzbare Bildschirmfläche, und bleibt bis 640 × 560 verkleinerbar. AppKit merkt sich die gewählte Größe und Position über Neustarts. Debug-Vorschauen verändern diesen gespeicherten Rahmen nicht. Der Prüfbericht öffnet mit 860 × 720 Punkten; bei kleinen Elternfenstern schrumpft er mit 24 Punkten Abstand pro Seite. Der Inhaltsbereich nutzt bis zu 800 Punkte einschließlich Abständen; Sprachkacheln erhalten dadurch mehr Spalten. Die Kopfzeile bleibt beim Scrollen sichtbar. Der Prüfbericht ist über ein dezentes Symbol mit Tooltip und VoiceOver-Namen erreichbar. Einstellungen, Prüfbericht und Wiederherstellungsfenster besitzen oben rechts ein X; die nativen Mac-Fensterknöpfe und Tastaturbefehle bleiben verfügbar.

Die Person prüft während des Schreibens kurz ihre Kürzel und Sprachen, abends im dunklen Systemmodus oder tagsüber in der hellen Mac-Oberfläche. Die Diktieren-Seite setzt deshalb auf eine kompakte native Einstellungsansicht: ein Status, kurze Anleitung, dicht gruppierte Kürzel und Sprachen daneben, sobald die Breite reicht. Bei schmalen Fenstern stehen die Gruppen untereinander. Die fünf Kürzelzeilen haben mindestens 28 Punkte Höhe und vier Punkte Abstand; die beiden vorhandenen Start-/Aktivitätsoptionen schließen direkt an. Keine zweite große Bedienungsüberschrift und keine ständig sichtbare Erklärung ausgeschalteter Kürzel, solange sie aktiv sind.

Freigaben und Modelle erscheinen als kurze Statuszeile mit ausgeschriebenen Namen und eindeutigen Symbolen. „Einrichtung anzeigen“ öffnet die Details, bei offenen Schritten „Einrichtung fortsetzen“ direkt den benötigten Schritt. Die volle Berechtigungs-/Download-Anleitung bleibt dort erhalten. In der regulären breiten Ansicht ist die Diktieren-Seite bei geschlossener zusätzlicher Sprachliste ohne Scrollen sichtbar; im Mindestfenster bleibt vertikales Scrollen möglich. Das Fenster behält seine Größe und gespeicherte Position. Die kompakte Sprachwahl nutzt dieselben Chips und Auswahlregeln wie die Einrichtung.


## Pill-Sichtbarkeit

Ruhende Zustände sind immer unsichtbar, einschließlich Bereit, Laden, offener Einrichtung, bewusst ausgeschalteten Kürzeln und Flow-Konflikt. Dies gilt auch bei offenen oder hintergründigen Einstellungen. Aufnahme und Verarbeitung erscheinen unabhängig vom Fenster; Abbruch blendet die Pill wieder aus. Erfolg bleibt für die bestehende kurze Haken-Rückmeldung sichtbar. Ein sichtbares Ergebnis- oder Fehler-Popover ersetzt die Pill vollständig, statt ein zweites Statussymbol darunter zu zeigen. Die Pill rendert im Ruhezustand auch bei einem verspäteten Panel-Update kein Mikrofon. Die App bleibt über Dock und Menüleiste erreichbar; die Pill übernimmt weiterhin keinen Tastaturfokus.


## Ergebnisrückmeldung nach erneutem Feedback

Nutzungssituation: Nach dem Loslassen bleibt die Person in ihrem aktiven Mail-, Chat- oder Browserfeld und braucht eine kurze, gut lesbare Rückmeldung im aktuellen hellen oder dunklen Systemmodus.

Neue vollständige Diktate werden bei einem fehlgeschlagenen oder nicht ausgeführten Einfügeversuch automatisch in die Zwischenablage kopiert. Nach einem bereits übermittelten, aber nicht bestätigten Versuch erscheint kein automatisches Text-Popover und keine zusätzliche Zwischenablage-Kopie. Das würde bereits eingefügten Text unnötig überdecken und könnte zu doppeltem Einfügen verleiten. Stattdessen bleibt für 1,5 Sekunden ein neutrales Warnsymbol sichtbar: Tooltip/VoiceOver nennen die fehlende Bestätigung und den Zugriff auf „Letzte Ergebnisse“. Ein bewusster Klick öffnet den Text; derselbe Hotkey kann sofort das nächste Diktat starten. Unbestätigt bleibt fachlich unbestätigt, kein grüner Erfolg und kein erneuter Einfügeversuch. Bestätigte Eingaben zeigen nur den kurzen Haken. Derselbe Feedbackweg gilt für normales Diktat und „Letzten Text einfügen“.

Ein tatsächlich angefordertes oder wegen Fehler geöffnetes Popover zeigt nur Zwischenablage-Symbol, kurzen Status, auswählbaren Text, Undo und Schließ-Countdown. Einfügegrund, Anleitung und Speicherhinweis sind per Mouse-over und VoiceOver erreichbar. Kritische Zustände bleiben ausdrücklich sichtbar: „Unvollständiger Text“, „Nicht kopiert“ oder der Aufnahmefehler. Ein manuell geöffnetes Ergebnis bietet bei mehreren Diktaten ein kleines Verlaufsmenü statt einer zusätzlichen Auswahlzeile. 420 Punkte Breite, bei kleiner Fläche schmaler; Höhe richtet sich nach dem Text, die Textfläche ist bei langen Diktaten auf 144 Punkte mit Scrollen begrenzt. Keine flexible Restfläche, zusätzliche Titelleiste oder breite Kopieren-Schaltfläche. SF-Systemschrift und Systemfarben.

Jede Rückmeldung schließt nach fünf Sekunden automatisch, auch manuell geöffnete Ergebnisse und Hinweise ohne Kopiermöglichkeit. Oben rechts zeigt ein kleiner Kreis die verbleibenden Sekunden; beim Mouse-over wird daraus ein anklickbares X. Lesen mit dem Mauszeiger pausiert die verbleibende Zeit, danach läuft sie weiter, ohne erneut bei fünf Sekunden anzufangen. Tastaturfokus allein hält das Fenster nicht dauerhaft offen. Der Countdown berücksichtigt reduzierte Bewegung und VoiceOver. Das automatische Anzeigen aktiviert Voice Wispr nicht und verändert den Fokus nicht. Ein neues Diktat kann die Rückmeldung direkt ablösen. Escape und Cmd+W bleiben erreichbar, Cmd+C kopiert bewusst, Cmd+Z stellt die vorige Zwischenablage wieder her. Texte und Undo bleiben nach dem Schließen bis zum App-Ende im Menü erreichbar.

Auch ein bewusst geöffnetes älteres Ergebnis, ein Teiltext oder ein Hinweis bei nicht sicherbarer Zwischenablage sperrt den nächsten Hotkey nicht. Der neue Durchlauf erhält seine Kennung vor dem Schließen des Popovers, damit die laufende Haltegeste erhalten bleibt. Manuelles Öffnen des nicht aktivierenden Panels aktiviert die App nicht. Erneutes Einfügen über das dafür konfigurierte Kürzel schließt die alte Rückmeldung und hat eine eigene abbrechbare Kennung; ein verspätetes Ergebnis darf keinen neuen Durchlauf überlagern.

Bestätigung prüft weiter die ursprüngliche App, das Fenster und das Textfeld. Der vollständige erwartete Feldinhalt genügt bei einer tatsächlichen Textänderung auch ohne aktuelle Cursorposition; bei einer unveränderten Ersetzung ist weiterhin Cursor-Evidenz nötig. Andere Texte oder Fokuswechsel werden nicht als Erfolg gewertet. Kein zweiter automatischer Einfügeversuch.

Undo stellt sämtliche gesicherten Einträge und Formate wieder her und verfällt bei einer neueren Kopieraktion, auch bei identischem Text. Snapshot ausschließlich im Speicher, höchstens 64 MiB. Ist kein vollständiger Snapshot möglich, bleibt die Zwischenablage unverändert; „Nicht kopiert“ bleibt bis zum Schließen sichtbar und der Text im Menü erreichbar. Frühere Ergebnisse und unvollständige Teiltexte werden nicht automatisch kopiert, ihre Rückmeldung schließt ebenfalls nach dem Countdown. Bestätigtes Einfügen behält die bestehende Zwischenablage-Regel.

Referenzen: Nutzer-Screenshot c2baf04a als Anti-Referenz (große Leerfläche und obligatorischer Kopierknopf); bestehende nicht aktivierende Pill für Position/Fokus; bestehendes WindowCloseButton/PointerAwareFocus für Symbolaktionen, X und Tastaturfokus. Zusammengesetzt aus vorhandenen AppKit-/SwiftUI-Primitiven und SF Symbols, keine externe UI-Bibliothek oder neue Icons.

## Wispr-Flow-Import nach Fehlerkorrektur

Die Vorschau trennt Quelleinträge, Duplikate und eindeutige Zielwerte. Wörterbuchzahlen und Einstellungen stehen bei ausreichender Breite nebeneinander; schmale Fenster ordnen sie automatisch untereinander an. Import und erneute Prüfung sind gemeinsam erreichbar. Ein fehlgeschlagener Vorschau-Leselauf blockiert den erneuten vollständigen Import nicht. Fehler verwenden einen Warnhinweis statt Erfolgstext und führen nicht zur nächsten Seite. Der bestehende große Fensterrahmen bleibt erhalten.

## Aufnahmefehler ohne neues Ergebnis

Nicht aktivierender Hinweis am selben Anker wie die Pill, Warnsymbol, kurze deutsche Überschrift, vollständige verständliche Meldung und Schließ-Countdown. Inhalt bestimmt die Höhe. Keine alte Textausgabe, Ergebnis-Auswahl, Kopier- oder Undo-Aktion in diesem Zustand. Nach fünf Sekunden schließen; Mouse-over pausiert die verbleibende Zeit, Tastaturfokus allein nicht. Währenddessen bleibt die Pill verborgen. Frühere Diktate bleiben bewusst über „Letzte Ergebnisse“ erreichbar. Zu kurze Audioabschnitte erhalten einen lokalisierten Hinweis; das SDK-Minimum von 300 ms wird nicht durch einen größeren pauschalen Aufnahmecutoff ersetzt.

## Wörterbuch: Großbuchstaben ohne automatische Umdeutung

Importierte Begriffe wie MIT, IT und US können auch gewöhnliche deutsche oder englische Wörter treffen. Ohne ausdrückliche Ersetzung verändert ein vollständig groß geschriebener Vokabulareintrag deshalb keine anders geschriebene Erkennung. „mit“/„Mit“ bleibt erhalten, „MIT“ bleibt als erkanntes Kürzel erhalten. Bewusste Ersetzungen dürfen weiterhin Schreibweisen erzwingen; bereits erkannte Namensschreibweisen bleiben erhalten. Dieselbe Regel und vollständige Wortgrenzen gelten für die Hinweise an die Textoptimierung. Bestehende Daten bleiben gespeichert; ein erneuter Wispr-Flow-Import führt die fehlerhafte Kanonisierung nicht wieder ein. Keine pauschale Kleinschreibung oder semantische Hochschul-Erkennung.

Nach dem weiteren Großschreibungsbefund gilt die Trennung grundsätzlich: gewöhnliche Wort-/Namenseinträge wie Das, Dass, Du und Klein sind Hinweise und keine direkten Schreibersetzungen. Sie erhalten die erkannte Schreibung und sind für absichtliche Ersetzungen transparent, auch wenn ein längerer Hinweis den Treffer überlappt. Gemischte Schreibweisen wie OpenAI und AInauten sowie ausdrücklich konfigurierte Ersetzungen bleiben wirksam. Damit bleibt „klein“ im gewöhnlichen Satz klein, ein erkanntes „Frau Klein“ unverändert. Die Textoptimierung entscheidet nach Kontext; kurze Sätze mit auffällig groß geschriebenen Funktionswörtern werden nicht mehr allein wegen vorhandener Satzzeichen übersprungen. Bereits unauffällige Sätze behalten die schnelle Verarbeitung. Kein Löschen gespeicherter Wörter, keine globale Kleinschreibung und keine neue Oberfläche.


## Übersicht, Verlauf und Statistik (4. Oktober 2026)

Aktueller Auftrag erweitert den früheren reinen Einstellungsaufbau. Übersicht ist beim Öffnen nach Einrichtung Standard. Primäre Sidebar: Übersicht, Verlauf, Statistik, Wörterbuch, Text & Stil. Einstellungen stehen unten und öffnen die vorhandenen Bereiche. Autostart bleibt ohne Fenster, ruhende Pill unsichtbar.

Referenzledger: Nutzer-Screenshot 039e286d für Datumsliste/Sidebar und getrennte Nutzungsleiste; 003d97cb für echte Kennzahlen und App-Nutzung; bestehende native Voice-Wispr-Controls für Fokus/Systemschrift/hell-dunkel; Ergebnis-Pill für sofortigen Rückweg. Fremde Werbung, persönliche Begrüßung, Ranglisten und Illustrationen werden nicht übernommen. Keine externe UI-Bibliothek: vorhandene SwiftUI-/AppKit-Primitiven, SF Symbols, SQLite.

Fingerprint: linksbündige feste Kopfzeile; bei mindestens 700 Punkten Inhaltsbreite asymmetrische letzte-fünf-Diktate-Liste und schmale Nutzungsleiste, darunter gestapelt; feine Trennlinien; Symbolaktionen mit Tooltip; keine Bilder; keine dekorative Animation. Die Hauptseiten nutzen die volle Fensterbreite. 1120 × 860 Standard, 640 × 560 Minimum, gespeicherter Rahmen bleibt erhalten.

Verlauf zeigt Suche und Filter, Datum, kompakte Vorschau, Favorit und Kopiersymbol. Vollständiger Text öffnet bewusst in einer Detailansicht mit inhaltsabhängiger Höhe (300–600 Punkte), Original-/Ausgabe-Wechsel und X. Kritische Teiltexte sichtbar benannt. Historischer Einfügestatus bleibt ehrlich und erklärt keine unbestätigte Eingabe zum Erfolg. Kein automatisch geöffnetes Verlauf-Fenster nach jedem Diktat.

Statistik: kompakte offene Kennzahlen, 14-Tage-Balken und tatsächliche App-Nutzung. Tooltip erklärt Aufnahmezeit inklusive Pausen und gewichtetes Tempo. Papierkorb/Probe/Abbruch zählen nicht. Leerer Zustand leitet zum ersten eigenen Diktat; Testfixtures nur isoliert und ausdrücklich als Beispieldaten erkennbar.

Wörterbuch-Suche umfasst Wort und Ersetzung; Filter ohne lange sichtbare Picker-Beschriftung. Ganze Wortzeile öffnet Bearbeitung. Abbrechen behält den Eintrag, Speichern markiert manuelle Bearbeitung; Entfernen hat Rückgängig. Treffer in 100er-Schritten zugänglich, Sortierung/Filter werden bei tatsächlicher Änderung berechnet statt bei jedem Pegelupdate.

Datenschutz benennt dauerhaften lokalen Textverlauf und bietet Speichern aus, Export sowie Zurücksetzen in den macOS-Papierkorb. Kein Audio-/Cloud-Archiv. Screenshot-Prüfung in breit/hell und klein/dunkel sowie Suche, Details, Copy, Wiederherstellung und Edit/Undo im isolierten nativen Fixture.
