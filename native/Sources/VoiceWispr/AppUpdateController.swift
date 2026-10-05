import AppKit
import Combine
import Sparkle
import VoiceWisprCore

/// Sparkle owns installation, verification and its persisted user preferences.
/// No launch-time override of a user's settings and no duplicate JSON preference.
@MainActor final class AppUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var automaticUpdates = false
    @Published private(set) var available = false
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?
    private(set) var installingUpdate = false
    @Published private var messageValue: LocalizedMessage = .key("updates.initializing", [])
    var message: String { get { messageValue.text } set { messageValue = L10n.message(newValue) } }
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    private var postponedRelaunch: (() -> Void)?
    private var relaunchTimer: Timer?
    var busy: () -> Bool = { false }

    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "0.1.1") (\(info["CFBundleVersion"] as? String ?? "3"))"
    }
    func start() {
        guard controller == nil, UpdatePolicy.configured(Bundle.main.infoDictionary ?? [:]) else { return }
        let instance = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller = instance
        do { try instance.updater.start() } catch {
            message = L10n.text("updates.unavailable"); controller = nil; return
        }
        available = true
        for key in [\SPUUpdater.automaticallyChecksForUpdates, \SPUUpdater.automaticallyDownloadsUpdates] {
            observations.append(instance.updater.observe(key, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        observations.append(instance.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in Task { @MainActor in self?.refresh() } })
        observations.append(instance.updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] _, _ in Task { @MainActor in self?.refresh() } })
        refresh()
    }
    private func refresh() {
        guard let updater = controller?.updater else { return }
        automaticUpdates = updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
        canCheck = updater.canCheckForUpdates
        lastCheck = updater.lastUpdateCheckDate
        message = automaticUpdates ? L10n.text("updates.automatic.on") : L10n.text("updates.automatic.off")
    }
    func setAutomaticUpdates(_ enabled: Bool) {
        guard available, let updater = controller?.updater else { return }
        updater.automaticallyDownloadsUpdates = enabled
        updater.automaticallyChecksForUpdates = enabled
        refresh()
    }
    func check() {
        guard available, canCheck else { return }
        guard !busy() else { message = L10n.text("updates.busy"); return }
        controller?.checkForUpdates(nil)
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !busy() else {
            throw NSError(domain: "AInautenVoice.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("updates.busy")])
        }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { installingUpdate = true }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        installingUpdate = false
        postponedRelaunch = nil; relaunchTimer?.invalidate(); relaunchTimer = nil
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard busy() else { return false }
        postponedRelaunch = installHandler
        message = L10n.text("updates.readyAfterDictation")
        relaunchTimer?.invalidate()
        relaunchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.resumeRelaunchIfIdle() }
        }
        return true
    }
    func resumeRelaunchIfIdle() {
        guard !busy(), let handler = postponedRelaunch else { return }
        postponedRelaunch = nil; relaunchTimer?.invalidate(); relaunchTimer = nil
        handler()
    }
}
