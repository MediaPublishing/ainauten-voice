import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VoiceWisprCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case overview = "Übersicht", history = "Verlauf", statistics = "Statistik"
    case setup = "Einrichtung", dictation = "Diktieren", formatting = "Text & Stil", dictionary = "Wörterbuch", migration = "Wispr Flow", privacy = "Datenschutz", updates = "Updates", beta = "Beta", help = "Hilfe"
    var id: String { rawValue }
    var title: String { L10n.text("navigation.\(previewKey)") }
    private var previewKey: String { switch self { case .overview: "overview"; case .history: "history"; case .statistics: "statistics"; case .setup: "setup"; case .dictation: "dictation"; case .formatting: "formatting"; case .dictionary: "dictionary"; case .migration: "migration"; case .privacy: "privacy"; case .updates: "updates"; case .beta: "beta"; case .help: "help" } }
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
    var title: String { L10n.text("setup.step.\(rawValue)") }
}

struct SettingsNavigation: Equatable {
    let id = UUID()
    let section: SettingsSection
    let setupStep: SetupStep?
}

struct WindowCloseButton: View {
    var label = L10n.text("window.close")
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
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
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
    @State private var languageSaveError: String?

    var body: some View {
        GeometryReader { geometry in
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) { Image(systemName: "waveform").font(.system(size: 22, weight: .medium)); Text("AInauten Voice").font(.system(size: 17, weight: .semibold)) }.padding(.bottom, 28).padding(.top, 12)
                ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                ForEach([SettingsSection.overview, .history, .statistics, .dictionary, .formatting, .help] + (settingsExpanded ? [.dictation, .setup, .migration, .privacy, .updates, .beta] : [])) { item in
                    Button { section = item; focusedSection = item } label: {
                        Label(item.title, systemImage: item.icon).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9).padding(.horizontal, 10)
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
                    HStack { Label(L10n.text("navigation.settings"), systemImage: "gearshape"); Spacer(); Image(systemName: settingsExpanded ? "chevron.up" : "chevron.down").font(.system(size: 10)) }
                        .padding(.vertical, 10).padding(.horizontal, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).pointerAwareFocus().help(L10n.text("navigation.settings.help"))
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.text("sidebar.localAudio"), systemImage: "lock.fill").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(L10n.text("sidebar.version", model.updates.version)).font(.system(size: 11)).foregroundStyle(.tertiary)
                        .padding(.leading, SidebarLabelStyle.textInset)
                }.padding(.leading, 10)
            }.labelStyle(SidebarLabelStyle()).padding(18).frame(width: 195).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(section.title).font(.system(size: 28, weight: .bold))
                    Spacer()
                    Button { showReport = true } label: {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 16))
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help(L10n.text("report.show")).accessibilityLabel(L10n.text("report.show")).pointerAwareFocus()
                    WindowCloseButton { model.closeSettings() }
                }.padding(.horizontal, 28).padding(.top, 32).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if section != .help { CrashReportNotice(reports: model.reports) { section = .help; focusedSection = .help } }
                        if let error = model.errorMessage {
                            HStack(alignment: .top) { Image(systemName: "exclamationmark.triangle"); Text(error).textSelection(.enabled); Spacer(); Button(L10n.text("error.report")) { section = .help; focusedSection = .help }; WindowCloseButton(label: L10n.text("error.dismiss")) { model.dismissError() } }.padding(12).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if !model.importReceipt.isEmpty && (section == .setup || section == .migration) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(model.importFailed ? L10n.text("import.incomplete") : L10n.text("import.result"), systemImage: model.importFailed ? "exclamationmark.triangle" : "checkmark.circle").font(.system(size: 13, weight: .semibold))
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
                HStack { Text(L10n.text("settings.report.title")).font(.system(size: 20, weight: .semibold)); Spacer(); WindowCloseButton(label: L10n.text("settings.report.close")) { showReport = false }.keyboardShortcut(.cancelAction) }
                ReportView(markdown: reportText)
            }.padding(24)
                .frame(width: min(860, max(530, geometry.size.width - 48)),
                       height: min(720, max(400, geometry.size.height - 48)))
        }
        }.frame(minWidth: 640, minHeight: 560)
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L10n.text("setup.intro")).font(.system(size: 18, weight: .semibold))
            if model.document.settings.onboardingComplete {
                Label(L10n.text("setup.complete"), systemImage: "checkmark.circle").foregroundStyle(.green)
                if step != .practice { Button(L10n.text("setup.toDictation")) { section = .dictation; focusedSection = .dictation } }
            } else { Text(L10n.text("setup.downloadIntro")).foregroundStyle(.secondary) }
            HStack(spacing: 6) { ForEach(SetupStep.allCases) { item in
                let done = model.setupStepDone(item)
                Button { step = item } label: { VStack(spacing: 6) {
                    Group { if done && item != step { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) } else { Text("\(item.rawValue + 1)").font(.system(size: 12, weight: .semibold)) } }
                        .frame(width: 26, height: 26).background(item == step ? Color.accentColor : done ? Color.green.opacity(0.16) : Color.secondary.opacity(0.1), in: Circle()).foregroundStyle(item == step ? Color.white : done ? Color.green : Color.primary)
                    Text(item.title).font(.system(size: 10)).lineLimit(1)
                }.frame(maxWidth: .infinity).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel(L10n.text("setup.stepAX", String(item.rawValue + 1), item.title) + (done ? L10n.text("setup.stepDone") : ""))
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
                if let previous = SetupStep(rawValue: step.rawValue - 1) { Button(L10n.text("common.back")) { step = previous } }
                Spacer()
                if step == .practice && model.practiceFeedback.succeeded {
                    let next = model.pendingSetupStep
                    Button(next == .switchover ? L10n.text("setup.nextSwitch") : next == .permissions ? L10n.text("permissions.accessibility.allow") : L10n.text("setup.toDictation")) {
                        if let next { step = next } else { model.completeSetup() }
                    }.buttonStyle(.borderedProminent)
                }
                else if let next = SetupStep(rawValue: step.rawValue + 1) { Button(L10n.text("common.next")) { step = next }.buttonStyle(.borderedProminent) }
                else { Button(L10n.text("setup.finish")) { model.completeSetup(); if model.document.settings.onboardingComplete { section = .dictation } }.buttonStyle(.borderedProminent).disabled(!model.canCompleteSetup) }
            }
        }
    }
    private var practice: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.practiceFeedback.succeeded ? (model.practiceAudioSource != nil ? L10n.text("practice.audioRecognized") : L10n.text("practice.recognized")) : L10n.text("practice.intro")).font(.system(size: 19, weight: .semibold))
            if let source = model.practiceAudioSource {
                Label(L10n.text("practice.file", source), systemImage: "testtube.2").foregroundStyle(.secondary)
                Text(L10n.text("practice.fileHelp")).foregroundStyle(.secondary)
            } else {
                Text(L10n.text("practice.help")).foregroundStyle(.secondary)
            }
            if model.practiceFeedback.phase == .recording {
                Label(model.practiceAudioSource != nil ? L10n.text("practice.audioReady") : model.captureReady ? L10n.text("practice.listening", model.durationLabel) : L10n.text("practice.microphoneStarting"), systemImage: model.practiceAudioSource != nil ? "waveform" : "mic.fill")
                ProgressView(value: Double(model.level)).frame(maxWidth: 250)
            }
            if model.practiceFeedback.phase == .processing { ProgressView(L10n.text("practice.processing")) }
            HStack {
                Button(model.practiceAudioSource != nil ? (model.practiceFeedback.phase == .recording ? L10n.text("practice.processAudio") : L10n.text("practice.startAudio")) : model.practiceFeedback.phase == .recording ? L10n.text("practice.stop") : model.practiceFeedback.phase == .idle ? L10n.text("practice.start") : L10n.text("practice.again")) {
                    if model.practiceFeedback.phase == .recording { model.stop() } else { model.startPractice() }
                }.buttonStyle(.borderedProminent).disabled(!model.modelsReady || !model.microphoneGranted || model.state == .processing || (model.state == .recording && !model.practiceFeedback.isActive))
                if model.practiceFeedback.isActive { Button(L10n.text("common.cancel")) { model.cancel() }.keyboardShortcut(.cancelAction) }
            }
            if !model.practiceFeedback.message.isEmpty {
                Label(L10n.diagnostic(model.practiceFeedback.message), systemImage: model.practiceFeedback.succeeded ? "checkmark.circle" : model.practiceFeedback.phase == .cancelled ? "xmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(model.practiceFeedback.succeeded ? Color.green : Color.primary)
            }
            if let result = model.practiceFeedback.result {
                HStack { Text(result.isComplete ? L10n.text("practice.text") : L10n.text("practice.partialText")).font(.system(size: 13, weight: .semibold)); Spacer(); Button(L10n.text("common.copy")) { model.copyPracticeResult() } }
                Text(result.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                if result.usedFallback { Label(L10n.text("practice.fallback"), systemImage: "info.circle").foregroundStyle(.secondary) }
            } else if model.practiceFeedback.phase == .idle && model.practiceComplete {
                Text(L10n.text("practice.previous")).foregroundStyle(.secondary)
            }
            if !model.microphoneGranted { Button(L10n.text("permissions.microphone.allow")) { step = .permissions } }
            else if !model.modelsReady { Label(model.downloading ? L10n.text("practice.waitForModels") : L10n.text("practice.modelsFirst"), systemImage: "hourglass").foregroundStyle(.secondary) }
        }
    }
    private let languages = ["de", "en", "bg", "da", "et", "fi", "fr", "el", "it", "hr", "lv", "lt", "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "es", "sv", "cs", "uk", "hu"]
    private func languageName(_ code: String) -> String { L10n.wordsLocale.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code }
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
            .accessibilityLabel(L10n.text(selected ? "dictation.language.removeAX" : "dictation.language.addAX", name))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private var languagePicker: some View {
        languageSelection(compact: false)
    }
    private func languageSelection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Text(compact ? L10n.text("dictation.languages") : L10n.text("dictation.languageQuestion")).font(.system(size: compact ? 16 : 19, weight: .semibold))
            Text(compact ? L10n.text("dictation.languageBrief") : L10n.text("dictation.languageHelp")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !compact { Text(L10n.text("dictation.languages.selected")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(model.document.settings.languages, id: \.self) { code in languageChip(code, languageName(code), selected: true) }
            }
            if !compact { Text(L10n.text("dictation.languages.required")).font(.system(size: 12)).foregroundStyle(.secondary) }
            Button { showAllLanguages.toggle() } label: {
                HStack(spacing: 8) { Image(systemName: showAllLanguages ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)); Text(showAllLanguages ? L10n.text("dictation.languages.hide") : L10n.text("dictation.languages.add")); Spacer() }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(showAllLanguages ? L10n.text("dictation.languages.hide") : L10n.text("dictation.languages.add"))
            if showAllLanguages {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(languages.filter { !model.document.settings.languages.contains($0) }, id: \.self) { code in languageChip(code, languageName(code), selected: false) }
                }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private var models: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("models.installTitle")).font(.system(size: 19, weight: .semibold))
            Text(L10n.text("models.size")).foregroundStyle(.secondary)
            if model.downloading { ProgressView(value: model.downloadFraction); Text(model.downloadLabel).font(.system(size: 12)).monospacedDigit(); Button(L10n.text("models.pause")) { model.pauseDownload() } }
            else if model.preparing { ProgressView(L10n.text("models.loading")) }
            else if model.modelsReady { Label(L10n.text("models.loaded"), systemImage: "checkmark.circle").foregroundStyle(.green) }
            else {
                Button(L10n.text("models.download")) {
                    model.installModels()
                    // The download continues in the background while the remaining steps are done.
                    if section == .setup && step == .models { step = .wispr }
                }.buttonStyle(.borderedProminent)
            }
            Text(L10n.text("models.resumeHelp")).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("permissions.title")).font(.system(size: 19, weight: .semibold))
            HStack { VStack(alignment: .leading, spacing: 4) { Label(L10n.text("permissions.microphone"), systemImage: model.microphoneGranted ? "checkmark.circle" : "mic"); Text(L10n.text("permissions.microphone.help")).font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Button(model.microphoneGranted ? L10n.text("permissions.allowed") : L10n.text("permissions.allow")) { model.requestMicrophone() }.disabled(model.microphoneGranted) }
            HStack { VStack(alignment: .leading, spacing: 4) { Label(L10n.text("permissions.accessibility"), systemImage: model.accessibilityGranted ? "checkmark.circle" : "keyboard"); Text(L10n.text("permissions.accessibility.help")).font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Button(model.accessibilityGranted ? L10n.text("permissions.allowed") : L10n.text("permissions.openSettings")) { model.requestAccessibility() }.disabled(model.accessibilityGranted) }
            if !model.accessibilityGranted {
                Text(L10n.text("permissions.steps")).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 38, height: 38).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) { Text("AInauten Voice.app").font(.system(size: 13, weight: .semibold)); Text(L10n.text("permissions.dragHint")).font(.system(size: 12)).foregroundStyle(.secondary) }
                    Spacer()
                    Image(systemName: "arrow.up.forward.square").foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                    .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                    .accessibilityLabel(L10n.text("permissions.dragAX"))
                Text(Bundle.main.bundlePath).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button(L10n.text("permissions.findApp")) { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                Text(L10n.text("permissions.cannotImport")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private var dictation: some View {
        VStack(alignment: .leading, spacing: 16) {
            interfaceLanguagePicker
            Label(model.status, systemImage: model.state == .ready ? "mic" : model.conflict ? "exclamationmark.circle" : "info.circle").fixedSize(horizontal: false, vertical: true)
            if model.conflict { Button(L10n.text("dictation.switchFlow")) { section = .migration; focusedSection = .migration } }
            Text(L10n.text("dictation.help")).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
    private var interfaceLanguagePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(L10n.text("settings.interfaceLanguage"), selection: Binding(get: { interfaceLanguage.choice }, set: { next in
                do { try interfaceLanguage.setChoice(next); languageSaveError = nil }
                catch { languageSaveError = error.localizedDescription }
            })) {
                Text(L10n.text("settings.interfaceLanguage.system")).tag(InterfaceLanguage.system)
                Text("Deutsch").tag(InterfaceLanguage.de)
                Text("English").tag(InterfaceLanguage.en)
            }.frame(maxWidth: 440, alignment: .leading)
                .help(L10n.text("settings.interfaceLanguage.help"))
            Text(L10n.text("settings.interfaceLanguage.help")).font(.system(size: 11)).foregroundStyle(.secondary)
            if let languageSaveError { Text(languageSaveError).font(.system(size: 12)).foregroundStyle(.orange) }
        }
    }
    private var dictationShortcuts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("shortcuts.title")).font(.system(size: 16, weight: .semibold)).padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 4) {
                shortcutRow(L10n.text("shortcuts.hold"), action: "hold", shortcuts: [model.document.settings.shortcut] + (model.document.settings.shortcutBindings?.holdExtras ?? []))
                shortcutRow(L10n.text("shortcuts.handsFree"), action: "handsFree", shortcuts: model.document.settings.shortcutBindings?.handsFree ?? [])
                shortcutRow(L10n.text("common.cancel"), action: "cancel", shortcuts: model.document.settings.shortcutBindings?.cancel.isEmpty == false ? model.document.settings.shortcutBindings!.cancel : [Shortcut(keyCode: 53, modifiers: 0)])
                shortcutRow(L10n.text("shortcuts.copyLast"), action: "copyLast", shortcuts: model.document.settings.shortcutBindings?.copyLast ?? [])
                shortcutRow(L10n.text("shortcuts.pasteLast"), action: "pasteLast", shortcuts: model.document.settings.shortcutBindings?.pasteLast ?? [])
            }
            if model.shortcutCapture { Text(L10n.text("shortcuts.captureHelp")).foregroundStyle(.secondary).font(.system(size: 12)) }
            Divider().padding(.vertical, 4)
            Toggle(L10n.text("shortcuts.enabled"), isOn: Binding(get: { !model.document.settings.paused }, set: { model.document.settings.paused = !$0; if !$0 { model.cancel() } }))
                .help(L10n.text("shortcuts.disabledHelp"))
            if model.document.settings.paused { Text(L10n.text("shortcuts.disabled")).font(.system(size: 12)).foregroundStyle(.secondary) }
            Toggle(L10n.text("startup.enabled"), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
            Toggle(L10n.text("settings.menuBarOnly"), isOn: Binding(get: { model.document.settings.menuBarOnly == true }, set: { model.document.settings.menuBarOnly = $0 }))
        }
    }
    private var dictationReadiness: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    readinessLabel(L10n.text("permissions.microphone"), ready: model.microphoneGranted)
                    readinessLabel(L10n.text("permissions.accessibility"), ready: model.accessibilityGranted)
                    readinessLabel(model.modelsReady ? L10n.text("models.ready") : model.preparing ? L10n.text("models.loadingBrief") : L10n.text("models.missing"), ready: model.modelsReady)
                }
                VStack(alignment: .leading, spacing: 6) {
                    readinessLabel(L10n.text("permissions.microphone"), ready: model.microphoneGranted)
                    readinessLabel(L10n.text("permissions.accessibility"), ready: model.accessibilityGranted)
                    readinessLabel(model.modelsReady ? L10n.text("models.ready") : model.preparing ? L10n.text("models.loadingBrief") : L10n.text("models.missing"), ready: model.modelsReady)
                }
            }
            Button(model.pendingSetupStep == nil ? L10n.text("setup.show") : L10n.text("setup.resume")) {
                section = .setup; focusedSection = .setup; step = model.pendingSetupStep ?? .permissions
            }.buttonStyle(.link)
        }.font(.system(size: 12))
    }
    private func readinessLabel(_ title: String, ready: Bool) -> some View {
        Label(title, systemImage: ready ? "checkmark.circle" : "exclamationmark.circle")
            .foregroundStyle(ready ? Color.secondary : Color.orange)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(L10n.text(ready ? "readiness.readyAX" : "readiness.pendingAX", title))
    }
    private var formatting: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("formatting.title")).font(.system(size: 19, weight: .semibold))
            Picker(L10n.text("formatting.default"), selection: $model.document.settings.defaultStyle) { ForEach(TextStyle.allCases) { Text($0.interfaceTitle).tag($0) } }
            Picker(L10n.text("formatting.manual"), selection: $model.document.settings.manualStyle) { Text(L10n.text("formatting.byApp")).tag(TextStyle?.none); ForEach(TextStyle.allCases) { Text($0.interfaceTitle).tag(Optional($0)) } }
            Text(L10n.text("formatting.help")).foregroundStyle(.secondary)
            Divider()
            Text(L10n.text("formatting.appStyles")).font(.system(size: 16, weight: .semibold))
            ForEach(model.document.settings.appStyles.keys.sorted(), id: \.self) { bundle in
                HStack { Text(appName(for: bundle)).lineLimit(1); Spacer(); Text(model.document.settings.appStyles[bundle]?.interfaceTitle ?? ""); Button { model.document.settings.appStyles.removeValue(forKey: bundle) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel(L10n.text("formatting.removeApp")) }
            }
            Button(appBundle.isEmpty ? L10n.text("formatting.chooseApp") : appName(for: appBundle)) { chooseApp() }
            HStack { Picker(L10n.text("formatting.style"), selection: $appStyle) { ForEach(TextStyle.allCases) { Text($0.interfaceTitle).tag($0) } }; Button(L10n.text("formatting.assign")) { model.document.settings.appStyles[appBundle.trimmingCharacters(in: .whitespaces)] = appStyle; appBundle = "" }.disabled(appBundle.trimmingCharacters(in: .whitespaces).isEmpty) }
            Divider()
            TextField(L10n.text("cloud.endpoint"), text: Binding(get: { model.document.settings.cloudEndpoint }, set: { model.document.settings.cloudEndpoint = $0.trimmingCharacters(in: .whitespacesAndNewlines); model.document.settings.cloudEnabled = false }))
            Toggle(L10n.text("cloud.enable"), isOn: Binding(get: { model.document.settings.cloudEnabled }, set: setCloudEnabled))
            Text(L10n.text("cloud.disclosure", model.document.settings.cloudEndpoint)).font(.system(size: 12)).foregroundStyle(.secondary)
            if model.document.settings.cloudEnabled {
                TextField(L10n.text("cloud.model"), text: $model.document.settings.cloudModel)
                SecureField(L10n.text("cloud.key"), text: $key)
                Button(L10n.text("cloud.saveKey")) { model.saveKey(key); key = "" }.disabled(key.isEmpty)
                Button(L10n.text("cloud.removeKey")) { model.saveKey(""); key = "" }
                Text(L10n.text("cloud.keyNotExported")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private var migration: some View { VStack(alignment: .leading, spacing: 24) { migrationPreview; Divider(); migrationSwitch } }
    private var migrationPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("import.title")).font(.system(size: 19, weight: .semibold))
            if model.isUIPreview { Text(L10n.text("import.preview")).foregroundStyle(.secondary) }
            else if model.importRefreshing || !model.importPreviewLoaded { ProgressView(L10n.text("import.checking")) }
            else if model.importPreview.isPartial { ForEach(model.importPreview.errors, id: \.self) { Text(L10n.diagnostic($0)).foregroundStyle(.secondary) } }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 36) {
                        migrationCounts
                        migrationBindings
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 20) { migrationCounts; migrationBindings }
                }
                ForEach(model.importPreview.unsupported, id: \.self) { Text(L10n.text("import.omitted", unsupportedLabel($0))).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            if !model.isUIPreview {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { migrationImportButton; migrationRefreshButton }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 10) { migrationImportButton; migrationRefreshButton }
                }
                Text(L10n.text("import.saved", model.document.dictionary.count.formatted(), model.document.settings.languages.map(languageName).joined(separator: ", "), model.document.settings.shortcut.spokenLabel))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Button(L10n.text("import.csv")) { model.importDictionaryCSV() }.disabled(model.isUIPreview)
            if model.canUndoImport { Button(L10n.text("import.undo")) { model.undoImport() } }
            if !model.importReceipt.isEmpty && !model.importFailed && section == .migration {
                Button(model.document.settings.onboardingComplete ? L10n.text("setup.toDictation") : L10n.text("setup.resume")) {
                    section = model.document.settings.onboardingComplete ? .dictation : .setup
                    focusedSection = section
                    if !model.document.settings.onboardingComplete { step = model.pendingSetupStep ?? .practice }
                }.buttonStyle(.borderedProminent)
            }
            Text(L10n.text("import.readOnly")).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(L10n.text("import.manualPriority")).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private var migrationCounts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("settings.dictionary.title")).font(.system(size: 13, weight: .semibold)).padding(.bottom, 2)
            LabeledContent(L10n.text("import.words"), value: "\(model.importPreview.words)")
            LabeledContent(L10n.text("import.replacements"), value: "\(model.importPreview.replacements)")
            LabeledContent(L10n.text("import.deleted"), value: "\(model.importPreview.deleted)")
            if model.importPreview.sourceDuplicates > 0 {
                LabeledContent(L10n.text("import.duplicates"), value: "\(model.importPreview.sourceDuplicates)")
                LabeledContent(L10n.text("import.unique"), value: "\(model.importPreview.uniqueEntries)")
            }
        }
    }
    private var migrationBindings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("navigation.settings")).font(.system(size: 13, weight: .semibold)).padding(.bottom, 2)
            LabeledContent(L10n.text("dictation.languages"), value: model.importPreview.languages.map(languageName).joined(separator: ", "))
            if let shortcut = model.importPreview.shortcut { LabeledContent(L10n.text("shortcuts.title"), value: shortcut.label) }
            if !model.importPreview.shortcutBindings.handsFree.isEmpty { LabeledContent(L10n.text("shortcuts.handsFree"), value: model.importPreview.shortcutBindings.handsFree.map(\.label).joined(separator: " / ")) }
            if !model.importPreview.shortcutBindings.copyLast.isEmpty { LabeledContent(L10n.text("shortcuts.copyLast"), value: model.importPreview.shortcutBindings.copyLast.map(\.label).joined(separator: " / ")) }
            if !model.importPreview.shortcutBindings.pasteLast.isEmpty { LabeledContent(L10n.text("shortcuts.pasteLast"), value: model.importPreview.shortcutBindings.pasteLast.map(\.label).joined(separator: " / ")) }
        }
    }
    private var migrationImportButton: some View {
        Button(model.importing ? L10n.text("import.importing") : model.importPreview.isPartial ? L10n.text("import.retry") : L10n.text("import.supported")) { model.importWispr() }.buttonStyle(.borderedProminent).disabled(!model.canImportWispr)
    }
    private var migrationRefreshButton: some View {
        Button(L10n.text("import.refresh")) { model.refreshImportPreview() }.disabled(model.importRefreshing || model.importing)
    }
    private var migrationSwitch: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("switch.title")).font(.system(size: 19, weight: .semibold))
            if model.wisprInstalled || model.wisprRunning {
                Text(L10n.text("switch.help")).foregroundStyle(.secondary)
                Button(model.switchingWispr ? L10n.text("switch.quitting") : L10n.text("switch.action")) { model.switchFromWispr() }.disabled(model.switchingWispr)
                if !model.switchReceipt.isEmpty { Text(model.switchReceipt).textSelection(.enabled).foregroundStyle(.secondary) }
                Label(model.wisprRunning ? L10n.text("switch.running") : L10n.text("switch.stopped"), systemImage: model.wisprRunning ? "exclamationmark.circle" : "checkmark.circle")
            } else {
                Label(L10n.text("switch.notInstalled"), systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            if !model.document.settings.onboardingComplete, let missing = model.pendingSetupStep, missing != .switchover {
                Text(L10n.text("setup.stillMissing", missing == .models ? L10n.text("setup.modelsMissing") : missing == .permissions ? L10n.text("setup.permissionsMissing") : L10n.text("setup.practiceMissing"))).foregroundStyle(.secondary)
                Button(missing == .models ? L10n.text("setup.toModels") : missing == .permissions ? L10n.text("setup.toPermissions") : L10n.text("practice.start")) {
                    model.settingsNavigation = SettingsNavigation(section: .setup, setupStep: missing)
                }
            }
            Label(L10n.text("switch.howTo", model.document.settings.shortcut.spokenLabel), systemImage: "keyboard").fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("switch.returnHelp")).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private var privacy: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("privacy.title")).font(.system(size: 20, weight: .semibold))
            Text(L10n.text("privacy.audio"))
            Toggle(L10n.text("privacy.history"), isOn: Binding(get: { model.historyEnabled }, set: { model.document.settings.historyEnabled = $0 }))
            Text(L10n.text("privacy.historyHelp")).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack { Button(L10n.text("privacy.exportHistory")) { model.exportHistory() }; Button(L10n.text("privacy.resetHistory")) { model.resetHistory() }.disabled(model.state == .recording || model.state == .processing || model.isUIPreview) }
            if !model.historyNotice.isEmpty { Text(model.historyNotice).font(.system(size: 12)).foregroundStyle(.secondary) }
            Toggle(L10n.text("privacy.clipboard"), isOn: Binding(get: { model.document.settings.usesClipboardForInsertion }, set: { model.document.settings.clipboardCompatibility = $0 }))
                .help(L10n.text("privacy.clipboardHelp"))
            Text(L10n.text("privacy.clipboardDetail")).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(L10n.text("privacy.cloud"))
            Button(L10n.text("privacy.showData")) { NSWorkspace.shared.open(ModelPaths.support) }
            Text(L10n.text("privacy.licenses")).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private func setCloudEnabled(_ enabled: Bool) {
        guard enabled else { model.document.settings.cloudEnabled = false; return }
        let endpoint = model.document.settings.cloudEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint), url.host != nil, url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")) else {
            model.errorMessage = L10n.text("cloud.invalidEndpoint"); return
        }
        let alert = NSAlert(); alert.messageText = L10n.text("cloud.confirm")
        alert.informativeText = L10n.text("cloud.confirmDetail", endpoint)
        alert.addButton(withTitle: L10n.text("cloud.approve")); alert.addButton(withTitle: L10n.text("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            do { try CloudRecipient.approve(endpoint); model.document.settings.cloudEndpoint = endpoint; model.document.settings.cloudEnabled = true }
            catch { model.errorMessage = L10n.text("cloud.approvalFailed") }
        }
    }
    private func appName(for bundle: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        let knownNames = ["com.microsoft.Outlook": "Microsoft Outlook", "com.microsoft.teams2": "Microsoft Teams", "com.superhuman.desktop": "Superhuman", "com.apple.MobileSMS": L10n.text("apps.messages"), "com.facebook.archon": "Messenger", "com.tencent.xinWeChat": "WeChat", "com.tinyspeck.slackmacgap": "Slack", "net.whatsapp.WhatsApp": "WhatsApp"]
        return knownNames[bundle] ?? L10n.text("apps.notInstalled")
    }
    private func unsupportedLabel(_ label: String) -> String {
        let names = ["unmappedApps": L10n.text("import.unsupportedApps"), "customUserStyles": L10n.text("import.unsupportedStyles"), "appTranscriptionFormats": L10n.text("import.unsupportedFormats"), "format": L10n.text("import.unknownFormat")]
        return L10n.diagnostic(names.reduce(label) { text, item in text.replacingOccurrences(of: item.key, with: item.value) })
    }
    private func chooseApp() {
        let panel = NSOpenPanel(); panel.title = L10n.text("formatting.appDialog"); panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier { appBundle = id }
    }
    private var reportText: String {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("verification-report.md"), let text = try? String(contentsOf: url, encoding: .utf8) else { return L10n.text("settings.report.unavailable") }
        let runtime = L10n.text("settings.report.runtime", model.microphoneGranted ? L10n.text("settings.report.allowed") : L10n.text("settings.report.pending"), model.accessibilityGranted ? L10n.text("settings.report.allowed") : L10n.text("settings.report.pending")) + (model.captureStartupMilliseconds.map { L10n.text("settings.report.captureStart", String(Int($0.rounded()))) } ?? L10n.text("settings.report.noRecording"))
        return runtime + "\n" + text
    }
    private func shortcutRow(_ title: String, action: String, shortcuts: [Shortcut]) -> some View {
        HStack(spacing: 8) { Text(title).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 4); Button(model.shortcutCapture && captureAction == action ? L10n.text("shortcuts.capture") : shortcuts.isEmpty ? L10n.text("shortcuts.choose") : shortcuts.map(\.label).joined(separator: " / ")) { beginShortcutCapture(action) }.frame(minWidth: 100).accessibilityLabel(title + ": " + (shortcuts.isEmpty ? L10n.text("shortcuts.set") : shortcuts.map(\.spokenLabel).joined(separator: L10n.text("shortcuts.or")))) }.frame(minHeight: 28)
    }
    /// System shortcuts and lone ⌘/⇧ holds would break typing everywhere; one combination per action.
    private func shortcutProblem(_ shortcut: Shortcut) -> String? {
        let command: UInt64 = 1 << 20, shift: UInt64 = 1 << 17
        let systemKeys: Set<UInt16> = [0, 6, 7, 8, 9, 12, 13, 48, 49] // A Z X C V Q W Tab Space
        if let key = shortcut.keyCode, shortcut.modifiers == command, systemKeys.contains(key) { return L10n.text("shortcuts.systemConflict", shortcut.label) }
        if shortcut.keyCode == nil, shortcut.modifiers == command || shortcut.modifiers == shift { return L10n.text("shortcuts.typingConflict", shortcut.label) }
        let settings = model.document.settings, bindings = settings.shortcutBindings ?? ShortcutBindings()
        let used: [(String, [Shortcut])] = [("hold", [settings.shortcut] + bindings.holdExtras), ("handsFree", bindings.handsFree), ("cancel", bindings.cancel), ("copyLast", bindings.copyLast), ("pasteLast", bindings.pasteLast), ("lipReading", settings.lipReadingShortcut.map { [$0] } ?? [])]
        if used.contains(where: { $0.0 != captureAction && $0.1.contains(shortcut) }) { return L10n.text("shortcuts.actionConflict", shortcut.label) }
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
                    Text(L10n.text("beta.title")).font(.system(size: 20, weight: .semibold))
                    Text(L10n.text("beta.subtitle")).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(L10n.text("beta.enable"), isOn: Binding(get: { model.lipEnabled }, set: { model.setLipEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).disabled(!LipReadingRuntime.releaseAvailable).accessibilityLabel(L10n.text("beta.enableAX"))
            }
            Text(L10n.text("beta.privacy"))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !LipReadingRuntime.releaseAvailable { Text(L10n.diagnostic(LipReadingRuntime.securityNotice)).font(.system(size: 12)).foregroundStyle(.secondary) }
            if model.lipEnabled {
                Divider()
                Picker(L10n.text("beta.language"), selection: Binding(get: { model.lipLanguage }, set: { model.setLipLanguage($0) })) {
                    ForEach(LipReadingLanguage.allCases) { language in Text(L10n.diagnostic(language.title)).tag(language) }
                }.pickerStyle(.segmented).frame(maxWidth: 320).disabled(model.lipInstalling || model.lipSession)
                shortcutRow(L10n.text("beta.hold"), action: "lipReading", shortcuts: [model.lipShortcut])
                Text(L10n.text("beta.instructions"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 10) {
                    if model.lipPreparing { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.lipReady ? "checkmark.circle" : "arrow.down.circle").foregroundStyle(model.lipReady ? Color.green : Color.secondary) }
                    Text(model.lipStatus).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                if model.lipLanguage == .german {
                    Label(L10n.text("beta.germanWarning"), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if !model.lipReady {
                        Button(L10n.text("beta.install")) { model.prepareLipReading(install: true) }.buttonStyle(.borderedProminent).disabled(model.lipPreparing)
                        Button(L10n.text("beta.reload")) { model.prepareLipReading() }.disabled(model.lipPreparing)
                    }
                    if !model.cameraGranted { Button(L10n.text("permissions.camera.allow")) { model.requestCamera() }.disabled(model.isUIPreview) }
                    if !model.accessibilityGranted { Button(L10n.text("permissions.accessibility.allow")) { model.requestAccessibility() }.disabled(model.isUIPreview) }
                }
                Text(L10n.text("beta.research"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .help(L10n.text("beta.modelsHelp"))
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
