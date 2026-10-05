import XCTest
@testable import VoiceWisprCore

private actor SeamProbeSpeech: SpeechTranscribing {
    var ranges: [Range<Int>] = []
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        let lower = Int((offset * 16_000).rounded())
        ranges.append(lower..<(lower + samples.count))
        let middle = offset + Double(samples.count) / 32_000
        return .init(sessionID: sessionID, index: index, text: "Wort\(index)", words: [.init(text: "Wort\(index)", start: middle, end: middle)])
    }
}
private actor SeamProbeFormatter: TextFormatting {
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String { text }
}

final class SeamTests: XCTestCase {
    private func word(_ text: String, _ start: Double, _ end: Double) -> TranscriptWord {
        .init(text: text, start: start, end: end)
    }
    private func selection(_ words: [TranscriptWord], _ bounds: Range<Int>, previous: [ProcessingPipeline.SeamWord] = []) throws -> ProcessingPipeline.SeamSelection {
        try ProcessingPipeline.selectSeamWords(segment: .init(sessionID: UUID(), index: 0, text: words.map(\.text).joined(separator: " "), words: words), bounds: bounds, requiresTimings: true, previous: previous)
    }
    func testObservedDieTimestampShiftDoesNotDuplicateSeamWord() throws {
        // Exact acoustic times from the hash-verified 77-second synthetic recording.
        let prior = try selection([word("Mac,", 41.50, 41.90), word("die", 41.90, 42.06), word("ausführlichen.", 42.06, 42.46)], 448_000..<672_000)
        let next = try selection([word("Mac.", 41.74, 42.22), word("Die", 42.22, 42.38), word("Aufnahme", 42.38, 42.94)], 672_000..<896_000, previous: prior.window)
        XCTAssertEqual(prior.text, "Mac, die")
        XCTAssertEqual(next.text, "Aufnahme")
        XCTAssertEqual(next.words.map(\.text), ["Aufnahme"])
    }
    func testObservedEinfügenTimestampShiftRetainsRightContextWordOnce() throws {
        let prior = try selection([word("das", 55.34, 55.50), word("Einfügen", 55.50, 55.98), word("in", 55.98, 56.06)], 672_000..<896_000)
        let next = try selection([word("Einfügen", 55.74, 56.38), word("in", 56.38, 56.54), word("verschiedenen", 56.54, 57.18)], 896_000..<1_120_000, previous: prior.window)
        XCTAssertEqual(prior.text, "das Einfügen")
        XCTAssertEqual(next.text, "in verschiedenen")
    }
    func testPriorRightContextRescuesWordThatShiftsLeftOfCut() throws {
        let prior = try selection([word("drei", 13.60, 13.84), word("Bücher.", 13.84, 14.24)], 0..<224_000)
        let next = try selection([word("Drei", 13.54, 13.70), word("Bücher", 13.70, 14.10), word("für", 14.10, 14.30)], 224_000..<448_000, previous: prior.window)
        XCTAssertEqual(prior.text, "drei")
        XCTAssertEqual(next.text, "Bücher für")
        XCTAssertEqual(next.words.map(\.text), ["Bücher", "für"])
    }
    func testLegitimateDoubleWordIsPreservedAcrossCut() throws {
        let prior = try selection([word("sehr", 13.65, 13.95), word("sehr", 14.05, 14.35)], 0..<224_000)
        let next = try selection([word("sehr", 13.80, 14.10), word("sehr", 14.20, 14.50), word("gut", 14.50, 14.80)], 224_000..<448_000, previous: prior.window)
        XCTAssertEqual(prior.text + " " + next.text, "sehr sehr gut")
    }
    func testUnseenIntentionalRepeatUsesOneToOneClosestAnchor() throws {
        let prior = try selection([word("sehr", 13.60, 13.90)], 0..<224_000)
        let next = try selection([word("sehr", 13.70, 14.00), word("sehr", 14.10, 14.40), word("gut", 14.50, 14.80)], 224_000..<448_000, previous: prior.window)
        XCTAssertEqual(prior.text + " " + next.text, "sehr sehr gut")
    }
    func testMissingAnchorKeepsAcousticOwnershipWithoutGlobalDeduplication() throws {
        let prior = try selection([word("ein", 13.50, 13.70), word("anderes", 13.70, 13.95)], 0..<224_000)
        let next = try selection([word("unbekannt", 13.60, 13.90), word("neues", 14.10, 14.30), word("neues", 15.20, 15.50)], 224_000..<448_000, previous: prior.window)
        XCTAssertEqual(next.text, "neues neues")
    }
    func testRightContextWaitsUntilItsOwningInterval() throws {
        let prior = try selection([word("Hallo", 13.70, 14.30), word("Welt", 14.30, 14.70)], 0..<224_000)
        let narrow = try selection([word("Hallo", 13.60, 13.80), word("Welt", 14.00, 14.20)], 224_000..<225_600, previous: prior.window)
        XCTAssertEqual(prior.text, "")
        XCTAssertEqual(narrow.text, "Hallo")
        XCTAssertFalse(narrow.window[1].committed)
    }
    func testSameWordBeyondOverlapIsAnIndependentOccurrence() throws {
        let prior = try selection([word("wieder", 12.80, 13.00)], 0..<224_000)
        let next = try selection([word("wieder", 14.20, 14.40)], 224_000..<448_000, previous: prior.window)
        XCTAssertEqual(prior.text + " " + next.text, "wieder wieder")
    }
    func testDeferredOwnershipSurvivesMultipleShortPauseWindows() throws {
        let initial = try selection([word("Welt", 14.30, 14.70)], 0..<224_000)
        let firstPause = try selection([word("Welt", 13.90, 14.12)], 224_000..<225_600, previous: initial.window)
        let secondPause = try selection([word("Welt", 14.00, 14.20)], 225_600..<228_800, previous: firstPause.window)
        let final = try selection([word("Welt", 14.20, 14.50)], 228_800..<233_600, previous: secondPause.window)
        XCTAssertEqual(initial.text + firstPause.text + secondPause.text, "")
        XCTAssertEqual(final.text, "Welt")
    }
    func testLoneDisjointRepeatCannotBeSuppressedAsDuplicate() throws {
        let prior = try selection([word("sehr", 13.65, 13.95)], 0..<224_000)
        let next = try selection([word("sehr", 14.05, 14.35)], 224_000..<448_000, previous: prior.window)
        XCTAssertEqual(prior.text + " " + next.text, "sehr sehr")
    }
    func testEightSecondExperimentCoversAudioWithNineSecondDecodeLimit() async throws {
        let speech = SeamProbeSpeech()
        let pipeline = ProcessingPipeline(speech: speech, formatter: SeamProbeFormatter(), coreSamples: 128_000)
        let count = 16_000 * 60 + 97
        let result = try await pipeline.process(samples: [Float](repeating: 0.1, count: count), sessionID: UUID(), style: .original)
        let ranges = await speech.ranges
        XCTAssertEqual(ranges.count, 8)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, count)
        XCTAssertTrue(ranges.allSatisfy { $0.count <= 144_000 })
        for pair in zip(ranges, ranges.dropFirst()) { XCTAssertTrue(pair.1.lowerBound <= pair.0.upperBound) }
        XCTAssertEqual(result.duration, Double(count) / 16_000, accuracy: 0.000001)
    }
    func testOneSecondOverlapCoversAudioWithoutExceedingFifteenSeconds() async throws {
        let speech = SeamProbeSpeech()
        let pipeline = ProcessingPipeline(speech: speech, formatter: SeamProbeFormatter(), coreSamples: 128_000, overlapSamples: 16_000)
        let count = 16_000 * 60 + 4095
        _ = try await pipeline.process(samples: [Float](repeating: 0.1, count: count), sessionID: UUID(), style: .original)
        let ranges = await speech.ranges
        XCTAssertEqual(ranges.count, 8)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, count)
        XCTAssertTrue(ranges.allSatisfy { $0.count <= 160_000 })
        for pair in zip(ranges, ranges.dropFirst()) { XCTAssertTrue(pair.1.lowerBound <= pair.0.upperBound) }
    }
}
