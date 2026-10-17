# Whisper-Wörterbuchhinweise / Vocabulary prompt evaluation

Lokaler gepaarter Versuch vom 16. Oktober 2026, Whisper large-v3 q5_0 mit dem
vorhandenen isolierten whisper.cpp-Helper (Revision 306c88f4, API 1.9.2).
Ein Test-Prototyp setzt `initial_prompt`; der produktive Helper bleibt unverändert.
Prompt nur über Standard-Eingabe, keine Wörterbucheinträge in Prozessargumenten.

## Aufbau

51 vorab festgelegte Aufnahmen, je einmal ohne und mit derselben festen Liste:
AInauten, Reto Stuber, Fabian, Durban, Beau, Sraffa, Den Helder, Zürich.
42 öffentliche Schweizerdeutsch-Aufnahmen aus dem FHNW All Swiss German Dialects
Test Set v1 (28 Auswahl-, 14 Bestätigungsfälle), zwei Ausschnitte des veröffentlichten
AInauten-Promovideos, vier separat gekennzeichnete synthetische deutsche Beispiele
und drei Stille-/Rauschkontrollen. Keine privaten Aufnahmen, Wörterbücher oder Cloud.
Die deutschen Promo-/Synthesefälle sind kein Schweizerdeutsch-Nachweis.

102 gültige Decoderläufe. Ein vorheriger Sandbox-Versuch scheiterte an der
GPU-Initialisierung und lieferte keine verwertbaren Ergebnisse; er ist ausgeschlossen.

| 42 echte Schweizerdeutsch-Fälle | Ohne Hinweise | Mit Hinweisen |
| --- | ---: | ---: |
| Wortfehler / Referenzwörter | 110 / 398 | 100 / 398 |
| Normalisierte WER | 27,64 % | 25,13 % |
| Median Prozesszeit | 2,009 s | 2,133 s |

WER bewertet Wortfolgen, keine semantische Zuverlässigkeit. Der feste kleine
Datensatz und die vorgegebenen Namen sind keine allgemeine Trefferraten-Garantie.
Die Prozesszeiten sind keine Messung vom Loslassen des Kürzels bis zum Einfügen.

## Ergebnis und Entscheidung

Einige Namen werden besser: „Zos Rafa“ → „Sraffa“, „die U-Bahn“ → „Durban“ und
„Bo“ → „Beau“. Im separaten deutschen Beispiel wird „Reto Stober“ zu „Reto Stuber“.
Die Marke AInauten wird dagegen weiterhin nicht zuverlässig erkannt, im
Promovideo mit Hinweisen sogar als „iNaughton“. Ein Schweizer Fall ändert „10“ in
„zehn“; die erkannten Verneinungen sind zwischen den Bedingungen unverändert.

**Nicht übernommen:** Bei leisem Rauschen erzeugt die Begriffsliste das nicht
gesprochene Wort „Zürich“. Der rohe Decoder liefert außerdem in beiden Bedingungen
Text auf Stille. Das verletzt die vorab festgelegte Freigabeschranke. Die vorhandene
Sprachaktivitätsprüfung der App bleibt notwendig; diese Kontrollen testen bewusst
den Decoder direkt. Die normale lokale Wörterbuchkorrektur nach der Erkennung
bleibt aktiv. Keine globale Begriffsliste im produktiven Whisper-Decoder.

## Reproduzierbarkeit

Modell-SHA-256:
`d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1`.
Manifest-SHA-256:
`d2e15bd8a473f5bdf87af691acaaf4d784d3521bf97483de0b01f12b817f88b4`.
Ergebnis-SHA-256:
`32499b2b675765847944be9d2f186887d3efa0d8c9b353ffe45c4cde82a338b4`.

Gewichte und Audiodateien bleiben außerhalb von Git. Der öffentliche
[Modellvergleich](swiss-german-beta.md#local-model-comparison) nennt Quelle,
Modellversion und den Schweizer Testkorpus.

## English

A local paired test ran 51 fixed public/synthetic/control recordings twice
(102 valid decoder runs). On 42 real Swiss recordings, normalized WER improved
from 27.64% to 25.13%; some names improved. AInauten remained unreliable, and quiet
noise became the unspoken prompted name “Zürich”. Both raw-decoder conditions
also produced text on silence. The predefined safety gate failed, so decoder
vocabulary prompts are not enabled. Existing local post-recognition dictionary
replacement and voice activity checks remain in place. No private audio or
cloud inference was used. These small fixed tests do not establish general
Swiss German accuracy or end-to-end latency.
