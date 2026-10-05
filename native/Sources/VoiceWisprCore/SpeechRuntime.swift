import Foundation
import FluidAudio

/// Optional full-session verification through the pinned SDK's own bounded chunk strategy.
public protocol SpeechSessionReconciling: Sendable {
    func reconcile(samples: [Float], sessionID: UUID) async throws -> TranscriptSegment
}

public struct SpeechRuntimeConfiguration: Sendable {
    public var sampleRate = 16_000
    public var maxSessionSeconds = 20 * 60
    public var modelDirectory: URL
    public var activityModelDirectory: URL
    public var encoderPrecision: ParakeetEncoderPrecision
    public var activitySilenceDuration: TimeInterval
    public var trimTrailingSilence: Bool
    public var sdkWorkers: Int
    /// Diagnostic opt-in to the pinned SDK's acoustic chunk-layout arbitration.
    /// Disabled until the same-audio quality and latency probes justify a change.
    public var dualDecodeArbitration = false
    /// Diagnostic override. Otherwise only sessions over ten minutes use blocks;
    /// shorter dictations retain the SDK path verified for the latency targets.
    public var reconciliationBlockSeconds: Int?
    public var reconciliationContextSeconds = 8
    func blockSeconds(for sampleCount: Int) -> Int? {
        reconciliationBlockSeconds ?? (sampleCount > 10 * 60 * sampleRate ? 60 : nil)
    }
    public init(modelDirectory: URL = ModelPaths.speech, activityModelDirectory: URL = ModelPaths.activity, encoderPrecision: ParakeetEncoderPrecision = .int8, activitySilenceDuration: TimeInterval = 0.5, trimTrailingSilence: Bool = false, sdkWorkers: Int = 2) {
        precondition(activitySilenceDuration.isFinite && activitySilenceDuration >= 0 && activitySilenceDuration <= 1)
        precondition((1...4).contains(sdkWorkers))
        self.modelDirectory = modelDirectory; self.activityModelDirectory = activityModelDirectory
        self.encoderPrecision = encoderPrecision
        self.activitySilenceDuration = activitySilenceDuration
        self.trimTrailingSilence = trimTrailingSilence
        self.sdkWorkers = sdkWorkers
    }
}

/// In-process Core ML recognition. Loading never downloads models or sends audio.
public actor SpeechRuntime: SpeechTranscribing, SpeechActivityDetecting, SpeechSessionReconciling {
    private let configuration: SpeechRuntimeConfiguration
    private var manager: AsrManager?
    private let activity: VadRuntime
    public init(configuration: SpeechRuntimeConfiguration = .init()) {
        self.configuration = configuration; self.activity = VadRuntime(modelDirectory: configuration.activityModelDirectory, minSilenceDuration: configuration.activitySilenceDuration)
    }
    public init(modelDirectory: URL) {
        let configuration = SpeechRuntimeConfiguration(modelDirectory: modelDirectory)
        self.configuration = configuration; self.activity = VadRuntime(modelDirectory: configuration.activityModelDirectory, minSilenceDuration: configuration.activitySilenceDuration)
    }
    public func prepare() async throws {
        AppLogger.minimumLevel = .fault
        AppLogger.mirrorsToConsole = false
        try Task.checkCancellation()
        guard manager == nil else { return }
        guard configuration.sampleRate == 16_000 else { throw VoiceError.message("Spracherkennung benötigt 16 kHz Mono-Audio") }
        // loadLocal is deliberately used instead of the SDK's network-recovering load.
        let models = try AsrModels.loadLocal(from: configuration.modelDirectory, version: .v3, encoderPrecision: configuration.encoderPrecision)
        let candidate = AsrManager(config: ASRConfig(sampleRate: 16_000, parallelChunkConcurrency: configuration.sdkWorkers, streamingEnabled: false, dualDecodeArbitration: configuration.dualDecodeArbitration))
        try await candidate.loadModels(models)
        // Initialize inference kernels before the app reports readiness. Silence stays in memory.
        var warmupDecoder = try TdtDecoderState()
        _ = try await candidate.transcribe([Float](repeating: 0, count: 16_000), decoderState: &warmupDecoder)
        try await activity.prepare()
        try Task.checkCancellation()
        manager = candidate
    }
    public func detectActivity(samples: [Float], state: SpeechActivityState) async throws -> SpeechActivityResult {
        try await activity.detect(samples: samples, state: state)
    }
    public func reconcile(samples: [Float], sessionID: UUID) async throws -> TranscriptSegment {
        if let seconds = configuration.blockSeconds(for: samples.count) {
            guard (30...120).contains(seconds) else { throw VoiceError.message("Ungültige Abgleichsblockgröße") }
            guard (2...10).contains(configuration.reconciliationContextSeconds) else { throw VoiceError.message("Ungültiger Abgleichskontext") }
            guard samples.count <= configuration.sampleRate * configuration.maxSessionSeconds else { throw VoiceError.message("Das Diktat überschreitet 20 Minuten") }
            let blocks = ReconciliationBlocks.plan(samples, coreSeconds: seconds, contextSeconds: configuration.reconciliationContextSeconds)
            var prior: [ProcessingPipeline.SeamWord] = [], words: [TranscriptWord] = [], text: [String] = []
            for (index, block) in blocks.enumerated() {
                try Task.checkCancellation()
                let segment = try await transcribe(samples: Array(samples[block.audio]), sessionID: sessionID, index: index, offset: Double(block.audio.lowerBound) / 16_000)
                let selection = try ProcessingPipeline.selectSeamWords(segment: segment, bounds: block.commit, requiresTimings: true, previous: prior)
                text.append(selection.text)
                words += selection.words
                prior = selection.window
            }
            return .init(sessionID: sessionID, index: 0, text: text.joined(separator: " "), words: words)
        }
        // For >15 seconds this delegates to the SDK ChunkProcessor: silence-aligned
        // starts, end-aligned final window and <=14.96-second model calls. No new AI pass.
        return try await transcribe(samples: samples, sessionID: sessionID, index: 0, offset: 0)
    }
    public func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        try Task.checkCancellation()
        guard let manager else { throw VoiceError.message("Spracherkennung ist nicht vorbereitet") }
        guard samples.count <= configuration.sampleRate * configuration.maxSessionSeconds else { throw VoiceError.message("Das Diktat überschreitet 20 Minuten") }
        guard !samples.isEmpty else { return .init(sessionID: sessionID, index: index, text: "") }
        try Self.validateInput(samples.count)
        // Each overlapping window is independent. Reusing decoder state would duplicate its prefix.
        var decoder = try TdtDecoderState()
        let inferenceSamples = configuration.trimTrailingSilence ? Self.speechBearingPrefix(samples) : samples
        let result: ASRResult
        do { result = try await manager.transcribe(inferenceSamples, decoderState: &decoder) }
        catch ASRError.invalidAudioData { throw SpeechInputError.tooShort }
        try Task.checkCancellation()
        let words = Self.words(from: result.tokenTimings ?? [], offset: offset)
        guard result.text.isEmpty || !words.isEmpty else { throw VoiceError.message("Spracherkennung hat keine Wortzeitstempel geliefert") }
        return .init(sessionID: sessionID, index: index, text: result.text, words: words)
    }
    static func validateInput(_ sampleCount: Int) throws {
        guard sampleCount >= ASRConstants.minimumRequiredSamples(forSampleRate: 16_000) else { throw SpeechInputError.tooShort }
    }
    /// Adapted from pinned FluidAudio ChunkProcessor.speechEndSamples (Apache 2.0).
    /// Its long path excludes dead-silence frames from the declared inference length:
    /// zero padding outside that length is safe, while an in-length silence tail can
    /// produce degenerate decoding. The capture and pipeline keep all original PCM.
    static func speechBearingPrefix(_ samples: [Float]) -> [Float] {
        let frame = 1280 // 80 ms at 16 kHz, matching the pinned SDK encoder frame.
        let floor: Float = 0.0005
        var end = samples.count
        while end > 0 {
            let start = max(0, end - frame)
            let energy = samples[start..<end].reduce(Float(0)) { $0 + $1 * $1 }
            if sqrt(energy / Float(end - start)) >= floor {
                // Unlike the vendor's internal long decoder, its public short API
                // requires 300 ms. Trimming must never invalidate a valid short tail.
                guard end >= ASRConstants.minimumRequiredSamples(forSampleRate: 16_000) else { return samples }
                return end == samples.count ? samples : Array(samples[..<end])
            }
            end = start
        }
        // Match the vendor's all-sub-floor rule: retain quiet/soft input in full.
        return samples
    }
    static func words(from tokens: [TokenTiming], offset: Double) -> [TranscriptWord] {
        var output: [TranscriptWord] = []
        var word = ""; var start = 0.0; var end = 0.0
        func flush() { if !word.isEmpty { output.append(.init(text: word, start: offset + start, end: offset + end)) }; word = "" }
        for timing in tokens {
            guard !timing.token.isEmpty, timing.token != "<blank>", timing.token != "<pad>" else { continue }
            let token = timing.token.replacingOccurrences(of: "▁", with: " ")
            if token.first?.isWhitespace == true { flush() }
            let piece = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            if word.isEmpty { start = timing.startTime }
            word += piece; end = max(timing.startTime, timing.endTime)
        }
        flush(); return output
    }
}
