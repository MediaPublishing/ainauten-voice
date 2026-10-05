import XCTest
@testable import VoiceWisprCore

private actor ActivitySpeech: SpeechTranscribing, SpeechActivityDetecting {
    var chunks = 0
    var windows: [Range<Int>] = []
    let pauseEvery: Int?
    let delay: Duration
    let holdFirstDetection: Bool
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false
    private var windowWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func waitForDetectionEntry() async {
        if entered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }
    func releaseDetection() { released = true; releaseWaiter?.resume(); releaseWaiter = nil }
    func waitForWindowCount(_ count: Int) async {
        if windows.count >= count { return }
        await withCheckedContinuation { windowWaiters.append((count, $0)) }
    }
    init(pauseEvery: Int? = nil, delay: Duration = .zero, holdFirstDetection: Bool = false) {
        self.pauseEvery = pauseEvery; self.delay = delay; self.holdFirstDetection = holdFirstDetection
    }
    func prepare() async throws {}
    func detectActivity(samples: [Float], state: SpeechActivityState) async throws -> SpeechActivityResult {
        XCTAssertEqual(samples.count, 4096)
        if holdFirstDetection && !entered {
            entered = true
            entryWaiters.forEach { $0.resume() }; entryWaiters = []
            if !released { await withCheckedContinuation { releaseWaiter = $0 } }
        }
        // Deliberately finish even after cancellation to exercise the pipeline's generation fence.
        try? await Task.sleep(for: delay)
        chunks += 1
        return .init(state: state, speechEnded: pauseEvery.map { chunks % $0 == 0 } ?? false)
    }
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        let lower = Int((offset * 16_000).rounded())
        windows.append(lower..<(lower + samples.count))
        let ready = windowWaiters.filter { windows.count >= $0.0 }
        windowWaiters.removeAll { windows.count >= $0.0 }; ready.forEach { $0.1.resume() }
        let mid = offset + Double(samples.count) / 32_000
        return .init(sessionID: sessionID, index: index, text: "Wort\(index)",
            words: [.init(text: "Wort\(index)", start: mid, end: mid)])
    }
}
private actor ActivityFormatter: TextFormatting {
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String { text }
}

private actor SplitLanguageSpeech: SpeechTranscribing, SpeechActivityDetecting, SpeechSessionReconciling {
    static let first = "In some areas boiling water for a minute is enough"
    static let second = "Eine Internetsuche wird vermutlich die Adresse einer örtlichen Firma anzeigen"
    let pauses: Bool
    private var frames = 0
    init(pauses: Bool = true) { self.pauses = pauses }
    func prepare() async throws {}
    func detectActivity(samples: [Float], state: SpeechActivityState) async throws -> SpeechActivityResult {
        frames += 1
        return .init(state: state, speechEnded: pauses && frames % 30 == 0)
    }
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        let text = index == 0 ? Self.first : index == 1 ? Self.second : ""
        let mid = offset + Double(samples.count) / 32_000
        return .init(sessionID: sessionID, index: index, text: text, words: text.split(separator: " ").map { .init(text: String($0), start: mid, end: mid) })
    }
    func reconcile(samples: [Float], sessionID: UUID) async throws -> TranscriptSegment {
        .init(sessionID: sessionID, index: 0, text: Self.second)
    }
}

final class VadTests: XCTestCase {
    func testShortPauseDecodesRetainEntireOmittedLanguage() async throws {
        for style in [TextStyle.original, .cleaned] {
            let pipeline = ProcessingPipeline(speech: SplitLanguageSpeech(), formatter: ActivityFormatter())
            let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: 256_000), sessionID: UUID(), style: style)
            XCTAssertEqual(result.original, SplitLanguageSpeech.first + " " + SplitLanguageSpeech.second)
            XCTAssertEqual(ProcessingPipeline.lexicalSequence(result.text), ProcessingPipeline.lexicalSequence(result.original)); XCTAssertFalse(result.usedFallback)
        }
    }
    func testForcedAndLongWindowsCannotOverrideWholeVerification() async throws {
        for (pauses, count) in [(false, 256_000), (true, 512_000)] {
            let pipeline = ProcessingPipeline(speech: SplitLanguageSpeech(pauses: pauses), formatter: ActivityFormatter())
            let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: count), sessionID: UUID(), style: .original)
            XCTAssertEqual(result.original, SplitLanguageSpeech.second)
        }
    }
    func testOmissionDetectionRequiresLargeOrderedExactAgreement() {
        XCTAssertTrue(ProcessingPipeline.wholeDecodeLostShortPausePrefix(segments: [SplitLanguageSpeech.first, SplitLanguageSpeech.second], verified: SplitLanguageSpeech.second))
        XCTAssertFalse(ProcessingPipeline.wholeDecodeLostShortPausePrefix(segments: ["Bitte nicht die alten 12 Euro senden"], verified: "Bitte die neuen 13 Euro senden"))
        XCTAssertFalse(ProcessingPipeline.wholeDecodeLostShortPausePrefix(segments: [SplitLanguageSpeech.first], verified: "minute enough water some areas"))
        XCTAssertFalse(ProcessingPipeline.wholeDecodeLostShortPausePrefix(segments: [SplitLanguageSpeech.first], verified: ""))
        XCTAssertFalse(ProcessingPipeline.wholeDecodeLostShortPausePrefix(segments: ["Bitte jetzt nicht senden"], verified: "Bitte nicht senden"))
    }
    func testRepeatedOrScatteredStreamingWordsCannotOverrideVerification() {
        XCTAssertFalse(ProcessingPipeline.wholeDecodeLostShortPausePrefix(segments: ["wir senden das heute heute heute heute heute heute heute heute heute heute"], verified: "wir senden das heute"))
        XCTAssertFalse(ProcessingPipeline.wholeDecodeLostShortPausePrefix(segments: ["wir senden das heute wir senden das heute wir senden das heute", "Eine gültige Nachricht"], verified: "Eine gültige Nachricht"))
        XCTAssertFalse(ProcessingPipeline.wholeDecodeLostShortPausePrefix(segments: ["wir senden heute diese neue Nachricht wir senden heute diese neue Nachricht", "Eine gültige Nachricht"], verified: "Eine gültige Nachricht"))
        XCTAssertFalse(ProcessingPipeline.wholeDecodeLostShortPausePrefix(segments: ["one extra two extra three extra four extra five extra six extra seven"], verified: "one two three four five six seven"))
    }
    func testModelActivityPausesStartRecognitionBeforeFinish() async throws {
        let speech = ActivitySpeech(pauseEvery: 3)
        let pipeline = ProcessingPipeline(speech: speech, formatter: ActivityFormatter())
        try await pipeline.start(style: .original)
        try await pipeline.append(samples: [Float](repeating: 0, count: 4096 * 4 + 73))
        await speech.waitForWindowCount(1)
        let before = await speech.windows
        XCTAssertEqual(before.count, 1)
        XCTAssertEqual(before[0], 0..<(4096 * 3))
        let result = try await pipeline.finish()
        let windows = await speech.windows
        XCTAssertEqual(windows.last?.upperBound, 4096 * 4 + 73)
        XCTAssertEqual(result.duration, Double(4096 * 4 + 73) / 16_000, accuracy: 0.000001)
        let chunks = await speech.chunks
        XCTAssertEqual(chunks, 4)
    }
    func testFinishWaitsForActivityAndPreservesPartialChunk() async throws {
        let speech = ActivitySpeech(pauseEvery: 1, delay: .milliseconds(20))
        let pipeline = ProcessingPipeline(speech: speech, formatter: ActivityFormatter())
        let result = try await pipeline.process(samples: [Float](repeating: 0, count: 4096 * 2 + 17), sessionID: UUID(), style: .original)
        let windows = await speech.windows
        let chunks = await speech.chunks
        XCTAssertEqual(chunks, 2)
        XCTAssertEqual(windows.first?.lowerBound, 0)
        XCTAssertEqual(windows.last?.upperBound, 4096 * 2 + 17)
        XCTAssertEqual(result.duration, Double(4096 * 2 + 17) / 16_000, accuracy: 0.000001)
    }
    func testForcedActivityWindowsStayWithinFifteenSecondsAndCoverAllAudio() async throws {
        let speech = ActivitySpeech()
        let pipeline = ProcessingPipeline(speech: speech, formatter: ActivityFormatter())
        // A tail just below a full VAD chunk exercises the final forced-window boundary.
        let count = 224_000 + 232_000 + 2000
        let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: count), sessionID: UUID(), style: .original)
        let windows = await speech.windows
        XCTAssertTrue(windows.allSatisfy { $0.count <= 240_000 })
        XCTAssertEqual(windows.first?.lowerBound, 0)
        XCTAssertEqual(windows.last?.upperBound, count)
        for pair in zip(windows, windows.dropFirst()) { XCTAssertTrue(pair.1.lowerBound <= pair.0.upperBound) }
        XCTAssertEqual(result.duration, Double(count) / 16_000, accuracy: 0.000001)
    }
    func testCancelledLateActivityCannotEnterNewSession() async throws {
        let speech = ActivitySpeech(holdFirstDetection: true)
        let pipeline = ProcessingPipeline(speech: speech, formatter: ActivityFormatter())
        let old = Task { try await pipeline.process(samples: [Float](repeating: 0.1, count: 4096 * 3), sessionID: UUID(), style: .original) }
        await speech.waitForDetectionEntry()
        await pipeline.cancel()
        let id = UUID()
        let current = try await pipeline.process(samples: [Float](repeating: 0.1, count: 511), sessionID: id, style: .original)
        XCTAssertEqual(current.id, id)
        XCTAssertEqual(current.duration, Double(511) / 16_000, accuracy: 0.000001)
        await speech.releaseDetection()
        do { _ = try await old.value; XCTFail("Abgebrochene Sprachaktivität darf kein Ergebnis liefern") }
        catch is CancellationError {} catch { XCTFail("Unerwarteter Fehler: \(error)") }
    }
}
