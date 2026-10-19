import XCTest
import Foundation
@testable import VoiceWisprCore

final class DictationQueueTests: XCTestCase {
    func testQueueAdvancesEquivalentEditorRepresentationAtExactEquivalentCaret() {
        for (text, observed, location) in [("Hallo Welt", "Hallo\u{00A0}Welt\n", 10),
            ("Erster\nZweiter", "Erster\r\nZweiter", 15),
            ("Änderung", "A\u{0308}nderung", 9)] {
            XCTAssertTrue(DeliveryVerification.canAdvanceQueuedInsertion(baseline: "", selection: NSRange(location: 0, length: 0),
                text: text, observed: observed, caret: NSRange(location: location, length: 0)))
        }
    }
    func testEquivalentEditorRepresentationStillRejectsWrongCaretAndUserText() {
        let selection = NSRange(location: 0, length: 0)
        for caret in [NSRange(location: 0, length: 0), NSRange(location: 9, length: 0),
            NSRange(location: 11, length: 0), NSRange(location: 10, length: 1)] {
            XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: "", selection: selection,
                text: "Hallo Welt", observed: "Hallo\u{00A0}Welt\n", caret: caret))
        }
        XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: "", selection: selection,
            text: "Hallo Welt", observed: "Hallo Erde\n", caret: NSRange(location: 10, length: 0)))
        XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: "Anfang Ende", selection: NSRange(location: 7, length: 0),
            text: "Mitte ", observed: "Mitte ", caret: NSRange(location: 6, length: 0)))
        XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: "", selection: selection,
            text: "Text\n", observed: "Text\r\n", caret: NSRange(location: 5, length: 0)))
    }
    func testFollowupRecordingDoesNotConsumeModifierReleaseDeadline() {
        var readiness = DictationDeliveryReadiness()
        XCTAssertEqual(readiness.update(recording: true, modifiersHeld: true, now: 0), .wait)
        XCTAssertEqual(readiness.update(recording: true, modifiersHeld: true, now: 20), .wait)
        XCTAssertEqual(readiness.update(recording: false, modifiersHeld: true, now: 20), .wait)
        XCTAssertEqual(readiness.update(recording: false, modifiersHeld: true, now: 21), .wait)
        XCTAssertEqual(readiness.update(recording: false, modifiersHeld: false, now: 21.1), .ready)
    }
    func testHandsFreeFollowupAlsoDefersDelivery() {
        var readiness = DictationDeliveryReadiness()
        XCTAssertEqual(readiness.update(recording: true, modifiersHeld: false, now: 0), .wait)
        XCTAssertEqual(readiness.update(recording: true, modifiersHeld: false, now: 1200), .wait)
        XCTAssertEqual(readiness.update(recording: false, modifiersHeld: false, now: 1200.1), .ready)
    }
    func testUnrelatedHeldModifiersStillHaveBoundedDeadline() {
        var readiness = DictationDeliveryReadiness()
        XCTAssertEqual(readiness.update(recording: false, modifiersHeld: true, now: 10), .wait)
        XCTAssertEqual(readiness.update(recording: false, modifiersHeld: true, now: 11.49), .wait)
        XCTAssertEqual(readiness.update(recording: false, modifiersHeld: true, now: 11.5), .timedOut)
    }
    func testNewCaptureRestartsReleaseDeadlineAndPreservesFIFOAdmission() {
        var readiness = DictationDeliveryReadiness()
        var queue = DictationQueue(maximumBytes: 30, reservationBytes: 10)
        let first = UUID(), second = UUID()
        XCTAssertTrue(queue.reserve(first)); XCTAssertTrue(queue.captured(first))
        XCTAssertEqual(queue.beginNext(), first)
        XCTAssertEqual(readiness.update(recording: false, modifiersHeld: true, now: 0), .wait)
        XCTAssertTrue(queue.reserve(second))
        XCTAssertEqual(readiness.update(recording: true, modifiersHeld: true, now: 1), .wait)
        XCTAssertEqual(readiness.update(recording: true, modifiersHeld: true, now: 10), .wait)
        XCTAssertTrue(queue.captured(second))
        XCTAssertEqual(readiness.update(recording: false, modifiersHeld: true, now: 10), .wait)
        XCTAssertEqual(readiness.update(recording: false, modifiersHeld: false, now: 10.1), .ready)
        XCTAssertTrue(queue.mayAutomaticallyDeliver(first)); XCTAssertNil(queue.beginNext())
        queue.finish(first); XCTAssertEqual(queue.beginNext(), second)
    }
    func testAdmissionReservesBytesBeforeCaptureAndCannotOverflow() {
        var queue = DictationQueue(maximumBytes: 20, reservationBytes: 10)
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertTrue(queue.reserve(a)); XCTAssertFalse(queue.reserve(b))
        XCTAssertTrue(queue.captured(a)); XCTAssertTrue(queue.reserve(b))
        XCTAssertEqual(queue.reservedBytes, 20); XCTAssertFalse(queue.canCapture)
        XCTAssertFalse(queue.reserve(c)); XCTAssertEqual(queue.entries.count, 2)
        queue.finish(a); XCTAssertFalse(queue.canCapture) // B still capturing.
        XCTAssertTrue(queue.captured(b)); XCTAssertTrue(queue.reserve(c))
        XCTAssertEqual(queue.reservedBytes, 20)
    }
    func testProcessingIsFIFOAndNeverConcurrentWithAnotherWorker() {
        var queue = DictationQueue(maximumBytes: 30, reservationBytes: 10)
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertTrue(queue.reserve(a)); XCTAssertTrue(queue.captured(a))
        XCTAssertEqual(queue.beginNext(), a)
        XCTAssertTrue(queue.reserve(b)); XCTAssertTrue(queue.captured(b))
        XCTAssertTrue(queue.reserve(c)); XCTAssertTrue(queue.captured(c))
        XCTAssertNil(queue.beginNext())
        queue.finish(a); XCTAssertEqual(queue.beginNext(), b)
        queue.finish(b); XCTAssertEqual(queue.beginNext(), c)
        queue.finish(c); XCTAssertEqual(queue.reservedBytes, 0)
    }
    func testOverlappingCapturesRemainEligibleOnlyInProcessingOrder() {
        var queue = DictationQueue(maximumBytes: 30, reservationBytes: 10)
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertTrue(queue.reserve(a)); XCTAssertTrue(queue.captured(a))
        XCTAssertEqual(queue.beginNext(), a)
        XCTAssertTrue(queue.reserve(b)); XCTAssertTrue(queue.captured(b))
        XCTAssertTrue(queue.reserve(c)); XCTAssertTrue(queue.captured(c))
        XCTAssertTrue(queue.overlaps); XCTAssertTrue(queue.mayAutomaticallyDeliver(a))
        XCTAssertFalse(queue.mayAutomaticallyDeliver(b)); XCTAssertFalse(queue.mayAutomaticallyDeliver(c))
        queue.finish(a); XCTAssertEqual(queue.beginNext(), b); XCTAssertTrue(queue.mayAutomaticallyDeliver(b))
        queue.finish(b); XCTAssertEqual(queue.beginNext(), c); XCTAssertTrue(queue.mayAutomaticallyDeliver(c))
        queue.finish(c); XCTAssertEqual(queue.reservedBytes, 0)
    }
    func testUncertainPredecessorSuppressesRemainingAutomaticInsertionsUntilBatchReset() {
        var queue = DictationQueue(maximumBytes: 20, reservationBytes: 10)
        let a = UUID(), b = UUID()
        XCTAssertTrue(queue.reserve(a)); XCTAssertTrue(queue.captured(a)); XCTAssertEqual(queue.beginNext(), a)
        XCTAssertTrue(queue.reserve(b)); XCTAssertTrue(queue.captured(b))
        queue.suppressAutomaticDelivery(); XCTAssertFalse(queue.mayAutomaticallyDeliver(a))
        queue.finish(a); XCTAssertEqual(queue.beginNext(), b); XCTAssertFalse(queue.mayAutomaticallyDeliver(b))
        queue.finish(b); queue.resetBatchIfIdle()
        let c = UUID(); XCTAssertTrue(queue.reserve(c)); XCTAssertTrue(queue.captured(c))
        XCTAssertEqual(queue.beginNext(), c); XCTAssertTrue(queue.mayAutomaticallyDeliver(c))
    }
    func testAnActiveSuppressedSeriesCannotBeResetByAnotherCapture() {
        var queue = DictationQueue(maximumBytes: 20, reservationBytes: 10)
        let first = UUID(), second = UUID()
        XCTAssertTrue(queue.reserve(first)); XCTAssertTrue(queue.captured(first)); XCTAssertEqual(queue.beginNext(), first)
        queue.suppressAutomaticDelivery(); queue.resetBatchIfIdle()
        XCTAssertTrue(queue.reserve(second)); XCTAssertTrue(queue.captured(second))
        XCTAssertFalse(queue.mayAutomaticallyDeliver(first))
        queue.finish(first); XCTAssertEqual(queue.beginNext(), second)
        XCTAssertFalse(queue.mayAutomaticallyDeliver(second))
    }
    func testQueueRebasingRequiresExactCompleteTextAndCaretAfterOurOwnInsertion() {
        let baseline = "Anfang ERSETZEN Ende", selection = (baseline as NSString).range(of: "ERSETZEN")
        let observed = "Anfang erster Text 👋 Ende"
        let caret = NSRange(location: selection.location + ("erster Text 👋" as NSString).length, length: 0)
        XCTAssertTrue(DeliveryVerification.canAdvanceQueuedInsertion(baseline: baseline, selection: selection, text: "erster Text 👋", observed: observed, caret: caret))
        XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: baseline, selection: selection, text: "erster Text 👋", observed: observed, caret: NSRange(location: 0, length: 0)))
        XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: baseline, selection: selection, text: "erster Text 👋", observed: observed + "Fremde Eingabe", caret: caret))
        XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: baseline, selection: selection, text: "erster Text 👋", observed: "Anfang erster Ende", caret: caret))
        XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: baseline, selection: selection, text: "erster Text 👋", observed: observed, caret: NSRange(location: caret.location, length: 1)))
    }
    func testFollowingSentenceSpacingParticipatesInQueueRebaseProof() {
        XCTAssertTrue(DeliveryVerification.canAdvanceQueuedInsertion(baseline: "Erster Satz.", selection: NSRange(location: 12, length: 0), text: "Second sentence.", observed: "Erster Satz. Second sentence.", caret: NSRange(location: 29, length: 0)))
        XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: "Erster Satz.", selection: NSRange(location: 12, length: 0), text: "Second sentence.", observed: "Erster Satz.Second sentence.", caret: NSRange(location: 28, length: 0)))
    }
    func testUnpunctuatedQueuedUtterancesHaveWordSpacingWithoutBreakingPunctuationOrDecimals() {
        func continuation(_ before: String, _ next: String) -> String {
            DeliveryVerification.queuedContinuationText(next, baseline: before, selection: NSRange(location: (before as NSString).length, length: 0))
        }
        XCTAssertEqual(continuation("Hallo", "Welt"), " Welt")
        XCTAssertEqual(continuation("Hello", "world"), " world")
        XCTAssertEqual(continuation("Γεια", "σου"), " σου")
        XCTAssertEqual(continuation("Bitte,", "weiter"), " weiter")
        XCTAssertEqual(continuation("12,", "5"), "5")
        XCTAssertEqual(continuation("Hallo ", "Welt"), "Welt")
        XCTAssertEqual(continuation("Hallo", ","), ",")
        XCTAssertEqual(continuation("(", "Text"), "Text")
    }
    func testFailureAndCancellationReleaseReservationsWithoutReorderingOthers() {
        var queue = DictationQueue(maximumBytes: 20, reservationBytes: 10)
        let a = UUID(), b = UUID()
        XCTAssertTrue(queue.reserve(a)); queue.finish(a) // Failed microphone start.
        XCTAssertTrue(queue.reserve(b)); XCTAssertTrue(queue.captured(b))
        XCTAssertEqual(queue.beginNext(), b); queue.suppressAutomaticDelivery()
        XCTAssertFalse(queue.mayAutomaticallyDeliver(b))
        queue.cancelAll(); XCTAssertNil(queue.beginNext()); XCTAssertEqual(queue.reservedBytes, 0)
    }
    func testNextSnippetCanBeCapturedWhileRealPipelineWaitsForFormatting() async throws {
        let formatter = QueueParkedFormatter()
        let pipeline = ProcessingPipeline(speech: QueueFixtureSpeech(), formatter: formatter)
        var queue = DictationQueue(maximumBytes: 20, reservationBytes: 10)
        let a = UUID(), b = UUID()
        XCTAssertTrue(queue.reserve(a)); XCTAssertTrue(queue.captured(a))
        XCTAssertEqual(queue.beginNext(), a)
        try await pipeline.start(sessionID: a, style: .cleaned, languages: ["de"])
        try await pipeline.append(samples: [Float](repeating: 0.2, count: 16_000))
        let finishingA = Task { try await pipeline.finish() }
        await formatter.waitForEntry()
        // The first pipeline is parked inside real formatting, while the next
        // microphone buffer can accept and stop a complete second recording.
        XCTAssertTrue(queue.reserve(b))
        let nextAudio = AudioCaptureBuffer()
        _ = nextAudio.append([Float](repeating: 0.3, count: 8_000))
        _ = nextAudio.finish()
        let nextPCM = nextAudio.snapshot()
        XCTAssertEqual(nextPCM.count, 8_000)
        XCTAssertTrue(queue.captured(b)); XCTAssertNil(queue.beginNext())
        XCTAssertTrue(queue.mayAutomaticallyDeliver(a))
        await formatter.release()
        let first = try await finishingA.value
        XCTAssertEqual(first.id, a); XCTAssertEqual(first.duration, 1)
        queue.finish(a); XCTAssertEqual(queue.beginNext(), b)
        let nextPipeline = ProcessingPipeline(speech: QueueFixtureSpeech(), formatter: QueueIdentityFormatter())
        let second = try await nextPipeline.process(samples: nextPCM, sessionID: b, style: .original)
        XCTAssertEqual(second.id, b); XCTAssertEqual(second.duration, 0.5)
        XCTAssertTrue(queue.mayAutomaticallyDeliver(b))
        XCTAssertEqual([first.text, second.text], ["Beispiel", "Beispiel"])
        queue.finish(b); XCTAssertEqual(queue.reservedBytes, 0)
    }
    func testInvalidTransitionsDoNotProduceDuplicateJobs() {
        var queue = DictationQueue(maximumBytes: 20, reservationBytes: 10)
        let id = UUID()
        XCTAssertFalse(queue.captured(id)); XCTAssertNil(queue.beginNext())
        XCTAssertTrue(queue.reserve(id)); XCTAssertFalse(queue.reserve(id))
        XCTAssertNil(queue.beginNext()); XCTAssertTrue(queue.captured(id))
        XCTAssertFalse(queue.captured(id)); XCTAssertEqual(queue.beginNext(), id)
        XCTAssertNil(queue.beginNext())
    }
    func testEveryConfiguredLanguageUsesTheQueueAndKeepsItsPipelineLanguage() async throws {
        for language in ["de", "en", "fr", "it", "es", "gsw"] {
            var settings = Settings()
            settings.languages = [language]
            settings.swissGermanEnabled = language == "gsw"
            let route = DictationProcessingRoute(settings: settings, style: .original)
            let speech = QueueLanguageSpeech()
            let pipeline = ProcessingPipeline(speech: speech, formatter: QueueIdentityFormatter())
            var queue = DictationQueue(maximumBytes: 20, reservationBytes: 10)
            let first = UUID(), second = UUID()
            XCTAssertTrue(queue.reserve(first)); XCTAssertTrue(queue.captured(first))
            XCTAssertEqual(queue.beginNext(), first)
            try await pipeline.start(sessionID: first, style: .original, languages: route.languages)
            XCTAssertTrue(queue.reserve(second)); XCTAssertTrue(queue.captured(second))
            try await pipeline.append(samples: [Float](repeating: 0.2, count: 16_000))
            let result = try await pipeline.finish()
            XCTAssertEqual(result.id, first)
            let configured = await speech.languages
            XCTAssertEqual(configured, language == "gsw" ? ["de"] : [language])
            XCTAssertTrue(queue.mayAutomaticallyDeliver(first))
            queue.finish(first); XCTAssertEqual(queue.beginNext(), second)
            XCTAssertTrue(queue.mayAutomaticallyDeliver(second))
        }
    }
}

private actor QueueLanguageSpeech: SpeechTranscribing, SpeechLanguageConfiguring {
    private(set) var languages: [String] = []
    func configureLanguages(_ languages: [String], sessionID: UUID) { self.languages = languages }
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        .init(sessionID: sessionID, index: index, text: "Beispiel", words: [.init(text: "Beispiel", start: offset + 0.1, end: offset + 0.2)])
    }
}

private struct QueueFixtureSpeech: SpeechTranscribing {
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        .init(sessionID: sessionID, index: index, text: "Beispiel",
              words: [.init(text: "Beispiel", start: offset + 0.1, end: offset + 0.2)])
    }
}
private struct QueueIdentityFormatter: TextFormatting {
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String { text }
}
private actor QueueParkedFormatter: TextFormatting {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var parked: CheckedContinuation<Void, Never>?
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        entered = true; entry?.resume(); entry = nil
        await withCheckedContinuation { parked = $0 }
        return text
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { entry = $0 }
    }
    func release() { parked?.resume(); parked = nil }
}
