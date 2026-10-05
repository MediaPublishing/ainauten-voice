import XCTest
@testable import VoiceWisprCore

final class ReconciliationBlocksTests: XCTestCase {
    func testProductionPolicyKeepsShortLatencyPathAndAddsLongContext() {
        var config = SpeechRuntimeConfiguration()
        XCTAssertNil(config.blockSeconds(for: 310 * 16_000))
        XCTAssertNil(config.blockSeconds(for: 600 * 16_000))
        XCTAssertEqual(config.blockSeconds(for: 601 * 16_000), 60)
        XCTAssertEqual(config.reconciliationContextSeconds, 8)
        config.reconciliationBlockSeconds = 30
        XCTAssertEqual(config.blockSeconds(for: 60 * 16_000), 30)
        let count = 20 * 60 * 16_000
        let blocks = ReconciliationBlocks.plan(Array(repeating: 0.1, count: count), coreSeconds: 60, contextSeconds: 8)
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.commit.count }, count)
        XCTAssertTrue(blocks.allSatisfy { $0.audio.count <= 81 * 16_000 })
    }
    func testTwentyMinutePlanOwnsEverySampleExactlyOnce() {
        let count = 20 * 60 * 16_000
        let blocks = ReconciliationBlocks.plan(Array(repeating: 0.1, count: count), coreSeconds: 60)
        XCTAssertEqual(blocks.count, 20)
        XCTAssertEqual(blocks.first?.commit.lowerBound, 0)
        XCTAssertEqual(blocks.last?.commit.upperBound, count)
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.commit.count }, count)
        for (index, block) in blocks.enumerated() {
            XCTAssertTrue(block.audio.contains(block.commit.lowerBound))
            XCTAssertTrue(block.audio.contains(block.commit.upperBound - 1))
            XCTAssertTrue(block.audio.count <= 69 * 16_000)
            if index > 0 { XCTAssertEqual(blocks[index - 1].commit.upperBound, block.commit.lowerBound) }
        }
    }
    func testNearestQuietBoundaryIsPreferredAndNoAudioIsTrimmed() {
        var samples = Array(repeating: Float(0.1), count: 75 * 16_000)
        let cut = 58 * 16_000
        for index in (cut - 2560)..<(cut + 2560) { samples[index] = 0 }
        let blocks = ReconciliationBlocks.plan(samples, coreSeconds: 60)
        XCTAssertEqual(blocks.first?.commit.upperBound, cut)
        XCTAssertEqual(blocks.last?.commit.upperBound, samples.count)
        XCTAssertEqual(blocks.first?.audio.upperBound, cut + 32_000)
        XCTAssertEqual(blocks.last?.audio.lowerBound, cut - 32_000)
    }
    func testTinyLastTailKeepsContextAndEmptyAudioProducesNoBlocks() {
        let count = 60 * 16_000 + 1
        let blocks = ReconciliationBlocks.plan(Array(repeating: 0.1, count: count), coreSeconds: 60)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.last?.commit.count, 1)
        XCTAssertEqual(blocks.last?.audio.count, 32_001)
        XCTAssertTrue(ReconciliationBlocks.plan([], coreSeconds: 60).isEmpty)
    }
}
