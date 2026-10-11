import Foundation
import Darwin

/// Re-recognizes the original PCM with an explicit language. The separately
/// signed helper isolates Whisper/ggml from the existing llama runtime.
struct WhisperLanguageFallback: Sendable {
    struct Output: Codable { let text: String; let words: [Word] }
    struct Word: Codable { let text: String; let start: Double; let end: Double }
    let executable: URL
    let model: URL
    static var bundled: Self {
        let root = Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/SpeechFallback")
            : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/upstream/speech-fallback")
        return .init(executable: root.appendingPathComponent(Bundle.main.bundleURL.pathExtension == "app" ? "AInautenSpeechFallback" : "build/AInautenSpeechFallback"), model: root.appendingPathComponent("ggml-small-q5_1.bin"))
    }
    func transcribe(_ samples: [Float], language: String, sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        guard (4800...AudioCaptureBuffer.maximumSamples).contains(samples.count),
              FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.fileExists(atPath: model.path),
              language.range(of: "^(auto|[a-z]{2,3})$", options: .regularExpression) != nil else { throw SpeechLanguageError.mismatch }
        let worker = SpeechFallbackProcess(executable: executable, arguments: [model.path, language])
        let bytes = samples.withUnsafeBytes { Data($0) }
        let task = Task.detached(priority: .userInitiated) { try worker.run(bytes) }
        let output = try await withTaskCancellationHandler { try await task.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        return try Self.decode(output, sessionID: sessionID, index: index, offset: offset, duration: Double(samples.count) / 16000)
    }
    static func decode(_ bytes: Data, sessionID: UUID, index: Int, offset: Double, duration: Double) throws -> TranscriptSegment {
        let value = try JSONDecoder().decode(Output.self, from: bytes)
        let text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !value.words.isEmpty,
              value.words.allSatisfy({ !$0.text.isEmpty && $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start && $0.end <= duration + 0.1 }),
              value.words.map(\.text).joined(separator: " ").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) == text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) else { throw SpeechLanguageError.mismatch }
        return .init(sessionID: sessionID, index: index, text: text,
                     words: value.words.map { .init(text: $0.text, start: offset + $0.start, end: offset + $0.end) })
    }
}

private final class SpeechFallbackProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private var timedOut = false
    init(executable: URL, arguments: [String]) { process.executableURL = executable; process.arguments = arguments }
    func cancel() {
        lock.lock(); cancelled = true; if process.isRunning { process.terminate() }; lock.unlock()
    }
    func run(_ pcm: Data) throws -> Data {
        let input = Pipe(), output = Pipe()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try process.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        let writer = DispatchGroup(); writer.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? input.fileHandleForWriting.close(); writer.leave() }
            // Writes in small blocks allow cancellation while the model initializes.
            for start in stride(from: 0, to: pcm.count, by: 65536) {
                do { try input.fileHandleForWriting.write(contentsOf: pcm[start..<min(pcm.count, start + 65536)]) } catch { return }
            }
        }
        let deadline = DispatchWorkItem { [self] in
            lock.lock(); timedOut = true; if process.isRunning { process.terminate() }; lock.unlock()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: deadline)
        defer { deadline.cancel(); try? output.fileHandleForReading.close() }
        var data = Data()
        while let part = try output.fileHandleForReading.read(upToCount: 65536), !part.isEmpty {
            guard data.count + part.count <= 6 * 1024 * 1024 else { cancel(); throw SpeechLanguageError.mismatch }
            data.append(part)
        }
        process.waitUntilExit(); writer.wait()
        lock.lock(); let wasCancelled = cancelled; let expired = timedOut; lock.unlock()
        if wasCancelled { throw CancellationError() }
        if expired { throw SpeechLanguageError.mismatch }
        guard process.terminationStatus == 0 else { throw SpeechLanguageError.mismatch }
        return data
    }
}
