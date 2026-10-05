# AInauten Voice Design

## Scene and register

Ein Leser öffnet die Downloadseite tagsüber zwischen Newsletter und Arbeit auf dem Mac oder Telefon. Die helle AInauten-Oberfläche soll schnell verständlich sein; echte native App-Screenshots zeigen den lokalen Arbeitsbereich. Brand-Register für die Seite, native Systemdarstellung in der App.

## Visual system

Die Referenz skills.ainauten.com/gpt-to-skill liefert AInauten-Nauti, dunkles violettes Ink, ruhige helle Flächen und klare Downloadaktionen. Vorhandene Brand-Familie Inter bleibt erhalten, Systemfont als lokale Alternative ohne externen Font-Aufruf. Farben als OKLCH: violettes Ink, nahezu weiße getönte Flächen, dezente Lavendeltöne. Keine Neonverläufe, kein Glas.

## Structural fingerprint

Links verankerter kurzer Einstieg und heller Download im flächigen AInauten-Violett; rechts eine große helle Szene aus dem eigenen Promo-Video als Produktgrafik. Das Video lässt sich direkt starten, statt zuerst ein Einstellungsfenster zu zeigen. Danach kompakter Halten/Sprechen/Loslassen-Ablauf. Echte native App-Screenshots mit wechselnden Bild-/Textspalten statt gleicher Karten. Installationsanleitung als nummerierte Liste; Details als native Akkordeons. Zurückhaltender Footer mit Herkunft und Rechtslinks. Kein automatischer Filmstart und keine Eingangsmotion.

## Components

Echte Screenshots aus der isolierten nativen Vorschau, Beispieldaten ausdrücklich als solche bezeichnet. Runde Hauptaktion, Textlinks sekundär, vollständige Klickflächen, klarer Fokus. Mobil untereinander; primärer Download bleibt sichtbar. Screenshot-Auswahl per Button mit beschrifteten Tabs und ohne Layoutsprung.

## Promo-Überarbeitung vom 4. Oktober 2026

Die bisherige reine App-Übersicht wurde vom Benutzer als zu wenig ansprechend bewertet. Gewählte Richtung: Der eigene 36-Sekunden-Film demonstriert das Produkt im Einstieg, eine Szene daraus ist die große Hauptgrafik. Der vorhandene Nauti und das dunkle Violett verbinden Film und Seite. Überschrift als echter Text: „Sprich einfach. Dein Mac schreibt mit.“ Schriftfamilie bleibt aus der bestehenden Identität erhalten, keine externe Font-Anfrage. Gleichmäßige normale Laufweite, feste responsive Schriftgrößen statt neuer Displayfont. Der Primär-Download ist heller als die Fläche und unmittelbar sichtbar.

Alternative reine Dashboard-Aufnahme verworfen, weil sie Einstellungen und Zahlen vor der eigentlichen Diktiergeste zeigt. Neue Stock-/AI-Illustration verworfen, weil bereits passendes eigenes Produktmaterial vorliegt. Keine generische Kartenserie, Neonverläufe, automatische Daueranimation oder künstliche Erfolgszahlen.

| Referenz | Übernommene Ebene | Entscheidung und Grenze |
|---|---|---|
| voicedock-promo-video/out/AInauten-Voice_Promo_DE_16x9.mp4, Scene S3 bei 9,4 s | Bild, Nauti, Violett, Stimme-zu-Text-Demo | Originalfilm unverändert lokal ausliefern, echtes Standbild als Poster; Illustration ausdrücklich als solche kennzeichnen. Keine neue Sprecher-/Musikgenerierung. |
| Bisherige AInauten-Voice-Seite und site/index.html | Nutzungsweg und bekannte Fakten | Installation, Beta-/Privacy-/Downloadhinweise und Screenshot-Tabs behalten. Reiner Screenshot als Hero ist die konkrete Anti-Referenz. |
| site/assets/screenshots/overview.png und dictionary/statistics/styles | Produktbeleg | Die echten nativen Vorschauen bleiben im Produktbereich. Persönliche Inhalte und korrigierte Farbdarstellungen nicht als neue Live-App ausgeben. |

Player: native HTML-Videokomponente mit Steuerelementen und lokalem deutschem WebVTT; mit JavaScript zusätzlicher beschrifteter Play-Knopf, ohne JavaScript native Bedienung. Kein Autoplay, preload=none. YouTube ist ein optionaler Link, kein automatisch geladener fremder Player. Optionales Texttranskript im selben Bereich. Das Video selbst trägt die erklärende Bewegung; übrige Seite bleibt ruhig. Keine zusätzliche Bibliothek.
