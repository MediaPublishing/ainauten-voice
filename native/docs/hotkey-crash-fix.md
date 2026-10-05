# Hotkey-Crash-Korrektur

5. Oktober 2026. Quellcode korrigiert und lokale App 0.1.1, Build 4 installiert.

Der gemeldete Hauptthread-Crash (`EXC_BAD_ACCESS`, Adresse `0x40`) tritt im globalen Tastatur-Callback während `MainActor.assumeIsolated` auf. Die seltene Originalstörung ist nicht deterministisch reproduziert; der Bericht beweist die Fehlerstelle, nicht die Herkunft des ungültigen Swift-Executor-Kontexts.

Der CGEventTap-Callback prüft jetzt vor dem Zugriff auf seinen Kontext den tatsächlichen Hauptthread. Ausschließlich die an `CFRunLoopGetMain()` gebundene synchrone Callback-Grenze überbrückt die Actor-Annotation ohne Swift-Executor-Introspektion. Tastaturereignisse werden weiterhin sofort konsumiert oder unverändert weitergereicht. Andere Threads greifen weder auf den Kontext noch auf die Zustandsmaschine zu. Timer und Aktivierungsbenachrichtigung wechseln regulär per MainActor-Task. Die AppKit-Ereignisschleife läuft außerhalb der kurzen Start-Closure; das Modell bleibt für die gesamte App-Laufzeit erhalten. Timer und Tap werden beim Entfernen aufgeräumt.

## Prüfungen

- 269 portable Vertragsfälle, 0 Fehler. Neue Regressionen prüfen synchronen Callback, Auto-Repeat, fremden Thread mit absichtlich ungültigem Kontext, Halten/Loslassen, Doppeltipp, freihändig, Esc und Timer-Abbruch. CLT-Adapter, kein Apple-XCTest-Lauf.
- Native CoreFoundation-Runloop-Probe: 20.002 synthetische Ereignisse mit echten Timern und parallelen MainActor-Wechseln; separater Prover ebenfalls bestanden. Keine OS-Tastendrücke, Mikrofonaufnahme oder Zwischenablage-Nutzung in dieser Probe. Wiederholbar mit `python3 native/scripts/run-hotkey-callback-checks.py`.
- Unabhängiger Code-/Probe-Check bestanden. Optimierter Release-Build mit Swift 6.4 und SDK 26.5 bestanden; SDK 27 hat auf der CLT-Umgebung noch ein separates SwiftUI-Macro-Problem. Vorhandene Warnungen der Kamera-Forschungsfunktion sind kein neu eingeführter Hotkey-Befund.
- Lokales Bundle: bestehende Signaturidentität und vollständige Signaturanforderung erhalten, Bibliothekspfade geprüft. Nur Programmdatei und Buildnummer geändert; vorhandene Ressourcen/Funktionen erhalten. App/Profil vor dem Austausch gesichert. Einstellungen bei Installation und nach Neustart bytegleich; native Oberfläche bestätigt Build 4 sowie bereite Freigaben und Modelle.

## Grenzen

Ein kurzer Stresstest ersetzt keine mehrstündige praktische Abnahme auf verschiedenen Macs. Die native Probe installiert keinen echten Accessibility-Tap. Bei der lokalen Startprüfung lief Wispr Flow parallel; die gemeinsamen Kürzel bleiben in diesem Konflikt bewusst pausiert. Keine neue Ende-zu-Ende-Mikrofon-/Einfügeabnahme.

Die Korrektur im Quellcode und die lokale Installation sind getrennt vom öffentlichen Download und vom Updatekanal. Der bisher veröffentlichte Installer wird durch einen Git-Push nicht ausgetauscht. Es wurde kein neues öffentliches Updateangebot aktiviert. Private Crashberichte, Nutzertexte und lokale Installationsbelege werden nicht mit dem Quellcode veröffentlicht.
