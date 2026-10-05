import Foundation
import Darwin

/// Installs optional models in the user's private support folder. No camera,
/// dictation content, credentials or inherited provider environment is involved.
public actor LipReadingInstaller {
    private var process: Process?
    public init() {}
    public func install(language: LipReadingLanguage, root: URL, resources: URL, progress: @escaping @Sendable (String) -> Void) async throws {
        guard process == nil else { throw VoiceError.message("Die Beta wird bereits eingerichtet.") }
        let uv = resources.appendingPathComponent("uv")
        guard FileManager.default.isExecutableFile(atPath: uv.path) else { throw VoiceError.message("Die Beta-Laufzeit fehlt im App-Paket. Bitte installiere die vollständige App.") }
        let child = Process(), output = Pipe()
        child.executableURL = uv
        let script = resources.appendingPathComponent(language == .german ? "setup_german.py" : "setup_runtime.py")
        let destination = language == .german ? root.appendingPathComponent("de") : root
        child.arguments = ["run", "--no-project", "--python", "3.11", script.path, "--root", destination.path, "--uv", uv.path] + (language == .german ? ["--download"] : ["--language", "en", "--models"])
        child.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "PYTHONDONTWRITEBYTECODE": "1", "PYTHONUNBUFFERED": "1", "UV_NO_PROGRESS": "1"]
        child.standardOutput = output; child.standardError = FileHandle.nullDevice; child.standardInput = FileHandle.nullDevice
        let lines = InstallerLines(progress: progress)
        output.fileHandleForReading.readabilityHandler = { handle in lines.receive(handle.availableData) }
        process = child
        defer { if process === child { process = nil }; output.fileHandleForReading.readabilityHandler = nil }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
                child.terminationHandler = { finished in
                    if finished.terminationStatus == 0 { reply.resume() }
                    else { reply.resume(throwing: VoiceError.message("Die Beta konnte nicht eingerichtet werden. Der Download bleibt lokal; du kannst erneut versuchen.")) }
                }
                do { try child.run() } catch { child.terminationHandler = nil; reply.resume(throwing: error) }
            }
            try Task.checkCancellation()
        } onCancel: { Self.stop(child) }
    }
    public func cancel() { if let process { Self.stop(process) } }
    private nonisolated static func stop(_ process: Process) {
        guard process.isRunning else { return }; process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) } }
    }
}

private final class InstallerLines: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    let progress: @Sendable (String) -> Void
    init(progress: @escaping @Sendable (String) -> Void) { self.progress = progress }
    func receive(_ data: Data) {
        lock.withLock {
            buffer.append(data)
            guard buffer.count < 65_536 else { buffer = Data(); return }
            while let end = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let state = object["state"] as? String else { continue }
                let labels = ["start": "Laufzeit wird eingerichtet …", "source_pinned": "Lokale Erkennung wird vorbereitet …", "model_download": "Modell wird heruntergeladen …", "model_verified": "Modell geprüft", "complete": "Download abgeschlossen"]
                if let label = labels[state] {
                    if state == "model_download", let current = object["current"] as? Int64, let total = object["total"] as? Int64, total > 0 {
                        progress(label + " \(min(100, current * 100 / total)) %")
                    } else { progress(label) }
                }
            }
        }
    }
}
