import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VoiceWisprCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case overview = "Übersicht", history = "Verlauf", statistics = "Statistik"
    case setup = "Einrichtung", dictation = "Diktieren", formatting = "Text & Stil", dictionary = "Wörterbuch", migration = "Wispr Flow", privacy = "Datenschutz", updates = "Updates", beta = "Beta", help = "Hilfe"
    var id: String { rawValue }
    var icon: String { switch self { case .overview: "waveform"; case .history: "clock.arrow.circlepath"; case .statistics: "chart.bar.xaxis"; case .setup: "checklist"; case .dictation: "keyboard"; case .formatting: "text.alignleft"; case .dictionary: "character.book.closed"; case .migration: "arrow.left.arrow.right"; case .privacy: "lock"; case .updates: "arrow.triangle.2.circlepath"; case .beta: "flask"; case .help: "questionmark.circle" } }
    var isMain: Bool { [.overview, .history, .statistics, .dictionary, .formatting].contains(self) }
    var previewName: String { switch self { case .overview: "overview"; case .history: "history"; case .statistics: "statistics"; case .dictionary: "dictionary"; case .updates: "updates"; case .beta: "beta"; case .help: "help"; default: "" } }
}

/// Models come first so the large download runs while the user completes the
/// other steps. The Wispr Flow import precedes the language choice so imported
/// languages are visible and not blocked by an earlier manual selection.
enum SetupStep: Int, CaseIterable, Identifiable {
    case models, wispr, language, permissions, practice, switchover
    var id: Int { rawValue }
    var title: String { switch self { case .models: "Modelle"; case .wispr: "Wispr Flow"; case .language: "Sprache"; case .permissions: "Freigaben"; case .practice: "Probediktat"; case .switchover: "Wechsel" } }
}

struct SettingsNavigation: Equatable {
    let id = UUID()
    let section: SettingsSection
    let setupStep: SetupStep?
}

struct WindowCloseButton: View {
    var label = "Fenster schließen"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.secondary).help(label).accessibilityLabel(label).pointerAwareFocus()
    }
}

private struct SidebarLabelStyle: LabelStyle {
    static let iconWidth: CGFloat = 16
    static let spacing: CGFloat = 8
    static var textInset: CGFloat { iconWidth + spacing }

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            configuration.icon.frame(width: Self.iconWidth)
            configuration.title
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var section: SettingsSection = .overview
    @FocusState private var focusedSection: SettingsSection?
    @ObservedObject private var focusPresentation = FocusPresentation.shared
    @State private var step: SetupStep = .models
    @State private var showAllLanguages = false
    @State private var key = ""
    @State private var shortcutMonitor: Any?
    @State private var appBundle = ""
    @State private var appStyle: TextStyle = .cleaned
    @State private var showReport = false
    @State private var captureAction = "hold"
    @State private var settingsExpanded = false

    var body: some View {
        GeometryReader { geometry in
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) { Image(systemName: "waveform").font(.system(size: 22, weight: .medium)); Text("AInauten Voice").font(.system(size: 17, weight: .semibold)) }.padding(.bottom, 28).padding(.top, 12)
                ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                ForEach([SettingsSection.overview, .history, .statistics, .dictionary, .formatting, .help] + (settingsExpanded ? [.dictation, .setup, .migration, .privacy, .updates, .beta] : [])) { item in
                    Button { section = item; focusedSection = item } label: {
                        Label(item.rawValue, systemImage: item.icon).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9).padding(.horizontal, 10)
                            .background(section == item ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .overlay { RoundedRectangle(cornerRadius: 7).stroke(focusedSection == item && focusPresentation.keyboardNavigation ? Color(nsColor: .keyboardFocusIndicatorColor) : .clear, lineWidth: 2).allowsHitTesting(false) }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).focused($focusedSection, equals: item).focusEffectDisabled()
                        .accessibilityAddTraits(section == item ? [.isSelected] : [])
                }
                }
                }.scrollIndicators(.hidden)
                Button {
                    settingsExpanded.toggle()
                    if settingsExpanded { section = .dictation; focusedSection = .dictation }
                    else if !section.isMain { section = .overview; focusedSection = .overview }
                } label: {
                    HStack { Label("Einstellungen", systemImage: "gearshape"); Spacer(); Image(systemName: settingsExpanded ? "chevron.up" : "chevron.down").font(.system(size: 10)) }
                        .padding(.vertical, 10).padding(.horizontal, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).pointerAwareFocus().help("Kürzel, Sprachen, Einrichtung und Datenschutz")
                VStack(alignment: .leading, spacing: 4) {
                    Label("Audio bleibt auf deinem Mac", systemImage: "lock.fill").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Version \(model.updates.version) · Lokal").font(.system(size: 11)).foregroundStyle(.tertiary)
                        .padding(.leading, SidebarLabelStyle.textInset)
                }.padding(.leading, 10)
            }.labelStyle(SidebarLabelStyle()).padding(18).frame(width: 195).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(section.rawValue).font(.system(size: 28, weight: .bold))
                    Spacer()
                    Button { showReport = true } label: {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 16))
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help("Prüfbericht anzeigen").accessibilityLabel("Prüfbericht anzeigen").pointerAwareFocus()
                    WindowCloseButton { model.closeSettings() }
                }.padding(.horizontal, 28).padding(.top, 32).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if section != .help { CrashReportNotice(reports: model.reports) { section = .help; focusedSection = .help } }
                        if let error = model.errorMessage {
                            HStack(alignment: .top) { Image(systemName: "exclamationmark.triangle"); Text(error).textSelection(.enabled); Spacer(); Button("Melden") { section = .help; focusedSection = .help }; WindowCloseButton(label: "Fehlermeldung schließen") { model.dismissError() } }.padding(12).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if !model.importReceipt.isEmpty && (section == .setup || section == .migration) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(model.importFailed ? "Import nicht abgeschlossen" : "Import-Ergebnis", systemImage: model.importFailed ? "exclamationmark.triangle" : "checkmark.circle").font(.system(size: 13, weight: .semibold))
                                Text(model.importReceipt).font(.system(size: 12)).textSelection(.enabled)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background((model.importFailed ? Color.orange : Color.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                        switch section {
                        case .overview: DashboardView(model: model, availableWidth: geometry.size.width - 252)
                        case .history: HistoryView(model: model)
                        case .statistics: StatisticsView(model: model)
                        case .setup: onboarding
                        case .dictation: dictation
                        case .formatting: formatting
                        case .dictionary: DictionaryEditor(model: model)
                        case .migration: migration
                        case .privacy: privacy
                        case .updates: UpdateSettingsView(updates: model.updates)
                        case .beta: beta
                        case .help: ErrorReportView(reports: model.reports)
                        }
                        Spacer(minLength: 20)
                    }.padding(.horizontal, 28).padding(.top, 4).padding(.bottom, 28).frame(maxWidth: section.isMain ? .infinity : 800, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading).id("page-top")
                }.disabled(model.importing)
                    .onChange(of: section) { _, _ in scroll.scrollTo("page-top", anchor: .top) }
                    .onChange(of: step) { _, _ in scroll.scrollTo("page-top", anchor: .top) }
                }
            }
        }.font(.system(size: 13)).frame(minWidth: 640, minHeight: 560)
        .onDisappear { endShortcutCapture() }
        .onChange(of: model.settingsNavigation, initial: true) { _, request in
            guard let request else { return }
            section = request.section
            if !section.isMain { settingsExpanded = true }
            if let requestedStep = request.setupStep { step = requestedStep }
            focusedSection = request.section
        }
        .onChange(of: model.importRevision) { _, _ in if section == .setup && step == .wispr { step = .language } }
        .onChange(of: model.microphoneGranted && model.accessibilityGranted) { _, granted in if granted && section == .setup && step == .permissions { step = .practice } }
        .sheet(isPresented: $showReport) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Prüfbericht").font(.system(size: 20, weight: .semibold)); Spacer(); WindowCloseButton(label: "Prüfbericht schließen") { showReport = false }.keyboardShortcut(.cancelAction) }
                ReportView(markdown: reportText)
            }.padding(24)
                .frame(width: min(860, max(530, geometry.size.width - 48)),
                       height: min(720, max(400, geometry.size.height - 48)))
        }
        }.frame(minWidth: 640, minHeight: 560)
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Dein Mac, deine Stimme.").font(.system(size: 18, weight: .semibold))
            if model.document.settings.onboardingComplete {
                Label("Einrichtung abgeschlossen. Der erfolgreiche Probetest ist bestätigt.", systemImage: "checkmark.circle").foregroundStyle(.green)
                if step != .practice { Button("Zum Diktieren") { section = .dictation; focusedSection = .dictation } }
            } else { Text("Starte den Download, dann richtest du den Rest ein, während die Modelle laden.").foregroundStyle(.secondary) }
            HStack(spacing: 6) { ForEach(SetupStep.allCases) { item in
                let done = model.setupStepDone(item)
                Button { step = item } label: { VStack(spacing: 6) {
                    Group { if done && item != step { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) } else { Text("\(item.rawValue + 1)").font(.system(size: 12, weight: .semibold)) } }
                        .frame(width: 26, height: 26).background(item == step ? Color.accentColor : done ? Color.green.opacity(0.16) : Color.secondary.opacity(0.1), in: Circle()).foregroundStyle(item == step ? Color.white : done ? Color.green : Color.primary)
                    Text(item.title).font(.system(size: 10)).lineLimit(1)
                }.frame(maxWidth: .infinity).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Schritt \(item.rawValue + 1): \(item.title)" + (done ? ", erledigt" : ""))
            } }
            if model.downloading && step != .models {
                HStack(spacing: 10) { ProgressView(value: model.downloadFraction).frame(maxWidth: 220); Text(model.downloadLabel).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1) }
            }
            Divider()
            Group {
                switch step {
                case .models: models
                case .wispr: migrationPreview
                case .language: languagePicker
                case .permissions: permissions
                case .practice: practice
                case .switchover: migrationSwitch
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            HStack {
                if let previous = SetupStep(rawValue: step.rawValue - 1) { Button("Zurück") { step = previous } }
                Spacer()
                if step == .practice && model.practiceFeedback.succeeded {
                    let next = model.pendingSetupStep
                    Button(next == .switchover ? "Weiter zum Wispr-Flow-Wechsel" : next == .permissions ? "Bedienungshilfen freigeben" : "Zum Diktieren") {
                        if let next { step = next } else { model.completeSetup() }
                    }.buttonStyle(.borderedProminent)
                }
                else if let next = SetupStep(rawValue: step.rawValue + 1) { Button("Weiter") { step = next }.buttonStyle(.borderedProminent) }
                else { Button("Einrichtung abschließen") { model.completeSetup(); if model.document.settings.onboardingComplete { section = .dictation } }.buttonStyle(.borderedProminent).disabled(!model.canCompleteSetup) }
            }
        }
    }
    private var practice: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.practiceFeedback.succeeded ? (model.practiceAudioSource != nil ? "Testaudio erkannt" : "Diktat erkannt") : "Ein Satz genügt").font(.system(size: 19, weight: .semibold))
            if let source = model.practiceAudioSource {
                Label("Dateitest · \(source)", systemImage: "testtube.2").foregroundStyle(.secondary)
                Text("Dieser Test verarbeitet die angegebene Audiodatei. Das Mikrofon bleibt aus. Starte das Testaudio und klicke anschließend auf „Testaudio auswerten“.").foregroundStyle(.secondary)
            } else {
                Text("Sage zum Beispiel: „Dies ist ein kurzer Test der Spracherkennung.“ Nach zwei Sekunden Sprechpause stoppt die Probe automatisch, spätestens nach 15 Sekunden. Der erkannte Text erscheint hier; dein anderes Textfeld bleibt unverändert.").foregroundStyle(.secondary)
            }
            if model.practiceFeedback.phase == .recording {
                Label(model.practiceAudioSource != nil ? "Testaudio ist bereit" : model.captureReady ? "Ich höre zu · \(model.durationLabel)" : "Mikrofon wird gestartet …", systemImage: model.practiceAudioSource != nil ? "waveform" : "mic.fill")
                ProgressView(value: Double(model.level)).frame(maxWidth: 250)
            }
            if model.practiceFeedback.phase == .processing { ProgressView("Dein Satz wird verarbeitet …") }
            HStack {
                Button(model.practiceAudioSource != nil ? (model.practiceFeedback.phase == .recording ? "Testaudio auswerten" : "Testaudio starten") : model.practiceFeedback.phase == .recording ? "Jetzt stoppen" : model.practiceFeedback.phase == .idle ? "Probediktat starten" : "Noch einmal testen") {
                    if model.practiceFeedback.phase == .recording { model.stop() } else { model.startPractice() }
                }.buttonStyle(.borderedProminent).disabled(!model.modelsReady || !model.microphoneGranted || model.state == .processing || (model.state == .recording && !model.practiceFeedback.isActive))
                if model.practiceFeedback.isActive { Button("Abbrechen") { model.cancel() }.keyboardShortcut(.cancelAction) }
            }
            if !model.practiceFeedback.message.isEmpty {
                Label(model.practiceFeedback.message, systemImage: model.practiceFeedback.succeeded ? "checkmark.circle" : model.practiceFeedback.phase == .cancelled ? "xmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(model.practiceFeedback.succeeded ? Color.green : Color.primary)
            }
            if let result = model.practiceFeedback.result {
                HStack { Text(result.isComplete ? "Erkannter Text" : "Erkannter Teiltext").font(.system(size: 13, weight: .semibold)); Spacer(); Button("Kopieren") { model.copyPracticeResult() } }
                Text(result.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                if result.usedFallback { Label("Die Optimierung war nicht verfügbar. Angezeigt wird der Originaltext.", systemImage: "info.circle").foregroundStyle(.secondary) }
            } else if model.practiceFeedback.phase == .idle && model.practiceComplete {
                Text("Ein früherer Probetest war erfolgreich. Starte eine neue Probe, um das aktuelle Ergebnis zu sehen.").foregroundStyle(.secondary)
            }
            if !model.microphoneGranted { Button("Mikrofon freigeben") { step = .permissions } }
            else if !model.modelsReady { Label(model.downloading ? "Die Probe ist möglich, sobald die Modelle geladen sind." : "Lade zuerst die Modelle im Schritt „Modelle“.", systemImage: "hourglass").foregroundStyle(.secondary) }
        }
    }
    private let languages: [(String, String)] = [("de","Deutsch"),("en","Englisch"),("bg","Bulgarisch"),("da","Dänisch"),("et","Estnisch"),("fi","Finnisch"),("fr","Französisch"),("el","Griechisch"),("it","Italienisch"),("hr","Kroatisch"),("lv","Lettisch"),("lt","Litauisch"),("mt","Maltesisch"),("nl","Niederländisch"),("pl","Polnisch"),("pt","Portugiesisch"),("ro","Rumänisch"),("ru","Russisch"),("sk","Slowakisch"),("sl","Slowenisch"),("es","Spanisch"),("sv","Schwedisch"),("cs","Tschechisch"),("uk","Ukrainisch"),("hu","Ungarisch")]
    private func languageName(_ code: String) -> String { languages.first { $0.0 == code }?.1 ?? Locale(identifier: "de").localizedString(forLanguageCode: code) ?? code }
    private func flag(_ code: String) -> String { ["de":"🇩🇪", "en":"🇬🇧", "bg":"🇧🇬", "da":"🇩🇰", "et":"🇪🇪", "fi":"🇫🇮", "fr":"🇫🇷", "el":"🇬🇷", "it":"🇮🇹", "hr":"🇭🇷", "lv":"🇱🇻", "lt":"🇱🇹", "mt":"🇲🇹", "nl":"🇳🇱", "pl":"🇵🇱", "pt":"🇵🇹", "ro":"🇷🇴", "ru":"🇷🇺", "sk":"🇸🇰", "sl":"🇸🇮", "es":"🇪🇸", "sv":"🇸🇪", "cs":"🇨🇿", "uk":"🇺🇦", "hu":"🇭🇺"][code] ?? "🌐" }
    private func languageChip(_ code: String, _ name: String, selected: Bool) -> some View {
        Button {
            if selected { if model.document.settings.languages.count > 1 { model.document.settings.languages.removeAll { $0 == code } } }
            else { model.document.settings.languages.append(code) }
        } label: {
            HStack(spacing: 6) { Text(flag(code)).accessibilityHidden(true); Text(name).lineLimit(1); Spacer(minLength: 0); Image(systemName: selected ? "checkmark" : "plus").font(.system(size: 11, weight: .semibold)) }
                .padding(.horizontal, 8).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.bordered).tint(selected ? .accentColor : .secondary)
            .disabled(selected && model.document.settings.languages.count == 1)
            .accessibilityLabel(name + (selected ? ", ausgewählt. Entfernen" : ", hinzufügen"))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private var languagePicker: some View {
        languageSelection(compact: false)
    }
    private func languageSelection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Text(compact ? "Sprachen" : "Welche Sprachen sprichst du?").font(.system(size: compact ? 16 : 19, weight: .semibold))
            Text(compact ? "Automatische Erkennung, auch bei Sprachwechseln." : "Die Erkennung findet die Sprache automatisch, auch beim Wechsel mitten im Satz.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !compact { Text("Ausgewählt").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(model.document.settings.languages, id: \.self) { code in languageChip(code, languageName(code), selected: true) }
            }
            if !compact { Text("Klicke eine Sprache an. Mindestens eine bleibt ausgewählt.").font(.system(size: 12)).foregroundStyle(.secondary) }
            Button { showAllLanguages.toggle() } label: {
                HStack(spacing: 8) { Image(systemName: showAllLanguages ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)); Text(showAllLanguages ? "Weitere Sprachen ausblenden" : "Weitere Sprachen hinzufügen"); Spacer() }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(showAllLanguages ? "Weitere Sprachen ausblenden" : "Weitere Sprachen hinzufügen")
            if showAllLanguages {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(languages.filter { !model.document.settings.languages.contains($0.0) }, id: \.0) { code, name in languageChip(code, name, selected: false) }
                }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private var models: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Erkennung und Optimierung installieren").font(.system(size: 19, weight: .semibold))
            Text("Einmalig etwa 3 GB: Parakeet für deine Stimme, Qwen für gute Texte. Danach funktionieren beide offline.").foregroundStyle(.secondary)
            if model.downloading { ProgressView(value: model.downloadFraction); Text(model.downloadLabel).font(.system(size: 12)).monospacedDigit(); Button("Download pausieren") { model.pauseDownload() } }
            else if model.preparing { ProgressView("Modelle werden geladen …") }
            else if model.modelsReady { Label("Beide Modelle sind geladen", systemImage: "checkmark.circle").foregroundStyle(.green) }
            else {
                Button("Modelle herunterladen (ca. 3 GB)") {
                    model.installModels()
                    // The download continues in the background while the remaining steps are done.
                    if section == .setup && step == .models { step = .wispr }
                }.buttonStyle(.borderedProminent)
            }
            Text("Der Download läuft im Hintergrund weiter, du kannst direkt mit den nächsten Schritten fortfahren. Unterbrochene Downloads werden fortgesetzt, jede Datei wird vor dem Laden geprüft.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Zwei Freigaben für dein Diktat").font(.system(size: 19, weight: .semibold))
            HStack { VStack(alignment: .leading, spacing: 4) { Label("Mikrofon", systemImage: model.microphoneGranted ? "checkmark.circle" : "mic"); Text("Nur während einer Aufnahme aktiv.").font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Button(model.microphoneGranted ? "Erlaubt" : "Freigeben") { model.requestMicrophone() }.disabled(model.microphoneGranted) }
            HStack { VStack(alignment: .leading, spacing: 4) { Label("Bedienungshilfen", systemImage: model.accessibilityGranted ? "checkmark.circle" : "keyboard"); Text("Für Tastenkürzel und geprüftes Einfügen.").font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Button(model.accessibilityGranted ? "Erlaubt" : "Einstellungen öffnen") { model.requestAccessibility() }.disabled(model.accessibilityGranted) }
            if !model.accessibilityGranted {
                Text("1. Öffne „Bedienungshilfen“.\n2. Ziehe die App unten in die Liste oder füge sie über + hinzu.\n3. Schalte den Eintrag „AInauten Voice“ ein.").fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 38, height: 38).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) { Text("AInauten Voice.app").font(.system(size: 13, weight: .semibold)); Text("Diese laufende App in die Liste ziehen").font(.system(size: 12)).foregroundStyle(.secondary) }
                    Spacer()
                    Image(systemName: "arrow.up.forward.square").foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                    .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                    .accessibilityLabel("AInauten Voice App. In die macOS-Bedienungshilfen ziehen. Alternativ im Finder zeigen.")
                Text(Bundle.main.bundlePath).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button("Aktuelle App im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                Text("Die Freigabe von Wispr Flow lässt sich nicht übernehmen.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private var dictation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(model.status, systemImage: model.state == .ready ? "mic" : model.conflict ? "exclamationmark.circle" : "info.circle").fixedSize(horizontal: false, vertical: true)
            if model.conflict { Button("Wechsel von Wispr Flow abschließen") { section = .migration; focusedSection = .migration } }
            Text("Cursor ins Textfeld setzen, Kürzel halten, sprechen und loslassen. Doppeltipp startet freihändig; erneutes Drücken stoppt. Die Pill erscheint nur während des Diktats.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    dictationShortcuts.frame(minWidth: 330, maxWidth: .infinity)
                    languageSelection(compact: true).frame(minWidth: 300, maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 20) {
                    dictationShortcuts
                    Divider()
                    languageSelection(compact: true)
                }
            }
            Divider()
            dictationReadiness
        }
    }
    private var dictationShortcuts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tastenkürzel").font(.system(size: 16, weight: .semibold)).padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 4) {
                shortcutRow("Halten zum Diktieren", action: "hold", shortcuts: [model.document.settings.shortcut] + (model.document.settings.shortcutBindings?.holdExtras ?? []))
                shortcutRow("Freihändig", action: "handsFree", shortcuts: model.document.settings.shortcutBindings?.handsFree ?? [])
                shortcutRow("Abbrechen", action: "cancel", shortcuts: model.document.settings.shortcutBindings?.cancel.isEmpty == false ? model.document.settings.shortcutBindings!.cancel : [Shortcut(keyCode: 53, modifiers: 0)])
                shortcutRow("Letzten Text kopieren", action: "copyLast", shortcuts: model.document.settings.shortcutBindings?.copyLast ?? [])
                shortcutRow("Letzten Text einfügen", action: "pasteLast", shortcuts: model.document.settings.shortcutBindings?.pasteLast ?? [])
            }
            if model.shortcutCapture { Text("Kombination drücken und loslassen. Esc bricht die Auswahl ab.").foregroundStyle(.secondary).font(.system(size: 12)) }
            Divider().padding(.vertical, 4)
            Toggle("Tastenkürzel aktiv", isOn: Binding(get: { !model.document.settings.paused }, set: { model.document.settings.paused = !$0; if !$0 { model.cancel() } }))
                .help("Ausgeschaltet reagiert AInauten Voice nicht auf globale Kürzel.")
            if model.document.settings.paused { Text("Globale Kürzel sind ausgeschaltet.").font(.system(size: 12)).foregroundStyle(.secondary) }
            Toggle("AInauten Voice bei der Anmeldung starten", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
        }
    }
    private var dictationReadiness: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    readinessLabel("Mikrofon", ready: model.microphoneGranted)
                    readinessLabel("Bedienungshilfen", ready: model.accessibilityGranted)
                    readinessLabel(model.modelsReady ? "Modelle geladen" : model.preparing ? "Modelle laden …" : "Modelle fehlen", ready: model.modelsReady)
                }
                VStack(alignment: .leading, spacing: 6) {
                    readinessLabel("Mikrofon", ready: model.microphoneGranted)
                    readinessLabel("Bedienungshilfen", ready: model.accessibilityGranted)
                    readinessLabel(model.modelsReady ? "Modelle geladen" : model.preparing ? "Modelle laden …" : "Modelle fehlen", ready: model.modelsReady)
                }
            }
            Button(model.pendingSetupStep == nil ? "Einrichtung anzeigen" : "Einrichtung fortsetzen") {
                section = .setup; focusedSection = .setup; step = model.pendingSetupStep ?? .permissions
            }.buttonStyle(.link)
        }.font(.system(size: 12))
    }
    private func readinessLabel(_ title: String, ready: Bool) -> some View {
        Label(title, systemImage: ready ? "checkmark.circle" : "exclamationmark.circle")
            .foregroundStyle(ready ? Color.secondary : Color.orange)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(title + (ready ? ": bereit" : ": offen"))
    }
    private var formatting: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("So soll dein Text aussehen").font(.system(size: 19, weight: .semibold))
            Picker("Standard", selection: $model.document.settings.defaultStyle) { ForEach(TextStyle.allCases) { Text($0.title).tag($0) } }
            Picker("Manuelle Auswahl", selection: $model.document.settings.manualStyle) { Text("Automatisch nach App").tag(TextStyle?.none); ForEach(TextStyle.allCases) { Text($0.title).tag(Optional($0)) } }
            Text("Eine manuelle Auswahl hat Vorrang. E-Mail fügt lesbare Absätze hinzu, Chat bleibt knapp. Namen, Zahlen und Bedeutung sollen erhalten bleiben.").foregroundStyle(.secondary)
            Divider()
            Text("Stil pro App").font(.system(size: 16, weight: .semibold))
            ForEach(model.document.settings.appStyles.keys.sorted(), id: \.self) { bundle in
                HStack { Text(appName(for: bundle)).lineLimit(1); Spacer(); Text(model.document.settings.appStyles[bundle]?.title ?? ""); Button { model.document.settings.appStyles.removeValue(forKey: bundle) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel("App-Zuordnung entfernen") }
            }
            Button(appBundle.isEmpty ? "App auswählen …" : appName(for: appBundle)) { chooseApp() }
            HStack { Picker("Stil", selection: $appStyle) { ForEach(TextStyle.allCases) { Text($0.title).tag($0) } }; Button("Zuordnen") { model.document.settings.appStyles[appBundle.trimmingCharacters(in: .whitespaces)] = appStyle; appBundle = "" }.disabled(appBundle.trimmingCharacters(in: .whitespaces).isEmpty) }
            Divider()
            TextField("OpenAI-kompatible Adresse", text: Binding(get: { model.document.settings.cloudEndpoint }, set: { model.document.settings.cloudEndpoint = $0.trimmingCharacters(in: .whitespacesAndNewlines); model.document.settings.cloudEnabled = false }))
            Toggle("Cloud nur für Textoptimierung aktivieren", isOn: Binding(get: { model.document.settings.cloudEnabled }, set: setCloudEnabled))
            Text("Bei Aktivierung wird ausschließlich dein transkribierter Text mit bis zu zwei vorherigen Sätzen und passenden Wörterbucheinträgen an \(model.document.settings.cloudEndpoint) gesendet. Eine Änderung der Adresse schaltet Cloud aus. Audio bleibt lokal. Bei Fehlern bleibt der Originaltext verfügbar.").font(.system(size: 12)).foregroundStyle(.secondary)
            if model.document.settings.cloudEnabled {
                TextField("Modellname", text: $model.document.settings.cloudModel)
                SecureField("Eigener API-Schlüssel", text: $key)
                Button("Im Schlüsselbund speichern") { model.saveKey(key); key = "" }.disabled(key.isEmpty)
                Button("API-Schlüssel entfernen") { model.saveKey(""); key = "" }
                Text("Der Schlüssel wird nicht exportiert.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private var migration: some View { VStack(alignment: .leading, spacing: 24) { migrationPreview; Divider(); migrationSwitch } }
    private var migrationPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Deine Wispr-Flow-Einstellungen übernehmen").font(.system(size: 19, weight: .semibold))
            if model.isUIPreview { Text("Oberflächenvorschau. Import und gespeicherte Einstellungen sind hier deaktiviert.").foregroundStyle(.secondary) }
            else if model.importRefreshing || !model.importPreviewLoaded { ProgressView("Wispr-Flow-Einstellungen werden geprüft …") }
            else if model.importPreview.isPartial { ForEach(model.importPreview.errors, id: \.self) { Text($0).foregroundStyle(.secondary) } }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 36) {
                        migrationCounts
                        migrationBindings
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 20) { migrationCounts; migrationBindings }
                }
                ForEach(model.importPreview.unsupported, id: \.self) { Text("Ausgelassen: \(unsupportedLabel($0))").font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            if !model.isUIPreview {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { migrationImportButton; migrationRefreshButton }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 10) { migrationImportButton; migrationRefreshButton }
                }
                Text("In AInauten Voice gespeichert: \(model.document.dictionary.count) Wörterbucheinträge. Sprachen: \(model.document.settings.languages.map(languageName).joined(separator: ", ")). Tastenkürzel: \(model.document.settings.shortcut.spokenLabel).")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Button("Wörterbuch aus CSV importieren …") { model.importDictionaryCSV() }.disabled(model.isUIPreview)
            if model.canUndoImport { Button("Letzten Wispr-Import rückgängig machen") { model.undoImport() } }
            if !model.importReceipt.isEmpty && !model.importFailed && section == .migration {
                Button(model.document.settings.onboardingComplete ? "Zum Diktieren" : "Einrichtung fortsetzen") {
                    section = model.document.settings.onboardingComplete ? .dictation : .setup
                    focusedSection = section
                    if !model.document.settings.onboardingComplete { step = model.pendingSetupStep ?? .practice }
                }.buttonStyle(.borderedProminent)
            }
            Text("Die Quelle wird nur gelesen. Wiederholter Import erzeugt keine Duplikate; deine manuellen Änderungen bleiben erhalten.").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Bereits von dir angepasste Sprachen, Tastenkürzel und Schreibstile behalten Vorrang.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private var migrationCounts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wörterbuch").font(.system(size: 13, weight: .semibold)).padding(.bottom, 2)
            LabeledContent("Wörter", value: "\(model.importPreview.words)")
            LabeledContent("Ersetzungen", value: "\(model.importPreview.replacements)")
            LabeledContent("Gelöschte Einträge überspringen", value: "\(model.importPreview.deleted)")
            if model.importPreview.sourceDuplicates > 0 {
                LabeledContent("Doppelte Einträge zusammenführen", value: "\(model.importPreview.sourceDuplicates)")
                LabeledContent("Eindeutige Einträge übernehmen", value: "\(model.importPreview.uniqueEntries)")
            }
        }
    }
    private var migrationBindings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Einstellungen").font(.system(size: 13, weight: .semibold)).padding(.bottom, 2)
            LabeledContent("Sprachen", value: model.importPreview.languages.map(languageName).joined(separator: ", "))
            if let shortcut = model.importPreview.shortcut { LabeledContent("Tastenkürzel", value: shortcut.label) }
            if !model.importPreview.shortcutBindings.handsFree.isEmpty { LabeledContent("Freihändig", value: model.importPreview.shortcutBindings.handsFree.map(\.label).joined(separator: " / ")) }
            if !model.importPreview.shortcutBindings.copyLast.isEmpty { LabeledContent("Letzten Text kopieren", value: model.importPreview.shortcutBindings.copyLast.map(\.label).joined(separator: " / ")) }
            if !model.importPreview.shortcutBindings.pasteLast.isEmpty { LabeledContent("Letzten Text einfügen", value: model.importPreview.shortcutBindings.pasteLast.map(\.label).joined(separator: " / ")) }
        }
    }
    private var migrationImportButton: some View {
        Button(model.importing ? "Einstellungen werden übernommen …" : model.importPreview.isPartial ? "Erneut prüfen und importieren" : "Unterstützte Einstellungen importieren") { model.importWispr() }.buttonStyle(.borderedProminent).disabled(!model.canImportWispr)
    }
    private var migrationRefreshButton: some View {
        Button("Erneut prüfen") { model.refreshImportPreview() }.disabled(model.importRefreshing || model.importing)
    }
    private var migrationSwitch: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Von Wispr Flow zu AInauten Voice wechseln").font(.system(size: 19, weight: .semibold))
            if model.wisprInstalled || model.wisprRunning {
                Text("Der Wechsel versucht, den Autostart von Wispr Flow auszuschalten, sonst öffnet sich die passende Einstellung. Danach wird Wispr Flow regulär beendet und bleibt installiert. Bis zum Beenden reagieren die übernommenen Kürzel nur in Wispr Flow.").foregroundStyle(.secondary)
                Button(model.switchingWispr ? "Wispr Flow wird beendet …" : "Wispr-Flow-Autostart ausschalten und Wispr Flow beenden") { model.switchFromWispr() }.disabled(model.switchingWispr)
                if !model.switchReceipt.isEmpty { Text(model.switchReceipt).textSelection(.enabled).foregroundStyle(.secondary) }
                Label(model.wisprRunning ? "Wispr Flow läuft noch" : "Wispr Flow ist beendet", systemImage: model.wisprRunning ? "exclamationmark.circle" : "checkmark.circle")
            } else {
                Label("Wispr Flow ist nicht installiert. Kein Wechsel nötig.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            if !model.document.settings.onboardingComplete, let missing = model.pendingSetupStep, missing != .switchover {
                Text("Zum Abschluss fehlt noch: \(missing == .models ? "Modelle laden" : missing == .permissions ? "Mikrofon und Bedienungshilfen freigeben" : "ein erfolgreiches Probediktat").").foregroundStyle(.secondary)
                Button(missing == .models ? "Zu den Modellen" : missing == .permissions ? "Zu den Freigaben" : "Probediktat starten") {
                    model.settingsNavigation = SettingsNavigation(section: .setup, setupStep: missing)
                }
            }
            Label("So diktierst du: \(model.document.settings.shortcut.spokenLabel) halten, sprechen, loslassen.", systemImage: "keyboard").fixedSize(horizontal: false, vertical: true)
            Text("Rückwechsel jederzeit über das AInauten-Voice-Menü in der Menüleiste.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private var privacy: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Deine Stimme bleibt lokal").font(.system(size: 20, weight: .semibold))
            Text("Audio wird nur im Speicher verarbeitet und nach dem Diktat freigegeben. Diagnosemeldungen enthalten keine Diktate.")
            Toggle("Diktate lokal im Verlauf speichern", isOn: Binding(get: { model.historyEnabled }, set: { model.document.settings.historyEnabled = $0 }))
            Text("Originaltext und aufbereiteter Text bleiben auf diesem Mac, auch nach einem Neustart. Abschalten gilt für neue Diktate; bestehende Texte bleiben verfügbar. Die Statistik berücksichtigt vollständige Diktate außerhalb des Papierkorbs.").font(.system(size: 12)).foregroundStyle(.secondary)
            HStack { Button("Verlauf exportieren …") { model.exportHistory() }; Button("Verlauf zurücksetzen …") { model.resetHistory() }.disabled(model.state == .recording || model.state == .processing || model.isUIPreview) }
            if !model.historyNotice.isEmpty { Text(model.historyNotice).font(.system(size: 12)).foregroundStyle(.secondary) }
            Toggle("Zwischenablage für kompatibles Einfügen verwenden", isOn: Binding(get: { model.document.settings.clipboardCompatibility ?? true }, set: { model.document.settings.clipboardCompatibility = $0 }))
                .help("Der vorherige Inhalt wird gesichert und wiederhergestellt. Eine neue Kopieraktion von dir hat Vorrang. Unklare Ergebnisse werden nicht automatisch erneut eingefügt.")
            Text("Beim Einfügen liegt dein Text kurz in der systemweiten Zwischenablage. Andere lokale Apps können ihn dort lesen. Ausgeschaltet wird nur direkt über Bedienungshilfen eingefügt; bei nicht unterstützten Feldern bleibt der Text in der App verfügbar.").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Cloud-Optimierung ist optional und sendet nur Text an deine gewählte Schnittstelle. Zugangsdaten liegen im macOS-Schlüsselbund.")
            Button("Lokale Daten im Finder zeigen") { NSWorkspace.shared.open(ModelPaths.support) }
            Text("Open Source: FluidAudio (Apache 2.0), FreeFlow und llama.cpp (MIT). Modelllizenzen: Parakeet CC BY 4.0, Qwen Apache 2.0.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private func setCloudEnabled(_ enabled: Bool) {
        guard enabled else { model.document.settings.cloudEnabled = false; return }
        let endpoint = model.document.settings.cloudEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint), url.host != nil, url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")) else {
            model.errorMessage = "Bitte eine HTTPS-Adresse oder eine lokale Schnittstelle angeben."; return
        }
        let alert = NSAlert(); alert.messageText = "Textoptimierung an dieser Adresse aktivieren?"
        alert.informativeText = "\(endpoint)\n\nGesendet werden der aktuelle transkribierte Text, höchstens zwei vorherige Sätze und passende Wörterbucheinträge. Audio bleibt lokal."
        alert.addButton(withTitle: "Für diese Adresse aktivieren"); alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn {
            do { try CloudRecipient.approve(endpoint); model.document.settings.cloudEndpoint = endpoint; model.document.settings.cloudEnabled = true }
            catch { model.errorMessage = "Cloud-Freigabe konnte nicht geschützt gespeichert werden." }
        }
    }
    private func appName(for bundle: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        let knownNames = ["com.microsoft.Outlook": "Microsoft Outlook", "com.microsoft.teams2": "Microsoft Teams", "com.superhuman.desktop": "Superhuman", "com.apple.MobileSMS": "Nachrichten", "com.facebook.archon": "Messenger", "com.tencent.xinWeChat": "WeChat", "com.tinyspeck.slackmacgap": "Slack", "net.whatsapp.WhatsApp": "WhatsApp"]
        return knownNames[bundle] ?? "Nicht installierte App"
    }
    private func unsupportedLabel(_ label: String) -> String {
        let names = ["unmappedApps": "Webseiten oder unbekannte Apps", "customUserStyles": "Eigene Schreibstile", "appTranscriptionFormats": "Weitere App-Schreibstile", "format": "Unbekanntes Textformat"]
        return names.reduce(label) { text, item in text.replacingOccurrences(of: item.key, with: item.value) }
    }
    private func chooseApp() {
        let panel = NSOpenPanel(); panel.title = "App für einen Schreibstil auswählen"; panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier { appBundle = id }
    }
    private var reportText: String {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("verification-report.md"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "Der Prüfbericht konnte nicht geladen werden. Bitte das vollständige App-Paket installieren. Die praktische Gesamtabnahme ist noch offen." }
        let runtime = "## Aktueller Prozess\n\nMikrofon: \(model.microphoneGranted ? "erlaubt" : "offen") · Bedienungshilfen: \(model.accessibilityGranted ? "erlaubt" : "offen")\n\n" + (model.captureStartupMilliseconds.map { "Aufnahmestart nach Auslösen: \(Int($0.rounded())) ms\n" } ?? "Noch keine Aufnahme in diesem Prozess.\n")
        return runtime + "\n" + text
    }
    private func shortcutRow(_ title: String, action: String, shortcuts: [Shortcut]) -> some View {
        HStack(spacing: 8) { Text(title).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 4); Button(model.shortcutCapture && captureAction == action ? "Jetzt drücken …" : shortcuts.isEmpty ? "Festlegen …" : shortcuts.map(\.label).joined(separator: " / ")) { beginShortcutCapture(action) }.frame(minWidth: 100).accessibilityLabel(title + ": " + (shortcuts.isEmpty ? "Festlegen" : shortcuts.map(\.spokenLabel).joined(separator: " oder "))) }.frame(minHeight: 28)
    }
    /// System shortcuts and lone ⌘/⇧ holds would break typing everywhere; one combination per action.
    private func shortcutProblem(_ shortcut: Shortcut) -> String? {
        let command: UInt64 = 1 << 20, shift: UInt64 = 1 << 17
        let systemKeys: Set<UInt16> = [0, 6, 7, 8, 9, 12, 13, 48, 49] // A Z X C V Q W Tab Space
        if let key = shortcut.keyCode, shortcut.modifiers == command, systemKeys.contains(key) { return "\(shortcut.label) ist ein Systemkürzel und bleibt frei. Wähle eine andere Kombination." }
        if shortcut.keyCode == nil, shortcut.modifiers == command || shortcut.modifiers == shift { return "Nur \(shortcut.label) würde bei jedem normalen Tippen auslösen. Nimm eine Kombination mit zwei Tasten oder Fn." }
        let settings = model.document.settings, bindings = settings.shortcutBindings ?? ShortcutBindings()
        let used: [(String, [Shortcut])] = [("hold", [settings.shortcut] + bindings.holdExtras), ("handsFree", bindings.handsFree), ("cancel", bindings.cancel), ("copyLast", bindings.copyLast), ("pasteLast", bindings.pasteLast), ("lipReading", settings.lipReadingShortcut.map { [$0] } ?? [])]
        if used.contains(where: { $0.0 != captureAction && $0.1.contains(shortcut) }) { return "\(shortcut.label) ist schon einer anderen Aktion zugeordnet." }
        return nil
    }
    private func storeShortcut(_ shortcut: Shortcut) {
        if let problem = shortcutProblem(shortcut) { model.errorMessage = problem; return }
        if captureAction == "hold" { model.document.settings.shortcut = shortcut; model.document.settings.shortcutBindings?.holdExtras = []; model.document.settings.importedWisprShortcut = model.importPreview.shortcut == shortcut }
        else if captureAction == "lipReading" { model.document.settings.lipReadingShortcut = shortcut }
        else {
            var bindings = model.document.settings.shortcutBindings ?? ShortcutBindings()
            switch captureAction { case "handsFree": bindings.handsFree = [shortcut]; case "cancel": bindings.cancel = [shortcut]; case "copyLast": bindings.copyLast = [shortcut]; case "pasteLast": bindings.pasteLast = [shortcut]; default: break }
            model.document.settings.shortcutBindings = bindings
        }
    }
    private var beta: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lippenlesen").font(.system(size: 20, weight: .semibold))
                    Text("Lautlos diktieren, mit deiner Kamera.").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Lippenlesen aktivieren", isOn: Binding(get: { model.lipEnabled }, set: { model.setLipEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).disabled(!LipReadingRuntime.releaseAvailable).accessibilityLabel("Lippenlesen-Beta aktivieren")
            }
            Text("Experimentell. Die Kamera läuft nur während deiner Aufnahme. Kein Ton, keine Cloud, keine gespeicherten Videos.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !LipReadingRuntime.releaseAvailable { Text(LipReadingRuntime.securityNotice).font(.system(size: 12)).foregroundStyle(.secondary) }
            if model.lipEnabled {
                Divider()
                Picker("Sprache", selection: Binding(get: { model.lipLanguage }, set: { model.setLipLanguage($0) })) {
                    ForEach(LipReadingLanguage.allCases) { language in Text(language.title).tag(language) }
                }.pickerStyle(.segmented).frame(maxWidth: 320).disabled(model.lipInstalling || model.lipSession)
                shortcutRow("Halten zum Lippenlesen", action: "lipReading", shortcuts: [model.lipShortcut])
                Text("In die Kamera schauen, Kürzel halten und lautlos einen kurzen Satz formen. Loslassen verarbeitet den Text. Esc bricht ab. Höchstens 30 Sekunden.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 10) {
                    if model.lipPreparing { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.lipReady ? "checkmark.circle" : "arrow.down.circle").foregroundStyle(model.lipReady ? Color.green : Color.secondary) }
                    Text(model.lipStatus).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                if model.lipLanguage == .german {
                    Label("Deutsch: Forschungsmodell, noch sehr ungenau. Ergebnisse vor dem Einfügen prüfen.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if !model.lipReady {
                        Button("Modell einrichten") { model.prepareLipReading(install: true) }.buttonStyle(.borderedProminent).disabled(model.lipPreparing)
                        Button("Erneut laden") { model.prepareLipReading() }.disabled(model.lipPreparing)
                    }
                    if !model.cameraGranted { Button("Kamera freigeben") { model.requestCamera() }.disabled(model.isUIPreview) }
                    if !model.accessibilityGranted { Button("Bedienungshilfen freigeben") { model.requestAccessibility() }.disabled(model.isUIPreview) }
                }
                Text("Nur für nichtkommerzielle Forschung. Die Erkennung und Modelle werden separat lokal eingerichtet und gehören nicht zum allgemeinen Downloadpaket.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .help("Englisch: Lipflow / Auto-AVSR. Deutsch: MuAViC / AV-HuBERT. Deutsch wird direkt aus dem Video erkannt, ohne englische Zwischenübersetzung. Lippenlesen bleibt mehrdeutig und ist weniger zuverlässig als Spracherkennung.")
            }
        }.padding(20).background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
    private func beginShortcutCapture(_ action: String = "hold") {
        if model.shortcutCapture { endShortcutCapture(); return }
        captureAction = action
        model.shortcutCapture = true
        var pendingModifiers: UInt64 = 0
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // A closed settings window may skip onDisappear; never keep recording keys after that.
            guard model.shortcutCapture else { endShortcutCapture(); return event }
            let mask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 23)
            let flags = UInt64(event.modifierFlags.rawValue) & mask
            if event.type == .keyDown {
                if event.keyCode == 53 && captureAction != "cancel" { endShortcutCapture(); return nil }
                if event.keyCode == 53 { storeShortcut(Shortcut(keyCode: 53, modifiers: flags)); endShortcutCapture(); return nil }
                guard flags != 0 else { return nil }
                storeShortcut(Shortcut(keyCode: event.keyCode, modifiers: flags))
                endShortcutCapture(); return nil
            }
            // Keep every modifier of the gesture: Ctrl+Shift released one key at a time stays Ctrl+Shift.
            if flags != 0 { pendingModifiers |= flags }
            else if pendingModifiers != 0 { storeShortcut(Shortcut(keyCode: nil, modifiers: pendingModifiers)); endShortcutCapture() }
            return event
        }
    }
    private func endShortcutCapture() { if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }; shortcutMonitor = nil; model.shortcutCapture = false }
}
