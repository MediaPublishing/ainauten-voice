import Foundation

/// Acoustic-only partitioning for bounded SDK verification experiments. Every
/// sample is owned once; overlap is read-only context and is never dropped.
enum ReconciliationBlocks {
    struct Block: Equatable, Sendable {
        let audio: Range<Int>
        let commit: Range<Int>
    }
    static func plan(_ samples: [Float], coreSeconds: Int, contextSeconds: Int = 2) -> [Block] {
        precondition((30...120).contains(coreSeconds))
        precondition((2...10).contains(contextSeconds))
        guard !samples.isEmpty else { return [] }
        let rate = 16_000, frame = 1280, context = contextSeconds * rate
        let core = coreSeconds * rate, radius = 5 * rate
        var blocks: [Block] = [], start = 0
        while start < samples.count {
            let target = min(samples.count, start + core)
            var end = target
            if target < samples.count {
                let lower = max(start + core / 2, target - radius)
                let upper = min(samples.count - frame * 2, target + radius)
                var bestDistance = Int.max
                // A 320 ms quiet interval near the nominal cut avoids cutting a
                // phoneme. Prefer the nearest sufficiently quiet interval rather
                // than the deepest valley several seconds away.
                if lower < upper {
                    for cut in stride(from: (lower / frame + 1) * frame, through: upper, by: frame) {
                        let range = (cut - 2 * frame)..<(cut + 2 * frame)
                        let energy = samples[range].reduce(Float(0)) { $0 + $1 * $1 }
                        if sqrt(energy / Float(range.count)) < 0.0005, abs(cut - target) < bestDistance {
                            end = cut; bestDistance = abs(cut - target)
                        }
                    }
                }
            }
            blocks.append(.init(audio: max(0, start - context)..<min(samples.count, end + context), commit: start..<end))
            start = end
        }
        return blocks
    }
}
