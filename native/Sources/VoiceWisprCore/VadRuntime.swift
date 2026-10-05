import Foundation
import FluidAudio
@preconcurrency import CoreML

/// State belongs to a dictation, so cancellation cannot leak a prior session into a new one.
public struct SpeechActivityState: Sendable {
    var modelState: VadStreamState = .initial()
    public init() {}
}
public struct SpeechActivityResult: Sendable {
    public let state: SpeechActivityState
    public let speechEnded: Bool
    public init(state: SpeechActivityState, speechEnded: Bool) {
        self.state = state; self.speechEnded = speechEnded
    }
}
public protocol SpeechActivityDetecting: Sendable {
    func detectActivity(samples: [Float], state: SpeechActivityState) async throws -> SpeechActivityResult
}

/// Uses the pinned, installed Silero Core ML model. Neither initializer has a download route.
actor VadRuntime {
    private let modelDirectory: URL
    private let minSilenceDuration: TimeInterval
    private var manager: VadManager?
    init(modelDirectory: URL, minSilenceDuration: TimeInterval = 0.5) {
        self.modelDirectory = modelDirectory; self.minSilenceDuration = minSilenceDuration
    }
    func prepare() async throws {
        guard manager == nil else { return }
        try Task.checkCancellation()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let model = try MLModel(contentsOf: modelDirectory, configuration: configuration)
        let candidate = VadManager(config: VadConfig(defaultThreshold: 0.5, debugMode: false), vadModel: model)
        _ = try await candidate.processStreamingChunk([Float](repeating: 0, count: VadManager.chunkSize), state: .initial())
        try Task.checkCancellation()
        manager = candidate
    }
    func detect(samples: [Float], state: SpeechActivityState) async throws -> SpeechActivityResult {
        guard let manager else { throw VoiceError.message("Sprachaktivitätserkennung ist nicht vorbereitet") }
        guard samples.count == VadManager.chunkSize else { throw VoiceError.message("Sprachaktivität benötigt einen vollständigen Audioabschnitt") }
        try Task.checkCancellation()
        let result = try await manager.processStreamingChunk(samples, state: state.modelState,
            config: VadSegmentationConfig(minSilenceDuration: minSilenceDuration))
        try Task.checkCancellation()
        var next = SpeechActivityState(); next.modelState = result.state
        return SpeechActivityResult(state: next, speechEnded: result.event?.isEnd == true)
    }
}
