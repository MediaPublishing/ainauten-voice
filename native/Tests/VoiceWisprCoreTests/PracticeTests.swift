import XCTest
@testable import VoiceWisprCore

final class PracticeTests: XCTestCase {
    private func result(_ text: String = "Hallo Fabian.", complete: Bool = true, fallback: Bool = false) -> DictationResult {
        .init(id: UUID(), text: text, original: text, usedFallback: fallback, duration: 5, isComplete: complete)
    }
    func testRecognizedTextRemainsAvailableAfterProbeCompletion() {
        var feedback = PracticeFeedback(); let id = UUID(); let text = result()
        feedback.begin(id); feedback.processing(id)
        XCTAssertTrue(feedback.finish(id, result: text))
        XCTAssertEqual(feedback.phase, .recognized)
        XCTAssertEqual(feedback.result?.id, text.id)
        XCTAssertFalse(feedback.isActive)
        feedback.cancel(id)
        XCTAssertEqual(feedback.result?.text, "Hallo Fabian.")
    }
    func testNewFailedProbeNeverDisplaysAnOlderSuccess() {
        var feedback = PracticeFeedback(); let first = UUID(), next = UUID()
        feedback.begin(first); feedback.finish(first, result: result())
        feedback.begin(next)
        XCTAssertNil(feedback.result)
        XCTAssertFalse(feedback.succeeded)
        feedback.fail(next, message: "Keine Sprache erkannt.")
        XCTAssertEqual(feedback.phase, .failed)
        XCTAssertNil(feedback.result)
        XCTAssertFalse(feedback.succeeded)
    }
    func testCancelledProbeRejectsLateRecognition() {
        var feedback = PracticeFeedback(); let id = UUID()
        feedback.begin(id); feedback.processing(id); feedback.cancel(id)
        XCTAssertFalse(feedback.finish(id, result: result()))
        XCTAssertEqual(feedback.phase, .cancelled)
        XCTAssertNil(feedback.result)
    }
    func testPreviousRunCannotOverwriteCurrentProbe() {
        var feedback = PracticeFeedback(); let first = UUID(), next = UUID()
        feedback.begin(first); feedback.begin(next)
        feedback.processing(first); feedback.fail(first, message: "Alter Fehler")
        XCTAssertEqual(feedback.phase, .recording)
        XCTAssertFalse(feedback.finish(first, result: result("Alter Text")))
        XCTAssertTrue(feedback.finish(next, result: result("Aktueller Text")))
        XCTAssertEqual(feedback.result?.text, "Aktueller Text")
    }
    func testEmptyAndPartialResultsCannotPassTheProbe() {
        var feedback = PracticeFeedback(); let empty = UUID(), partial = UUID()
        feedback.begin(empty)
        XCTAssertFalse(feedback.finish(empty, result: result(" \n")))
        XCTAssertEqual(feedback.phase, .failed)
        XCTAssertNil(feedback.result)
        feedback.begin(partial)
        XCTAssertFalse(feedback.finish(partial, result: result("Hallo", complete: false)))
        XCTAssertEqual(feedback.phase, .partial)
        XCTAssertEqual(feedback.result?.text, "Hallo")
        XCTAssertFalse(feedback.succeeded)
    }
    func testFallbackAndInterruptedProbeKeepTheirOwnText() {
        var feedback = PracticeFeedback(); let fallback = UUID(), interrupted = UUID()
        feedback.begin(fallback)
        XCTAssertTrue(feedback.finish(fallback, result: result(fallback: true)))
        XCTAssertEqual(feedback.result?.usedFallback, true)
        feedback.begin(interrupted)
        feedback.fail(interrupted, message: "Unterbrochen", partial: result("Teiltext", complete: false))
        XCTAssertEqual(feedback.phase, .partial)
        XCTAssertEqual(feedback.result?.text, "Teiltext")
    }
    func testProbeStopsAfterSpeechPauseButNotInitialSilence() {
        var probe = PracticeSession()
        XCTAssertFalse(probe.shouldStop(level: 0, elapsed: 5))
        XCTAssertFalse(probe.shouldStop(level: 0.2, elapsed: 6))
        XCTAssertFalse(probe.shouldStop(level: 0, elapsed: 7.9))
        XCTAssertTrue(probe.shouldStop(level: 0, elapsed: 8))
    }
    func testProbeAlwaysStopsAtFifteenSeconds() {
        var probe = PracticeSession()
        XCTAssertFalse(probe.shouldStop(level: 0.3, elapsed: 14.9))
        XCTAssertTrue(probe.shouldStop(level: 0.3, elapsed: 15))
        var silent = PracticeSession()
        XCTAssertTrue(silent.shouldStop(level: 0, elapsed: 15))
    }
    func testWizardCompletionRequiresEveryDictationPrerequisite() {
        // Completion happens automatically once all are met, so a later grant cannot loop the wizard.
        XCTAssertTrue(PracticeSession.canFinish(modelsReady: true, microphoneGranted: true, accessibilityGranted: true, practiceComplete: true))
        XCTAssertFalse(PracticeSession.canFinish(modelsReady: false, microphoneGranted: true, accessibilityGranted: true, practiceComplete: true))
        XCTAssertFalse(PracticeSession.canFinish(modelsReady: true, microphoneGranted: false, accessibilityGranted: true, practiceComplete: true))
        XCTAssertFalse(PracticeSession.canFinish(modelsReady: true, microphoneGranted: true, accessibilityGranted: false, practiceComplete: true))
        XCTAssertFalse(PracticeSession.canFinish(modelsReady: true, microphoneGranted: true, accessibilityGranted: true, practiceComplete: false))
    }
    func testPracticeFlagPersistsAndOldVersionOneStillLoads() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("probe-settings-\(UUID().uuidString)/settings.json")
        let store = SettingsStore(url: url)
        var document = ExportDocument()
        document.settings.practiceCompleted = true
        document.settings.onboardingComplete = true
        try await store.save(document)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.settings.practiceCompleted, true)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var settings = try XCTUnwrap(legacy["settings"] as? [String: Any])
        settings.removeValue(forKey: "practiceCompleted"); legacy["settings"] = settings
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let old = try await store.load()
        XCTAssertNil(old.settings.practiceCompleted)
        XCTAssertTrue(old.settings.onboardingComplete)
    }
}
