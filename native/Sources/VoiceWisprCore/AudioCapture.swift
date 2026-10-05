import Foundation
import AVFoundation

public struct AudioChunk: Sendable, Equatable {
    public let samples: [Float]
    public let startSample: Int
    public init(samples: [Float], startSample: Int) { self.samples = samples; self.startSample = startSample }
}

/// Audio is held only in memory, at most twenty minutes of normalized mono PCM.
public final class AudioCaptureBuffer: @unchecked Sendable {
    public let sampleRate = 16_000
    public static let maximumSamples = 16_000 * 20 * 60
    private var storage: [Float] = []
    private let lock = NSLock()
    private var finished = false
    public init() {}
    @discardableResult public func append(_ samples: [Float]) -> AudioChunk {
        lock.lock(); defer { lock.unlock() }
        let start = storage.count
        guard !finished else { return .init(samples: [], startSample: start) }
        let accepted = Array(samples.prefix(max(0, Self.maximumSamples - storage.count)))
        storage.append(contentsOf: accepted)
        if storage.count == Self.maximumSamples { finished = true }
        return .init(samples: accepted, startSample: start)
    }
    public func snapshot(from start: Int = 0) -> [Float] { lock.lock(); defer { lock.unlock() }; return Array(storage.dropFirst(max(0, start))) }
    public var count: Int { lock.lock(); defer { lock.unlock() }; return storage.count }
    public var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    public func finish() { lock.lock(); finished = true; lock.unlock() }
}

/// The host requests microphone permission before calling start; capture itself never prompts.
public final class AudioCapture: @unchecked Sendable {
    public typealias SamplesHandler = @Sendable ([Float]) -> Void
    public typealias LevelHandler = @Sendable (Float) -> Void
    public typealias ErrorHandler = @Sendable (Error) -> Void
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var running = false
    private var activeBuffer: AudioCaptureBuffer?
    private var configurationObserver: NSObjectProtocol?
    public init() {}
    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }
    public func start(onSamples: @escaping SamplesHandler, onLevel: @escaping LevelHandler, onError: @escaping ErrorHandler, onCompletion: (@Sendable () -> Void)? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        guard !running else { throw VoiceError.message("Audioaufnahme läuft bereits") }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw VoiceError.message("Mikrofonzugriff fehlt") }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { throw VoiceError.message("Mikrofonformat wird nicht unterstützt") }
        let sessionBuffer = AudioCaptureBuffer()
        activeBuffer = sessionBuffer
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { pcm, _ in
            guard !sessionBuffer.isFinished else { return }
            let capacity = AVAudioFrameCount(ceil(Double(pcm.frameLength) * 16_000 / inputFormat.sampleRate)) + 64
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { onError(VoiceError.message("Audio-Puffer konnte nicht angelegt werden")); return }
            var supplied = false; var failure: NSError?
            let status = converter.convert(to: output, error: &failure) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return pcm
            }
            if let failure { onError(failure); return }
            guard status != .error, let channel = output.floatChannelData?[0] else { onError(VoiceError.message("Audio konnte nicht auf 16 kHz umgerechnet werden")); return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            let chunk = sessionBuffer.append(samples)
            guard !chunk.samples.isEmpty else { return }
            let rms = sqrt(chunk.samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.samples.count))
            onLevel(min(1, rms * 8)); onSamples(chunk.samples)
            if chunk.samples.count < samples.count || sessionBuffer.isFinished {
                if let onCompletion { onCompletion() } else { onError(VoiceError.message("Das maximale Diktat von 20 Minuten wurde erreicht")) }
            }
        }
        engine.prepare()
        do {
            try engine.start(); running = true
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
                guard !sessionBuffer.isFinished else { return }
                if let onCompletion { onCompletion() } else { onError(VoiceError.message("Mikrofon wurde geändert. Das bisherige Diktat wird abgeschlossen.")) }
            }
        }
        catch { input.removeTap(onBus: 0); activeBuffer = nil; throw error }
    }
    public func start(onSamples: @escaping @Sendable ([Float], Float) -> Void, onError: @escaping @Sendable (String) -> Void, onCompletion: (@Sendable () -> Void)? = nil) throws {
        try start(onSamples: { samples in
            let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, samples.count)))
            onSamples(samples, min(1, rms * 8))
        }, onLevel: { _ in }, onError: { onError($0.localizedDescription) }, onCompletion: onCompletion)
    }
    @discardableResult public func stop() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        guard running else { return [] }
        activeBuffer?.finish()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver); self.configurationObserver = nil }
        engine.stop(); engine.inputNode.removeTap(onBus: 0); running = false
        let samples = activeBuffer?.snapshot() ?? []; activeBuffer = nil
        return samples
    }
}

/// Segments partition the original PCM exactly, including silence. No quiet samples are discarded.
public enum SilenceSegmenter {
    public static func ranges(samples: [Float], sampleRate: Int = 16_000, silence: Double = 0.5, maxDuration: Double = 15, threshold: Float = 0.012) -> [Range<Int>] {
        guard !samples.isEmpty else { return [] }
        let frame = max(1, sampleRate / 100), gap = max(1, Int(silence * Double(sampleRate))), cap = max(1, Int(maxDuration * Double(sampleRate)))
        var ranges: [Range<Int>] = []; var start = 0; var quiet = 0; var hadSpeech = false
        var offset = 0
        while offset < samples.count {
            let end = min(samples.count, offset + frame)
            let rms = sqrt(samples[offset..<end].reduce(Float(0)) { $0 + $1 * $1 } / Float(end - offset))
            if rms < threshold { quiet += end - offset } else { quiet = 0; hadSpeech = true }
            if (hadSpeech && quiet >= gap) || end - start >= cap {
                ranges.append(start..<end); start = end; quiet = 0; hadSpeech = false
            }
            offset = end
        }
        if start < samples.count { ranges.append(start..<samples.count) }
        return ranges
    }
}
