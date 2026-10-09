import XCTest
import AVFoundation
@testable import VoiceWisprCore

private final class CaptureTestDriver: AudioCaptureDriving, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let stopped = DispatchSemaphore(value: 0)
    let startGate: DispatchSemaphore?
    let stopGate: DispatchSemaphore?
    private let lock = NSLock()
    private var sessions: [(AudioCaptureBuffer, AudioCapture.SamplesHandler, AudioCapture.ErrorHandler, (@Sendable () -> Void)?)] = []
    private(set) var startedOnMainThread = false
    init(startGate: DispatchSemaphore? = nil, stopGate: DispatchSemaphore? = nil) {
        self.startGate = startGate; self.stopGate = stopGate
    }
    func start(buffer: AudioCaptureBuffer, onSamples: @escaping AudioCapture.SamplesHandler,
               onLevel: @escaping AudioCapture.LevelHandler, onError: @escaping AudioCapture.ErrorHandler,
               onCompletion: (@Sendable () -> Void)?) throws {
        lock.lock(); startedOnMainThread = Thread.isMainThread
        sessions.append((buffer, onSamples, onError, onCompletion)); lock.unlock()
        started.signal()
        if let startGate { _ = startGate.wait(timeout: .now() + 2) }
    }
    func stop() {
        stopped.signal()
        if let stopGate { _ = stopGate.wait(timeout: .now() + 2) }
    }
    func emit(_ samples: [Float], session: Int = 0) {
        lock.lock(); let (buffer, callback, _, _) = sessions[session]; lock.unlock()
        let chunk = buffer.append(samples)
        if !chunk.samples.isEmpty { callback(chunk.samples) }
    }
    func fail(session: Int) {
        lock.lock(); let callback = sessions[session].2; lock.unlock()
        callback(VoiceError.message("Synthetic audio failure"))
    }
    func changeDevice() {
        lock.lock(); let (buffer, _, _, completion) = sessions[0]; lock.unlock()
        if !buffer.isFinished { completion?() }
    }
}

final class AudioCaptureTests: XCTestCase {
    func testConversionFollowsDeliveredFormatAcrossDeviceRateChanges() throws {
        let converter = AudioCaptureConverter()
        for (rate, channels) in [(48_000.0, 1), (44_100.0, 1), (48_000.0, 2), (16_000.0, 1), (44_100.0, 1), (48_000.0, 1)] {
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(channels), interleaved: false))
            let frames = AVAudioFrameCount(rate / 10)
            let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            pcm.frameLength = frames
            let data = try XCTUnwrap(pcm.floatChannelData)
            for channel in 0..<channels {
                for frame in 0..<Int(frames) { data[channel][frame] = 0.25 * Float(sin(2 * .pi * 440 * Double(frame) / rate)) }
            }
            let samples = try converter.samples(from: pcm)
            XCTAssertTrue(samples.allSatisfy { $0.isFinite })
            XCTAssertTrue(samples.contains { abs($0) > 0.1 })
            // Allow system resampler priming and carried frames across the two 100 ms blocks.
            let continuation = try converter.samples(from: pcm)
            XCTAssertEqual(Double(samples.count + continuation.count) / 16_000, 0.2, accuracy: 0.025)
        }
    }
    func testEmptyPCMProducesNoSamples() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
        XCTAssertTrue(try AudioCaptureConverter().samples(from: pcm).isEmpty)
    }
    func testFirstAudioWinsOverEmptyBufferTimeout() {
        let buffer = AudioCaptureBuffer()
        buffer.append([0])
        XCTAssertFalse(buffer.finish(onlyIfEmpty: true))
        XCTAssertFalse(buffer.isFinished)
        buffer.append([0.2])
        XCTAssertEqual(buffer.snapshot(), [0, 0.2])
        let empty = AudioCaptureBuffer()
        XCTAssertTrue(empty.finish(onlyIfEmpty: true))
        XCTAssertTrue(empty.append([0.3]).samples.isEmpty)
    }
    @MainActor func testStartAndStopDoNotWaitForBlockedNativeStartup() throws {
        let gate = DispatchSemaphore(value: 0), driver = CaptureTestDriver(startGate: gate)
        defer { gate.signal() }
        let capture = AudioCapture(driver: driver, microphoneAuthorized: { true })
        try capture.start(onSamples: { _, _ in }, onError: { _ in })
        XCTAssertEqual(driver.started.wait(timeout: .now() + 1), .success)
        XCTAssertFalse(driver.startedOnMainThread)
        driver.emit([0.1, 0.2])
        XCTAssertEqual(capture.stop(), [0.1, 0.2])
        XCTAssertFalse(capture.isRunning)
        driver.emit([0.3])
        XCTAssertTrue(capture.stop().isEmpty)
    }
    @MainActor func testNativeStopDoesNotBlockTheNextStartRequest() throws {
        let gate = DispatchSemaphore(value: 0), driver = CaptureTestDriver(stopGate: gate)
        defer { gate.signal(); gate.signal() }
        let capture = AudioCapture(driver: driver, microphoneAuthorized: { true })
        try capture.start(onSamples: { _, _ in }, onError: { _ in })
        XCTAssertEqual(driver.started.wait(timeout: .now() + 1), .success)
        _ = capture.stop()
        XCTAssertEqual(driver.stopped.wait(timeout: .now() + 1), .success)
        try capture.start(onSamples: { _, _ in }, onError: { _ in })
        XCTAssertTrue(capture.isRunning)
        gate.signal()
        XCTAssertEqual(driver.started.wait(timeout: .now() + 1), .success)
        driver.emit([0.4], session: 1)
        XCTAssertEqual(capture.stop(), [0.4])
    }
    @MainActor func testFirstAudioDeadlineRunsWhileNativeStartupIsBlocked() throws {
        let gate = DispatchSemaphore(value: 0), driver = CaptureTestDriver(startGate: gate)
        defer { gate.signal() }
        let failed = DispatchSemaphore(value: 0)
        let capture = AudioCapture(driver: driver, startupTimeout: 0.05, microphoneAuthorized: { true })
        try capture.start(onSamples: { _, _ in }, onError: { _ in failed.signal() })
        XCTAssertEqual(driver.started.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(failed.wait(timeout: .now() + 1), .success)
        XCTAssertFalse(capture.isRunning)
        XCTAssertTrue(capture.stop().isEmpty)
        gate.signal()
        XCTAssertEqual(driver.stopped.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(failed.wait(timeout: .now() + 0.1), .timedOut)
    }
    func testSilentAudioCountsAsSuccessfulStartup() throws {
        let driver = CaptureTestDriver(), failed = DispatchSemaphore(value: 0)
        let capture = AudioCapture(driver: driver, startupTimeout: 0.05, microphoneAuthorized: { true })
        try capture.start(onSamples: { _, _ in }, onError: { _ in failed.signal() })
        XCTAssertEqual(driver.started.wait(timeout: .now() + 1), .success)
        driver.emit([0, 0, 0])
        XCTAssertEqual(failed.wait(timeout: .now() + 0.15), .timedOut)
        XCTAssertEqual(capture.stop(), [0, 0, 0])
    }
    func testOldErrorsAndDeadlinesCannotStopANewSession() throws {
        let driver = CaptureTestDriver(), failed = DispatchSemaphore(value: 0)
        let capture = AudioCapture(driver: driver, startupTimeout: 0.05, microphoneAuthorized: { true })
        try capture.start(onSamples: { _, _ in }, onError: { _ in failed.signal() })
        XCTAssertEqual(driver.started.wait(timeout: .now() + 1), .success)
        _ = capture.stop()
        try capture.start(onSamples: { _, _ in }, onError: { _ in failed.signal() })
        XCTAssertEqual(driver.started.wait(timeout: .now() + 1), .success)
        driver.emit([0.25], session: 1)
        driver.fail(session: 0)
        XCTAssertEqual(failed.wait(timeout: .now() + 0.15), .timedOut)
        XCTAssertTrue(capture.isRunning)
        XCTAssertEqual(capture.stop(), [0.25])
    }
    func testDeviceChangeKeepsTheCapturedTailForCompletion() throws {
        let driver = CaptureTestDriver(), completed = DispatchSemaphore(value: 0)
        let capture = AudioCapture(driver: driver, microphoneAuthorized: { true })
        try capture.start(onSamples: { _, _ in }, onError: { _ in }, onCompletion: { completed.signal() })
        XCTAssertEqual(driver.started.wait(timeout: .now() + 1), .success)
        driver.emit([0.2, 0.3, 0.4])
        driver.changeDevice()
        XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(capture.stop(), [0.2, 0.3, 0.4])
        driver.changeDevice()
        XCTAssertEqual(completed.wait(timeout: .now() + 0.05), .timedOut)
    }
    func testPermissionAndDuplicateStartAreRejected() throws {
        let driver = CaptureTestDriver()
        let denied = AudioCapture(driver: driver, microphoneAuthorized: { false })
        XCTAssertThrowsError(try denied.start(onSamples: { _, _ in }, onError: { _ in }))
        XCTAssertFalse(denied.isRunning)
        let capture = AudioCapture(driver: driver, microphoneAuthorized: { true })
        try capture.start(onSamples: { _, _ in }, onError: { _ in })
        XCTAssertThrowsError(try capture.start(onSamples: { _, _ in }, onError: { _ in }))
        XCTAssertTrue(capture.isRunning)
        _ = capture.stop()
    }
}
