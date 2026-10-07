import XCTest
@testable import VoiceWisprCore

final class AudioSpectrumMeterTests: XCTestCase {
    private func tone(_ frequency: Double, amplitude: Float = 0.025) -> [Float] {
        (0..<512).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / 16_000)) }
    }

    func testEqualVolumeTonesDriveDifferentFrequencyBands() {
        for (frequency, band) in [(62.5, 0), (187.5, 4), (437.5, 8)] {
            let levels = AudioSpectrumMeter().levels(for: tone(frequency))
            XCTAssertEqual(levels.count, 9)
            XCTAssertEqual(levels.firstIndex(of: levels.max()!), band)
            XCTAssertGreaterThan(levels[band], 0.55)
            XCTAssertLessThan(levels[(band + 4) % 9], 0.1)
        }
    }

    func testQuietTonesHaveVisiblePeaksWithoutSaturating() {
        let levels = AudioSpectrumMeter().levels(for: tone(187.5, amplitude: 0.005))
        XCTAssertGreaterThan(levels[4], 0.3)
        XCTAssertLessThan(levels[4], 0.8)
    }

    func testMixedTonesShowSeparateLowAndHighPeaks() {
        let samples = zip(tone(62.5), tone(437.5)).map(+)
        let levels = AudioSpectrumMeter().levels(for: samples)
        XCTAssertGreaterThan(levels[0], 0.55)
        XCTAssertGreaterThan(levels[8], 0.65)
        XCTAssertLessThan(levels[4], 0.1)
    }

    func testBassReductionPreservesCalibratedQuietPeak() {
        // Reference for the selected 40...500 Hz display with 8 dB bass reduction.
        let levels = AudioSpectrumMeter().levels(for: tone(62.5, amplitude: 0.005))
        XCTAssertEqual(Double(levels[0]), 0.16609447, accuracy: 0.00001)
        XCTAssertEqual(Double(levels[1]), 0.05093882, accuracy: 0.00001)
    }

    func testSmallCallbacksMatchACompleteAudioWindow() {
        let samples = tone(187.5)
        let meter = AudioSpectrumMeter()
        var levels: [Float] = []
        for start in stride(from: 0, to: 512, by: 128) {
            levels = meter.levels(for: Array(samples[start..<start + 128]))
        }
        XCTAssertEqual(levels, AudioSpectrumMeter().levels(for: samples))
    }

    func testHighTonesOutsideTheVoiceDisplayDoNotCreateFalsePeaks() {
        let levels = AudioSpectrumMeter().levels(for: tone(4000))
        XCTAssertTrue(levels.allSatisfy { $0 < 0.1 })
    }

    func testSilenceEmptyAndInvalidSamplesStayFiniteAndBounded() {
        let meter = AudioSpectrumMeter()
        _ = meter.levels(for: tone(187.5))
        for samples: [Float] in [[Float](repeating: 0, count: 512), [], [.nan, .infinity, -.infinity]] {
            let levels = meter.levels(for: samples)
            XCTAssertEqual(levels, [Float](repeating: 0, count: 9))
        }
        XCTAssertTrue(meter.levels(for: tone(187.5, amplitude: 1)).allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
    }
}
