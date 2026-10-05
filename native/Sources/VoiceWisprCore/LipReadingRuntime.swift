import Foundation
import Darwin

public enum LipReadingLanguage: String, CaseIterable, Sendable, Identifiable {
    case english = "en", german = "de"
    public var id: String { rawValue }
    public var title: String { self == .german ? "Deutsch" : "Englisch" }
    /// The current German research checkpoint is too inaccurate to insert
    /// unreviewed text automatically. Audio dictation is unaffected.
    public var requiresReview: Bool { self == .german }
    public static var defaultShortcut: Shortcut { Shortcut(keyCode: 37, modifiers: (1 << 18) | (1 << 19) | (1 << 20)) }
}

/// Own child process, bounded NDJSON, no diagnostics containing video or text.
private final class LipWorkerProcess: @unchecked Sendable {
    let process = Process()
    private let input = Pipe(), output = Pipe()
    private let writeQueue = DispatchQueue(label: "com.mediapublishing.voice.lip.ipc")
    private let lock = NSLock()
    private var pending = Data()
    private var closed = false
    let messages: AsyncThrowingStream<[String: String], Error>
    private let continuation: AsyncThrowingStream<[String: String], Error>.Continuation
    init(executable: URL, arguments: [String]) throws {
        var yielded: AsyncThrowingStream<[String: String], Error>.Continuation!
        messages = AsyncThrowingStream { yielded = $0 }; continuation = yielded
        process.executableURL = executable; process.arguments = arguments
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "PYTHONUNBUFFERED": "1", "PYTHONDONTWRITEBYTECODE": "1", "PYTHONIOENCODING": "utf-8", "TOKENIZERS_PARALLELISM": "false", "OMP_NUM_THREADS": "4", "PYTORCH_ENABLE_MPS_FALLBACK": "1"]
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] { environment["TMPDIR"] = tmp }
        process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { self?.continuation.finish(throwing: VoiceError.message("Die Lippenlese-Laufzeit wurde beendet.")); return }
            self?.receive(data)
        }
        process.terminationHandler = { [weak self] _ in self?.continuation.finish(throwing: VoiceError.message("Die Lippenlese-Laufzeit wurde beendet.")) }
        try process.run()
    }
    private func receive(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        pending.append(data)
        guard pending.count <= 65_536 else { continuation.finish(throwing: VoiceError.message("Ungültige Antwort der Lippenlese-Laufzeit.")); return }
        while let index = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: index); pending.removeSubrange(...index)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continuation.finish(throwing: VoiceError.message("Die Lippenlese-Laufzeit hat ungültige Daten geliefert.")); return }
            let values = object.reduce(into: [String: String]()) { if let value = $1.value as? String { $0[$1.key] = value } }
            continuation.yield(values)
        }
    }
    func send(_ objects: [[String: Any]]) async throws {
        try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
            writeQueue.async {
                do {
                    for object in objects {
                        self.lock.lock(); let active = !self.closed; self.lock.unlock()
                        guard active else { throw CancellationError() }
                        var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
                        try self.input.fileHandleForWriting.write(contentsOf: data)
                    }
                    reply.resume()
                } catch { reply.resume(throwing: error) }
            }
        }
    }
    func shutdown() {
        lock.lock(); guard !closed else { lock.unlock(); return }; closed = true; pending = Data(); lock.unlock()
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close(); continuation.finish(throwing: CancellationError())
        guard process.isRunning else { return }
        process.terminate()
        let child = process
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { if child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL) } }
    }
    deinit { shutdown() }
}

public actor LipReadingRuntime {
    public let root: URL
    public let resources: URL
    private var child: LipWorkerProcess?
    private var language: LipReadingLanguage?
    private var ready = false
    private var activeSession: UUID?
    public init(root: URL = ModelPaths.support.appendingPathComponent("LipReading"), resources: URL) { self.root = root; self.resources = resources }
    public func installed(_ language: LipReadingLanguage) -> Bool {
        FileManager.default.isExecutableFile(atPath: root.appendingPathComponent(language.rawValue + "/.venv/bin/python").path)
    }
    public func prepare(_ requested: LipReadingLanguage) async throws {
        if ready && language == requested { return }
        cancel()
        let python = root.appendingPathComponent(requested.rawValue + "/.venv/bin/python")
        guard installed(requested) else { throw VoiceError.message("Bitte richte zuerst die Lippenlesen-Beta für \(requested.title) ein.") }
        let worker = try LipWorkerProcess(executable: python, arguments: ["-u", resources.appendingPathComponent("worker.py").path, "--language", requested.rawValue, "--root", root.path])
        child = worker; language = requested
        do {
            let message = try await response(worker, timeout: 120, session: nil)
            guard child === worker, message["type"] == "ready", message["language"] == requested.rawValue else { throw VoiceError.message("Lippenlese-Modell ist nicht bereit.") }
            ready = true
        } catch { if child === worker { cancel() }; throw error }
    }
    public func transcribe(_ frames: [LipReadingFrame], session: UUID) async throws -> String {
        guard ready, let worker = child else { throw VoiceError.message("Das Lippenlese-Modell ist noch nicht bereit.") }
        guard activeSession == nil else { throw VoiceError.message("Eine Lippenaufnahme wird bereits verarbeitet.") }
        guard frames.count >= 8, frames.count <= CameraCapture.maximumFrames,
              frames.reduce(0, { $0 + $1.jpeg.count }) <= CameraCapture.maximumBytes,
              frames.allSatisfy({ !$0.jpeg.isEmpty && $0.jpeg.count <= 150_000 && (0...30_000).contains($0.milliseconds) }),
              zip(frames, frames.dropFirst()).allSatisfy({ $0.milliseconds < $1.milliseconds }) else { throw VoiceError.message("Die Lippenaufnahme ist zu kurz oder überschreitet die Beta-Grenze.") }
        let id = session.uuidString.lowercased()
        activeSession = session
        defer { if activeSession == session { activeSession = nil } }
        let objects: [[String: Any]] = [["op": "begin", "session": id, "ts_ms": 0]] + frames.map { ["op": "frame", "session": id, "ts_ms": $0.milliseconds, "jpeg": $0.jpeg.base64EncodedString()] } + [["op": "finish", "session": id]]
        do {
            return try await withTaskCancellationHandler {
                try await worker.send(objects)
                let message = try await response(worker, timeout: 120, session: id)
                guard child === worker, !Task.isCancelled, message["type"] == "result", let text = message["text"], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 16_384 else { throw VoiceError.message("Keine Worte erkannt. Bitte schaue direkt in die Kamera und forme einen kurzen Satz.") }
                return text
            } onCancel: { worker.shutdown() }
        } catch {
            // A protocol error may leave a partial session in the worker.
            // Never reuse it or mistake late replies for a fresh recording.
            if child === worker { cancel() }
            throw error
        }
    }
    private func response(_ worker: LipWorkerProcess, timeout: Double, session: String?) async throws -> [String: String] {
        try await withThrowingTaskGroup(of: [String: String].self) { group in
            group.addTask {
                for try await message in worker.messages {
                    if message["type"] == "error" { throw VoiceError.message(message["message"] ?? "Lippenlesen nicht verfügbar.") }
                    if let session { if message["session"] == session && message["type"] == "result" { return message } }
                    else if message["type"] == "ready" { return message }
                }
                throw VoiceError.message("Die Lippenlese-Laufzeit wurde beendet.")
            }
            group.addTask { try await Task.sleep(for: .seconds(timeout)); worker.shutdown(); throw VoiceError.message("Die Lippenlesen-Beta hat zu lange gebraucht. Bitte starte sie erneut.") }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }; return first
        }
    }
    public func cancel() { child?.shutdown(); child = nil; ready = false; language = nil; activeSession = nil }
}
