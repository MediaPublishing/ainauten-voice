import AppKit
import Sparkle
import VoiceWisprCore

@main struct UpdateNativeChecks {
    @MainActor static func main() throws {
        func require(_ condition: Bool, _ message: String) {
            if !condition { print("FAIL " + message); exit(1) }
        }
        let model = AppModel()
        let controller = model.updates
        controller.start()
        require(!controller.available && !controller.automaticUpdates, "Missing publishing identity must leave updater inactive")
        controller.setAutomaticUpdates(true)
        require(!controller.automaticUpdates, "Inactive updater must reject opt-in")
        let peer = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
        var active = true
        controller.busy = { active }
        do { try controller.updater(peer, mayPerform: .updates); require(false, "Busy update check was allowed") } catch {}
        let item = SUAppcastItem(dictionary: ["title": "Public update fixture", "sparkle:version": "999", "enclosure": ["url": "https://voice.ainauten.com/updates/fixture.zip", "length": "1", "type": "application/octet-stream"]])!
        var calls = 0
        require(controller.updater(peer, shouldPostponeRelaunchForUpdate: item, untilInvokingBlock: { calls += 1 }), "Busy restart must be postponed")
        controller.resumeRelaunchIfIdle(); require(calls == 0, "Restart ran during dictation")
        controller.updater(peer, willInstallUpdate: item)
        require(model.applicationShouldTerminate(NSApplication.shared) == .terminateCancel, "Installation path bypassed recording protection")
        active = false; try controller.updater(peer, mayPerform: .updates)
        controller.resumeRelaunchIfIdle(); controller.resumeRelaunchIfIdle()
        require(calls == 1, "Idle callback must run exactly once")
        controller.updater(peer, didAbortWithError: NSError(domain: "fixture", code: 1))
        require(!controller.installingUpdate, "Failed update left termination blocked")
        active = true
        require(controller.updater(peer, shouldPostponeRelaunchForUpdate: item, untilInvokingBlock: { calls += 1 }), "Second busy restart was not postponed")
        controller.updater(peer, didAbortWithError: NSError(domain: "fixture", code: 2))
        active = false; controller.resumeRelaunchIfIdle()
        require(calls == 1, "Aborted update resumed its stale restart")
        print("PASS native updater missing-key gate, rejected opt-in, busy search, postponed relaunch, terminate fence, idle single resumption, abort cleanup")
    }
}
