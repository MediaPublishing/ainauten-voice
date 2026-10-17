import Foundation

/// Audited optional MIT weights, shared by manifest validation and readiness.
public enum SwissGermanModel {
    public static let group = "swiss-german"
    public static let path = "swiss/ggml-large-v3-q5_0.bin"
    public static let size: Int64 = 1_081_140_203
    public static let sha256 = "d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1"
}

public enum SpeechDecoderError: LocalizedError, Sendable {
    case failed, timeout, invalidOutput
    public var errorDescription: String? {
        switch self {
        case .failed: L10n.text("speech.decoder.failed")
        case .timeout: L10n.text("speech.decoder.timeout")
        case .invalidOutput: L10n.text("speech.decoder.invalidOutput")
        }
    }
}

/// Swiss speech -> standard German directly from audio. No translation of a
/// Parakeet transcript and no network or automatic download route. Long recordings
/// receive a final acoustic reconciliation because coarse Whisper timestamps can
/// lose short words at streaming seams. Each helper loads its own
/// model, so warm-up primes OS/Metal caches, not a resident model server.
public actor SwissGermanSpeechRuntime: SpeechTranscribing, SpeechActivityDetecting, SpeechPipelinePreferences, SpeechSessionReconciling {
    public nonisolated var minimumNaturalSegmentSamples: Int { 8 * 16_000 }
    /// Prefix-wide checkpoints would repeatedly reload the large model as a
    /// session grows. Keep streaming formatting and perform only the final audit.
    public nonisolated var allowsFormattingCheckpoints: Bool { false }
    private let modelURL: URL
    private let helper: WhisperLanguageFallback
    private let activity: VadRuntime
    private var prepared = false
    public init(modelURL: URL = ModelPaths.swissGerman, activityModelDirectory: URL = ModelPaths.activity) {
        self.modelURL = modelURL
        let bundled = WhisperLanguageFallback.bundled
        helper = .init(executable: bundled.executable, model: modelURL)
        activity = VadRuntime(modelDirectory: activityModelDirectory)
    }
    public func prepare() async throws {
        try Task.checkCancellation()
        guard !prepared else { return }
        try await Self.validateModel(modelURL)
        guard FileManager.default.isExecutableFile(atPath: helper.executable.path) else { throw SpeechDecoderError.failed }
        // Empty output is valid for this synthetic warm-up only; discard every
        // returned word so no hallucinated silence text reaches a dictation.
        _ = try await helper.transcribe([Float](repeating: 0, count: 16_000), language: "de", sessionID: UUID(), index: 0, offset: 0, allowEmpty: true)
        try await activity.prepare()
        try Task.checkCancellation()
        prepared = true
    }
    static func validateModel(_ url: URL) async throws {
        try Task.checkCancellation()
        guard (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(SwissGermanModel.size) else { throw VoiceError.message(L10n.text("swiss.modelRequired")) }
        let digest = try await Task.detached(priority: .utility) { try ModelDownloader.digest(url) }.value
        try Task.checkCancellation()
        guard digest == SwissGermanModel.sha256 else { throw VoiceError.message(L10n.text("swiss.modelInvalid")) }
    }
    public func detectActivity(samples: [Float], state: SpeechActivityState) async throws -> SpeechActivityResult {
        try await activity.detect(samples: samples, state: state)
    }
    static func validate(_ samples: [Float], offset: Double) throws {
        guard samples.count >= 4800 else { throw SpeechInputError.tooShort }
        guard samples.count <= AudioCaptureBuffer.maximumSamples,
              samples.allSatisfy(\.isFinite), offset.isFinite, offset >= 0 else { throw SpeechDecoderError.invalidOutput }
    }
    static func validateLanguage(_ text: String) throws {
        guard !SpeechLanguagePolicy(["de"]).needsRecovery(text) else { throw SpeechLanguageError.mismatch }
    }
    /// Fail closed on a long decoder loop, rather than inserting repeated invented
    /// sentences. Ordinary short repetitions are retained; nothing is deleted.
    static func validateRepetition(_ text: String) throws {
        let words = ProcessingPipeline.lexicalSequence(text)
        guard words.count >= 36 else { return }
        for length in 6...min(20, words.count / 4) {
            for start in 0...(words.count - length * 4) {
                let phrase = Array(words[start..<(start + length)])
                if (1...3).allSatisfy({ repeatIndex in Array(words[(start + repeatIndex * length)..<(start + (repeatIndex + 1) * length)]) == phrase }) {
                    throw SpeechDecoderError.invalidOutput
                }
            }
        }
    }
    public func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        try Task.checkCancellation()
        try Self.validate(samples, offset: offset)
        guard prepared else { throw SpeechDecoderError.failed }
        let result = try await helper.transcribe(samples, language: "de", sessionID: sessionID, index: index, offset: offset, allowEmpty: true)
        try Self.validateLanguage(result.text)
        try Self.validateRepetition(result.text)
        return result
    }
    public func reconcile(samples: [Float], sessionID: UUID) async throws -> TranscriptSegment {
        try Self.validate(samples, offset: 0)
        if samples.count <= 60 * 16_000 {
            return try await transcribe(samples: samples, sessionID: sessionID, index: 0, offset: 0)
        }
        // Bound each long-session call independently of a 20-minute capture.
        let blocks = ReconciliationBlocks.plan(samples, coreSeconds: 60, contextSeconds: 8)
        var prior: [ProcessingPipeline.SeamWord] = [], words: [TranscriptWord] = [], text: [String] = []
        for (index, block) in blocks.enumerated() {
            try Task.checkCancellation()
            let segment = try await transcribe(samples: Array(samples[block.audio]), sessionID: sessionID, index: index, offset: Double(block.audio.lowerBound) / 16_000)
            let selection = try ProcessingPipeline.selectSeamWords(segment: segment, bounds: block.commit, requiresTimings: true, previous: prior)
            text.append(selection.text); words += selection.words; prior = selection.window
        }
        return .init(sessionID: sessionID, index: 0, text: text.joined(separator: " "), words: words)
    }
}
