import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers
import VoiceWisprCore

/// Preserve tap order even when main-actor callback tasks are scheduled out of order.
private final class CaptureSampleOffsets: @unchecked Sendable {
    private let lock = NSLock()
    private var next = 0
    func reserve(_ count: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        let offset = next; next += count; return offset
    }
}

// The experimental visual path shares delivery and dictionary behaviour, but
// never starts AudioCapture, SpeechRuntime or a cloud formatter.
extension AppModel {
    var lipEnabled: Bool { document.settings.lipReadingEnabled ?? false }
    var lipLanguage: LipReadingLanguage { LipReadingLanguage(rawValue: document.settings.lipReadingLanguage ?? "en") ?? .english }
    var lipShortcut: Shortcut { document.settings.lipReadingShortcut ?? LipReadingLanguage.defaultShortcut }
    private var lipResources: URL { (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("LipReading") }
    private var lipShortcutConflict: Bool {
        ([document.settings.shortcut] + (document.settings.shortcutBindings?.all ?? [])).contains(lipShortcut)
    }
    private func updateLipHotkey() {
        lipHotkey.shortcut = lipShortcut
        lipHotkey.bindings = ShortcutBindings()
        lipHotkey.cancellationEnabled = lipSession && accessibilityGranted && !shortcutCapture
        let available = lipEnabled && lipReady && cameraGranted && accessibilityGranted && !document.settings.paused && !conflict && !lipShortcutConflict && !shortcutCapture
        lipHotkey.enabled = available && (sessionID == nil || (lipSession && state == .recording))
        if available { _ = lipHotkey.install() }
        if lipEnabled && lipShortcutConflict { lipStatus = "Dieses Kürzel wird schon fürs Diktieren verwendet. Bitte wähle ein anderes." }
    }
    func setLipEnabled(_ enabled: Bool) {
        guard !previewMode else { document.settings.lipReadingEnabled = enabled; return }
        document.settings.lipReadingEnabled = enabled
        if enabled { prepareLipReading() }
        else {
            lipPreparationID = UUID(); lipPreparation?.cancel(); lipPreparing = false; lipInstalling = false; lipReady = false
            if lipSession { cancel() }
            Task { await lipRuntime.cancel(); await lipInstaller.cancel() }
            lipStatus = "Ausgeschaltet"; updateHotkey()
        }
    }
    func setLipLanguage(_ language: LipReadingLanguage) {
        if lipSession { cancel() }
        document.settings.lipReadingLanguage = language.rawValue
        lipReady = false
        if lipEnabled { prepareLipReading() }
    }
    func requestCamera() {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in Task { @MainActor in self?.refreshPermissions() } }
        } else { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!) }
    }
    func prepareLipReading(install: Bool = false) {
        guard lipEnabled, !quitting, !previewMode, !lipInstalling else { return }
        let id = UUID(), language = lipLanguage
        lipPreparationID = id; lipPreparation?.cancel(); lipReady = false; lipPreparing = true
        lipInstalling = install; lipStatus = install ? "Laufzeit wird eingerichtet …" : "Modell wird geladen …"
        updateHotkey()
        lipPreparation = Task {
            do {
                try Task.checkCancellation()
                // A model/language switch cannot keep an older worker alive.
                await lipRuntime.cancel()
                if install {
                    try await lipInstaller.install(language: language, root: ModelPaths.support.appendingPathComponent("LipReading"), resources: lipResources) { [weak self] label in
                        Task { @MainActor in if self?.lipPreparationID == id { self?.lipStatus = label } }
                    }
                }
                guard lipPreparationID == id, lipEnabled, !Task.isCancelled else { return }
                try await lipRuntime.prepare(language)
                guard lipPreparationID == id, lipEnabled, !Task.isCancelled else { return }
                lipReady = true
                lipStatus = language.requiresReview ? "Deutsch · Forschungsmodell geladen" : "Englisch · Bereit zum Lippenlesen"
            } catch is CancellationError {} catch {
                if lipPreparationID == id { lipStatus = error.localizedDescription; lipReady = false }
            }
            if lipPreparationID == id { lipPreparing = false; lipInstalling = false; updateHotkey() }
        }
    }
    func startLipReading() {
        guard !quitting, !previewMode, sessionID == nil, lipEnabled, lipReady,
              cameraGranted, accessibilityGranted, !document.settings.paused, !conflict, !lipShortcutConflict else { return }
        let id = UUID(); sessionID = id; lipSession = true
        closeRecovery(); quietDeliveryFeedback = false; errorMessage = nil; originalRequested = false
        practiceSession = false; focus = FocusSnapshot.capture(); pill?.position()
        let style = document.settings.style(for: focus?.bundleID)
        historyContext = HistoryCaptureContext(date: Date(), style: style, bundleID: focus?.bundleID,
            appName: focus.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName }, enabled: historyEnabled)
        state = .recording; status = "Lautlos sprechen · Kamera wird gestartet …"
        elapsed = 0; level = 0; captureReady = false; startedAt = ProcessInfo.processInfo.systemUptime
        updateHotkey()
        operation = Task {
            do {
                try await camera.start(sessionID: id) { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.sessionID == id else { return }
                        if message.contains("Beta-Aufnahme") { self.stop() } else { self.fail(message, title: "Kamera prüfen") }
                    }
                }
                guard sessionID == id, state == .recording else { return }
                captureReady = true; status = "Lautlos sprechen · höchstens 30 Sekunden"
                clock = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.sessionID == id, self.state == .recording else { return }
                        self.elapsed = ProcessInfo.processInfo.systemUptime - self.startedAt
                        if self.elapsed >= 30 { self.stop() }
                    }
                }
            } catch { if sessionID == id { fail(error.localizedDescription, title: "Kamera prüfen") } }
        }
    }
    private func stopLipReading(_ id: UUID) {
        captureReady = false; clock?.invalidate(); clock = nil
        state = .processing; status = "Lippen werden gelesen …"; updateHotkey()
        let initialization = operation, duration = elapsed, language = lipLanguage
        let style = document.settings.style(for: focus?.bundleID), dictionary = document.dictionary
        operation = Task {
            // Stop invalidates capture immediately, including a pending start.
            let frames = await camera.stop(sessionID: id)
            await initialization?.value
            guard sessionID == id, !Task.isCancelled else { return }
            do {
                let original = try await lipRuntime.transcribe(frames, session: id)
                guard sessionID == id, !Task.isCancelled else { return }
                let matcher = DictionaryMatcher(dictionary)
                let replaced = matcher.replace(in: original)
                var text = replaced, fallback = false
                if style != .original && !originalRequested {
                    status = "Text wird lokal optimiert …"
                    do {
                        try await formatter.prepare()
                        text = try await formatter.format(replaced, style: style, context: "", vocabulary: matcher.topVocabulary(in: replaced))
                    } catch is CancellationError { throw CancellationError() }
                    catch { fallback = true }
                }
                guard sessionID == id, !Task.isCancelled else { return }
                if originalRequested { text = replaced; fallback = false }
                let result = DictationResult(id: id, text: text, original: original, usedFallback: fallback, duration: duration)
                results.insert(result, at: 0); results = Array(results.prefix(5))
                let outcome: DeliveryOutcome
                if language.requiresReview {
                    outcome = DeliveryOutcome(.notAttempted, reason: "Deutsche Forschungs-Beta: Prüfe den Text vor dem Einfügen. Die Erkennung ist noch ungenau.")
                } else if conflict {
                    outcome = DeliveryOutcome(.notAttempted, reason: "Wispr Flow ist wieder gestartet. Der Text bleibt verfügbar.")
                } else {
                    outcome = await DeliveryCoordinator().deliver(text: text, to: focus)
                }
                guard sessionID == id, !Task.isCancelled else { return }
                if let context = historyContext { recordHistory(result, context: context, delivery: outcome.status) }
                sessionID = nil; focus = nil; historyContext = nil; lipSession = false; lipHotkey.reset()
                lipHotkey.cancellationEnabled = false; hotkey.cancellationEnabled = false
                presentDelivery(outcome, result: result); updateHotkey()
            } catch is CancellationError {} catch {
                if sessionID == id { fail(error.localizedDescription, title: "Lippenlesen nicht möglich") }
            }
        }
    }
}

private struct NoSpeechDetected: LocalizedError { let errorDescription: String? }

@MainActor final class AppModel: NSObject, ObservableObject, NSWindowDelegate, NSApplicationDelegate {
    let reports = ErrorReportController()
    @Published var document = ExportDocument() { didSet { scheduleSave(); updateHotkey() } }
    @Published var state: PillState = .loading { didSet { updatePillVisibility(); if state != oldValue { announceState() } } }
    @Published var status = "Einrichtung abschließen"
    @Published var level: Float = 0
    @Published var captureReady = false
    @Published var captureStartupMilliseconds: Double?
    @Published var elapsed: TimeInterval = 0
    @Published var results: [DictationResult] = []
    @Published var practiceFeedback = PracticeFeedback()
    @Published var recoveryReason = ""
    @Published var recoverySelection: UUID?
    @Published var recoveryClipboardStatus = ""
    @Published var recoveryCanUndo = false
    @Published var recoveryTransient = false
    @Published var recoveryTextHeight: CGFloat = 44
    @Published var recoveryCountdownRemaining: TimeInterval = 5
    @Published var recoveryCountdownPaused = false
    /// A failed attempt must not masquerade as, or copy, a previous result.
    @Published var recoveryFailureTitle: String?
    private var recoveryCopiedID: UUID?
    private var recoveryClipboard = ClipboardRecovery()
    private var recoveryTimer: Timer?
    private var recoveryCountdown: FeedbackCountdown?
    private var recoveryHovered = false
    @Published var downloadFraction: Double = 0
    @Published var downloadLabel = ""
    @Published var downloading = false
    @Published var preparing = false
    @Published var modelsReady = false
    @Published var microphoneGranted = false
    @Published var accessibilityGranted = false
    @Published var cameraGranted = false
    @Published var lipReady = false
    @Published var lipPreparing = false
    @Published var lipInstalling = false
    @Published var lipSession = false
    @Published var lipStatus = "Noch nicht eingerichtet"
    private let camera = CameraCapture()
    private let lipHotkey = GlobalHotkey()
    private let lipInstaller = LipReadingInstaller()
    private lazy var lipRuntime = LipReadingRuntime(resources: lipResources)
    private var lipPreparation: Task<Void, Never>?
    private var lipPreparationID = UUID()
    @Published var wisprRunning = false
    @Published var wisprInstalled = false
    @Published var importPreview = ImportPreview()
    @Published var importPreviewLoaded = false
    @Published var importRefreshing = false
    @Published var importing = false
    @Published var importReceipt = ""
    @Published var importFailed = false
    @Published var importRevision = 0
    @Published var switchReceipt = ""
    @Published var switchingWispr = false
    @Published var errorMessage: String?
    var practiceComplete: Bool { document.settings.practiceCompleted ?? document.settings.onboardingComplete }
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var canUndoImport = false
    @Published var shortcutCapture = false { didSet { updateHotkey() } }
    @Published var settingsNavigation: SettingsNavigation?
    let updates = AppUpdateController()
    @Published var historyEntries: [HistoryEntry] = []
    @Published var latestHistory: [HistoryEntry] = []
    @Published var historyTotal = 0
    @Published var historyStatistics = HistoryStatistics()
    @Published var allHistoryStatistics = HistoryStatistics()
    @Published var historyLoading = false
    @Published var historyError: String?
    @Published var historySaveError: String?
    @Published var historyQuery = ""
    @Published var historyCollection: HistoryCollection = .all
    @Published var historyPeriod: HistoryPeriod = .all
    @Published var historyCopyID: UUID?
    @Published var historyNotice = ""
    var historyStore = HistoryStore(url: ModelPaths.support.appendingPathComponent("history.sqlite"))
    var historyRequestID = UUID()
    var historyReadTask: Task<Void, Never>?
    var historyWriteTask: Task<Void, Never>?
    private var historyContext: HistoryCaptureContext?
    let store = SettingsStore(url: ModelPaths.support.appendingPathComponent("settings.json"))
    let downloader = ModelDownloader()
    let speech = SpeechRuntime(modelDirectory: ModelPaths.speech)
    let formatter = LocalFormatter(modelURL: ModelPaths.formatter)
    let capture = AudioCapture()
    let hotkey = GlobalHotkey()
    private var pipeline: ProcessingPipeline?
    private var focus: FocusSnapshot?
    private var sessionID: UUID?
    private var deliveryFeedbackID: UUID?
    private var quietDeliveryFeedback = false
    private var operation: Task<Void, Never>?
    private var appendTask: Task<Void, Never>?
    private var acceptedSamples = 0
    private var pendingSamples: [Int: [Float]] = [:]
    private var practiceSession = false
    private var practiceError = false
    private var practiceStopper = PracticeSession()
    private var originalRequested = false
    private var saveTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var clock: Timer?
    private var startedAt: TimeInterval = 0
    private var refreshClock: Timer?
    private var pill: PillWindow?
    private var settingsWindow: NSWindow?
    private var settingsOpen = false
    private var recoveryWindow: NSPanel?
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var wisprMenuItem: NSMenuItem?
    private var statusSymbol = "waveform"
    private var sleepInterrupted = false
    private var loading = true
    private var quitting = false
    private var shutdownComplete = false
    private var previewMode = false
    #if DEBUG
    var historyPreviewEntries: [HistoryEntry] = []
    private var practiceFixture: [Float]?
    private var recoveryPreviewBoard: NSPasteboard?
    private var recoveryPreviewStarted: TimeInterval = 0
    private var recoveryPreviewGeneralCount = 0
    #endif
    var isUIPreview: Bool { previewMode }
    var practiceAudioSource: String? {
        #if DEBUG
        guard previewMode, CommandLine.arguments.contains("--preview-ui=practice") else { return nil }
        guard let path = CommandLine.arguments.first(where: { $0.hasPrefix("--practice-fixture=") })?.dropFirst("--practice-fixture=".count) else { return "Keine Testdatei ausgewählt" }
        let name = URL(fileURLWithPath: String(path)).lastPathComponent
        let code = name.split(separator: "-").first.map(String.init) ?? ""
        let language = ["de": "Deutsch", "en": "Englisch"][code]
        return language.map { "\($0) · \(name)" } ?? name
        #else
        return nil
        #endif
    }
    // A failed cached preview must not lock the user out of a fresh transactional import.
    var canImportWispr: Bool { !previewMode && !loading && importPreviewLoaded && !importRefreshing && !importing }
    var acceptsDictationGesture: Bool {
        state == .ready || state == .recording || state == .success || (state == .error && sessionID == nil)
    }

    var pillLabel: String { state == .ready ? document.settings.shortcut.spokenLabel : status }
    var durationLabel: String { String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60) }
    var conflict: Bool {
        guard wisprRunning else { return false }
        let current = [document.settings.shortcut] + (document.settings.shortcutBindings?.all ?? [])
        let imported = importPreview.shortcut.map { [$0] } ?? []
        return document.settings.importedWisprShortcut || current.contains { imported.contains($0) || importPreview.shortcutBindings.all.contains($0) }
    }
    var canCompleteSetup: Bool { PracticeSession.canFinish(modelsReady: modelsReady, microphoneGranted: microphoneGranted, accessibilityGranted: accessibilityGranted, practiceComplete: practiceComplete) }
    /// The first setup step that still needs the user, or nil when dictation can start.
    var pendingSetupStep: SetupStep? {
        if !modelsReady && !downloading && !preparing { return .models }
        if !microphoneGranted || !accessibilityGranted { return .permissions }
        if !modelsReady || !practiceComplete { return .practice }
        if conflict { return .switchover }
        return nil
    }
    func setupStepDone(_ step: SetupStep) -> Bool {
        switch step {
        case .models: modelsReady
        case .wispr: !wisprInstalled || canUndoImport || importRevision > 0
        case .language: !document.settings.languages.isEmpty
        case .permissions: microphoneGranted && accessibilityGranted
        case .practice: practiceComplete
        case .switchover: !wisprRunning
        }
    }

    func launch(preview: String? = nil) {
        previewMode = preview != nil
        pill = PillWindow(model: self)
        #if DEBUG
        // Opt-in, content-free AppKit readback. Computer Use can reopen an app
        // when inspecting it with no windows, masking a successful close.
        if CommandLine.arguments.contains("--trace-pill-visibility") {
            var lastTrace = Data()
            Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let snapshot: [String: Any] = ["state": self.state.rawValue,
                        "pillVisible": self.pill?.panel.isVisible == true,
                        "settingsVisible": self.settingsWindow?.isVisible == true,
                        "settingsOpen": self.settingsOpen, "appActive": NSApp.isActive]
                    guard let trace = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]), trace != lastTrace else { return }
                    lastTrace = trace
                    FileHandle.standardOutput.write(Data("PILL_VISIBILITY ".utf8) + trace + Data("\n".utf8))
                }
            }
        }
        #endif
        makeMenu()
        reports.start(preview: previewMode)
        updates.busy = { [weak self] in
            guard let self else { return true }
            return UpdatePolicy.busy(recording: self.state == .recording,
                processing: self.state == .processing,
                setup: self.loading || self.downloading || self.preparing || self.importing || self.switchingWispr || self.lipPreparing || self.lipInstalling || !self.document.settings.onboardingComplete)
        }
        if !previewMode { updates.start() }
        hotkey.onGesture = { [weak self] gesture in switch gesture { case .start: self?.start(); case .stop: self?.stop(); case .cancel: self?.cancel(); case .handsFree: break; case .copyLast: if self?.results.isEmpty == false { self?.copyResult(at: 0) }; case .pasteLast: self?.pasteLastResult() } }
        hotkey.onFailure = { [weak self] message in guard let self else { return }; if self.sessionID != nil { self.cancel() }; self.status = message; self.state = .error; self.resetErrorSoon() }
        lipHotkey.onGesture = { [weak self] gesture in
            switch gesture { case .start: self?.startLipReading(); case .stop: self?.stop(); case .cancel: self?.cancel(); default: break }
        }
        lipHotkey.onFailure = { [weak self] message in self?.lipStatus = message }
        if let preview {
            #if DEBUG
            if ["overview", "history", "statistics", "dictionary", "updates", "beta", "help"].contains(preview) {
                loadHistoryPreview(empty: CommandLine.arguments.contains("--preview-empty"))
                document.settings.onboardingComplete = true; modelsReady = true; microphoneGranted = true; accessibilityGranted = true
                settingsNavigation = SettingsNavigation(section: SettingsSection.allCases.first { $0.previewName == preview } ?? .overview, setupStep: nil)
                showSettings()
            }
            #endif
            loading = false; state = PillState(rawValue: preview) ?? .ready
            status = state == .processing ? "Text wird aufbereitet …" : state == .error ? "Einfügen prüfen" : state == .success ? "Eingefügt" : state == .paused ? "Pausiert" : "Bereit"
            level = 0.65; elapsed = 24
            if state == .error { results = [.init(id: UUID(), text: "Vielen Dank für die Rückmeldung.\n\nDer Entwurf wird morgen geprüft.", original: "", usedFallback: false, duration: 24)]; recoveryReason = "Das Textfeld hat sich geändert. Prüfe das Ziel und kopiere deinen Text."; showRecovery() }
            if preview == "settings" { showSettings() }
            #if DEBUG
            if preview == "dictation-layout" {
                // Isolated layout fixture. No model, microphone, event tap or stored user data.
                document.settings.onboardingComplete = true; document.settings.practiceCompleted = true
                document.settings.languages = ["de", "en"]
                document.settings.shortcut = Shortcut(keyCode: nil, modifiers: (1 << 17) | (1 << 18))
                var bindings = ShortcutBindings()
                bindings.handsFree = [Shortcut(keyCode: 49, modifiers: 1 << 23)]
                bindings.cancel = [Shortcut(keyCode: 53, modifiers: 0)]
                bindings.copyLast = [Shortcut(keyCode: 8, modifiers: (1 << 18) | (1 << 20))]
                bindings.pasteLast = [Shortcut(keyCode: 9, modifiers: (1 << 18) | (1 << 20))]
                document.settings.shortcutBindings = bindings
                modelsReady = true; microphoneGranted = true; accessibilityGranted = true
                state = .ready; status = "Bereit zum Diktieren"
                settingsNavigation = SettingsNavigation(section: .dictation, setupStep: nil)
                showSettings()
            }
            if preview == "clipboard" {
                // A named pasteboard proves the real copy/undo UI without
                // reading, changing, or persisting the user's clipboard.
                recoveryPreviewGeneralCount = NSPasteboard.general.changeCount
                let board = NSPasteboard.withUniqueName(); recoveryPreviewBoard = board
                let original = NSPasteboardItem(); original.setString("Vorheriger Testinhalt", forType: .string); original.setString("<b>Vorheriger Testinhalt</b>", forType: .html)
                board.writeObjects([original]); recoveryClipboard = ClipboardRecovery(board: board)
                var text = "Vielen Dank für die Rückmeldung.\n\nDer Entwurf wird morgen geprüft."
                if CommandLine.arguments.contains("--preview-long") { text = Array(repeating: text, count: 100).joined(separator: "\n\n") }
                results = [.init(id: UUID(), text: text, original: "", usedFallback: false, duration: 24)]
                if CommandLine.arguments.contains("--preview-history") { results.append(.init(id: UUID(), text: "Dies ist ein früheres Diktat.", original: "", usedFallback: false, duration: 10)) }
                recoveryReason = "Das Textfeld hat sich geändert. Prüfe das Zielfeld."
                state = .error; status = "Text verfügbar"; recoveryPreviewStarted = ProcessInfo.processInfo.systemUptime
                showRecovery(autoCopy: !CommandLine.arguments.contains("--preview-history"), activate: false)
                traceRecoveryPreview("shown")
            }
            if preview == "recording-error" {
                recoveryPreviewGeneralCount = NSPasteboard.general.changeCount
                let board = NSPasteboard.withUniqueName(); recoveryPreviewBoard = board
                let original = NSPasteboardItem(); original.setString("Vorheriger Testinhalt", forType: .string); original.setString("<b>Vorheriger Testinhalt</b>", forType: .html)
                board.writeObjects([original]); recoveryClipboard = ClipboardRecovery(board: board)
                if CommandLine.arguments.contains("--preview-history") {
                    results = [.init(id: UUID(), text: "Dies ist ein früheres Diktat.", original: "", usedFallback: false, duration: 10)]
                }
                recoveryPreviewStarted = ProcessInfo.processInfo.systemUptime
                fail(SpeechInputError.tooShort.localizedDescription, title: "Audio zu kurz")
                traceRecoveryPreview("shown")
            }
            if preview == "continuity" {
                // Real keyboard delivery to the real state machine, no audio,
                // models, persisted settings, or user pasteboard writes.
                recoveryPreviewGeneralCount = NSPasteboard.general.changeCount
                let board = NSPasteboard.withUniqueName(); recoveryPreviewBoard = board
                recoveryPreviewStarted = ProcessInfo.processInfo.systemUptime
                document.settings.shortcut = Shortcut(keyCode: 49, modifiers: (1 << 17) | (1 << 18) | (1 << 19))
                document.settings.shortcutBindings = ShortcutBindings()
                modelsReady = true; microphoneGranted = true; accessibilityGranted = AXIsProcessTrusted()
                state = .error; results = [.init(id: UUID(), text: "Öffentlicher Prüftext.", original: "", usedFallback: false, duration: 3)]
                recoveryReason = "Kürzelprüfung ohne Mikrofon: Control + Option + Shift + Leertaste."
                showRecovery(activate: false)
                hotkey.shortcut = document.settings.shortcut
                hotkey.bindings = document.settings.shortcutBindings ?? ShortcutBindings()
                hotkey.enabled = accessibilityGranted && acceptsDictationGesture
                _ = hotkey.install()
                traceRecoveryPreview("waiting-for-shortcut")
            }
            if preview == "practice" { loadPracticeFixture() }
            if preview == "error", CommandLine.arguments.contains("--test-delivery") {
                // Public preview text only. Exercise actual delivery through
                // the nonactivating Pill without audio or persisted settings.
                updatePillVisibility()
                print("DELIVERY_TEST_ACCESSIBILITY \(AXIsProcessTrusted())")
                fflush(stdout)
            }
            #endif
            return
        }
        Task {
            do { document = try await store.load() } catch { errorMessage = "Einstellungen konnten nicht geladen werden: \(error.localizedDescription)"; reports.record(component: .settings, code: .settingsLoadFailed) }
            loading = false
            wisprInstalled = WisprSwitch.installedURL != nil
            refreshImportPreview()
            canUndoImport = FileManager.default.fileExists(atPath: ModelPaths.support.appendingPathComponent("wispr-import-undo.json").path)
            refreshPermissions()
            settingsNavigation = SettingsNavigation(section: document.settings.onboardingComplete ? .overview : .setup, setupStep: nil)
            refreshHistory()
            if !document.settings.onboardingComplete { showSettings() }
            if (try? await downloader.installed()) == true { await prepareModels() }
            if lipEnabled { prepareLipReading() }
            updateHotkey()
        }
        refreshClock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshPermissions() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.prepareForSleep() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.updateHotkey() } }
        // Let Electron/Chromium apps build their text-field accessibility before the first dictation.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in WebAccessibility.enable(for: app) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.pill?.position() } }
    }
    private func makeMenu() {
        let mainMenu = NSMenu(), appMenu = NSMenu(), appItem = NSMenuItem()
        let settingsItem = NSMenuItem(title: "Einstellungen …", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self; appMenu.addItem(settingsItem)
        let updateItem = NSMenuItem(title: "Nach Updates suchen …", action: #selector(checkUpdates), keyEquivalent: "")
        updateItem.target = self; appMenu.addItem(updateItem)
        let reportItem = NSMenuItem(title: "Fehler melden …", action: #selector(openReportHelp), keyEquivalent: "")
        reportItem.target = self; appMenu.addItem(reportItem)
        let quitItem = NSMenuItem(title: "AInauten Voice beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem); appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let fileItem = NSMenuItem(title: "Ablage", action: nil, keyEquivalent: ""), fileMenu = NSMenu(title: "Ablage")
        fileMenu.addItem(withTitle: "Fenster schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu; mainMenu.addItem(fileItem)
        let editItem = NSMenuItem(title: "Bearbeiten", action: nil, keyEquivalent: ""), editMenu = NSMenu(title: "Bearbeiten")
        for (title, selector, key) in [("Rückgängig", Selector(("undo:")), "z"), ("Ausschneiden", #selector(NSText.cut(_:)), "x"), ("Kopieren", #selector(NSText.copy(_:)), "c"), ("Einfügen", #selector(NSText.paste(_:)), "v"), ("Alles auswählen", #selector(NSText.selectAll(_:)), "a")] { editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key) }
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApplication.shared.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "AInauten Voice")
        let menu = NSMenu()
        for (title, selector) in [("AInauten Voice öffnen", #selector(openOverview)), ("Diktatverlauf", #selector(openHistory)), ("Letzte Ergebnisse", #selector(openResults)), ("Tastenkürzel aktiv", #selector(togglePause)), ("Zu Wispr Flow zurückwechseln", #selector(returnToWispr)), ("Beenden", #selector(quit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
            if selector == #selector(togglePause) { pauseMenuItem = item }
            if selector == #selector(returnToWispr) { wisprMenuItem = item }
        }
        statusItem?.menu = menu
        updateStatusItem()
    }
    /// Paused shortcuts are otherwise invisible while the idle pill is hidden.
    private func updateStatusItem() {
        let paused = document.settings.paused
        pauseMenuItem?.state = paused ? .off : .on
        wisprMenuItem?.isHidden = !wisprInstalled
        let symbol = paused ? "mic.slash" : "waveform"
        if statusSymbol != symbol {
            statusSymbol = symbol
            statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: paused ? "AInauten Voice, Tastenkürzel ausgeschaltet" : "AInauten Voice")
        }
    }
    @objc private func openSettings() { navigate(to: .dictation) }
    @objc private func openReportHelp() { navigate(to: .help) }
    @objc private func checkUpdates() {
        navigate(to: .updates)
        updates.check()
    }
    @objc private func openOverview() { navigate(to: document.settings.onboardingComplete ? .overview : .setup) }
    @objc private func openHistory() { navigate(to: .history) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        #if DEBUG
        if previewMode, CommandLine.arguments.contains("--test-delivery") { return true }
        if previewMode, recoveryPreviewBoard != nil { return true }
        #endif
        openOverview(); return true
    }
    @objc private func openResults() { showRecovery() }
    @objc private func togglePause() { document.settings.paused.toggle(); if document.settings.paused { cancel() } else if state == .error { dismissError() } }
    @objc private func returnToWispr() {
        document.settings.paused = true; cancel()
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: WisprSwitch.bundleID) { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if shutdownComplete { return .terminateNow }
        // Sparkle's deferral delegate is not called for every installation path.
        // Never let its relaunch cancel an active recording or processing task.
        if updates.installingUpdate && updates.busy() { return .terminateCancel }
        if !quitting {
            quitting = true; cancel(); downloadTask?.cancel(); refreshClock?.invalidate(); lipPreparation?.cancel()
            let pendingSave = saveTask, pendingHistory = historyWriteTask
            Task { await lipRuntime.cancel(); await lipInstaller.cancel(); await pendingSave?.value; await pendingHistory?.value; await formatter.shutdown(); shutdownComplete = true; sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    func refreshPermissions() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let accessibility = AXIsProcessTrusted()
        let wispr = !NSRunningApplication.runningApplications(withBundleIdentifier: WisprSwitch.bundleID).isEmpty
        if microphoneGranted != mic { microphoneGranted = mic }
        if accessibilityGranted != accessibility { accessibilityGranted = accessibility }
        let cameraAccess = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if cameraGranted != cameraAccess { cameraGranted = cameraAccess }
        if lipSession && (!cameraAccess || !accessibility) { cancel() }
        if wisprRunning != wispr { wisprRunning = wispr; if wispr { wisprInstalled = true } }
        if conflict && state == .recording && !practiceSession { stop() }
        // Finish setup as soon as every prerequisite holds, e.g. Accessibility granted after the probe.
        if !loading && !previewMode && !document.settings.onboardingComplete && canCompleteSetup && !conflict { markSetupComplete() }
        let actualLogin = SMAppService.mainApp.status == .enabled
        if loginEnabled != actualLogin { loginEnabled = actualLogin }
        if state == .recording, let pipeline { Task { let backlog = await pipeline.backlogSeconds(); if backlog > 30 && self.state == .recording { self.status = "Verarbeitung verzögert sich. Audio bleibt erhalten." } } }
        updateHotkey()
    }
    private func updateHotkey() {
        updateStatusItem()
        guard !quitting else { hotkey.enabled = false; hotkey.cancellationEnabled = false; lipHotkey.enabled = false; lipHotkey.cancellationEnabled = false; return }
        #if DEBUG
        guard !previewMode || CommandLine.arguments.contains("--preview-ui=continuity") else { return }
        #else
        guard !previewMode else { return }
        #endif
        hotkey.cancellationEnabled = sessionID != nil && (state == .recording || state == .processing) && accessibilityGranted && !shortcutCapture
        hotkey.shortcut = document.settings.shortcut
        hotkey.bindings = document.settings.shortcutBindings ?? ShortcutBindings()
        updateLipHotkey()
        let allowed = modelsReady && microphoneGranted && accessibilityGranted && !lipSession && !conflict && !document.settings.paused && !shortcutCapture
        // A result panel, including manual history/partial text, never blocks
        // a new dictation. start() closes it while retaining the hold gesture.
        hotkey.enabled = allowed && acceptsDictationGesture
        if allowed { _ = hotkey.install() }
        guard state != .recording && state != .processing && state != .success && state != .error else { return }
        let nextState: PillState = allowed ? .ready : preparing || loading ? .loading : conflict ? .conflict : document.settings.paused ? .paused : .needsSetup
        let nextStatus = allowed ? "Bereit zum Diktieren" : preparing || loading ? "Modelle werden geladen" : conflict ? "Wispr Flow läuft. Bitte den Wechsel abschließen." : document.settings.paused ? "Tastenkürzel ausgeschaltet" : !modelsReady ? "Modelle einrichten" : !microphoneGranted ? "Mikrofon freigeben" : "Bedienungshilfen freigeben"
        if state != nextState { state = nextState }
        if status != nextStatus { status = nextStatus }
        hotkey.enabled = allowed
    }
    func requestMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in Task { @MainActor in self?.refreshPermissions() } }
        } else { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func installModels() {
        guard !downloading else { return }; downloading = true; errorMessage = nil
        downloadTask = Task {
            do {
                try await downloader.install { [weak self] current, total, group in
                    Task { @MainActor in self?.downloadFraction = Double(current) / Double(max(1, total)); self?.downloadLabel = "\(group == "parakeet" ? "Spracherkennung" : "Textoptimierung"): \(ByteCountFormatter.string(fromByteCount: current, countStyle: .file)) von \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))" }
                }
                downloading = false; await prepareModels()
            } catch is CancellationError { downloading = false; downloadLabel = "Download pausiert. Beim nächsten Start geht es weiter." }
            catch { downloading = false; errorMessage = error.localizedDescription }
        }
    }
    func pauseDownload() { downloadTask?.cancel(); Task { await downloader.cancel() } }
    func prepareModels() async {
        guard !quitting else { return }
        preparing = true; state = .loading; status = "Modelle werden geladen …"
        do {
            try await speech.prepare()
            guard !quitting else { return }
            try await formatter.prepare()
            guard !quitting else { return }
            modelsReady = true; state = .paused; status = "Bereit"
        }
        catch { modelsReady = false; errorMessage = error.localizedDescription; status = "Modelle prüfen"; reports.record(component: .models, code: .modelLoadFailed) }
        preparing = false; updateHotkey()
    }
    func refreshImportPreview() {
        guard !previewMode && !importRefreshing && !importing else { return }
        importRefreshing = true
        Task {
            let preview = await Task.detached(priority: .userInitiated) { WisprMigrationService().preview() }.value
            importPreview = preview; importPreviewLoaded = true; importRefreshing = false
        }
    }
    func importWispr() {
        guard canImportWispr else { return }
        importing = true; errorMessage = nil; importReceipt = ""; importFailed = false
        let current = document
        let pendingSave = saveTask
        pendingSave?.cancel()
        Task {
            await pendingSave?.value
            loading = true
            defer { loading = false; importing = false }
            do {
                // Flush the live settings before migration. A delayed autosave must never undo an import.
                try await store.save(current)
                let result = try await store.applyWisprImport(WisprMigrationService())
                importPreview = result.preview; importPreviewLoaded = true
                guard !result.preview.isPartial else {
                    importFailed = true
                    importReceipt = "Import nicht ausgeführt. Deine bisherigen Einstellungen bleiben erhalten. Du kannst direkt erneut prüfen und importieren."
                    return
                }
                document = try await store.load()
                canUndoImport = true
                importReceipt = result.summary(savedCount: document.dictionary.count)
                importRevision += 1
                updateHotkey()
            } catch {
                importFailed = true
                importReceipt = "Der Import konnte nicht vollständig bestätigt werden. Prüfe den gespeicherten Bestand, bevor du ihn erneut startest."
                errorMessage = error.localizedDescription
                reports.record(component: .migration, code: .importFailed)
            }
        }
    }
    func undoImport() {
        Task { do { saveTask?.cancel(); try await store.undoWisprImport(); loading = true; document = try await store.load(); loading = false; importFailed = false; importReceipt = "Der Stand vor dem letzten Wispr-Import wurde wiederhergestellt."; updateHotkey() } catch { loading = false; errorMessage = error.localizedDescription } }
    }
    func switchFromWispr() {
        guard !switchingWispr, !previewMode else { return }
        switchingWispr = true
        Task {
            let outcome = await WisprSwitch().switchFromWispr()
            switchReceipt = outcome.reason; switchingWispr = false; refreshPermissions()
            if outcome.status == .completed {
                document.settings.paused = false
                if canCompleteSetup { markSetupComplete() }
            }
        }
    }
    func completeSetup() {
        guard canCompleteSetup else {
            settingsNavigation = SettingsNavigation(section: .setup, setupStep: pendingSetupStep ?? .practice)
            return
        }
        markSetupComplete()
        settingsNavigation = SettingsNavigation(section: .overview, setupStep: nil)
    }
    private func markSetupComplete() {
        document.settings.onboardingComplete = true
        document.settings.paused = false
        updateHotkey()
    }
    func startPractice() { start(practice: true) }
    func start(practice: Bool = false) {
        guard !quitting else { return }
        guard sessionID == nil else { return }
        guard !preparing, modelsReady, microphoneGranted else {
            if practice {
                let id = UUID(); practiceFeedback.begin(id)
                practiceFeedback.fail(id, message: !modelsReady ? "Die Modelle sind noch nicht bereit. Lade sie im Schritt „Modelle“." : "Die Mikrofonfreigabe fehlt. Öffne den Schritt „Freigaben“ und erlaube AInauten Voice den Zugriff.")
            }
            return
        }
        guard practice || !conflict else { status = "Wispr Flow zuerst beenden"; return }
        // Fence windowWillClose before closing: its idle-state update would
        // otherwise disable/reset the hold that has just started this session.
        let id = UUID(); sessionID = id
        closeRecovery()
        quietDeliveryFeedback = false; sleepInterrupted = false
        practiceSession = practice; originalRequested = false; acceptedSamples = 0; pendingSamples = [:]; appendTask = nil
        practiceError = false
        errorMessage = nil
        if practice { practiceFeedback.begin(id) }
        practiceStopper = PracticeSession()
        focus = practice ? nil : FocusSnapshot.capture(); pill?.position()
        state = .recording; hotkey.cancellationEnabled = !practice && accessibilityGranted; level = 0; elapsed = 0; captureReady = false; captureStartupMilliseconds = nil
        updateLipHotkey()
        let requestedAt = ProcessInfo.processInfo.systemUptime
        #if DEBUG
        if previewMode && CommandLine.arguments.contains("--preview-ui=continuity") {
            captureReady = true; status = "Kürzelprüfung ohne Mikrofon"
            traceRecoveryPreview("recording"); return
        }
        #endif
        let style = document.settings.style(for: focus?.bundleID)
        historyContext = HistoryCaptureContext(date: Date(), style: style, bundleID: focus?.bundleID,
            appName: focus.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName }, enabled: document.settings.historyEnabled ?? true)
        let dictionary = document.dictionary
        operation = Task {
            do {
                let selectedFormatter: any TextFormatting
                if document.settings.cloudEnabled && style != .original {
                    guard let endpoint = URL(string: document.settings.cloudEndpoint), let key = try KeychainStorage().key() else { throw VoiceError.message("Cloud-Optimierung benötigt einen API-Schlüssel.") }
                    selectedFormatter = CloudFormatter(endpoint: endpoint, model: document.settings.cloudModel, key: key)
                } else { selectedFormatter = formatter }
                let pipeline = ProcessingPipeline(speech: speech, formatter: selectedFormatter); self.pipeline = pipeline
                guard sessionID == id, state == .recording else { return }
                #if DEBUG
                if practice && practiceFixture != nil {
                    try await pipeline.start(sessionID: id, style: style, dictionary: dictionary)
                    guard sessionID == id, state == .recording else { return }
                    captureReady = true; level = 0.65; return
                }
                #endif
                let offsets = CaptureSampleOffsets()
                try capture.start(onSamples: { [weak self] samples, level in
                    let offset = offsets.reserve(samples.count)
                    Task { @MainActor in guard let self, self.sessionID == id, self.state == .recording else { return }; self.level = level
                        self.pendingSamples[offset] = samples
                        while let contiguous = self.pendingSamples.removeValue(forKey: self.acceptedSamples) {
                            self.acceptedSamples += contiguous.count
                            let prior = self.appendTask
                            let initialization = self.operation
                            self.appendTask = Task {
                                await prior?.value
                                // Capture begins immediately. Keep early PCM while
                                // model/dictionary preparation finishes in parallel.
                                await initialization?.value
                                guard self.sessionID == id, !Task.isCancelled else { return }
                                do { try await pipeline.append(samples: contiguous) } catch { if self.sessionID == id { self.fail(error.localizedDescription) } }
                            }
                        }
                    }
                }, onError: { [weak self] message in Task { @MainActor in if self?.sessionID == id { if message.contains("20 Minuten") || message.contains("Mikrofon wurde geändert") { self?.stop() } else { self?.fail(message) } } } })
                captureReady = true
                captureStartupMilliseconds = (ProcessInfo.processInfo.systemUptime - requestedAt) * 1000
                startedAt = ProcessInfo.processInfo.systemUptime
                clock = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in guard let self, self.sessionID == id, self.state == .recording else { return }; self.elapsed = ProcessInfo.processInfo.systemUptime - self.startedAt
                    if self.practiceSession && self.practiceStopper.shouldStop(level: self.level, elapsed: self.elapsed) { self.stop(); return }
                    if self.elapsed >= 1200 { self.stop() } else if self.elapsed >= 1140 { self.status = "Noch eine Minute bis zum Aufnahmelimit" }
                } }
                try await pipeline.start(sessionID: id, style: style, dictionary: dictionary)
                guard sessionID == id else { await pipeline.cancel(); return }
            } catch { if sessionID == id { fail(error.localizedDescription) } }
        }
    }
    func stop() {
        guard let id = sessionID, state == .recording else { return }
        if lipSession { stopLipReading(id); return }
        #if DEBUG
        if previewMode && CommandLine.arguments.contains("--preview-ui=continuity") {
            sessionID = nil; captureReady = false; hotkey.reset(); state = .ready
            traceRecoveryPreview("stopped"); return
        }
        #endif
        var captured = capture.stop(); captureReady = false; clock?.invalidate(); clock = nil
        // Short recordings may contain a complete word. Let recognition decide;
        // the no-speech path below already avoids opening a recovery window.
        #if DEBUG
        if practiceSession, let practiceFixture { captured = practiceFixture }
        #endif
        state = .processing; status = "Text wird aufbereitet …"; hotkey.enabled = false; hotkey.cancellationEnabled = accessibilityGranted
        let prior = operation; let appended = appendTask; let accepted = acceptedSamples; let practice = practiceSession
        if practice { practiceFeedback.processing(id) }
        pendingSamples = [:]
        operation = Task {
            await prior?.value; await appended?.value
            guard sessionID == id, !Task.isCancelled, let pipeline else { return }
            do {
                guard !captured.isEmpty else { throw NoSpeechDetected(errorDescription: "Es wurde kein Audio aufgenommen. Starte die Probe erneut und warte, bis „Ich höre zu“ erscheint.") }
                // The tap stores PCM before dispatching UI callbacks. Reconcile its
                // immutable stop snapshot so queued callbacks cannot lose the tail.
                guard accepted <= captured.count else { throw VoiceError.message("Audioabschnitte konnten nicht sicher zusammengefügt werden.") }
                if accepted < captured.count { try await pipeline.append(samples: Array(captured.dropFirst(accepted))) }
                if originalRequested { await pipeline.requestOriginal() }
                let result = try await pipeline.finish()
                guard sessionID == id, !Task.isCancelled else { return }
                guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NoSpeechDetected(errorDescription: "Keine Sprache erkannt. Bitte sprich einen ganzen Satz und versuche es erneut.") }
                results.insert(result, at: 0); results = Array(results.prefix(5))
                if practice && result.isComplete { document.settings.practiceCompleted = true }
                let outcome: DeliveryOutcome
                if practice { outcome = DeliveryOutcome(.notAttempted) }
                else if conflict { outcome = DeliveryOutcome(.notAttempted, reason: "Wispr Flow läuft wieder. Dein Diktat bleibt verfügbar, das Tastenkürzel ist pausiert.") }
                else if !result.isComplete { outcome = DeliveryOutcome(.notAttempted, reason: "Dieses Ergebnis ist unvollständig und wird nicht automatisch eingefügt.") }
                else if sleepInterrupted { outcome = DeliveryOutcome(.notAttempted, reason: "Der Mac ist in den Ruhezustand gegangen. Dein Diktat wurde deshalb nicht eingefügt.") }
                else { outcome = await DeliveryCoordinator().deliver(text: result.text, to: focus) }
                guard sessionID == id else { return }
                if !practice, let context = historyContext { recordHistory(result, context: context, delivery: outcome.status) }
                historyContext = nil
                sessionID = nil; focus = nil; hotkey.cancellationEnabled = false; self.pipeline = nil; appendTask = nil; acceptedSamples = 0; pendingSamples = [:]; practiceSession = false
                if practice {
                    practiceFeedback.finish(id, result: result)
                    practiceError = !result.isComplete
                    state = result.isComplete ? .success : .error; status = result.isComplete ? "Probediktat erkannt" : "Probediktat unvollständig"
                    if result.isComplete && canCompleteSetup { markSetupComplete() }
                    if !result.isComplete { resetErrorSoon() }
                }
                else { presentDelivery(outcome, result: result) }
                if practice { Task { try? await Task.sleep(for: .seconds(1.5)); guard self.sessionID == nil, self.state == .success, self.results.first?.id == result.id else { return }; self.state = .paused; self.updateHotkey() } }
            } catch let partial as PartialDictationError {
                guard sessionID == id, !Task.isCancelled else { return }
                reports.record(component: .recognition, code: .processingFailed)
                results.insert(partial.result, at: 0); results = Array(results.prefix(5))
                if practice {
                    practiceFeedback.fail(id, message: "Die Erkennung wurde unterbrochen. Der folgende Teiltext ist unvollständig. " + partial.localizedDescription, partial: partial.result)
                    practiceError = true
                    cancel(); state = .error; status = "Probediktat prüfen"; resetErrorSoon(); return
                }
                if let context = historyContext { recordHistory(partial.result, context: context, delivery: .notAttempted) }
                cancel(); state = .error; status = "Teiltext anzeigen"
                recoveryReason = "Die Erkennung wurde unterbrochen. Dieser Teiltext ist unvollständig und wurde nicht eingefügt. " + partial.localizedDescription
                errorMessage = recoveryReason; showRecovery()
            } catch let silence as NoSpeechDetected {
                guard sessionID == id, !Task.isCancelled else { return }
                if practice { fail(silence.localizedDescription) } else { showNoSpeech() }
            } catch is CancellationError {} catch {
                if sessionID == id {
                    if !(error is SpeechInputError) { reports.record(component: .recognition, code: .processingFailed) }
                    fail(error.localizedDescription, title: error is SpeechInputError ? "Audio zu kurz" : "Aufnahme nicht erkannt")
                }
            }
        }
    }
    /// The setup page already shows probe errors; the pill must not keep floating on every Space.
    private func resetErrorSoon() {
        let shown = status
        Task { try? await Task.sleep(for: .seconds(3)); guard self.sessionID == nil, self.state == .error, self.status == shown, self.recoveryWindow?.isVisible != true else { return }; self.state = .paused; self.updateHotkey() }
    }
    /// Sleep must not silently drop what was already said. Finish the recording,
    /// keep processing, and show the text instead of pasting after wake.
    private func prepareForSleep() {
        if sessionID != nil && !practiceSession && !lipSession && (state == .recording || state == .processing) {
            sleepInterrupted = true
            if state == .recording { stop() }
            return
        }
        cancel(); state = .paused; status = "Mac im Ruhezustand"
    }
    /// VoiceOver users otherwise get no feedback while focus stays in the target app.
    private func announceState() {
        let message: String? = switch state { case .recording: "Aufnahme läuft"; case .success: status; case .error: status; default: nil }
        guard let message, !message.isEmpty, !previewMode else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
    /// Silence is not a failure worth a window. The pill shows it briefly; the hotkey stays live.
    private func showNoSpeech() {
        cancel(); state = .error; status = "Keine Sprache erkannt"; updateHotkey()
        Task { try? await Task.sleep(for: .seconds(1.5)); guard self.sessionID == nil, self.state == .error, self.status == "Keine Sprache erkannt" else { return }; self.state = .paused; self.updateHotkey() }
    }
    func useOriginal() {
        guard state == .processing, sessionID != nil else { return }
        originalRequested = true; status = "Originaltext wird abgeschlossen …"
        if let pipeline { Task { await pipeline.requestOriginal() } }
    }
    func cancel() {
        let wasLipSession = lipSession
        camera.cancel(); lipHotkey.reset(); lipHotkey.cancellationEnabled = false; lipSession = false
        if practiceSession, let id = sessionID { practiceFeedback.cancel(id) }
        sessionID = nil; focus = nil; historyContext = nil; hotkey.cancellationEnabled = false; operation?.cancel(); appendTask?.cancel(); operation = nil; appendTask = nil
        acceptedSamples = 0; pendingSamples = [:]; practiceSession = false; originalRequested = false
        _ = capture.stop(); clock?.invalidate(); clock = nil; hotkey.reset()
        if let pipeline { Task { await pipeline.cancel() } }; pipeline = nil
        state = .paused; level = 0; captureReady = false; updateHotkey()
        if wasLipSession {
            lipReady = false
            Task { await lipRuntime.cancel(); if lipEnabled && !quitting { prepareLipReading() } }
        }
    }
    private func fail(_ message: String, title: String = "Aufnahme nicht erkannt") {
        if practiceSession, let id = sessionID {
            practiceFeedback.fail(id, message: message)
            practiceError = true
            cancel(); state = .error; status = "Probediktat prüfen"; resetErrorSoon()
            return
        }
        cancel(); state = .error; status = "Aufnahme prüfen"; errorMessage = message
        recoveryReason = message
        showRecovery(activate: false, transient: true, failureTitle: title)
    }
    #if DEBUG
    /// A public synthetic WAV exercises the same stop/finish/UI path without
    /// claiming microphone or permission acceptance. Never available in release.
    private func loadPracticeFixture() {
        settingsNavigation = SettingsNavigation(section: .setup, setupStep: .practice)
        showSettings()
        Task {
            do {
                guard let path = CommandLine.arguments.first(where: { $0.hasPrefix("--practice-fixture=") }).map({ String($0.dropFirst("--practice-fixture=".count)) }) else { throw VoiceError.message("Audiotest benötigt eine synthetische WAV-Datei.") }
                let file = try AVAudioFile(forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatFloat32, interleaved: false)
                guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1, file.length <= 16_000 * 1200,
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw VoiceError.message("Audiotest benötigt Mono mit 16 kHz, höchstens 20 Minuten.") }
                try file.read(into: buffer)
                guard let samples = buffer.floatChannelData?[0] else { throw VoiceError.message("Audiotest konnte nicht gelesen werden.") }
                practiceFixture = Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
                document.settings.defaultStyle = CommandLine.arguments.contains("--fixture-original") ? .original : .cleaned
                await prepareModels()
                microphoneGranted = true
            } catch {
                let id = UUID(); practiceFeedback.begin(id); practiceFeedback.fail(id, message: error.localizedDescription)
            }
        }
    }
    #endif
    func copyPracticeResult() {
        guard let text = practiceFeedback.result?.text else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    var pillActionLabel: String {
        #if DEBUG
        if previewMode, CommandLine.arguments.contains("--test-delivery") { return "Öffentlichen Einfügetest starten" }
        #endif
        if state == .error && quietDeliveryFeedback { return status + " Klicken, um den Text zu prüfen." }
        return state == .ready ? "Diktat starten. Halten: " + document.settings.shortcut.spokenLabel : state == .error ? "Diktat prüfen" : state == .paused ? "Tastenkürzel wieder einschalten" : "AInauten Voice öffnen: " + status
    }
    func openFromPill() {
        #if DEBUG
        if previewMode, CommandLine.arguments.contains("--test-delivery") { pasteLastResult(); return }
        #endif
        if state == .ready { hotkey.beginHandsFree(); start(); return }
        if state == .paused { document.settings.paused = false; updateHotkey(); return }
        if state == .error {
            if practiceError { settingsNavigation = SettingsNavigation(section: .setup, setupStep: .practice); showSettings() }
            else { showRecovery(failureTitle: recoveryFailureTitle) }
            return
        }
        if state == .conflict {
            settingsNavigation = SettingsNavigation(section: .migration, setupStep: nil)
            showSettings(); return
        }
        let setupStep = pendingSetupStep
        settingsNavigation = SettingsNavigation(section: setupStep != nil ? .setup : .dictation, setupStep: setupStep)
        showSettings()
    }
    func showSettings() {
        if settingsWindow == nil {
            let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1120, height: 892)
            let size = NSSize(width: min(1120, available.width), height: min(860, available.height - 32))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = previewMode ? "AInauten Voice · Oberflächenprüfung" : "AInauten Voice"; window.minSize = NSSize(width: 640, height: 560); window.isReleasedWhenClosed = false; window.delegate = self
            if previewMode {
                if let size = CommandLine.arguments.first(where: { $0.hasPrefix("--window-size=") })?.dropFirst(14).split(separator: "x"), size.count == 2, let width = Double(size[0]), let height = Double(size[1]) { window.setContentSize(NSSize(width: width, height: height)) }
                if CommandLine.arguments.contains("--appearance=light") { window.appearance = NSAppearance(named: .aqua) }
                if CommandLine.arguments.contains("--appearance=dark") { window.appearance = NSAppearance(named: .darkAqua) }
            }
            window.contentView = NSHostingView(rootView: SettingsView(model: self))
            if !previewMode {
                let frameName = "VoiceWispr.Settings"
                if !window.setFrameUsingName(frameName) { window.setContentSize(size); window.center() }
                window.setFrameAutosaveName(frameName)
            } else { window.center() }
            settingsWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
        settingsOpen = true; updatePillVisibility()
    }
    func closeSettings() { settingsWindow?.performClose(nil) }
    private func updatePillVisibility() {
        let active = state == .recording || state == .processing || state == .success || (state == .error && recoveryWindow?.isVisible != true)
        #if DEBUG
        if previewMode, CommandLine.arguments.contains("--test-delivery") { pill?.setVisible(!quitting); return }
        #endif
        // The shortcut is the entry point. No persistent idle microphone,
        // including when Settings remains open in the background.
        pill?.setVisible(!quitting && active)
    }
    func pasteLastResult() {
        guard sessionID == nil, !conflict, let result = results.first else { return }
        guard result.isComplete else { recoveryReason = "Dieser Teiltext wird nicht automatisch eingefügt."; showRecovery(); return }
        let target = FocusSnapshot.capture()
        #if DEBUG
        // Computer Use may address a background window without activating it.
        // Never let the public diagnostic insert into an unintended app.
        if previewMode, CommandLine.arguments.contains("--test-delivery"),
           !["com.apple.TextEdit", "ai.perplexity.comet"].contains(target?.bundleID ?? "") {
            print("DELIVERY_TEST_TARGET_MISMATCH \(target?.bundleID ?? "unavailable")"); fflush(stdout); return
        }
        if previewMode, CommandLine.arguments.contains("--test-delivery") {
            // A background AX click may leave a different window frontmost.
            // Require the explicitly named public test window, not merely an
            // allowed app (which might currently show a sign-in form).
            let prefix = "--test-delivery-target-title="
            let expected = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }).map { String($0.dropFirst(prefix.count)) }
            var title: CFTypeRef?
            if let target { _ = AXUIElementCopyAttributeValue(target.window, kAXTitleAttribute as CFString, &title) }
            guard let expected, !expected.isEmpty, let actual = title as? String, actual.contains(expected) else {
                print("DELIVERY_TEST_WINDOW_MISMATCH"); fflush(stdout); return
            }
        }
        #endif
        let id = UUID(); sessionID = id
        closeRecovery(); state = .processing; status = "Text wird eingefügt …"; updateHotkey()
        operation = Task {
            #if DEBUG
            let measurementStart = ProcessInfo.processInfo.systemUptime
            #endif
            let outcome = await DeliveryCoordinator().deliver(text: result.text, to: target)
            #if DEBUG
            if previewMode, CommandLine.arguments.contains("--test-delivery") {
                let trace: [String: Any] = ["status": outcome.status.rawValue, "seconds": ProcessInfo.processInfo.systemUptime - measurementStart,
                    "targetCaptured": target != nil, "targetApp": target?.bundleID ?? "", "reason": outcome.reason]
                if let data = try? JSONSerialization.data(withJSONObject: trace, options: [.sortedKeys]) {
                    FileHandle.standardOutput.write(Data("DELIVERY_TEST ".utf8) + data + Data("\n".utf8))
                }
            }
            #endif
            guard sessionID == id, !Task.isCancelled else { return }
            sessionID = nil; operation = nil; hotkey.cancellationEnabled = false
            presentDelivery(outcome, result: result)
        }
    }
    /// Both normal dictation and explicit paste-last use the same feedback rule.
    func presentDelivery(_ outcome: DeliveryOutcome, result: DictationResult) {
        let feedbackID = UUID(); deliveryFeedbackID = feedbackID
        quietDeliveryFeedback = !outcome.shouldShowRecovery && outcome.status != .confirmed
        recoveryReason = outcome.reason + (result.usedFallback ? " Die Optimierung war nicht verfügbar; verfügbar ist der Originaltext." : "")
        recoveryFailureTitle = nil
        if outcome.shouldShowRecovery {
            state = .error; status = "Text verfügbar"; showRecovery(autoCopy: result.isComplete)
            return
        }
        // Never label an unverified submission as a confirmed insertion, retry
        // it, or replace the user's clipboard with an automatic recovery copy.
        closeRecovery()
        let finalState: PillState = outcome.status == .confirmed ? .success : .error
        state = finalState
        status = outcome.status == .confirmed ? (result.usedFallback ? "Original eingefügt" : "Eingefügt") : "Einfügen nicht bestätigt. Text über Letzte Ergebnisse verfügbar."
        let feedbackStatus = status
        updateHotkey()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard self.sessionID == nil, self.state == finalState, self.status == feedbackStatus,
                  self.deliveryFeedbackID == feedbackID, self.results.first?.id == result.id,
                  self.recoveryWindow?.isVisible != true else { return }
            self.state = .paused; self.updateHotkey()
        }
    }
    var recoveryResult: DictationResult? {
        guard recoveryFailureTitle == nil else { return nil }
        return results.first(where: { $0.id == recoverySelection }) ?? results.first
    }
    var recoveryTitle: String {
        if let title = recoveryFailureTitle { return title }
        if recoveryResult?.isComplete == false { return "Unvollständiger Text" }
        switch recoveryClipboardStatus {
        case "In der Zwischenablage": return "Kopiert"
        case "Vorherige Zwischenablage wiederhergestellt": return "Rückgängig"
        case "Zwischenablage unverändert", "Kopieren nicht möglich": return "Nicht kopiert"
        case "Zwischenablage geändert", "Neue Zwischenablage bleibt erhalten": return "Zwischenablage geändert"
        case "Wiederherstellen nicht möglich": return "Rückgängig nicht möglich"
        default: return results.isEmpty ? "Diktat nicht verfügbar" : "Erkannter Text"
        }
    }
    var recoveryDetails: String { [recoveryReason, recoveryFooter, "Letzte Ergebnisse bleiben bis zum Beenden im Menü erreichbar."].filter { !$0.isEmpty }.joined(separator: "\n\n") }
    var recoveryHasCopy: Bool { recoveryCopiedID == recoveryResult?.id && recoveryCanUndo }
    var recoveryFooter: String {
        if recoveryFailureTitle != nil { return recoveryReason }
        if recoveryResult?.isComplete == false && recoveryHasCopy { return "Unvollständiger Teiltext. Vor dem Einfügen prüfen." }
        if recoveryHasCopy { return "Mit ⌘V einfügen. Prüfe vorher das Zielfeld." }
        switch recoveryClipboardStatus {
        case "Zwischenablage unverändert": return "Vorheriger Inhalt konnte nicht vollständig gesichert werden. Der Text bleibt im Menü Letzte Ergebnisse verfügbar."
        case "Kopieren nicht möglich": return "Über das Zwischenablage-Symbol erneut versuchen. Der Text bleibt im Menü Letzte Ergebnisse verfügbar."
        case "Zwischenablage geändert", "Neue Zwischenablage bleibt erhalten": return "Deine neue Kopieraktion bleibt erhalten."
        case "Vorherige Zwischenablage wiederhergestellt": return "Mit ⌘V fügst du wieder den vorherigen Inhalt ein."
        case "Wiederherstellen nicht möglich": return "Die vorherige Zwischenablage konnte nicht wiederhergestellt werden."
        default: return recoveryReason
        }
    }
    func showRecovery(autoCopy: Bool = false, activate: Bool = true, resultID: UUID? = nil, transient: Bool = false, failureTitle: String? = nil) {
        recoveryFailureTitle = failureTitle
        recoverySelection = failureTitle == nil ? resultID ?? results.first?.id : nil
        if failureTitle != nil { recoveryClipboardStatus = ""; recoveryCanUndo = false }
        recoveryTransient = autoCopy || transient
        if autoCopy, let result = recoveryResult, result.isComplete { copyRecoveryText(result) }
        else if recoveryCopiedID != recoveryResult?.id { recoveryClipboardStatus = ""; recoveryCanUndo = false }
        if recoveryCanUndo && !recoveryClipboard.canUndo { recoveryCanUndo = false; recoveryClipboardStatus = "Zwischenablage geändert" }
        if recoveryWindow == nil {
            let panel = RecoveryPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 160), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "AInauten Voice Ergebnis"
            if previewMode {
                if CommandLine.arguments.contains("--appearance=light") { panel.appearance = NSAppearance(named: .aqua) }
                if CommandLine.arguments.contains("--appearance=dark") { panel.appearance = NSAppearance(named: .darkAqua) }
            }
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false; panel.level = .floating; panel.delegate = self; panel.contentView = NSHostingView(rootView: RecoveryView(model: self)); recoveryWindow = panel
        }
        sizeRecovery()
        if autoCopy || !activate { recoveryWindow?.orderFrontRegardless() }
        else { recoveryWindow?.makeKeyAndOrderFront(nil) }
        startRecoveryTimer()
        updatePillVisibility()
        updateHotkey()
    }
    func selectRecoveryResult() {
        recoveryTransient = false
        recoveryClipboardStatus = recoveryCopiedID == recoveryResult?.id && recoveryClipboard.canUndo ? "In der Zwischenablage" : ""
        recoveryCanUndo = recoveryCopiedID == recoveryResult?.id && recoveryClipboard.canUndo
        sizeRecovery()
        startRecoveryTimer()
    }
    private func sizeRecovery() {
        guard let panel = recoveryWindow else { return }
        let screen = pill?.panel.screen ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var width = min(420, bounds.width - 24)
        #if DEBUG
        if previewMode, let value = CommandLine.arguments.first(where: { $0.hasPrefix("--recovery-width=") }).flatMap({ Double($0.dropFirst("--recovery-width=".count)) }) { width = min(width, max(320, value)) }
        #endif
        let text = recoveryResult?.text ?? ""
        let textRect = (text as NSString).boundingRect(with: NSSize(width: width - 40, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 13)])
        recoveryTextHeight = text.isEmpty ? 0 : min(144, max(22, ceil(textRect.height) + 8))
        let height: CGFloat
        if recoveryFailureTitle != nil {
            let description = (recoveryReason as NSString).boundingRect(with: NSSize(width: width - 36, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 12)])
            recoveryTextHeight = min(160, max(30, ceil(description.height) + 4))
            height = 64 + recoveryTextHeight
        } else {
            height = 64 + recoveryTextHeight
        }
        let anchor = pill?.panel.frame ?? NSRect(x: bounds.midX, y: bounds.minY, width: 0, height: 32)
        panel.setFrame(NSRect(x: min(max(bounds.minX + 12, anchor.midX - width / 2), bounds.maxX - width - 12),
            y: min(max(bounds.minY + 12, anchor.maxY + 8), bounds.maxY - height - 12), width: width, height: height), display: true)
    }
    private func startRecoveryTimer() {
        recoveryTimer?.invalidate()
        recoveryCountdown = FeedbackCountdown(now: ProcessInfo.processInfo.systemUptime)
        recoveryCountdown?.setPaused(recoveryCountdownShouldPause, at: ProcessInfo.processInfo.systemUptime)
        recoveryCountdownRemaining = 5; recoveryCountdownPaused = recoveryCountdownShouldPause
        recoveryTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.recoveryWindow?.isVisible == true else { return }
                if self.recoveryCanUndo && !self.recoveryClipboard.canUndo {
                    self.recoveryCanUndo = false; self.recoveryClipboard.discardUndo()
                    self.recoveryClipboardStatus = "Zwischenablage geändert"
                }
                #if DEBUG
                if self.previewMode && CommandLine.arguments.contains("--preview-pin") { return }
                #endif
                let now = ProcessInfo.processInfo.systemUptime
                self.recoveryCountdown?.setPaused(self.recoveryCountdownShouldPause, at: now)
                self.recoveryCountdownRemaining = self.recoveryCountdown?.remaining(at: now) ?? 0
                self.recoveryCountdownPaused = self.recoveryCountdown?.isPaused == true
                // Becoming key after a click must not pin feedback indefinitely.
                if self.recoveryCountdown?.expired(at: now) == true {
                    #if DEBUG
                    self.traceRecoveryPreview("expired")
                    #endif
                    self.closeRecovery()
                }
            }
        }
        if let recoveryTimer { RunLoop.main.add(recoveryTimer, forMode: .common) }
    }
    func hoverRecovery(_ hovered: Bool) {
        recoveryHovered = hovered
        let now = ProcessInfo.processInfo.systemUptime
        recoveryCountdown?.setPaused(recoveryCountdownShouldPause, at: now)
        recoveryCountdownRemaining = recoveryCountdown?.remaining(at: now) ?? 0
        recoveryCountdownPaused = recoveryCountdown?.isPaused == true
    }
    private var recoveryCountdownShouldPause: Bool {
        #if DEBUG
        if previewMode && CommandLine.arguments.contains("--preview-pin") { return true }
        #endif
        return recoveryHovered
    }
    private func copyRecoveryText(_ result: DictationResult) {
        switch recoveryClipboard.copy(result.text) {
        case .copied: recoveryClipboardStatus = "In der Zwischenablage"; recoveryCopiedID = result.id; recoveryCanUndo = true
        case .unavailable: recoveryClipboardStatus = "Zwischenablage unverändert"; recoveryCanUndo = false; recoveryTransient = false
        case .failed: recoveryClipboardStatus = "Kopieren nicht möglich"; recoveryCanUndo = false; recoveryTransient = false
        }
    }
    func undoRecoveryCopy() {
        switch recoveryClipboard.undo() {
        case .restored: recoveryClipboardStatus = "Vorherige Zwischenablage wiederhergestellt"
        case .changed: recoveryClipboardStatus = "Neue Zwischenablage bleibt erhalten"
        case .failed: recoveryClipboardStatus = "Wiederherstellen nicht möglich"
        }
        recoveryCanUndo = false
        #if DEBUG
        traceRecoveryPreview("undo")
        #endif
    }
    #if DEBUG
    private func traceRecoveryPreview(_ event: String) {
        guard let board = recoveryPreviewBoard else { return }
        let value: [String: Any] = ["event": event, "seconds": ProcessInfo.processInfo.systemUptime - recoveryPreviewStarted,
            "windowVisible": recoveryWindow?.isVisible == true, "windowKey": recoveryWindow?.isKeyWindow == true,
            "width": recoveryWindow?.frame.width ?? 0, "height": recoveryWindow?.frame.height ?? 0,
            "appActive": NSApp.isActive, "copied": board.string(forType: .string) == recoveryResult?.text,
            "originalRestored": board.string(forType: .string) == "Vorheriger Testinhalt" && board.string(forType: .html) == "<b>Vorheriger Testinhalt</b>",
            "canUndo": recoveryCanUndo, "hasResult": recoveryResult != nil, "failure": recoveryFailureTitle != nil,
            "countdownRemaining": recoveryCountdownRemaining, "countdownPaused": recoveryCountdownPaused,
            "state": state.rawValue, "shortcutEnabled": hotkey.enabled, "pillVisible": pill?.panel.isVisible == true,
            "generalUnchanged": NSPasteboard.general.changeCount == recoveryPreviewGeneralCount]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(Data("RECOVERY_PREVIEW ".utf8) + data + Data("\n".utf8))
        }
    }
    #endif
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            settingsOpen = false; updatePillVisibility(); return
        }
        guard let window = notification.object as? NSWindow, window === recoveryWindow else { return }
        recoveryTimer?.invalidate(); recoveryTimer = nil; recoveryCountdown = nil; recoveryTransient = false
        recoveryHovered = false
        recoveryCountdownRemaining = 0; recoveryCountdownPaused = false
        guard sessionID == nil, state == .error else { return }
        state = .paused; errorMessage = nil; updateHotkey()
    }
    func closeRecovery() {
        recoveryWindow?.close()
        #if DEBUG
        traceRecoveryPreview("closed")
        #endif
    }
    func dismissError() {
        errorMessage = nil
        guard sessionID == nil, state == .error else { return }
        recoveryWindow?.close(); state = .paused; updateHotkey()
    }
    func copyResult(at index: Int) {
        guard results.indices.contains(index) else { return }
        recoverySelection = results[index].id; recoveryTransient = true
        copyRecoveryText(results[index])
        // Copy-last is an explicit action. It may copy a labelled partial result;
        // only complete new results enter the automatic-copy path above.
        showRecovery(activate: false, resultID: results[index].id, transient: recoveryCanUndo)
    }
    func saveKey(_ key: String) { do { try KeychainStorage().setKey(key) } catch { errorMessage = "API-Schlüssel konnte nicht im Schlüsselbund gespeichert werden." } }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { errorMessage = "Autostart konnte nicht geändert werden: \(error.localizedDescription)" }
        loginEnabled = SMAppService.mainApp.status == .enabled
        if enabled && SMAppService.mainApp.status == .requiresApproval { errorMessage = "Der Autostart wartet auf deine Freigabe unter macOS → Anmeldeobjekte."; SMAppService.openSystemSettingsLoginItems() }
    }
    func exportSettings() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "AInauten-Voice-Einstellungen.json"
        if panel.runModal() == .OK, let url = panel.url { Task { do { try await store.export(to: url) } catch { errorMessage = error.localizedDescription } } }
    }
    func importDictionaryCSV() {
        let panel = NSOpenPanel(); panel.title = "Wörterbuch als CSV auswählen"; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: 10 * 1024 * 1024 + 1) ?? Data()
            let preview = try DictionaryCSV.preview(data: data)
            let merged = preview.merged(with: document.dictionary)
            let alert = NSAlert(); alert.messageText = "CSV-Import prüfen"
            alert.informativeText = "\(merged.added) neue Einträge, \(preview.entries.count - merged.added) vorhandene Ausdrücke unverändert, \(preview.skipped) ausgelassen. Deine bestehenden Einträge haben Vorrang. Die CSV-Datei wird nicht verändert."
            alert.addButton(withTitle: "Importieren"); alert.addButton(withTitle: "Abbrechen")
            if alert.runModal() == .alertFirstButtonReturn { document.dictionary = merged.entries; importFailed = false; importReceipt = "\(merged.added) CSV-Einträge importiert, vorhandene Änderungen erhalten." }
        } catch { errorMessage = error.localizedDescription }
    }
    func importSettings() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.json]
        panel.title = "Einstellungen und Wörterbuch importieren"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let imported = try await store.importDocument(from: url)
                // A settings import replaces everything. Confirm with counts and keep the previous state.
                let alert = NSAlert(); alert.messageText = "Einstellungen und Wörterbuch ersetzen?"
                alert.informativeText = "Die Datei enthält \(imported.dictionary.count) Wörterbucheinträge. Sie ersetzt deine aktuellen Einstellungen und alle \(document.dictionary.count) Einträge. Dein bisheriger Stand wird vorher als Sicherung im Datenordner gespeichert."
                alert.addButton(withTitle: "Ersetzen"); alert.addButton(withTitle: "Abbrechen")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let backup = ModelPaths.support.appendingPathComponent("settings-before-import-\(stamp).json")
                try await store.export(to: backup)
                document = imported; importFailed = false
                importReceipt = "Einstellungen importiert. Der vorherige Stand liegt als \(backup.lastPathComponent) im Datenordner. Cloud bleibt aus; aktiviere sie bei Bedarf unter Text & Stil."
            } catch { errorMessage = error.localizedDescription }
        }
    }
    private func scheduleSave() {
        guard !loading && !previewMode else { return }; saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(for: .milliseconds(200)); guard !Task.isCancelled else { return }; do { try await store.save(document) } catch { errorMessage = "Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)" } }
    }
}
