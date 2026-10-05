# AInauten Voice

Native lokale Diktier-App für Apple Silicon und macOS 14+. Halten, sprechen, loslassen: Text im aktiven Feld. Doppeltipp innerhalb von 500 ms startet freihändig, erneutes Drücken stoppt; Escape verwirft die Sitzung. Die ruhende Pill bleibt verborgen und aktive Rückmeldungen übernehmen keinen Fokus.

Audio bleibt lokal und wird nach dem Diktat freigegeben. Original, Optimiert (Standard), E-Mail und Chat. Lokale Textoptimierung mit eingebettetem llama.cpp; Cloud nur nach ausdrücklicher Aktivierung für Text, niemals Audio. Keine Meetings oder Notizfunktionen.

Hauptoberfläche: Übersicht, Verlauf, Statistik, Wörterbuch und Text & Stil. Einstellungen für Kürzel, Sprachen, Einrichtung, Wispr Flow und Datenschutz sind gesondert erreichbar. Nach abgeschlossener Einrichtung ist die Übersicht beim Öffnen Standard; Autostart öffnet kein Fenster.

Ausdrückliche Erweiterung vom 4. Oktober 2026: Diktate dauerhaft als Original und Ausgabe in einer lokalen SQLite-Datenbank speichern. Kein Audio und keine Cloud-Synchronisierung. Suche, Favoriten, vollständige Textansicht, Kopieren, Papierkorb/Wiederherstellung und bewusster JSON-Export. Ausschalten gilt für neue Diktate; vollständiges Zurücksetzen verschiebt die bisherige Datenbank in den macOS-Papierkorb. Bisher nie gespeicherte Texte werden nicht rückwirkend erfunden oder automatisch aus Wispr Flow übernommen.

Nutzungswerte entstehen aus vollständigen gespeicherten Diktaten außerhalb des Papierkorbs: erkannte Wörter, Zahl der Diktate, Aufnahmezeit einschließlich Pausen, gewichtete Wörter pro Minute, aktive Tage und Nutzung pro Ziel-App. Probediktate, Vorschauen, Abbruch und erneutes Einfügen/Kopieren zählen nicht. Keine erfundene Zeitersparnis oder Rangliste.

Wörterbuch: Suche in Wörtern und Ersetzungen, Filter, Editieren mit manuellem Vorrang, weitere Treffer und Entfernen mit Rückgängig. Wispr-Flow-Import mit Vorschau und idempotenter Übernahme; Quelle bleibt unverändert. Wispr bleibt installiert. Wechsel nur durch die ausdrückliche Aktion; konflikthafte Kürzel nicht gleichzeitig aktivieren.

Bestätigtes Einfügen erhält die Zwischenablage. Bereits übermittelte, aber unbestätigte Eingaben öffnen kein automatisches Textfenster. Echte Fehler/Nichtversuche zeigen vollständige neue Ergebnisse kompakt und kopieren sie mit sicherem Undo; neuere Kopieraktionen haben Vorrang. Fünf RAM-Ergebnisse bleiben als schneller Menüzugriff getrennt vom dauerhaften Verlauf. Diagnosemeldungen enthalten keine Diktate.

Abnahme: echte native App, lokale Modelle, DMG, Lizenzen, gezielte Tests und ehrlicher Prüfbericht. Module-/Oberflächentests sind keine vollständige Sprach-, p95- oder externe App-Abnahme.
