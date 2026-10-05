# Gesperrte Vorlage für isolierte Fehleranalyse

Kein AI-Hintergrundjob ist aktiviert. `prepare-context.mjs` übernimmt ausschließlich ein validiertes technisches Schema und explizit erlaubte Quelldateien; freiwillige Angaben werden entfernt. `analyst.py` verweigert API-Aufrufe ohne ausdrückliche Freigabevariable, Modell und eigenen Schlüssel.

`validate-context.mjs` prüft Quellen, Schema und Grenzen erneut. `validate-patch.mjs` lehnt Secrets, Identitäten, Paketdateien, CI-/Release-Code, Pfadtraversal, Symlinks, Binärdateien und Umbenennungen ab. Ein Vorschlag braucht Regressionstest, isolierten macOS-Test und unabhängigen Review. Kein automatisches Merge oder Release. Eine vorgeschlagene Änderung ist keine ausgelieferte Fehlerbehebung.

Dauerhafte AI-Verarbeitung, Anbieter, Kostenlimit und PR-Schreibrechte benötigen eine separate Betreiberfreigabe. Für eine normale App-Installation wird nichts hiervon ausgeführt.
