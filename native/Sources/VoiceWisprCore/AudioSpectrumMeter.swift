import Foundation
import Accelerate

/// Display-only frequency levels from the existing 16 kHz mono capture.
/// Keep each instance on one serial executor; this never modifies recognition audio.
public final class AudioSpectrumMeter {
    public static let bandCount = 9
    private static let sampleCount = 512
    // Accepted demo spacing, scaled to the selected 40...500 Hz display range.
    private static let edges: [Double] = [60.0, 140, 230, 340, 480, 650, 900, 1250, 1750, 2500].map {
        40 * pow(500.0 / 40, log($0 / 60) / log(2500.0 / 60))
    }
    private let setup: vDSP_DFT_Setup?
    private let window: [Float]
    private let windowSum: Float
    private var recent: [Float] = []

    public init() {
        setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(Self.sampleCount), .FORWARD)
        var window = [Float](repeating: 0, count: Self.sampleCount)
        vDSP_hann_window(&window, vDSP_Length(Self.sampleCount), Int32(vDSP_HANN_NORM))
        self.window = window
        windowSum = window.reduce(0, +)
    }

    deinit { if let setup { vDSP_DFT_DestroySetup(setup) } }

    public func levels(for samples: [Float]) -> [Float] {
        let quiet = [Float](repeating: 0, count: Self.bandCount)
        // An empty callback must not leave an old speech peak on screen.
        guard !samples.isEmpty else { recent.removeAll(keepingCapacity: true); return quiet }
        recent.append(contentsOf: samples.suffix(Self.sampleCount).map { $0.isFinite ? $0 : 0 })
        if recent.count > Self.sampleCount { recent.removeFirst(recent.count - Self.sampleCount) }
        guard recent.count == Self.sampleCount, let setup else { return quiet }

        var real = [Float](repeating: 0, count: Self.sampleCount)
        let imaginary = [Float](repeating: 0, count: Self.sampleCount)
        var outputReal = real, outputImaginary = real
        vDSP_vmul(recent, 1, window, 1, &real, 1, vDSP_Length(Self.sampleCount))
        vDSP_DFT_Execute(setup, real, imaginary, &outputReal, &outputImaginary)

        return (0..<Self.bandCount).map { band in
            let lower = Int(ceil(Self.edges[band] * Double(Self.sampleCount) / 16_000))
            let upper = Int(ceil(Self.edges[band + 1] * Double(Self.sampleCount) / 16_000))
            var power: Float = 0
            for bin in lower..<upper {
                power += outputReal[bin] * outputReal[bin] + outputImaginary[bin] * outputImaginary[bin]
            }
            let magnitude = 2 * sqrt(power) / windowSum
            // Decibel scaling makes normal speech visible without amplifying ASR input.
            // Taper the selected 8 dB bass reduction to zero at the highest band.
            let decibels = 20 * log10(max(1e-9, magnitude)) - Float(8 * pow(1 - Double(band) / 8, 2))
            return min(1, max(0, (decibels + 60) / 36))
        }
    }
}
