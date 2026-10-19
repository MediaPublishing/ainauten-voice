import XCTest
import Foundation
@testable import VoiceWisprCore

final class SwissGermanTests: XCTestCase {
    func testLegacySettingsStayDisabledAndLanguageSelectionSurvivesOptIn() throws {
        var settings = Settings(); settings.languages = ["de", "en"]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        json.removeValue(forKey: "swissGermanEnabled")
        var decoded = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.swissGermanEnabled); XCTAssertFalse(decoded.usesSwissGerman)
        decoded.swissGermanEnabled = true
        let imported = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(decoded))
        XCTAssertTrue(imported.usesSwissGerman); XCTAssertEqual(imported.languages, ["de", "en"])
        decoded.swissGermanEnabled = false
        XCTAssertEqual(DictationProcessingRoute(settings: decoded, style: .cleaned).languages, ["de", "en"])
    }
    func testSwissRouteNeverConstructsCloudEvenWithAnInvalidEndpoint() async throws {
        var settings = Settings(); settings.swissGermanEnabled = true
        settings.cloudEnabled = true; settings.cloudEndpoint = "invalid://endpoint"
        for style in TextStyle.allCases {
            let route = DictationProcessingRoute(settings: settings, style: style)
            XCTAssertTrue(route.usesSwissGerman); XCTAssertEqual(route.languages, ["de"]); XCTAssertFalse(route.usesCloudFormatter)
            let formatter = try route.selectFormatter(local: SwissIdentityFormatter()) {
                XCTFail("Cloud construction/key authorization must not run for Swiss")
                throw VoiceError.message("Cloud must not run")
            }
            let text = try await formatter.format("Bitte nicht senden.", style: style, context: "", vocabulary: [])
            XCTAssertEqual(text, "Bitte nicht senden.")
        }
        settings.swissGermanEnabled = false
        XCTAssertTrue(DictationProcessingRoute(settings: settings, style: .cleaned).usesCloudFormatter)
        XCTAssertFalse(DictationProcessingRoute(settings: settings, style: .original).usesCloudFormatter)
    }
    func testPinnedOptionalManifestMatchesTheRuntime() throws {
        let files = try ModelManifest.bundled().files.filter { $0.group == SwissGermanModel.group }
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.path, SwissGermanModel.path)
        XCTAssertEqual(files.first?.size, SwissGermanModel.size)
        XCTAssertEqual(files.first?.sha256, SwissGermanModel.sha256)
        XCTAssertTrue(files.first?.url.absoluteString.contains("5359861c739e955e79d9a303bcbc70fb988958b1") == true)
    }
    func testShortInvalidPCMAndWrongLanguageAreRejected() {
        XCTAssertThrowsError(try SwissGermanSpeechRuntime.validate([Float](repeating: 0, count: 4799), offset: 0))
        XCTAssertThrowsError(try SwissGermanSpeechRuntime.validate([Float](repeating: .nan, count: 4800), offset: 0))
        XCTAssertThrowsError(try SwissGermanSpeechRuntime.validate([Float](repeating: 0, count: 4800), offset: .infinity))
        XCTAssertThrowsError(try SwissGermanSpeechRuntime.validateLanguage("Это текст на русском языке."))
        XCTAssertThrowsError(try SwissGermanSpeechRuntime.validateLanguage("Please do not send the report to the customer today."))
    }
    func testSilenceContractIsExplicitAndInvalidWordOrderCannotBeInserted() throws {
        let empty = Data(#"{"text":"","words":[]}"#.utf8)
        XCTAssertThrowsError(try WhisperLanguageFallback.decode(empty, sessionID: UUID(), index: 0, offset: 0, duration: 1))
        let result = try WhisperLanguageFallback.decode(empty, sessionID: UUID(), index: 0, offset: 0, duration: 1, allowEmpty: true)
        XCTAssertEqual(result.text, ""); XCTAssertTrue(result.words.isEmpty)
        for bad in [#"{"text":"Hallo Welt","words":[{"text":"Hallo","start":1,"end":1.2},{"text":"Welt","start":0.2,"end":0.5}]}"#,
                    #"{"text":"Hallo","words":[]}"#, #"{"text":"","words":[{"text":"Hallo","start":0,"end":0.2}]}"#] {
            XCTAssertThrowsError(try WhisperLanguageFallback.decode(Data(bad.utf8), sessionID: UUID(), index: 0, offset: 0, duration: 2, allowEmpty: true))
        }
    }
    func testMissingSwissModelCannotReportReadyOrUseParakeet() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-swiss-\(UUID()).bin")
        let runtime = SwissGermanSpeechRuntime(modelURL: missing)
        do { try await runtime.prepare(); XCTFail("Missing model cannot prepare") } catch { XCTAssertEqual(error.localizedDescription, L10n.text("swiss.modelRequired")) }
        do { _ = try await runtime.transcribe(samples: [Float](repeating: 0, count: 4800), sessionID: UUID(), index: 0, offset: 0); XCTFail("No silent fallback") } catch { }
    }
    func testSameSizeTamperingFailsTheChecksumAndCannotPrepare() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("swiss-tampered-\(UUID()).bin")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: file) }
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(SwissGermanModel.size)); try handle.close()
        do { try await SwissGermanSpeechRuntime.validateModel(file); XCTFail("Size alone must not establish readiness") }
        catch { XCTAssertEqual(error.localizedDescription, L10n.text("swiss.modelInvalid")) }
    }
    func testFormatterReadinessTracksActualStyleRequirements() {
        var settings = Settings(); settings.defaultStyle = .original
        XCTAssertFalse(settings.swissNeedsFormatter)
        settings.appStyles["example.editor"] = .cleaned; XCTAssertTrue(settings.swissNeedsFormatter)
        settings.manualStyle = .original; XCTAssertFalse(settings.swissNeedsFormatter)
        settings.manualStyle = .cleaned; XCTAssertTrue(settings.swissNeedsFormatter)
    }
    func testLongDecoderLoopIsRejectedWithoutRemovingOrdinaryRepetitions() throws {
        let prefix = "Wir testen diesen längeren Satz mit mehreren verschiedenen Wörtern, damit die nächste Wiederholung trotz der Mindestlänge tatsächlich geprüft werden kann. "
        let phrase = "Er ist der Geschäftsführer eines Orts. "
        try SwissGermanSpeechRuntime.validateRepetition(prefix + String(repeating: phrase, count: 3))
        XCTAssertThrowsError(try SwissGermanSpeechRuntime.validateRepetition(prefix + String(repeating: phrase, count: 8)))
        try SwissGermanSpeechRuntime.validateRepetition(prefix + String(repeating: "Es bleibt heute bei uns. ", count: 4))
        try SwissGermanSpeechRuntime.validateRepetition("Nein nein, bitte nicht senden. Ich wiederhole: bitte nicht senden.")
    }
    func testSwissContextSkipsEarlyPausesButKeepsTheFinalShortSentence() async throws {
        let speech = SwissContextSpeech()
        let pipeline = ProcessingPipeline(speech: speech, formatter: SwissIdentityFormatter())
        let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: 6 * 16000), sessionID: UUID(), style: .original)
        XCTAssertEqual(result.text, "Bitte nicht senden.")
        let windows = await speech.windows
        XCTAssertEqual(windows, [0..<96000])
    }
    func testSwissContextStillBoundsLongWindowsAndRetainsTheTail() async throws {
        let speech = SwissContextSpeech()
        let pipeline = ProcessingPipeline(speech: speech, formatter: SwissIdentityFormatter())
        _ = try await pipeline.process(samples: [Float](repeating: 0.1, count: 61 * 16000), sessionID: UUID(), style: .original)
        let windows = await speech.windows
        XCTAssertGreaterThan(windows.count, 1)
        XCTAssertEqual(windows.first?.lowerBound, 0); XCTAssertEqual(windows.last?.upperBound, 61 * 16000)
        XCTAssertTrue(windows.allSatisfy { $0.count <= 240000 })
    }
    func testSwissDoesNotRepeatedlyReconcileGrowingPrefixesWhileRecording() async throws {
        let speech = SwissContextSpeech()
        let pipeline = ProcessingPipeline(speech: speech, formatter: SwissIdentityFormatter())
        try await pipeline.start(style: .cleaned)
        try await pipeline.append(samples: [Float](repeating: 0.1, count: 80 * 16000))
        try await Task.sleep(for: .milliseconds(200))
        let beforeFinish = await speech.reconciliations
        XCTAssertEqual(beforeFinish, 0)
        let result = try await pipeline.finish()
        let afterFinish = await speech.reconciliations
        XCTAssertEqual(afterFinish, 1); XCTAssertEqual(result.text, "Bitte nicht senden.")
    }
    func testHelperTimeoutAndCancellationStopAnUncooperativeChild() async throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("swiss-helper-\(UUID()).py")
        try Data("import sys,signal,time\nsignal.signal(signal.SIGTERM,signal.SIG_IGN)\nsys.stdin.buffer.read()\ntime.sleep(60)\n".utf8).write(to: script)
        defer { try? FileManager.default.removeItem(at: script) }
        let python = ProcessInfo.processInfo.environment["VOICE_TEST_PYTHON"] ?? "/usr/bin/python3"
        let helper = WhisperLanguageFallback(executable: URL(fileURLWithPath: python), model: script)
        let began = Date()
        do { _ = try await helper.transcribe([Float](repeating: 0, count: 16000), language: "de", sessionID: UUID(), index: 0, offset: 0, timeout: 0.4); XCTFail("Expected timeout") }
        catch let error as SpeechDecoderError { if case .timeout = error {} else { XCTFail("Wrong decoder error") } }
        XCTAssertLessThan(Date().timeIntervalSince(began), 8)
        let task = Task { try await helper.transcribe([Float](repeating: 0, count: 16000), language: "de", sessionID: UUID(), index: 0, offset: 0) }
        try await Task.sleep(for: .milliseconds(400)); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(began), 15)
    }
}
private struct SwissIdentityFormatter: TextFormatting {
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String { text }
}
private actor SwissContextSpeech: SpeechTranscribing, SpeechActivityDetecting, SpeechPipelinePreferences, SpeechSessionReconciling {
    nonisolated var minimumNaturalSegmentSamples: Int { 128000 }
    nonisolated var allowsFormattingCheckpoints: Bool { false }
    var reconciliations = 0
    var windows: [Range<Int>] = []
    func prepare() async throws {}
    func detectActivity(samples: [Float], state: SpeechActivityState) async throws -> SpeechActivityResult { .init(state: state, speechEnded: true) }
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        let begin = Int((offset * 16000).rounded()); windows.append(begin..<(begin + samples.count))
        let words = ["Bitte", "nicht", "senden."]
        let center = offset + Double(samples.count) / 32000
        return .init(sessionID: sessionID, index: index, text: words.joined(separator: " "), words: words.map { .init(text: $0, start: center, end: center + 0.01) })
    }
    func reconcile(samples: [Float], sessionID: UUID) async throws -> TranscriptSegment {
        reconciliations += 1
        return .init(sessionID: sessionID, index: 0, text: "Bitte nicht senden.")
    }
}
