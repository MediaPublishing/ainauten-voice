import AVFoundation
import CoreImage
import Foundation

public struct LipReadingFrame: Sendable {
    public let milliseconds: Int
    public let jpeg: Data
    public init(milliseconds: Int, jpeg: Data) { self.milliseconds = milliseconds; self.jpeg = jpeg }
}

/// Camera-only, memory-only capture. Invalidating a generation fences startup
/// and queued sample callbacks before the serial capture session is stopped.
public final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public static let maximumSeconds = 30.0
    public static let maximumFrames = 750
    public static let maximumBytes = 64 * 1024 * 1024
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.mediapublishing.voice.camera.session")
    private let sampleQueue = DispatchQueue(label: "com.mediapublishing.voice.camera.samples")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var generation: UUID?
    private var frames: [LipReadingFrame] = []
    private var bytes = 0
    private var origin: Double?
    private var lastTimestamp = -40
    private var limitReported = false
    private var onError: (@Sendable (String) -> Void)?
    private var onLimit: (@Sendable () -> Void)?
    private var observer: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    public override init() { super.init() }
    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    public func start(sessionID: UUID, onError: @escaping @Sendable (String) -> Void, onLimit: (@Sendable () -> Void)? = nil) async throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw VoiceError.message("Bitte erlaube die Kamera für die Lippenlesen-Beta.") }
        try lock.withLock {
            guard generation == nil else { throw VoiceError.message("Eine Kameraaufnahme läuft bereits.") }
            generation = sessionID; frames = []; bytes = 0; origin = nil; lastTimestamp = -40; limitReported = false; self.onError = onError; self.onLimit = onLimit
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    guard self.current(sessionID) else { throw CancellationError() }
                    if self.session.inputs.isEmpty {
                        guard let device = AVCaptureDevice.default(for: .video) else { throw VoiceError.message("Keine Kamera gefunden.") }
                        let input = try AVCaptureDeviceInput(device: device)
                        let output = AVCaptureVideoDataOutput()
                        output.alwaysDiscardsLateVideoFrames = true
                        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                        self.session.beginConfiguration()
                        defer { self.session.commitConfiguration() }
                        if self.session.canSetSessionPreset(.vga640x480) { self.session.sessionPreset = .vga640x480 }
                        guard self.session.canAddInput(input), self.session.canAddOutput(output) else { throw VoiceError.message("Kamera konnte nicht eingerichtet werden.") }
                        self.session.addInput(input); self.session.addOutput(output)
                        output.setSampleBufferDelegate(self, queue: self.sampleQueue)
                    }
                    guard self.current(sessionID) else { throw CancellationError() }
                    if self.observer == nil {
                        self.observer = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: self.session, queue: nil) { [weak self] _ in self?.report("Die Kamera wurde unterbrochen. Bitte starte die Aufnahme erneut.") }
                        self.interruptionObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: self.session, queue: nil) { [weak self] _ in self?.report("Die Kamera ist nicht mehr verfügbar. Bitte starte die Aufnahme erneut.") }
                    }
                    self.session.startRunning()
                    guard self.current(sessionID) else { self.session.stopRunning(); throw CancellationError() }
                    guard self.session.isRunning else { throw VoiceError.message("Die Kamera konnte nicht gestartet werden.") }
                    continuation.resume()
                } catch {
                    self.invalidate(sessionID); self.session.stopRunning()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func stop(sessionID: UUID) async -> [LipReadingFrame] {
        let (snapshot, owned) = lock.withLock {
            let owned = generation == sessionID
            let value = generation == sessionID ? frames : []
            if generation == sessionID { generation = nil; frames = []; bytes = 0; onError = nil; onLimit = nil }
            return (value, owned)
        }
        guard owned else { return [] }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                // An older queued stop must not stop a newly started session.
                if self.lock.withLock({ self.generation == nil }) { self.session.stopRunning() }
                continuation.resume()
            }
        }
        return snapshot
    }
    public func cancel() {
        lock.lock(); generation = nil; frames = []; bytes = 0; onError = nil; onLimit = nil; lock.unlock()
        sessionQueue.async { if self.lock.withLock({ self.generation == nil }) { self.session.stopRunning() } }
    }
    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return generation != nil }
    private func current(_ id: UUID) -> Bool { lock.lock(); defer { lock.unlock() }; return generation == id }
    private func invalidate(_ id: UUID) { lock.lock(); defer { lock.unlock() }; if generation == id { generation = nil; frames = []; bytes = 0 } }
    private func report(_ text: String) { lock.lock(); let callback = onError; lock.unlock(); callback?(text) }
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let absolute = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard absolute.isFinite, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        guard let id = generation else { lock.unlock(); return }
        if origin == nil { origin = absolute }
        let timestamp = Int(((absolute - origin!) * 1000).rounded())
        // One frame per 40-ms bucket. Requiring a 40-ms gap on a 30-fps
        // webcam discards every other frame and unintentionally yields 15 fps.
        guard timestamp >= 0, timestamp / 40 > lastTimestamp / 40 else { lock.unlock(); return }
        lastTimestamp = timestamp
        lock.unlock()
        let image = CIImage(cvPixelBuffer: buffer)
        guard let data = context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.65]), data.count <= 150_000 else { return }
        lock.lock()
        guard generation == id else { lock.unlock(); return }
        guard timestamp <= 30_000, frames.count < Self.maximumFrames, bytes + data.count <= Self.maximumBytes else {
            let notify = !limitReported; limitReported = true; let callback = onError; let completion = onLimit; lock.unlock()
            if notify {
                if let completion { completion() } else { callback?("Die Beta-Aufnahme wird nach 30 Sekunden oder an der Speichergrenze abgeschlossen.") }
            }
            return
        }
        frames.append(LipReadingFrame(milliseconds: timestamp, jpeg: data)); bytes += data.count
        lock.unlock()
    }
}
