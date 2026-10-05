# AInauten Voice

**Sprechen statt tippen. Lokal auf deinem Mac.**

Kürzel halten, sprechen, loslassen. AInauten Voice schreibt deinen Text in das aktive Feld und optimiert Satzzeichen und Schreibweise. Spracherkennung und Textoptimierung laufen auf deinem Mac.

**[Beta herunterladen](https://voice.ainauten.com/)** · [Installation](#installation) · [Mit einem Agent installieren](#mit-einem-agent-installieren)

## In 36 Sekunden erklärt

https://github.com/user-attachments/assets/95a90b19-aea8-41cc-b28f-28d6cf89eee9

*Deutsch, mit Ton. Die Videografiken zeigen die Bedienung mit Beispieldaten.*

## Installation

1. [Beta herunterladen](https://voice.ainauten.com/), das DMG öffnen und **AInauten Voice.app** nach **Programme** ziehen.
2. App öffnen und die Einrichtung durchlaufen: Modelle laden, Sprache wählen, Mikrofon und Bedienungshilfen erlauben.
3. Probediktat testen. Danach den Cursor in ein Textfeld setzen und mit deinem Kürzel diktieren.

**macOS blockiert den Start?** Die Beta ist noch nicht Apple-notarisiert. Wähle **Fertig**, dann **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen**. [Anleitung mit Bildern](https://voice.ainauten.com/installation.html), auch offline im DMG unter **00 - ZUERST LESEN.html**. Bei einer Meldung über eine beschädigte oder schädliche App gilt diese Anleitung nicht.

**Du brauchst:** einen Mac mit Apple Silicon (M1 oder neuer), macOS 14+, mindestens 8 GB RAM und 8 GB freien Speicher. 16 GB RAM empfohlen. Die Modelle werden einmal heruntergeladen; danach kannst du lokal und offline diktieren.

## Was die App kann

- **In anderen Apps diktieren:** Kürzel halten oder freihändig starten. Esc bricht ab.
- **Text passend aufbereiten:** Original, Optimiert, E-Mail oder Chat, auch automatisch je App.
- **Wörterbuch bearbeiten:** Namen, Fachbegriffe und eigene Ersetzungen ergänzen.
- **Wispr Flow importieren:** Unterstützte Wörter, Ersetzungen, Sprachen und Kürzel übernehmen.
- **Diktate wiederfinden:** Im lokalen Verlauf suchen, kopieren und als Favorit speichern.
- **Nutzung sehen:** Gesprochene Wörter, Aufnahmezeit und Sprechgeschwindigkeit.

![AInauten Voice: Übersicht mit Verlauf und Nutzungsstatistik](site/assets/screenshots/overview.png)

| Wörterbuch | Statistik |
|---|---|
| ![Bearbeitbares Wörterbuch](site/assets/screenshots/dictionary.png) | ![Nutzungsstatistik](site/assets/screenshots/statistics.png) |

*Echte App-Oberflächen aus der Vorschau. Texte und Nutzungszahlen sind Beispieldaten.*

## Mit einem Agent installieren

Kopiere diesen Auftrag in deinen Agent:

> Installiere AInauten Voice auf meinem Mac. Lies zuerst AGENTS.md und docs/agent-installation.md im Repository https://github.com/MediaPublishing/ainauten-voice. Verwende die veröffentlichte Beta und erhalte bestehende Einstellungen.

Mikrofon, Bedienungshilfen und den ersten macOS-Start bestätigst du selbst. [Details zur Agent-Installation](docs/agent-installation.md).

## Deine Daten

Audio bleibt auf deinem Mac und wird nicht dauerhaft gespeichert. Den lokalen Textverlauf kannst du ausschalten. Cloud-Textoptimierung ist optional und standardmäßig aus.

<details>
<summary>Für Entwickler: Technik, Versionsstand und Lizenz</summary>

Die native App verwendet SwiftUI/AppKit, FluidAudio mit Parakeet v3 und eingebettetes llama.cpp mit Qwen3-4B. [Entwicklungsanleitung](native/README.md) · [Prüfbericht](native/docs/verification-report.md) · [Website entwickeln](site/README.md).

Der öffentliche Download ist Beta **0.1.1, Build 2**. Er enthält noch keinen Updater. Der vorbereitete signierte Updatekanal und die ausgeschaltete Lippenlesen-Forschungs-Beta gehören zum Entwicklungsstand. Der Fehlerbericht-Ausbau ist noch nicht allgemein aktiviert. Ein Git-Push aktualisiert die installierte App nicht. [Installations- und Updatehinweise](docs/agent-installation.md#updates-und-entwicklungsbuilds).

Der Quellcode ist öffentlich einsehbar. Für den eigenen App-Code wurde bislang keine Open-Source-Lizenz erteilt; alle Rechte bleiben vorbehalten. Abhängigkeiten und Modelle haben eigene Lizenzen. [Lizenznachweise](native/Resources/Licenses/NOTICE.md) · [Forschungsmodell-Lizenzen](native/lipreading_runtime/licenses/NOTICE-Research-Models.txt).

</details>

Entwickelt von [AInauten](https://www.ainauten.com/). AInauten Voice ist ein eigenständiges Projekt und steht nicht mit Wispr Flow in Verbindung.
