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
    @discardableResult public func finish(onlyIfEmpty: Bool = false) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !onlyIfEmpty || storage.isEmpty else { return false }
        finished = true; return true
    }
}

/// Native audio operations are confined to AudioCapture's serial session queue.
protocol AudioCaptureDriving: Sendable {
    func start(buffer: AudioCaptureBuffer, onSamples: @escaping AudioCapture.SamplesHandler,
               onLevel: @escaping AudioCapture.LevelHandler, onError: @escaping AudioCapture.ErrorHandler,
               onCompletion: (@Sendable () -> Void)?) throws
    func stop()
}

/// The host requests microphone permission before calling start; capture itself never prompts.
public final class AudioCapture: @unchecked Sendable {
    public typealias SamplesHandler = @Sendable ([Float]) -> Void
    public typealias LevelHandler = @Sendable (Float) -> Void
    public typealias ErrorHandler = @Sendable (Error) -> Void
    private let sessionQueue = DispatchQueue(label: "com.mediapublishing.voice.audio.session")
    private let lock = NSLock()
    private let driver: any AudioCaptureDriving
    private let startupTimeout: TimeInterval
    private let microphoneAuthorized: @Sendable () -> Bool
    private var activeBuffer: AudioCaptureBuffer?
    public convenience init() { self.init(driver: AVAudioCaptureDriver()) }
    init(driver: any AudioCaptureDriving, startupTimeout: TimeInterval = 5,
         microphoneAuthorized: @escaping @Sendable () -> Bool = { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }) {
        self.driver = driver; self.startupTimeout = startupTimeout; self.microphoneAuthorized = microphoneAuthorized
    }
    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return activeBuffer != nil }
    public func start(onSamples: @escaping SamplesHandler, onLevel: @escaping LevelHandler, onError: @escaping ErrorHandler, onCompletion: (@Sendable () -> Void)? = nil) throws {
        guard microphoneAuthorized() else { throw VoiceError.message("Mikrofonzugriff fehlt") }
        lock.lock(); defer { lock.unlock() }
        guard activeBuffer == nil else { throw VoiceError.message("Audioaufnahme läuft bereits") }
        let buffer = AudioCaptureBuffer(); activeBuffer = buffer
        // Enqueue while holding only the short state lock, preserving start/stop order.
        sessionQueue.async { [self] in
            guard !buffer.isFinished else { return }
            do {
                try self.driver.start(buffer: buffer, onSamples: onSamples, onLevel: onLevel,
                    onError: { [weak self] error in self?.finishWithError(error, buffer: buffer, onError: onError) },
                    onCompletion: onCompletion)
            } catch { self.finishWithError(error, buffer: buffer, onError: onError) }
        }
        // This deadline must run even when a native driver call blocks the session queue.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + startupTimeout) { [weak self, weak buffer] in
            guard let self, let buffer else { return }
            self.finishWithError(VoiceError.message("Das Mikrofon liefert kein Audio. Prüfe das Eingabegerät und starte das Diktat erneut."),
                                 buffer: buffer, onError: onError, onlyIfEmpty: true)
        }
    }
    public func start(onSamples: @escaping @Sendable ([Float], Float) -> Void, onError: @escaping @Sendable (String) -> Void, onCompletion: (@Sendable () -> Void)? = nil) throws {
        try start(onSamples: { samples in
            let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, samples.count)))
            onSamples(samples, min(1, rms * 8))
        }, onLevel: { _ in }, onError: { onError($0.localizedDescription) }, onCompletion: onCompletion)
    }
    @discardableResult public func stop() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        guard let buffer = activeBuffer else { return [] }
        buffer.finish(); activeBuffer = nil
        sessionQueue.async { self.driver.stop() }
        return buffer.snapshot()
    }
    private func finishWithError(_ error: Error, buffer: AudioCaptureBuffer, onError: ErrorHandler, onlyIfEmpty: Bool = false) {
        lock.lock()
        guard activeBuffer === buffer, buffer.finish(onlyIfEmpty: onlyIfEmpty) else { lock.unlock(); return }
        activeBuffer = nil
        sessionQueue.async { self.driver.stop() }
        lock.unlock()
        onError(error)
    }
}

/// Follows the delivered PCM format, which can differ from a cached input-node format.
/// Used only on the native tap's serial audio callback.
final class AudioCaptureConverter {
    private var converter: AVAudioConverter?
    func samples(from pcm: AVAudioPCMBuffer) throws -> [Float] {
        guard pcm.frameLength > 0 else { return [] }
        let inputFormat = pcm.format
        guard inputFormat.sampleRate.isFinite, inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw VoiceError.message("Mikrofonformat wird nicht unterstützt") }
        if converter?.inputFormat != inputFormat {
            guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
                  let next = AVAudioConverter(from: inputFormat, to: outputFormat) else { throw VoiceError.message("Mikrofonformat wird nicht unterstützt") }
            converter = next
        }
        guard let converter else { throw VoiceError.message("Mikrofonformat wird nicht unterstützt") }
        let capacity = AVAudioFrameCount(ceil(Double(pcm.frameLength) * 16_000 / inputFormat.sampleRate)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { throw VoiceError.message("Audio-Puffer konnte nicht angelegt werden") }
        var supplied = false; var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return pcm
        }
        if let failure { throw failure }
        guard status != .error, let channel = output.floatChannelData?[0] else { throw VoiceError.message("Audio konnte nicht auf 16 kHz umgerechnet werden") }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

private final class AVAudioCaptureDriver: AudioCaptureDriving, @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var configurationObserver: NSObjectProtocol?
    deinit { if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) } }
    func start(buffer sessionBuffer: AudioCaptureBuffer, onSamples: @escaping AudioCapture.SamplesHandler,
               onLevel: @escaping AudioCapture.LevelHandler, onError: @escaping AudioCapture.ErrorHandler,
               onCompletion: (@Sendable () -> Void)?) throws {
        guard !sessionBuffer.isFinished else { return }
        // A stopped engine can retain the previous device's sample rate after sleep or a route change.
        let engine = AVAudioEngine(); self.engine = engine
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw VoiceError.message("Mikrofonformat wird nicht unterstützt") }
        let converter = AudioCaptureConverter()
        // Let Core Audio choose its current format instead of applying a stale node format.
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { pcm, _ in
            guard !sessionBuffer.isFinished else { return }
            let samples: [Float]
            do { samples = try converter.samples(from: pcm) }
            catch { onError(error); return }
            let chunk = sessionBuffer.append(samples)
            guard !chunk.samples.isEmpty else { return }
            let rms = sqrt(chunk.samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.samples.count))
            onLevel(min(1, rms * 8)); onSamples(chunk.samples)
            if chunk.samples.count < samples.count || sessionBuffer.isFinished {
                if let onCompletion { onCompletion() } else { onError(VoiceError.message("Das maximale Diktat von 20 Minuten wurde erreicht")) }
            }
        }
        tapInstalled = true
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
            guard !sessionBuffer.isFinished else { return }
            if let onCompletion { onCompletion() } else { onError(VoiceError.message("Mikrofon wurde geändert. Das bisherige Diktat wird abgeschlossen.")) }
        }
        guard !sessionBuffer.isFinished else { return }
        engine.prepare()
        guard !sessionBuffer.isFinished else { return }
        try engine.start()
    }
    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver); self.configurationObserver = nil }
        guard let engine else { return }
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        self.engine = nil
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
