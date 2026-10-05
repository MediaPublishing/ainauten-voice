# AInauten Voice Downloadseite

Statische, eigenständige Seite ohne Tracking, externe Fonts oder Runtime-Abhängigkeiten. Brand-Herkunft und Rechtslinks aus dem bestehenden AInauten-Websystem. Screenshots stammen aus der nativen DEBUG-Vorschau, ausschließlich Beispieldaten. Der neue violette Einstieg zeigt das eigene Promo-Video mit lokaler Wiedergabe, deutschen Untertiteln und optionalem Transkript. YouTube bleibt ein Link; es wird kein fremder Player automatisch geladen.

Lokal: npm run dev:local → http://127.0.0.1:8916
Prüfen: npm run check
Gebautes Paket prüfen: python3 check.py --root dist
Paket vorbereiten: python3 build.py --package ../native/artifacts/ZEITSTEMPEL --promo-video /absoluter/pfad/AInauten-Voice_Promo_DE_16x9.mp4
Deploy: wrangler pages deploy dist --project-name ainauten-voice --branch main
Ziel: https://voice.ainauten.com/

DMG und Prüfsummen werden beim Build in dist/downloads eingefügt und nicht ins Quell-Repository committed. Das ausdrücklich bereitgestellte MP4 wird unverändert nach dist/assets/video/ kopiert, SHA256/Größe in media.json erfasst. Keine Videodatei in Git. Für die lokale Vorschau das MP4 nach assets/video/ainauten-voice-promo-de.mp4 kopieren (ignoriert); Originalquelle hier: ../../voicedock-promo-video/out/AInauten-Voice_Promo_DE_16x9.mp4. Poster aus Frame 9,4 s, Sprecher-Untertitel nach der überprüften lokalen vo-times.js; beides getrackt. Herkunft/Rechte im Medienprojekt research/assets-and-rights.md, eigene Marke/Film/Illustrationen/Musik. Der Film und die App-Ansichten zeigen ausdrücklich Beispieldaten.

Vor Publish Signatur/DMG prüfen, vollständigen öffentlichen Download per SHA256 zurücklesen. Videowiedergabe, Untertitel, Range-Request und Desktop-/Tablet-/Mobileansichten prüfen. Custom-Domain nur dem zugehörigen Pages-Projekt zuordnen; vorhandene DNS-Zustände vorher sichern. Rückweg: vorheriges Pages-Deployment aktivieren bzw. neu deployen. Diese grafische Überarbeitung benötigt keine DNS-Änderung.

Cloudflare Pages beantwortet Range-Anfragen derzeit mit der vollständigen Datei (HTTP 200); ein 206-Teilabruf wurde nicht erreicht. Die öffentliche Videowiedergabe und unveränderte Dateien sind geprüft. Keine zusätzliche Runtime für diese Plattformgrenze.
