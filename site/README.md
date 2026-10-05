# AInauten Voice Downloadseite

Statische Downloadseite ohne Tracking, externe Fonts oder fremde Scripts. Header, Footer, ThemeToggle und Tool-Registry stammen aus `@ainauten/ui`; Farben und Maße aus `@ainauten/tokens`. Die gemeinsamen Komponenten liegen als festgehaltener Quellstand unter `vendor/`, damit auch das öffentliche Repository unabhängig vom internen Package-Repository gebaut werden kann. Herkunft, Revision und Prüfsummen stehen in `vendor/upstream.json`; dort ist auch die lokale Footer-Anpassung ohne AI-Hinweis und Copyright-Zeile dokumentiert. Anpassungen gehören möglichst in `shell/`; Updates der gemeinsamen Komponenten immer aus einem geprüften, committed Package-Stand übernehmen.

React, Lucide und die gemeinsamen Komponenten werden lokal gebündelt. Header und Footer werden beim Build außerdem als HTML gerendert, sodass ihre Links ohne JavaScript sichtbar bleiben. Das kleine lokale Theme-Script setzt die gespeicherte Auswahl bzw. den Systemmodus vor der ersten Darstellung. Inter wird mit eigener Lizenzdatei lokal ausgeliefert.

Screenshots stammen aus der nativen DEBUG-Vorschau, ausschließlich Beispieldaten. Der violette Einstieg zeigt das eigene Promo-Video mit lokaler Wiedergabe und deutschen Untertiteln. YouTube bleibt ein Link; es wird kein fremder Player automatisch geladen.

Abhängigkeiten: npm ci --ignore-scripts
Shell bauen: npm run build:shell
Quellvorschau: npm run dev:local → http://127.0.0.1:8916 (ohne Downloadpaket)
Vollständige Vorschau nach dem Paket-Build: npm run dev:preview → http://127.0.0.1:8916
Prüfen: npm run check
Gebautes Paket prüfen: python3 check.py --root dist
Paket vorbereiten: python3 build.py --package ../native/artifacts/ZEITSTEMPEL --promo-video /absoluter/pfad/AInauten-Voice_Promo_DE_16x9.mp4
Nur Website aktualisieren: denselben vollständigen Paket-Build mit --package und --updates ausführen. --existing-site ist aus Sicherheitsgründen stillgelegt; fremde Deployment-Bäume werden nicht übernommen.
Deploy aus dem Verzeichnis `site/`: `wrangler pages deploy dist --project-name ainauten-voice --branch main`. Die dortige `wrangler.toml` muss geladen werden, damit die vorhandene `REPORTING`-Service-Bindung mit ausgeliefert wird. Danach `/api/reports/<UUID>` ohne Betreiberzugang prüfen: HTTP 401, nicht 503. Keine Secrets in Pages hinterlegen.
Ziel: https://voice.ainauten.com/

`build.py` baut und prüft die gemeinsame Shell vor dem Kopieren. Ein bestehender signierter Updatekanal muss mit `--updates` erhalten bleiben. Den Download bei einer reinen Website-Änderung aus dem bereits veröffentlichten Paket übernehmen; dadurch wird keine neue App-Version veröffentlicht.

DMG und Prüfsummen werden beim Build in dist/downloads eingefügt und nicht ins Quell-Repository committed. Das ausdrücklich bereitgestellte MP4 wird unverändert nach dist/assets/video/ kopiert, SHA256/Größe in media.json erfasst. Keine Videodatei in Git. Für die lokale Vorschau das MP4 nach assets/video/ainauten-voice-promo-de.mp4 kopieren (ignoriert); Poster aus Frame 9,4 s, Sprecher-Untertitel nach der überprüften lokalen vo-times.js; beides getrackt. Eigene Marke, eigener Film, eigene Illustrationen und Musik. Der Film und die App-Ansichten zeigen ausdrücklich Beispieldaten.

Vor Publish Signatur/DMG prüfen, vollständigen öffentlichen Download per SHA256 zurücklesen. Videowiedergabe, Untertitel, Range-Request und Desktop-/Tablet-/Mobileansichten prüfen. Custom-Domain nur dem zugehörigen Pages-Projekt zuordnen; vorhandene DNS-Zustände vorher sichern. Rückweg: vorheriges Pages-Deployment aktivieren bzw. neu deployen. Diese grafische Überarbeitung benötigt keine DNS-Änderung.

Cloudflare Pages beantwortet Range-Anfragen derzeit mit der vollständigen Datei (HTTP 200); ein 206-Teilabruf wurde nicht erreicht. Die öffentliche Videowiedergabe und unveränderte Dateien sind geprüft. Keine zusätzliche Runtime für diese Plattformgrenze.
