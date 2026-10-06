import XCTest
@testable import VoiceWisprCore

private actor RevisionSpeech: SpeechTranscribing, SpeechSessionReconciling {
    let old: String
    let final: String
    init(old: String, final: String) { self.old = old; self.final = final }
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        let text = index == 0 ? old : ""
        let words = text.split(separator: " ").enumerated().map { TranscriptWord(text: String($0.element), start: offset + Double($0.offset) * 0.2, end: offset + Double($0.offset) * 0.2 + 0.1) }
        return .init(sessionID: sessionID, index: index, text: text, words: words)
    }
    func reconcile(samples: [Float], sessionID: UUID) async throws -> TranscriptSegment { .init(sessionID: sessionID, index: 0, text: final) }
}
private actor RevisionFormatter: TextFormatting {
    private(set) var inputs: [String] = []
    let failOn: String?
    init(failOn: String? = nil) { self.failOn = failOn }
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        inputs.append(text)
        if let failOn, text.contains(failOn) { throw VoiceError.message("Revision failed") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
private actor RevisionPunctuationFormatter: TextFormatting {
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasSuffix(",") ? String(text.dropLast()) + "." : text
    }
}
private actor RevisionEndFormatter: TextFormatting {
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = value.last, ".,!?;:".contains(last) { value.removeLast() }
        return value + "."
    }
}

/// Deliberately completes late, even after cancellation, to test the session fence.
private actor DelayedRevisionFormatter: TextFormatting {
    private var entered = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var parked: CheckedContinuation<Void, Never>?
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        if text.contains("nicht") {
            entered = true
            observers.forEach { $0.resume() }; observers = []
            await withCheckedContinuation { parked = $0 }
        }
        return text
    }
    func waitForRevision() async {
        if entered { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { parked?.resume(); parked = nil }
}

private actor PendingFirstFormatter: TextFormatting {
    private var entered = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var parked: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        calls += 1
        if calls == 1 {
            entered = true; observers.forEach { $0.resume() }; observers = []
            await withCheckedContinuation { parked = $0 }
        }
        return text
    }
    func waitForEntry() async { if !entered { await withCheckedContinuation { observers.append($0) } } }
    func release() { parked?.resume(); parked = nil }
}

final class FormattingRevisionTests: XCTestCase {
    private let old = "Wir prüfen heute gemeinsam den Entwurf und warten vor dem Versand auf die Rückmeldung von Fabian danach legen wir die Dokumente lokal ab"
    private var final: String { old.replacingOccurrences(of: "vor dem Versand", with: "nicht vor dem Versand") }
    private func assemble(_ plan: FormattingRevision.Plan) -> String {
        plan.pieces.map { piece in switch piece { case .reuse(let s), .revise(let s): s } }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func testEnglishRevisionDoesNotReopenGermanSentence() throws {
        let german = "Wir prüfen heute den Entwurf und warten vor dem Versand auf die Rückmeldung."
        let english = "Please keep the draft on this computer until we have received approval."
        let targetEnglish = english.replacingOccurrences(of: "draft", with: "report")
        let plan = try XCTUnwrap(FormattingRevision.plan(target: german + " " + targetEnglish, cache: [.init(input: german, output: german, formatted: true), .init(input: english, output: english, formatted: true)]))
        XCTAssertEqual(assemble(plan), german + " " + targetEnglish)
        XCTAssertTrue(plan.pieces.allSatisfy { if case .revise(let s) = $0 { return !s.contains("Rückmeldung") }; return true })
        XCTAssertEqual(ProcessingPipeline.lexicalSequence(assemble(plan)), ProcessingPipeline.lexicalSequence(german + " " + targetEnglish))
    }
    func testArtificialRevisionEndDoesNotSplitUnchangedWordPair() async throws {
        let input = "Lion acts much like packs of wolves or dogs in the wild."
        let target = input.replacingOccurrences(of: "acts much", with: "acts often much")
        let plan = try XCTUnwrap(FormattingRevision.plan(target: target, cache: [.init(input: input, output: input, formatted: true)]))
        XCTAssertTrue(plan.trailingSeparators.values.contains(""))
        let result = try await FormattingRevision.render(plan: plan, target: target, formatter: RevisionEndFormatter(), style: .cleaned, dictionary: DictionaryMatcher([]))
        XCTAssertEqual(result.0, target)
        XCTAssertFalse(result.1)
        XCTAssertFalse(result.0.contains("like. packs"))
    }
    func testRevisionKeepsValidatedSentenceQuestionAndCommaSeparators() async throws {
        for separator in [".", "?", ",", ":"] {
            let input = "We keep the report here Please wait for the final decision."
            let output = input.replacingOccurrences(of: "here Please", with: "here\(separator) Please")
            let target = input.replacingOccurrences(of: "the report", with: "the new report")
            let plan = try XCTUnwrap(FormattingRevision.plan(target: target, cache: [.init(input: input, output: output, formatted: true)]))
            XCTAssertTrue(plan.trailingSeparators.values.contains(separator))
            let result = try await FormattingRevision.render(plan: plan, target: target, formatter: RevisionEndFormatter(), style: .cleaned, dictionary: DictionaryMatcher([]))
            XCTAssertEqual(result.0, target.replacingOccurrences(of: "here Please", with: "here\(separator) Please"))
            XCTAssertFalse(result.1)
        }
    }
    func testExplicitRelativeClauseCommaOverridesCachedPeriod() async throws {
        let target = "Ein weiterer Satz am Gaumen, was bedeutete, dass es kein Entkommen gab."
        let plan = FormattingRevision.Plan(pieces: [.reuse("Ein weiterer"), .revise("Satz am Gaumen, was bedeutete,"), .reuse(" dass es kein Entkommen gab.")], reusedWords: 8, revisedWords: 5, trailingSeparators: [1: "."])
        let result = try await FormattingRevision.render(plan: plan, target: target, formatter: RevisionEndFormatter(), style: .cleaned, dictionary: DictionaryMatcher([]))
        XCTAssertTrue(result.0.contains("bedeutete, dass"))
        XCTAssertFalse(result.1)
    }
    func testLiteralAndQuotedRevisionBoundariesCannotAuthorizeSeparators() throws {
        for literal in ["https://example.org/a", "12.5", "U.S.", "\"like\"", "'like'", "’like’", "'like", "like'", "@someone"] {
            // The unchanged pair at the artificial end contains a literal.
            let input = "We keep the \(literal) here until the final decision arrives."
            let target = input.replacingOccurrences(of: "keep the", with: "often keep the")
            let plan = try XCTUnwrap(FormattingRevision.plan(target: target, cache: [.init(input: input, output: input, formatted: true)]))
            XCTAssertTrue(plan.trailingSeparators.isEmpty)
            XCTAssertEqual(ProcessingPipeline.lexicalSequence(assemble(plan)), ProcessingPipeline.lexicalSequence(target))
        }
    }
    func testInternalApostropheStillAllowsVerifiedBoundaryReuse() async throws {
        for word in ["don't", "don’t"] {
            let input = "We explain why we \(word) change the settings again today."
            let target = input.replacingOccurrences(of: "why we", with: "why sometimes we")
            let plan = try XCTUnwrap(FormattingRevision.plan(target: target, cache: [.init(input: input, output: input, formatted: true)]))
            XCTAssertTrue(plan.trailingSeparators.values.contains(""))
            let result = try await FormattingRevision.render(plan: plan, target: target, formatter: RevisionEndFormatter(), style: .cleaned, dictionary: DictionaryMatcher([]))
            XCTAssertEqual(result.0, target)
            XCTAssertFalse(result.1)
        }
    }
    func testNonconsecutiveCachePairAndParagraphCutCannotAuthorizeSeparator() throws {
        for input in ["Lion acts much like old packs of wolves or dogs in the wild.", "Lion acts much like\n\npacks of wolves or dogs in the wild."] {
            let target = input.replacingOccurrences(of: "acts much", with: "acts often much").replacingOccurrences(of: "old packs", with: "packs")
            let plan = try XCTUnwrap(FormattingRevision.plan(target: target, cache: [.init(input: input, output: input, formatted: true)]))
            if input.contains("\n") { XCTAssertTrue(plan.trailingSeparators.isEmpty) }
            else {
                // Removing an old intervening word prevents anchoring its former cut.
                XCTAssertFalse(plan.pieces.enumerated().contains { index, piece in
                    if case .revise(let text) = piece, text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("like") { return plan.trailingSeparators[index] != nil }
                    return false
                })
            }
        }
    }
    func testFinalDictationEndStillAllowsSentenceCompletion() async throws {
        let input = "We keep the report on this computer until approval"
        let target = input.replacingOccurrences(of: "approval", with: "final approval")
        let plan = try XCTUnwrap(FormattingRevision.plan(target: target, cache: [.init(input: input, output: input, formatted: true)]))
        XCTAssertTrue(plan.trailingSeparators.isEmpty)
        let result = try await FormattingRevision.render(plan: plan, target: target, formatter: RevisionEndFormatter(), style: .cleaned, dictionary: DictionaryMatcher([]))
        XCTAssertEqual(result.0, target + ".")
        XCTAssertFalse(result.1)
    }
    func testRevisionKeepsCommaBeforeRetainedRelativeClause() async throws {
        let target = "Ein weiterer Satz am Gaumen, was bedeutete, dass es kein Entkommen gab."
        let plan = FormattingRevision.Plan(pieces: [.reuse("Ein weiterer"), .revise("Satz am Gaumen, was bedeutete,"), .reuse(" dass es kein Entkommen gab.")], reusedWords: 8, revisedWords: 5)
        let value = try await FormattingRevision.render(plan: plan, target: target, formatter: RevisionPunctuationFormatter(), style: .cleaned, dictionary: DictionaryMatcher([]))
        XCTAssertEqual(value.0, target)
        XCTAssertFalse(value.1)
        XCTAssertTrue(value.0.contains("bedeutete, dass"))
    }
    func testRevisionDoesNotForceCommaWithoutFollowingRelativeClause() async throws {
        let target = "Wir prüfen heute den Entwurf, danach warten wir auf die Rückmeldung."
        let plan = FormattingRevision.Plan(pieces: [.revise("Wir prüfen heute den Entwurf,"), .reuse(" danach warten wir auf die Rückmeldung.")], reusedWords: 7, revisedWords: 6)
        let value = try await FormattingRevision.render(plan: plan, target: target, formatter: RevisionPunctuationFormatter(), style: .cleaned, dictionary: DictionaryMatcher([]))
        XCTAssertEqual(value.0, "Wir prüfen heute den Entwurf. danach warten wir auf die Rückmeldung.")
        XCTAssertFalse(value.1)
    }
    func testOnlyChangedNeighbourhoodIsRevisedAndAllFinalWordsRemain() throws {
        let plan = try XCTUnwrap(FormattingRevision.plan(target: final, cache: [.init(input: old, output: old, formatted: true)]))
        XCTAssertGreaterThan(plan.reusedWords, plan.revisedWords)
        XCTAssertEqual(ProcessingPipeline.lexicalSequence(assemble(plan)), ProcessingPipeline.lexicalSequence(final))
        XCTAssertTrue(plan.pieces.contains { if case .revise(let s) = $0 { return s.contains("nicht") }; return false })
    }
    func testAChangedSignDecimalAndURLCannotReuseOldLiterals() throws {
        let input = old + " mit 12,5 Euro und https://example.org/a"
        let target = input.replacingOccurrences(of: "12,5", with: "-12.5").replacingOccurrences(of: "/a", with: "/b")
        let plan = try XCTUnwrap(FormattingRevision.plan(target: target, cache: [.init(input: input, output: input, formatted: true)]))
        let text = assemble(plan)
        XCTAssertTrue(text.contains("-12.5")); XCTAssertTrue(text.contains("https://example.org/b"))
        XCTAssertFalse(text.contains("12,5")); XCTAssertFalse(text.contains("https://example.org/a"))
    }
    func testNoUnvalidatedCacheOrFullSecondPass() {
        XCTAssertNil(FormattingRevision.plan(target: final, cache: [.init(input: old, output: old + " Neue Fakten", formatted: true)]))
        XCTAssertNil(FormattingRevision.plan(target: final, cache: [.init(input: old, output: old, formatted: false)]))
        XCTAssertNil(FormattingRevision.plan(target: "Ein vollständig anderer Inhalt bleibt maßgeblich", cache: [.init(input: old, output: old, formatted: true)]))
    }
    func testRemovedMentionsEmojiAndSeparateSignsNeverReturnFromCache() throws {
        let input = old + " @ Name🙂 - 12 Euro"
        let target = old + " Name 12 Euro"
        let plan = try XCTUnwrap(FormattingRevision.plan(target: target, cache: [.init(input: input, output: input, formatted: true)]))
        let text = assemble(plan)
        XCTAssertFalse(text.contains("@")); XCTAssertFalse(text.contains("🙂")); XCTAssertFalse(text.contains(" - "))
        XCTAssertEqual(ProcessingPipeline.lexicalSequence(text), ProcessingPipeline.lexicalSequence(target))
    }
    func testValidatedFormatterAddedListMarkersSurviveRevision() throws {
        let output = "- " + old.replacingOccurrences(of: "danach legen", with: "\n- danach legen")
        let plan = try XCTUnwrap(FormattingRevision.plan(target: final, cache: [.init(input: old, output: output, formatted: true)]))
        let text = assemble(plan)
        XCTAssertTrue(text.hasPrefix("- ")); XCTAssertTrue(text.contains("\n- danach"))
        XCTAssertEqual(ProcessingPipeline.lexicalSequence(text), ProcessingPipeline.lexicalSequence(final))
    }
    func testChangedPartsAreBoundedAndRepeatedWordsStayOrdered() throws {
        let input = Array(repeating: "Anfang Mitte Ende", count: 12).joined(separator: " ")
        let target = "Anfang " + Array(repeating: "neu", count: 70).joined(separator: " ") + " Mitte Ende " + input
        let plan = try XCTUnwrap(FormattingRevision.plan(target: target, cache: [.init(input: input, output: input, formatted: true)]))
        XCTAssertEqual(ProcessingPipeline.lexicalSequence(assemble(plan)), ProcessingPipeline.lexicalSequence(target))
        XCTAssertTrue(plan.pieces.allSatisfy { if case .revise(let text) = $0 { return text.split(whereSeparator: \.isWhitespace).count <= 40 }; return true })
    }
    func testPipelineFormatsCorrectedPartAndKeepsVerifiedNegation() async throws {
        let formatter = RevisionFormatter()
        let pipeline = ProcessingPipeline(speech: RevisionSpeech(old: old, final: final), formatter: formatter)
        let result = try await pipeline.process(samples: Array(repeating: 0.1, count: 256_000), sessionID: UUID(), style: .cleaned)
        XCTAssertEqual(result.original, final)
        XCTAssertEqual(ProcessingPipeline.lexicalSequence(result.text), ProcessingPipeline.lexicalSequence(final))
        XCTAssertFalse(result.usedFallback)
        let inputs = await formatter.inputs
        XCTAssertTrue(inputs.contains { $0.contains("nicht") })
        XCTAssertFalse(inputs.contains(final))
    }
    func testFailedRevisionReturnsCompleteVerifiedTextWithVisibleFallback() async throws {
        let pipeline = ProcessingPipeline(speech: RevisionSpeech(old: old, final: final), formatter: RevisionFormatter(failOn: "nicht"))
        let result = try await pipeline.process(samples: Array(repeating: 0.1, count: 256_000), sessionID: UUID(), style: .cleaned)
        XCTAssertEqual(ProcessingPipeline.lexicalSequence(result.text), ProcessingPipeline.lexicalSequence(final))
        XCTAssertTrue(result.usedFallback); XCTAssertTrue(result.isComplete)
    }
    func testCancelDuringRevisionRejectsLateResult() async throws {
        let formatter = DelayedRevisionFormatter()
        let pipeline = ProcessingPipeline(speech: RevisionSpeech(old: old, final: final), formatter: formatter)
        let task = Task { try await pipeline.process(samples: Array(repeating: Float(0.1), count: 256_000), sessionID: UUID(), style: .cleaned) }
        await formatter.waitForRevision()
        await pipeline.cancel()
        await formatter.release()
        do { _ = try await task.value; XCTFail("Cancelled revision must not deliver") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    func testOriginalDuringRevisionReturnsVerifiedTextOnly() async throws {
        let formatter = DelayedRevisionFormatter()
        let pipeline = ProcessingPipeline(speech: RevisionSpeech(old: old, final: final), formatter: formatter)
        let task = Task { try await pipeline.process(samples: Array(repeating: Float(0.1), count: 256_000), sessionID: UUID(), style: .cleaned) }
        await formatter.waitForRevision()
        await pipeline.requestOriginal()
        await formatter.release()
        let result = try await task.value
        XCTAssertEqual(result.text, final)
        XCTAssertTrue(result.usedFallback); XCTAssertTrue(result.isComplete)
    }
    func testFinalRecognitionWaitsForUsefulPendingCache() async throws {
        let formatter = PendingFirstFormatter()
        let pipeline = ProcessingPipeline(speech: RevisionSpeech(old: old, final: final), formatter: formatter)
        let task = Task { try await pipeline.process(samples: [Float](repeating: 0.1, count: 256_000), sessionID: UUID(), style: .cleaned) }
        await formatter.waitForEntry()
        await formatter.release()
        let result = try await task.value
        XCTAssertEqual(ProcessingPipeline.lexicalSequence(result.text), ProcessingPipeline.lexicalSequence(final))
        XCTAssertFalse(result.usedFallback)
        let calls = await formatter.calls
        XCTAssertGreaterThan(calls, 1)
    }
    func testOriginalDoesNotWaitForUncooperativePendingCache() async throws {
        let formatter = PendingFirstFormatter()
        let pipeline = ProcessingPipeline(speech: RevisionSpeech(old: old, final: final), formatter: formatter)
        let task = Task { try await pipeline.process(samples: [Float](repeating: 0.1, count: 256_000), sessionID: UUID(), style: .cleaned) }
        await formatter.waitForEntry()
        await pipeline.requestOriginal()
        let result = try await task.value
        XCTAssertEqual(result.text, final); XCTAssertTrue(result.usedFallback)
        await formatter.release()
    }
    func testCancellationReleasesPendingCacheWithoutLateDelivery() async throws {
        let formatter = PendingFirstFormatter()
        let pipeline = ProcessingPipeline(speech: RevisionSpeech(old: old, final: final), formatter: formatter)
        let task = Task { try await pipeline.process(samples: [Float](repeating: 0.1, count: 256_000), sessionID: UUID(), style: .cleaned) }
        await formatter.waitForEntry()
        await pipeline.cancel()
        do { _ = try await task.value; XCTFail("Cancelled formatting cannot deliver") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        await formatter.release()
    }
}
