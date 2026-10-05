import XCTest
import FluidAudio
@testable import VoiceWisprCore

private actor TestSpeech: SpeechTranscribing {
    var calls = 0
    var sessions: [UUID] = []
    let delay: Duration
    init(delay: Duration = .zero) { self.delay = delay }
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        calls += 1; sessions.append(sessionID)
        // Deliberately ignores cancellation to exercise the session fence.
        try? await Task.sleep(for: delay)
        let duration = Double(samples.count) / 16_000
        let text = "Abschnitt\(index)"
        return .init(sessionID: sessionID, index: index, text: text, words: [.init(text: text, start: offset + duration / 2, end: offset + duration / 2 + 0.01)])
    }
}
private actor TestFormatter: TextFormatting {
    let fails: Bool
    let delay: Duration
    var contexts: [String] = []
    init(fails: Bool = false, delay: Duration = .zero) { self.fails = fails; self.delay = delay }
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        contexts.append(context)
        try await Task.sleep(for: delay)
        if fails { throw VoiceError.message("Testfehler") }
        return "[\(text)]"
    }
}

/// A deterministic handshake, including workers that intentionally ignore cancellation.
private actor ProcessingGate {
    private var entered = false
    private var waitingForEntry: [CheckedContinuation<Void, Never>] = []
    private var parked: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true
        waitingForEntry.forEach { $0.resume() }; waitingForEntry = []
        await withCheckedContinuation { parked = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { waitingForEntry.append($0) }
    }
    func release() { parked?.resume(); parked = nil }
}
private actor GatedSpeech: SpeechTranscribing {
    let gate = ProcessingGate()
    private var calls = 0
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        calls += 1
        if calls == 1 { await gate.pause() }
        let middle = offset + Double(samples.count) / 32_000
        return .init(sessionID: sessionID, index: index, text: "Abschnitt\(index)", words: [.init(text: "Abschnitt\(index)", start: middle, end: middle)])
    }
}
private actor FailingSpeech: SpeechTranscribing {
    let failingIndex: Int
    let gate: ProcessingGate?
    init(failingIndex: Int, gate: ProcessingGate? = nil) { self.failingIndex = failingIndex; self.gate = gate }
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        if index == failingIndex {
            if let gate { await gate.pause() }
            throw VoiceError.message("Test: späterer Erkennungsabschnitt fehlgeschlagen")
        }
        let middle = offset + Double(samples.count) / 32_000
        return .init(sessionID: sessionID, index: index, text: "Abschnitt\(index)", words: [.init(text: "Abschnitt\(index)", start: middle, end: middle)])
    }
}
private actor GatedFormatter: TextFormatting {
    let gate = ProcessingGate()
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        await gate.pause()
        return "Verspätete Glättung"
    }
}
private actor ReconcilingSpeech: SpeechTranscribing, SpeechSessionReconciling {
    let text: String
    let failingIndex: Int?
    let reconciliationFails: Bool
    let gate: ProcessingGate?
    let formatterEntry: ProcessingGate?
    var reconciliations = 0
    var reconciledSamples = 0
    var reconciliationWasCancelled = false
    init(text: String = "Abschnitt0 Abschnitt1", failingIndex: Int? = nil, reconciliationFails: Bool = false, gate: ProcessingGate? = nil, formatterEntry: ProcessingGate? = nil) {
        self.text = text; self.failingIndex = failingIndex; self.reconciliationFails = reconciliationFails
        self.gate = gate; self.formatterEntry = formatterEntry
    }
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        if index == failingIndex { throw VoiceError.message("Stream-Erkennung fehlgeschlagen") }
        let middle = offset + Double(samples.count) / 32_000
        return .init(sessionID: sessionID, index: index, text: "Abschnitt\(index)", words: [.init(text: "Abschnitt\(index)", start: middle, end: middle)])
    }
    func reconcile(samples: [Float], sessionID: UUID) async throws -> TranscriptSegment {
        reconciliations += 1; reconciledSamples = samples.count
        if let formatterEntry { await formatterEntry.waitForEntry() }
        if let gate { await gate.pause() } // Deliberately ignores cancellation.
        reconciliationWasCancelled = Task.isCancelled
        if reconciliationFails { throw VoiceError.message("SDK-Abgleich fehlgeschlagen") }
        return .init(sessionID: sessionID, index: 0, text: text)
    }
}

final class ProcessingTests: XCTestCase {
    func testSilenceAndMaximumRangesPreserveEverySample() {
        let speech = Array(repeating: Float(0.1), count: 16_000)
        let quiet = Array(repeating: Float(0), count: 12_000)
        let samples = speech + quiet + Array(repeating: Float(0.1), count: 16_000 * 16)
        let ranges = SilenceSegmenter.ranges(samples: samples)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, samples.count)
        XCTAssertEqual(ranges.map(\.count).reduce(0, +), samples.count)
        XCTAssertTrue(ranges.allSatisfy { $0.count <= 240_000 })
        for pair in zip(ranges, ranges.dropFirst()) { XCTAssertEqual(pair.0.upperBound, pair.1.lowerBound) }
    }
    func testCaptureBufferTwentyMinuteBoundAndFinishedFence() {
        let buffer = AudioCaptureBuffer()
        buffer.append(Array(repeating: 0, count: AudioCaptureBuffer.maximumSamples - 4))
        let accepted = buffer.append(Array(repeating: 1, count: 12))
        XCTAssertEqual(accepted.samples.count, 4)
        XCTAssertEqual(buffer.count, AudioCaptureBuffer.maximumSamples)
        XCTAssertTrue(buffer.isFinished)
        XCTAssertEqual(buffer.append([1]).samples, [])
    }
    func testProtectedNumbersNegationAndURLsRejectChanges() throws {
        let input = "Bitte nicht 123,45 Euro an https://example.com/a senden."
        XCTAssertThrowsError(try LocalFormatter.validate("Bitte 123,45 Euro an https://example.com/a senden.", original: input, vocabulary: []))
        XCTAssertThrowsError(try LocalFormatter.validate("Bitte nicht 124,45 Euro an https://example.com/a senden.", original: input, vocabulary: []))
        XCTAssertThrowsError(try LocalFormatter.validate("Bitte nicht 123,45 Euro an https://example.net/a senden.", original: input, vocabulary: []))
        XCTAssertEqual(try LocalFormatter.validate(input, original: input, vocabulary: []), input)
    }
    func testFormattingCannotCompleteAnUnfinishedClauseWithExtraWords() throws {
        XCTAssertThrowsError(try LocalFormatter.validate("Wait before making any changes.", original: "Wait before making any", vocabulary: []))
        XCTAssertEqual(try LocalFormatter.validate("Wait before making any changes.", original: "wait before making any changes", vocabulary: []), "Wait before making any changes.")
    }
    func testFormattingPreservesSubjectPluralAndWordOrder() throws {
        XCTAssertThrowsError(try LocalFormatter.validate("before you prepare", original: "before we prepare", vocabulary: []))
        XCTAssertThrowsError(try LocalFormatter.validate("Die Nachrichten", original: "Die Nachricht", vocabulary: []))
        XCTAssertThrowsError(try LocalFormatter.validate("Morgen senden wir den Bericht", original: "Wir senden morgen den Bericht", vocabulary: []))
        XCTAssertEqual(try LocalFormatter.validate("Die Nachricht.", original: "ähm die nachricht", vocabulary: []), "Die Nachricht.")
    }
    func testEmptyOrUnrelatedDictionaryDoesNotSplitTheLastWord() {
        var empty = StreamingDictionaryMatcher([])
        XCTAssertEqual(empty.process("We wait for approval. "), "We wait for approval. ")
        var dictionary = StreamingDictionaryMatcher([DictionaryEntry(phrase: "New York", replacement: "NYC")])
        XCTAssertEqual(dictionary.process("We wait for approval. "), "We wait for approval. ")
        XCTAssertEqual(dictionary.process("Next stop New "), "Next stop ")
        XCTAssertEqual(dictionary.process("York. "), "NYC. ")
        XCTAssertEqual(dictionary.process("", final: true), "")
    }
    func testActualTokenTimingsBecomeAbsoluteWords() {
        let tokens = [TokenTiming(token: " Hallo", tokenId: 1, startTime: 0.2, endTime: 0.4, confidence: 1), TokenTiming(token: "welt", tokenId: 2, startTime: 0.4, endTime: 0.8, confidence: 1), TokenTiming(token: " jetzt", tokenId: 3, startTime: 1.1, endTime: 1.3, confidence: 1)]
        let words = SpeechRuntime.words(from: tokens, offset: 30)
        XCTAssertEqual(words.map(\.text), ["Hallowelt", "jetzt"])
        XCTAssertEqual(words[0].start, 30.2, accuracy: 0.001)
        XCTAssertEqual(words[0].end, 30.8, accuracy: 0.001)
        XCTAssertEqual(words[1].start, 31.1, accuracy: 0.001)
    }
    func testOverlappingCoreBoundaryCommitsWordExactlyOnce() throws {
        let id = UUID()
        let words = [TranscriptWord(text: "links", start: 13.0, end: 13.8), TranscriptWord(text: "Grenzwort", start: 13.8, end: 14.2), TranscriptWord(text: "rechts", start: 14.2, end: 14.7)]
        let segment = TranscriptSegment(sessionID: id, index: 0, text: "links Grenzwort rechts", words: words)
        let first = try ProcessingPipeline.committedText(segment: segment, bounds: 0..<224_000, requiresTimings: true)
        let second = try ProcessingPipeline.committedText(segment: segment, bounds: 224_000..<448_000, requiresTimings: true)
        XCTAssertEqual(first, "links")
        XCTAssertEqual(second, "Grenzwort rechts")
        XCTAssertThrowsError(try ProcessingPipeline.committedText(segment: .init(sessionID: id, index: 0, text: "ohne Zeiten"), bounds: 0..<224_000, requiresTimings: true))
    }
    func testRecognitionStartsDuringCaptureAndResultsStayOrdered() async throws {
        let speech = TestSpeech()
        let pipeline = ProcessingPipeline(speech: speech, formatter: TestFormatter())
        try await pipeline.start(sessionID: UUID(), style: .cleaned)
        try await pipeline.append(samples: Array(repeating: 0.1, count: 16_000 * 16))
        try await Task.sleep(for: .milliseconds(30))
        let callsBeforeFinish = await speech.calls
        XCTAssertGreaterThan(callsBeforeFinish, 0)
        let result = try await pipeline.finish()
        XCTAssertEqual(result.original, "Abschnitt0 Abschnitt1")
        XCTAssertTrue(result.text.contains("Abschnitt0"))
        XCTAssertTrue(result.text.contains("Abschnitt1"))
        let zero = result.text.range(of: "Abschnitt0")!.lowerBound
        let one = result.text.range(of: "Abschnitt1")!.lowerBound
        XCTAssertLessThan(zero, one)
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.duration, 16)
    }
    func testFormatterFailureIsVisibleRawFallback() async throws {
        let pipeline = ProcessingPipeline(speech: TestSpeech(), formatter: TestFormatter(fails: true))
        let result = try await pipeline.process(samples: Array(repeating: 0.1, count: 16_000), sessionID: UUID(), style: .cleaned)
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.text, result.original)
    }
    func testOriginalStyleIsNotMisreportedAsFallback() async throws {
        let pipeline = ProcessingPipeline(speech: TestSpeech(), formatter: TestFormatter())
        let result = try await pipeline.process(samples: Array(repeating: 0.1, count: 16_000), sessionID: UUID(), style: .original)
        XCTAssertFalse(result.usedFallback)
    }
    func testFormattingBacklogFallsBackWithoutLosingASROrOrder() async throws {
        let pipeline = ProcessingPipeline(speech: TestSpeech(), formatter: TestFormatter(delay: .milliseconds(100)))
        let result = try await pipeline.process(samples: Array(repeating: 0.1, count: 16_000 * 100), sessionID: UUID(), style: .cleaned)
        XCTAssertTrue(result.usedFallback)
        for index in 0..<8 { XCTAssertTrue(result.text.contains("Abschnitt\(index)")) }
        XCTAssertEqual(result.original.split(separator: " ").count, 8)
        XCTAssertEqual(result.duration, 100)
    }
    func testRealRuntimesRequireLocalModelFiles() async throws {
        let missing = URL(fileURLWithPath: "/nonexistent/voice-wispr-model-\(UUID().uuidString)")
        let formatter = LocalFormatter(modelURL: missing)
        do { try await formatter.prepare(); XCTFail("Fehlendes GGUF muss Fehler liefern") } catch {}
        let speech = SpeechRuntime(modelDirectory: missing)
        do { try await speech.prepare(); XCTFail("Fehlende Core-ML-Modelle müssen Fehler liefern") } catch {}
    }
    func testShutdownRejectsQueuedFormatterReload() async throws {
        let formatter = LocalFormatter(modelURL: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"))
        await formatter.shutdown()
        await formatter.shutdown()
        do { try await formatter.prepare(); XCTFail("A terminated formatter cannot reload GPU resources") }
        catch { XCTAssertEqual(error.localizedDescription, "Lokale Formatierung ist beendet") }
    }
    func testCancelledLateRecognitionCannotEnterNewSession() async throws {
        let speech = GatedSpeech()
        let pipeline = ProcessingPipeline(speech: speech, formatter: TestFormatter())
        let old = Task { try await pipeline.process(samples: Array(repeating: 0.1, count: 16_000), sessionID: UUID(), style: .original) }
        await speech.gate.waitForEntry()
        await pipeline.cancel()
        let id = UUID()
        let new = try await pipeline.process(samples: Array(repeating: 0.1, count: 16_000), sessionID: id, style: .original)
        XCTAssertEqual(new.id, id)
        XCTAssertEqual(new.text, "Abschnitt0")
        await speech.gate.release()
        do { _ = try await old.value; XCTFail("Abgebrochene Sitzung darf kein Ergebnis liefern") } catch is CancellationError {} catch { XCTFail("Unerwarteter Fehler: \(error)") }
    }
    func testCancelledBenchmarkTaskThrows() async throws {
        let speech = GatedSpeech()
        let pipeline = ProcessingPipeline(speech: speech, formatter: TestFormatter())
        let task = Task { try await pipeline.process(samples: Array(repeating: 0.1, count: 16_000), sessionID: UUID(), style: .original) }
        await speech.gate.waitForEntry()
        task.cancel()
        await speech.gate.release()
        do { _ = try await task.value; XCTFail("Cancellation erwartet") } catch is CancellationError {} catch { XCTFail("Unerwarteter Fehler") }
    }
    func testLaterRecognitionFailurePreservesPartialRawText() async throws {
        let id = UUID()
        let pipeline = ProcessingPipeline(speech: FailingSpeech(failingIndex: 1), formatter: TestFormatter())
        do {
            _ = try await pipeline.process(samples: [Float](repeating: 0.1, count: 16_000 * 16), sessionID: id, style: .original)
            XCTFail("Späterer Fehler darf kein vollständiges Ergebnis liefern")
        } catch let partial as PartialDictationError {
            XCTAssertEqual(partial.result.id, id)
            XCTAssertEqual(partial.result.text, "Abschnitt0")
            XCTAssertEqual(partial.result.original, "Abschnitt0")
            XCTAssertFalse(partial.result.isComplete)
        }
    }
    func testFirstRecognitionFailureDoesNotFabricatePartialResult() async throws {
        let pipeline = ProcessingPipeline(speech: FailingSpeech(failingIndex: 0), formatter: TestFormatter())
        do {
            _ = try await pipeline.process(samples: [Float](repeating: 0.1, count: 16_000), sessionID: UUID(), style: .original)
            XCTFail("Fehler im ersten Abschnitt muss Fehler bleiben")
        } catch is PartialDictationError { XCTFail("Kein Teiltext ohne bereits erkannte Wörter") }
        catch {}
    }
    func testCancellationAfterRecognizedTextNeverLeaksPartialError() async throws {
        let gate = ProcessingGate()
        let speech = FailingSpeech(failingIndex: 1, gate: gate)
        let pipeline = ProcessingPipeline(speech: speech, formatter: TestFormatter())
        let task = Task { try await pipeline.process(samples: [Float](repeating: 0.1, count: 16_000 * 16), sessionID: UUID(), style: .original) }
        await gate.waitForEntry()
        task.cancel()
        await gate.release()
        do { _ = try await task.value; XCTFail("Abbruch darf keinen Teiltext liefern") }
        catch is CancellationError {} catch { XCTFail("Unerwarteter Fehler: \(error)") }
    }
    func testRequestOriginalDuringFinishKeepsDictionaryAndRejectsLateFormatting() async throws {
        let formatter = GatedFormatter()
        let pipeline = ProcessingPipeline(speech: TestSpeech(), formatter: formatter)
        let id = UUID()
        try await pipeline.start(sessionID: id, style: .cleaned, dictionary: [DictionaryEntry(phrase: "Abschnitt0", replacement: "Wörterbuch")])
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 16_000))
        let finish = Task { try await pipeline.finish() }
        await formatter.gate.waitForEntry()
        await pipeline.requestOriginal()
        let result = try await finish.value
        await formatter.gate.release()
        XCTAssertEqual(result.id, id)
        XCTAssertEqual(result.original, "Abschnitt0")
        XCTAssertEqual(result.text, "Wörterbuch")
        XCTAssertTrue(result.usedFallback)
        XCTAssertTrue(result.isComplete)
    }
    func testVendorInferencePrefixRetainsAllSilentAndVerySoftInput() {
        let silent = [Float](repeating: 0, count: 3200)
        let soft = [Float](repeating: 0.0004, count: 3200)
        XCTAssertEqual(SpeechRuntime.speechBearingPrefix(silent), silent)
        XCTAssertEqual(SpeechRuntime.speechBearingPrefix(soft), soft)
    }
    func testVendorInferencePrefixDoesNotTrimSpeechBearingWordTail() {
        let samples = [Float](repeating: 0.1, count: 1280 * 3) + [Float](repeating: 0.00051, count: 1280)
        XCTAssertEqual(SpeechRuntime.speechBearingPrefix(samples), samples)
    }
    func testVendorInferencePrefixRemovesOnlySubFloorTailFrames() {
        let speech = [Float](repeating: 0.03, count: 1280 * 4)
        let samples = speech + [Float](repeating: 0, count: 1280 * 3)
        XCTAssertEqual(SpeechRuntime.speechBearingPrefix(samples), speech)
        XCTAssertEqual(samples.count, 1280 * 7)
    }
    func testVendorInferencePrefixCannotInvalidateShortSpeechTail() {
        let samples = [Float](repeating: 0.03, count: 1280) + [Float](repeating: 0, count: 1280 * 3)
        XCTAssertEqual(SpeechRuntime.speechBearingPrefix(samples), samples)
    }
    func testLongSessionReconciliationKeepsFormattingWhenWordsAgree() async throws {
        let speech = ReconcilingSpeech(text: "ABSCHNITT0. Abschnitt1!")
        let pipeline = ProcessingPipeline(speech: speech, formatter: TestFormatter())
        let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: 256_000), sessionID: UUID(), style: .cleaned)
        XCTAssertEqual(result.original, "ABSCHNITT0. Abschnitt1!")
        XCTAssertTrue(result.text.contains("[Abschnitt0"))
        XCTAssertTrue(result.text.contains("[Abschnitt1"))
        XCTAssertFalse(result.usedFallback)
        XCTAssertTrue(result.isComplete)
        let count = await speech.reconciliations, sampleCount = await speech.reconciledSamples
        XCTAssertEqual(count, 1); XCTAssertEqual(sampleCount, 256_000)
    }
    func testChangedReconciliationCancelsFormattingAndAppliesWholeDictionary() async throws {
        let formatter = GatedFormatter()
        let speech = ReconcilingSpeech(text: "Bitte nicht New York ändern.", formatterEntry: formatter.gate)
        let pipeline = ProcessingPipeline(speech: speech, formatter: formatter)
        let id = UUID()
        try await pipeline.start(sessionID: id, style: .cleaned, dictionary: [DictionaryEntry(phrase: "New York", replacement: "NYC")])
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 256_000))
        let result = try await pipeline.finish()
        XCTAssertEqual(result.original, "Bitte nicht New York ändern.")
        XCTAssertEqual(result.text, "Bitte nicht NYC ändern.")
        XCTAssertTrue(result.usedFallback); XCTAssertTrue(result.isComplete)
        await formatter.gate.release()
        let next = try await pipeline.process(samples: [Float](repeating: 0.1, count: 16_000), sessionID: UUID(), style: .original)
        XCTAssertEqual(next.text, "Abschnitt0")
    }
    func testOriginalReconciliationIsNotFormattingFallback() async throws {
        let pipeline = ProcessingPipeline(speech: ReconcilingSpeech(text: "Vollständig erkannt."), formatter: TestFormatter())
        let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: 256_000), sessionID: UUID(), style: .original)
        XCTAssertEqual(result.text, "Vollständig erkannt.")
        XCTAssertFalse(result.usedFallback); XCTAssertTrue(result.isComplete)
    }
    func testWholeSDKCanRecoverFailedStreamingRecognition() async throws {
        let pipeline = ProcessingPipeline(speech: ReconcilingSpeech(text: "Alle Wörter bleiben erhalten.", failingIndex: 1), formatter: TestFormatter())
        let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: 256_000), sessionID: UUID(), style: .original)
        XCTAssertEqual(result.text, "Alle Wörter bleiben erhalten.")
        XCTAssertTrue(result.isComplete)
    }
    func testFailedWholeSDKNeverApprovesOtherwiseCompleteStream() async throws {
        let pipeline = ProcessingPipeline(speech: ReconcilingSpeech(reconciliationFails: true), formatter: TestFormatter())
        do {
            _ = try await pipeline.process(samples: [Float](repeating: 0.1, count: 256_000), sessionID: UUID(), style: .cleaned)
            XCTFail("Fehlgeschlagener Abgleich darf kein vollständiges Ergebnis liefern")
        } catch let partial as PartialDictationError {
            XCTAssertEqual(partial.result.original, "Abschnitt0 Abschnitt1")
            XCTAssertEqual(partial.result.text, partial.result.original)
            XCTAssertFalse(partial.result.isComplete)
        }
    }
    func testEmptyWholeSDKCannotEraseAlreadyRecognizedWords() async throws {
        let pipeline = ProcessingPipeline(speech: ReconcilingSpeech(text: ""), formatter: TestFormatter())
        do {
            _ = try await pipeline.process(samples: [Float](repeating: 0.1, count: 256_000), sessionID: UUID(), style: .original)
            XCTFail("Leerer Abgleich darf erkannte Wörter nicht löschen")
        } catch let partial as PartialDictationError {
            XCTAssertEqual(partial.result.original, "Abschnitt0 Abschnitt1")
            XCTAssertFalse(partial.result.isComplete)
        }
    }
    func testNoPartialFabricatedWhenBothRecognitionRoutesFailImmediately() async throws {
        let pipeline = ProcessingPipeline(speech: ReconcilingSpeech(failingIndex: 0, reconciliationFails: true), formatter: TestFormatter())
        do {
            _ = try await pipeline.process(samples: [Float](repeating: 0.1, count: 256_000), sessionID: UUID(), style: .original)
            XCTFail("Beide Erkennungswege fehlgeschlagen")
        } catch is PartialDictationError { XCTFail("Ohne Wörter darf kein Teiltext entstehen") }
        catch {}
    }
    func testCancellationWhileWholeSDKRunsCannotDeliverLateResult() async throws {
        let gate = ProcessingGate()
        let speech = ReconcilingSpeech(gate: gate)
        let pipeline = ProcessingPipeline(speech: speech, formatter: TestFormatter())
        let task = Task { try await pipeline.process(samples: [Float](repeating: 0.1, count: 256_000), sessionID: UUID(), style: .original) }
        await gate.waitForEntry()
        await pipeline.cancel()
        let newID = UUID()
        let next = try await pipeline.process(samples: [Float](repeating: 0.1, count: 16_000), sessionID: newID, style: .original)
        XCTAssertEqual(next.id, newID); XCTAssertEqual(next.text, "Abschnitt0")
        await gate.release()
        do { _ = try await task.value; XCTFail("Abgebrochener Abgleich darf kein Ergebnis liefern") }
        catch is CancellationError {} catch { XCTFail("Unerwarteter Fehler: \(error)") }
        let cancelled = await speech.reconciliationWasCancelled
        XCTAssertTrue(cancelled)
    }
    func testShortSessionDoesNotRepeatRecognition() async throws {
        let speech = ReconcilingSpeech()
        let pipeline = ProcessingPipeline(speech: speech, formatter: TestFormatter())
        let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: 240_000), sessionID: UUID(), style: .original)
        XCTAssertTrue(result.isComplete)
        let count = await speech.reconciliations
        XCTAssertEqual(count, 0)
    }
    func testReconciliationComparisonPreservesNegationNumbersAndApostrophes() {
        XCTAssertEqual(ProcessingPipeline.lexicalSequence("Don’t change 12!"), ProcessingPipeline.lexicalSequence("don't CHANGE 12."))
        XCTAssertFalse(ProcessingPipeline.lexicalSequence("Bitte nicht 12") == ProcessingPipeline.lexicalSequence("Bitte 12"))
        XCTAssertFalse(ProcessingPipeline.lexicalSequence("Bitte 12") == ProcessingPipeline.lexicalSequence("Bitte 13"))
        XCTAssertFalse(ProcessingPipeline.lexicalSequence("can't") == ProcessingPipeline.lexicalSequence("cant"))
    }
}
