import XCTest
@testable import VoiceWisprCore

private final class CheckpointSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(Int, Bool)] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func record(_ sample: Int, _ succeeded: Bool) {
        lock.lock()
        entries.append((sample, succeeded))
        let ready = waiters.filter { $0.0 <= sample }
        waiters.removeAll { $0.0 <= sample }
        lock.unlock()
        ready.forEach { $0.1.resume() }
    }
    func wait(for sample: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if entries.contains(where: { $0.0 >= sample }) { lock.unlock(); continuation.resume() }
            else { waiters.append((sample, continuation)); lock.unlock() }
        }
    }
    var snapshot: [(Int, Bool)] { lock.lock(); defer { lock.unlock() }; return entries }
}
private actor CheckpointGate {
    private var entered = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var parked: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true; observers.forEach { $0.resume() }; observers = []
        await withCheckedContinuation { parked = $0 }
    }
    func waitForEntry() async { if !entered { await withCheckedContinuation { observers.append($0) } } }
    func release() { parked?.resume(); parked = nil }
}
private actor CheckpointSpeech: SpeechTranscribing, SpeechSessionReconciling {
    let prefix: String, tail: String
    let gate: CheckpointGate?
    let failFirst: Bool
    let failAll: Bool
    let streamText: String?
    private(set) var lengths: [Int] = []
    init(prefix: String, tail: String, gate: CheckpointGate? = nil, failFirst: Bool = false, failAll: Bool = false, streamText: String? = nil) {
        self.prefix = prefix; self.tail = tail; self.gate = gate; self.failFirst = failFirst; self.failAll = failAll; self.streamText = streamText
    }
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        let middle = offset + Double(samples.count) / 32_000
        let text = streamText.map { index == 0 ? $0 : "" } ?? "Vorläufig\(index)"
        return .init(sessionID: sessionID, index: index, text: text, words: text.split(separator: " ").map { .init(text: String($0), start: middle, end: middle) })
    }
    func reconcile(samples: [Float], sessionID: UUID) async throws -> TranscriptSegment {
        lengths.append(samples.count)
        if lengths.count == 1 {
            if let gate { await gate.pause() } // Deliberately ignores cancellation.
            if failFirst { throw VoiceError.message("Background recognition failed") }
        }
        if failAll { throw VoiceError.message("Repeated background failure") }
        return .init(sessionID: sessionID, index: 0, text: prefix + (samples.count > 300_000 ? tail : ""))
    }
}

private actor PendingStreamFormatter: TextFormatting {
    let gate = CheckpointGate()
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        if text.contains("Vorläufiger") || text.hasSuffix(" ") { await gate.pause() }
        return text
    }
}
private actor CheckpointFormatter: TextFormatting {
    let gate: CheckpointGate?
    private(set) var inputs: [String] = []
    init(gate: CheckpointGate? = nil) { self.gate = gate }
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        inputs.append(text)
        if let gate, text.contains("Geprüfter") { await gate.pause() }
        return text
    }
}

final class CheckpointTests: XCTestCase {
    private let prefix = "Geprüfter Text wir prüfen heute gemeinsam den Entwurf und warten vor dem Versand auf die Rückmeldung von Fabian"
    private let tail = " danach legen wir die Dokumente lokal ab und senden sie nicht automatisch"
    private let audio = [Float](repeating: 0.1, count: 300_000)
    private func pipeline(_ speech: CheckpointSpeech, _ formatter: CheckpointFormatter, _ signal: CheckpointSignal) -> ProcessingPipeline {
        ProcessingPipeline(speech: speech, formatter: formatter, checkpointMinimumSamples: 300_000, checkpointIntervalSamples: 20_000, observeCheckpoint: { signal.record($0, $1) })
    }
    func testExactCheckpointDoesNotWaitForPendingStreamingFormat() async throws {
        for corrected in [false, true] {
        let signal = CheckpointSignal(), formatter = PendingStreamFormatter()
        let speech = CheckpointSpeech(prefix: prefix, tail: tail, streamText: corrected ? prefix.replacingOccurrences(of: "Geprüfter", with: "Vorläufiger") : prefix)
        let pipeline = ProcessingPipeline(speech: speech, formatter: formatter, checkpointMinimumSamples: 300_000, checkpointIntervalSamples: 20_000, observeCheckpoint: { signal.record($0, $1) })
        try await pipeline.start(style: .cleaned)
        try await pipeline.append(samples: audio)
        await formatter.gate.waitForEntry()
        await signal.wait(for: 300_000)
        let result = try await pipeline.finish()
        XCTAssertEqual(result.text, prefix); XCTAssertFalse(result.usedFallback)
        await formatter.gate.release()
        }
    }
    func testRepeatedCheckpointFailureBacksOffAndStopsForSession() async throws {
        let signal = CheckpointSignal(), speech = CheckpointSpeech(prefix: prefix, tail: tail, failAll: true)
        let pipeline = pipeline(speech, CheckpointFormatter(), signal)
        try await pipeline.start(style: .cleaned)
        try await pipeline.append(samples: audio)
        await signal.wait(for: 300_000)
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 39_000))
        var lengths = await speech.lengths; XCTAssertEqual(lengths, [300_000])
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 1000))
        await signal.wait(for: 340_000)
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 79_000))
        lengths = await speech.lengths; XCTAssertEqual(lengths, [300_000, 340_000])
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 1000))
        await signal.wait(for: 420_000)
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 200_000))
        lengths = await speech.lengths; XCTAssertEqual(lengths, [300_000, 340_000, 420_000])
        XCTAssertEqual(signal.snapshot.map(\.1), [false, false, false])
        await pipeline.cancel()
    }
    func testFinishedPrefixAvoidsDuplicateRecognitionAndFormatting() async throws {
        let signal = CheckpointSignal(), speech = CheckpointSpeech(prefix: prefix, tail: tail), formatter = CheckpointFormatter()
        let pipeline = pipeline(speech, formatter, signal)
        try await pipeline.start(style: .cleaned)
        try await pipeline.append(samples: audio)
        await signal.wait(for: audio.count)
        let result = try await pipeline.finish()
        XCTAssertEqual(result.text, prefix); XCTAssertEqual(result.original, prefix); XCTAssertFalse(result.usedFallback)
        let lengths = await speech.lengths
        XCTAssertEqual(lengths, [300_000])
        let inputs = await formatter.inputs
        XCTAssertEqual(inputs.filter { $0.contains("Geprüfter") }.count, 1)
    }
    func testFinalTailReusesPrefixAndReplacesDictionaryPhraseAcrossBoundary() async throws {
        let signal = CheckpointSignal(), speech = CheckpointSpeech(prefix: prefix, tail: tail), formatter = CheckpointFormatter()
        let pipeline = pipeline(speech, formatter, signal)
        let dictionary = [DictionaryEntry(phrase: "Fabian danach", replacement: "Fabian Bonleitner anschließend")]
        try await pipeline.start(style: .email, dictionary: dictionary)
        try await pipeline.append(samples: audio)
        await signal.wait(for: audio.count)
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 10_000))
        let result = try await pipeline.finish()
        XCTAssertEqual(result.original, prefix + tail)
        XCTAssertEqual(ProcessingPipeline.lexicalSequence(result.text), ProcessingPipeline.lexicalSequence(DictionaryMatcher(dictionary).replace(in: prefix + tail)))
        XCTAssertFalse(result.usedFallback); XCTAssertTrue(result.text.contains("nicht"))
        let inputs = await formatter.inputs
        XCTAssertFalse(inputs.contains(prefix + tail))
        XCTAssertFalse(inputs.contains(DictionaryMatcher(dictionary).replace(in: prefix + tail)))
    }
    func testPendingOffersCoalesceIntoLatestPrefix() async throws {
        let gate = CheckpointGate(), signal = CheckpointSignal(), formatter = CheckpointFormatter()
        let speech = CheckpointSpeech(prefix: prefix, tail: tail, gate: gate)
        let pipeline = pipeline(speech, formatter, signal)
        try await pipeline.start(style: .chat)
        try await pipeline.append(samples: audio)
        await gate.waitForEntry()
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 80_000))
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 70_000))
        await gate.release()
        await signal.wait(for: 450_000)
        let lengths = await speech.lengths
        XCTAssertEqual(lengths, [300_000, 450_000])
        let result = try await pipeline.finish()
        XCTAssertEqual(ProcessingPipeline.lexicalSequence(result.text), ProcessingPipeline.lexicalSequence(prefix + tail))
        XCTAssertFalse(result.usedFallback)
    }
    func testOriginalModeNeverStartsCheckpoint() async throws {
        let signal = CheckpointSignal(), speech = CheckpointSpeech(prefix: prefix, tail: tail), formatter = CheckpointFormatter()
        let pipeline = pipeline(speech, formatter, signal)
        try await pipeline.start(style: .original)
        try await pipeline.append(samples: audio)
        let result = try await pipeline.finish()
        XCTAssertEqual(result.text, prefix)
        XCTAssertTrue(signal.snapshot.isEmpty)
        let lengths = await speech.lengths
        XCTAssertEqual(lengths, [300_000])
    }
    func testBackgroundFailureStillCompletesFinalRecognition() async throws {
        let signal = CheckpointSignal(), speech = CheckpointSpeech(prefix: prefix, tail: tail, failFirst: true), formatter = CheckpointFormatter()
        let pipeline = pipeline(speech, formatter, signal)
        try await pipeline.start(style: .cleaned)
        try await pipeline.append(samples: audio)
        await signal.wait(for: 300_000)
        let result = try await pipeline.finish()
        XCTAssertEqual(result.original, prefix); XCTAssertEqual(result.text, prefix); XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(signal.snapshot.map(\.1), [false])
    }
    func testStopDoesNotWaitForCancelledBackgroundFormatter() async throws {
        let gate = CheckpointGate(), signal = CheckpointSignal(), speech = CheckpointSpeech(prefix: prefix, tail: tail)
        let pipeline = pipeline(speech, CheckpointFormatter(gate: gate), signal)
        try await pipeline.start(style: .cleaned)
        try await pipeline.append(samples: audio)
        await gate.waitForEntry()
        let result = try await pipeline.finish()
        XCTAssertEqual(result.text, prefix); XCTAssertTrue(result.usedFallback)
        await gate.release()
        XCTAssertTrue(signal.snapshot.isEmpty)
    }
    func testOriginalDuringCheckpointRejectsLateFormatting() async throws {
        let gate = CheckpointGate(), signal = CheckpointSignal(), speech = CheckpointSpeech(prefix: prefix, tail: tail)
        let pipeline = pipeline(speech, CheckpointFormatter(gate: gate), signal)
        try await pipeline.start(style: .email)
        try await pipeline.append(samples: audio)
        await gate.waitForEntry()
        await pipeline.requestOriginal()
        let result = try await pipeline.finish()
        XCTAssertEqual(result.text, prefix); XCTAssertTrue(result.usedFallback)
        await gate.release()
        XCTAssertTrue(signal.snapshot.isEmpty)
    }
    func testLateCheckpointCannotContaminateNewSession() async throws {
        let gate = CheckpointGate(), signal = CheckpointSignal(), speech = CheckpointSpeech(prefix: prefix, tail: tail, gate: gate)
        let pipeline = pipeline(speech, CheckpointFormatter(), signal)
        try await pipeline.start(style: .cleaned)
        try await pipeline.append(samples: audio)
        await gate.waitForEntry()
        await pipeline.cancel()
        let id = UUID()
        try await pipeline.start(sessionID: id, style: .original)
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 16_000))
        await gate.release()
        let result = try await pipeline.finish()
        XCTAssertEqual(result.id, id); XCTAssertEqual(result.text, "Vorläufig0")
        XCTAssertTrue(signal.snapshot.isEmpty)
    }
    func testColdPrefixFormattingUsesOnlyBoundedSections() {
        let target = Array(repeating: "Wort", count: 123).joined(separator: " ")
        let plan = FormattingRevision.coldPlan(target: target)
        XCTAssertEqual(plan.pieces.count, 4)
        XCTAssertTrue(plan.pieces.allSatisfy { if case .revise(let text) = $0 { return text.split(whereSeparator: \.isWhitespace).count <= 40 }; return false })
    }
}
