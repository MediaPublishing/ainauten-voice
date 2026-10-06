import XCTest
@testable import VoiceWisprCore

private actor WindowSpeech: SpeechTranscribing {
    let sections: [String]
    init(_ sections: [String]) { self.sections = sections }
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        let text = sections[index]
        let time = offset + Double(samples.count) / 32_000
        return .init(sessionID: sessionID, index: index, text: text,
                     words: text.split(separator: " ").map { .init(text: String($0), start: time, end: time) })
    }
}
private actor WindowFormatter: TextFormatting {
    let failContinuation: Bool
    private(set) var inputs: [String] = []
    init(failContinuation: Bool = false) { self.failContinuation = failContinuation }
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        inputs.append(text)
        if text.contains("Form. Bringen") {
            if failContinuation { throw VoiceError.message("Test: Optimierung fehlgeschlagen") }
            return text.replacingOccurrences(of: "Form. Bringen", with: "Form bringen")
        }
        return text
    }
}
final class FormattingWindowTests: XCTestCase {
    func testPipelineKeepsLanguageSwitchInSeparateFormattingCalls() async throws {
        let german = "Wir prüfen heute den Entwurf und warten vor dem Versand auf die Rückmeldung."
        let english = "Please keep the report on this computer until we have received approval."
        for sections in [[german, english], [english, german]] {
            let formatter = WindowFormatter()
            let pipeline = ProcessingPipeline(speech: WindowSpeech(sections), formatter: formatter, coreSamples: 16_000, overlapSamples: 0)
            let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: 32_000), sessionID: UUID(), style: .cleaned)
            XCTAssertEqual(result.text, sections.joined(separator: " "))
            XCTAssertEqual(result.original, sections.joined(separator: " "))
            XCTAssertFalse(result.usedFallback)
            let inputs = await formatter.inputs
            XCTAssertFalse(inputs.contains { $0.contains("Rückmeldung") && $0.contains("approval") })
            XCTAssertGreaterThan(inputs.count, 1)
        }
    }
    func testCompleteLanguageSwitchDoesNotReopenVerifiedSentence() throws {
        let german = "Wir prüfen heute den Entwurf und warten vor dem Versand auf die Rückmeldung."
        let english = "Please keep the report on this computer until we have received approval."
        XCTAssertTrue(FormattingWindow.hasLanguageBoundary(previous: german, next: english))
        XCTAssertTrue(FormattingWindow.hasLanguageBoundary(previous: english, next: german))
        XCTAssertNil(FormattingWindow.continuation(previous: .init(input: german, output: german, formatted: true), next: english))
        XCTAssertNil(FormattingWindow.continuation(previous: .init(input: english, output: english, formatted: true), next: german))
    }
    func testAmbiguousShortOrUnfinishedSpeechKeepsContinuation() throws {
        let german = "Wir prüfen heute den Entwurf und warten vor dem Versand auf die Rückmeldung."
        let english = "Please keep the report on this computer until we have received approval."
        XCTAssertFalse(FormattingWindow.hasLanguageBoundary(previous: "Wir warten.", next: english))
        XCTAssertFalse(FormattingWindow.hasLanguageBoundary(previous: german, next: "Please wait."))
        XCTAssertFalse(FormattingWindow.hasLanguageBoundary(previous: String(german.dropLast()), next: english))
        XCTAssertFalse(FormattingWindow.hasLanguageBoundary(previous: german, next: english.lowercased()))
        _ = try XCTUnwrap(FormattingWindow.continuation(previous: .init(input: german, output: german, formatted: true), next: "Danach prüfen wir alles noch einmal."))
        _ = try XCTUnwrap(FormattingWindow.continuation(previous: .init(input: "Das Ganze in eine saubere Form.", output: "Das Ganze in eine saubere Form.", formatted: true), next: "Bringen und als Goal definieren lassen."))
    }
    func testLanguageBoundaryUsesLastAndFirstSentencesOnly() {
        let german = "Wir prüfen heute den Entwurf und warten vor dem Versand auf die Rückmeldung."
        let english = "Please keep the report on this computer until we have received approval."
        XCTAssertTrue(FormattingWindow.hasLanguageBoundary(previous: english + " " + german, next: english + " " + german))
        XCTAssertFalse(FormattingWindow.hasLanguageBoundary(previous: german + " " + english, next: english + " " + german))
        XCTAssertEqual(FormattingWindow.languageBoundaryOffsets(in: german + " " + english), [(german as NSString).length + 1])
    }
    func testContinuationCanRemoveAPausePointAcrossCaptureSections() async throws {
        let sections = ["Das Ganze in eine saubere Form.", "Bringen und als Goal definieren lassen."]
        let pipeline = ProcessingPipeline(speech: WindowSpeech(sections), formatter: WindowFormatter(), coreSamples: 16_000, overlapSamples: 0)
        let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: 32_000), sessionID: UUID(), style: .cleaned)
        XCTAssertEqual(result.text, "Das Ganze in eine saubere Form bringen und als Goal definieren lassen.")
        XCTAssertEqual(result.original, sections.joined(separator: " "))
        XCTAssertFalse(result.usedFallback)
    }
    func testFailureKeepsPreviousResultAndAllNewWords() async throws {
        let sections = ["Das Ganze in eine saubere Form.", "Bringen und als Goal definieren lassen."]
        let pipeline = ProcessingPipeline(speech: WindowSpeech(sections), formatter: WindowFormatter(failContinuation: true), coreSamples: 16_000, overlapSamples: 0)
        let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: 32_000), sessionID: UUID(), style: .cleaned)
        XCTAssertEqual(result.text, sections.joined(separator: " "))
        XCTAssertTrue(result.usedFallback)
    }
    func testOnlyBoundedSentenceSuffixIsReopenedAndPrefixStaysIntact() throws {
        let prefix = Array(repeating: "Ein vollständiger Satz bleibt erhalten.", count: 20).joined(separator: " ")
        let input = prefix + " Bitte nicht 12,5 Euro senden. Wir warten."
        let next = "Danach prüfen wir https://example.org/a."
        let window = try XCTUnwrap(FormattingWindow.continuation(previous: .init(input: input, output: input, formatted: true), next: next, maximumWords: 20))
        XCTAssertTrue(window.prefixOutput.hasPrefix(prefix))
        XCTAssertTrue(window.input.contains("nicht 12,5 Euro"))
        XCTAssertTrue(try FormattingGrammar.atoms(window.input).count <= 20)
        XCTAssertEqual(try LocalFormatter.validate(window.prefixOutput + window.input, original: input + " " + next, vocabulary: []), window.prefixOutput + window.input)
    }
    func testFillersDoNotShiftSuffixIntoWrongWords() throws {
        let prefix = Array(repeating: "Ein Satz bleibt erhalten.", count: 8).joined(separator: " ")
        let input = "Ähm " + prefix + " Äh bitte nicht senden. Wir warten."
        let output = prefix + " Bitte nicht senden. Wir warten."
        let window = try XCTUnwrap(FormattingWindow.continuation(previous: .init(input: input, output: output, formatted: true), next: "Danach prüfen wir.", maximumWords: 14))
        XCTAssertTrue(window.input.lowercased().contains("bitte nicht senden"))
        XCTAssertEqual(ProcessingPipeline.lexicalSequence(window.prefixInput + window.input).filter { !["äh", "ähm"].contains($0) }, ProcessingPipeline.lexicalSequence(output + " Danach prüfen wir."))
    }
    func testUnvalidatedCacheAndOversizedClauseCannotAuthorizeRevision() {
        XCTAssertNil(FormattingWindow.continuation(previous: .init(input: "Nicht senden", output: "Senden", formatted: true), next: "Heute."))
        let long = Array(repeating: "Wort", count: 50).joined(separator: " ")
        XCTAssertNil(FormattingWindow.continuation(previous: .init(input: long, output: long, formatted: true), next: "Danach prüfen.", maximumWords: 10))
    }
    func testFinalRevisionDoesNotReopenAnEntireAlreadyVerifiedPrefix() {
        let prefix = "Der geprüfte Anfang bleibt unverändert und wird vollständig erhalten"
        XCTAssertNil(FormattingWindow.continuation(previous: .init(input: prefix, output: prefix, formatted: true), next: "danach prüfen wir", preservePrefix: true))
    }
    func testLongParagraphsReceiveWhitespaceOnlyBreaksAndExistingLayoutsStay() {
        let source = Array(repeating: "Wir prüfen den Entwurf und warten vor dem Versand auf die Rückmeldung.", count: 8).joined(separator: " ")
        let result = ParagraphLayout.apply(source, style: .cleaned)
        XCTAssertTrue(result.contains("\n\n"))
        XCTAssertEqual(result.filter { !$0.isWhitespace }, source.filter { !$0.isWhitespace })
        XCTAssertEqual(ParagraphLayout.apply(result, style: .cleaned), result)
        XCTAssertEqual(ParagraphLayout.apply(source, style: .original), source)
        XCTAssertEqual(ParagraphLayout.apply("Bitte nicht senden. Wir warten.", style: .cleaned), "Bitte nicht senden. Wir warten.")
    }
    func testJoiningSectionsKeepsParagraphsWithoutDoubleSpaces() {
        XCTAssertEqual(ParagraphLayout.joinSections(["Ein Satz. ", " Noch einer. "]), "Ein Satz. Noch einer.")
        XCTAssertEqual(ParagraphLayout.joinSections(["Ein Absatz.\n\n", "Nächster Absatz."]), "Ein Absatz.\n\nNächster Absatz.")
        XCTAssertEqual(ParagraphLayout.joinSections(["Ein Absatz.", "\n\nNächster Absatz."]), "Ein Absatz.\n\nNächster Absatz.")
    }
    func testLongRenderedHistoryAndAddedBulletsStillAlign() throws {
        let prefix = Array(repeating: "Wir prüfen den Entwurf und warten.", count: 60).joined(separator: " ")
        let input = prefix + " Bitte nicht senden. Wir warten."
        let output = "- " + prefix + "\n- Bitte nicht senden. Wir warten."
        let next = "Danach prüfen wir."
        let window = try XCTUnwrap(FormattingWindow.continuation(previous: .init(input: input, output: output, formatted: true), next: next, maximumWords: 20, preservePrefix: true))
        XCTAssertTrue(window.input.contains("Bitte nicht senden"))
        XCTAssertTrue(window.prefixOutput.hasPrefix("- "))
        _ = try LocalFormatter.validate(ParagraphLayout.joinSections([window.prefixOutput, window.input]), original: input + " " + next, vocabulary: [])
    }
    func testSurvivingFillerSoundInDictionaryNameIsNotCutOff() throws {
        let prefix = Array(repeating: "Wir prüfen den Entwurf und warten.", count: 12).joined(separator: " ")
        let input = "Ähm " + prefix + " Ähm Han schreibt. Wir warten."
        let output = prefix + " Ähm Han schreibt. Wir warten."
        let window = try XCTUnwrap(FormattingWindow.continuation(previous: .init(input: input, output: output, formatted: true), next: "Danach prüfen wir.", maximumWords: 15))
        XCTAssertTrue(window.input.contains("Ähm Han"))
        _ = try LocalFormatter.validate(ParagraphLayout.joinSections([window.prefixOutput, window.input]), original: input + " Danach prüfen wir.", vocabulary: ["Ähm Han"])
    }
    func testOriginalDoesNotReformatSectionBoundaries() async throws {
        let sections = ["Form.", "Bringen und nicht senden."]
        let pipeline = ProcessingPipeline(speech: WindowSpeech(sections), formatter: WindowFormatter(), coreSamples: 16_000, overlapSamples: 0)
        let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: 32_000), sessionID: UUID(), style: .original)
        XCTAssertEqual(result.text, sections.joined(separator: " "))
    }
}
