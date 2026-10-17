# Schweizerdeutsch (Beta) / Swiss German (Beta)

## Deutsch

Unter **Diktieren → Sprachen → Schweizerdeutsch (Beta)** oder
**Einstellungen → Beta → Schweizerdeutsch** aktivieren und das Zusatzmodell
laden (1,08 GB). Danach mit dem bisherigen Diktierkürzel auf Schweizerdeutsch
sprechen. Die Erkennung zielt direkt auf hochdeutschen Text. Es gibt vorerst
keine separate Dialektauswahl. Die normale Sprachauswahl bleibt gespeichert und
gilt wieder, sobald die Beta ausgeschaltet wird. Die Beta ist standardmäßig aus.

Erkennung, Wörterbuch und Textoptimierung laufen lokal. Das gilt auch, wenn für
normale Diktate ein Cloud-Formatter eingerichtet ist: Dieser wird im Schweizer
Profil weder erzeugt noch autorisiert. Nur der bewusst gestartete Modelldownload
benötigt Internet. Der Modus lädt keine Gewichte im Aufnahmeweg nach. Sprachlose
Antworten werden nicht als Diktat erfunden; fehlerhafte Decoderantworten werden
abgelehnt. Bei einem Decoderfehler gibt es keinen stillen Parakeet-Fallback.

Whisper large-v3 q5_0 (MIT) übernimmt die Erkennung; Qwen bearbeitet im vorhandenen
lokalen Formatierungsweg Satzzeichen und Großschreibung. Qwen rekonstruiert keine
verlorenen Namen oder fehlende Wörter. „Original“ überspringt Qwen. Längere
Aufnahmen werden über VAD-/Überlappungsfenster verarbeitet und abschließend
akustisch abgeglichen. Das verringert Verluste kurzer Wörter an Abschnittsgrenzen.
Bis eine Minute wird die ganze Aufnahme abgeglichen, danach in begrenzten
60-Sekunden-Blöcken mit acht Sekunden Kontext. Auffällige lange Wiederholungsschleifen
werden als Decoderfehler abgelehnt; der Text wird nicht automatisch eingefügt.
Der isolierte Whisper-Prozess lädt sein Modell pro Abschnitt neu. Auf wiederholte
Gesamtabgleiche im Hintergrund wird für diese Beta verzichtet. Der Schlussabgleich
kann zusätzliche Sekunden benötigen; bei einer Zeitüberschreitung wird ein
unvollständiger Text nicht automatisch eingefügt. Die
Vorbereitung prüft Größe und SHA-256 und führt synthetische Stille aus, deren
Text vollständig verworfen wird. Sie hält kein Modell dauerhaft im RAM.

**Experimentell:** Wichtige Namen, Zahlen und Verneinungen prüfen. Die Erkennung
kann langsamer sein als der normale Parakeet-Modus. Ein zuverlässiges
Meetingprotokoll oder eine bestimmte Trefferrate für jeden Dialekt wird nicht
versprochen. Mehrere Sprecher und Protokollzusammenfassung sind kein neues
Feature dieser Beta.

### Weiterdiktieren während der Verarbeitung

Die folgende Beschreibung gilt für den veröffentlichten Stand 0.1.16. Der lokale
Folgestand 0.1.17 (21) erweitert die Warteschlange auf alle Audiosprachen und
fügt Ergebnisse automatisch in Reihenfolge ein, solange das ursprüngliche Ziel
sicher unverändert bleibt: [Details und Grenzen](queued-dictation.md).

Nach dem Loslassen kann eine neue Aufnahme beginnen, während die vorherige
lokal verarbeitet wird. Die Verarbeitung läuft nacheinander. Sobald Aufnahmen
überlappen, werden fertige Texte unter **Diktieren → Aufeinanderfolgende Diktate**
in Aufnahme-Reihenfolge gesammelt. Dort gemeinsam kopieren und bewusst einfügen;
es erfolgt kein verspätetes automatisches Einfügen in ein inzwischen anderes
Textfeld. Ein einzelnes Diktat verwendet weiterhin die geprüfte automatische
Texteingabe. Nicht bestätigte Einfügungen vorher im Zielfeld prüfen.

Die Warteschlange reserviert vor jeder Aufnahme einen begrenzten PCM-Arbeitsspeicher
(768 MiB Budget, höchstens drei Aufnahmen). Bei voller Warteschlange muss ein Text
fertig werden, bevor die nächste Aufnahme startet. Fertige gesammelte Texte bleiben
auch bei ausgeschaltetem Verlauf bis zum Kopieren oder Beenden im App-Speicher.
Esc verwirft noch laufende Aufnahmen und Verarbeitung; fertige Texte bleiben.
Der App-Neustart stellt nicht verarbeitete Aufnahmen nicht wieder her.

### Wörterbuchhinweise im Decoder: noch nicht aktiviert

Ein gepaarter lokaler Versuch mit 42 öffentlichen Schweizerdeutsch-Aufnahmen
verbesserte einige Eigennamen. Die gleiche feste Begriffsliste erzeugte bei
leisem Rauschen jedoch das ungesprochene Wort „Zürich“. Auch „AInauten“ wurde
in separaten deutschen Beispielen nicht zuverlässig besser. Deshalb wird
`initial_prompt` nicht im produktiven Decoder gesetzt. Die vorhandene lokale
Wörterbuchkorrektur nach der Erkennung bleibt erhalten. Details im
[Versuchsbericht](whisper-vocabulary-evaluation.md).

## English

Select **Dictation → Languages → Swiss German (Beta)** or enable it under
**Settings → Beta → Swiss German**, then download the extra model
(1.08 GB). Use your existing dictation shortcut to speak Swiss German and obtain
standard German text. No dialect selection is required. Your ordinary language
choices are preserved and restored when you disable the beta. It is off by default.

Recognition, dictionary matching and text optimization stay local, even if the
ordinary cloud formatter is enabled. The beta never constructs or authorizes
that formatter. Only the explicit model download needs a network connection.
Whisper large-v3 q5_0 performs acoustic recognition; the existing local Qwen
formatter handles punctuation and capitalization. Original skips Qwen. No silent
Parakeet fallback is used. Long recordings use VAD/overlap windows and a final acoustic reconciliation
(whole audio up to one minute, then bounded 60-second blocks with context);
the isolated helper reloads the model for each window. Warm-up checks the model
and primes caches; it is not a persistent model server.

**Experimental:** Check important names, numbers and negations. Recognition can
be slower. This beta does not promise meeting minutes, speaker diarization or a
guaranteed accuracy for every dialect.

### Consecutive recordings

Start another recording while earlier text is processed locally. Processing is
serial. Once recordings overlap, completed text is collected in capture order
under **Dictation → Consecutive dictations** for explicit combined copy and paste.
There is no delayed automatic insertion into a different field. A single
recording retains normal verified insertion. Check unconfirmed insertions in the
target before pasting again. A 768 MiB PCM reservation budget admits at most three
recordings; it does not represent total app/model memory. Pending audio lives in
RAM, not on disk. Escape discards unfinished work; completed snippets remain until
copying or quitting. Restarting does not restore pending recordings.

Decoder vocabulary prompts remain disabled: the local paired experiment improved
some names but also hallucinated an unspoken hinted name in quiet noise. Existing
post-recognition dictionary replacement remains in use.

## Local model comparison

Public [FHNW All Swiss German Dialects Test Set v1](https://cs.technik.fhnw.ch/i4ds-datasets)
(MIT). First 28 published records fixed before inference; a separate confirmation
set of two further records per region (14 total) fixed before confirmation runs.
No user dictations, cloud inference or private dictionaries were used.

| Candidate, same 28 recordings | Normalized WER | Median decoder process time | Peak process RSS |
| --- | ---: | ---: | ---: |
| Existing Parakeet v3 Original pipeline | 40.88% | 0.322 s | 500 MB |
| Whisper large-v3 q5_0 | 28.47% | 1.140 s | 1.57 GB |
| Whisper large-v3-turbo q5_0 | 27.01% | 0.740 s | 769 MB |
| Flix Swiss German full, locally converted to q5_0 | 25.91% | 1.206 s | 1.55 GB |

The 14 confirmation recordings were run with Large, Turbo and Flix. Turbo lost
a negation in one OST sample. Large and Flix retained it. All three still made
some important proper-name errors (for example Durban and Beau). The predefined
zero-critical-name-error criterion **was not met**. Large was selected for the
reviewable beta candidate because it retained that negation, has a pinned public
MIT download and reuses the existing isolated helper. Flix weights are evaluation
material only and are not distributed with this feature.

WER is not a meaning-error percentage: a different, correct German word order
can score poorly. Times include per-process model loading, mostly with warm
OS/Metal caches. First Parakeet/Large runs took 20.4/12.0 seconds. These figures
are not physical shortcut-release-to-paste measurements or total app memory.
Engineering tests do not establish general acoustic accuracy.

Model conversion source:
[Whisper models, pinned revision](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1).
Optional group `swiss-german`, path `swiss/ggml-large-v3-q5_0.bin`,
size 1081140203, SHA-256
`d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1`.

Developer fixture check (no microphone, target paste, settings or cloud access):

```sh
VoiceWisprProbe swiss-transcribe public-fixture.wav /path/to/ggml-large-v3-q5_0.bin original
VoiceWisprProbe swiss-transcribe public-fixture.wav /path/to/ggml-large-v3-q5_0.bin cleaned stream
```

Install the existing local Silero model first; cleaned also requires the local
Qwen model. Model download is intentionally separate from this probe.
