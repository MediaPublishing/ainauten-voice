import XCTest
import Foundation
@testable import VoiceWisprCore

final class DictationQueueTests: XCTestCase {
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
    func testLaterCapturePermanentlySuppressesLateInsertionForTheBatch() {
        var queue = DictationQueue(maximumBytes: 20, reservationBytes: 10)
        let a = UUID(), b = UUID()
        XCTAssertTrue(queue.reserve(a)); XCTAssertTrue(queue.captured(a))
        XCTAssertEqual(queue.beginNext(), a); XCTAssertTrue(queue.mayAutomaticallyDeliver(a))
        XCTAssertTrue(queue.reserve(b)); XCTAssertFalse(queue.mayAutomaticallyDeliver(a))
        queue.finish(b); XCTAssertFalse(queue.mayAutomaticallyDeliver(a))
        queue.finish(a); queue.resetBatchIfIdle()
        let c = UUID(); XCTAssertTrue(queue.reserve(c)); XCTAssertTrue(queue.captured(c))
        XCTAssertEqual(queue.beginNext(), c); XCTAssertTrue(queue.mayAutomaticallyDeliver(c))
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
        XCTAssertFalse(queue.mayAutomaticallyDeliver(a))
        await formatter.release()
        let first = try await finishingA.value
        XCTAssertEqual(first.id, a); XCTAssertEqual(first.duration, 1)
        queue.finish(a); XCTAssertEqual(queue.beginNext(), b)
        let nextPipeline = ProcessingPipeline(speech: QueueFixtureSpeech(), formatter: QueueIdentityFormatter())
        let second = try await nextPipeline.process(samples: nextPCM, sessionID: b, style: .original)
        XCTAssertEqual(second.id, b); XCTAssertEqual(second.duration, 0.5)
        XCTAssertFalse(queue.mayAutomaticallyDeliver(b))
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
