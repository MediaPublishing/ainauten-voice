import Foundation
import CryptoKit

public struct ModelFile: Codable, Sendable {
    public let path: String
    public let url: URL
    public let sha256: String
    public let size: Int64
    public let group: String
}
public struct ModelManifest: Codable, Sendable {
    public let version: Int
    public let files: [ModelFile]
    public static func bundled() throws -> ModelManifest {
        let appResources = Bundle.main.resourceURL?.appendingPathComponent("VoiceWispr_VoiceWisprCore.bundle/Resources/model-manifest.json")
        let url: URL?
        if Bundle.main.bundleURL.pathExtension == "app" { url = appResources }
        else { url = Bundle.module.url(forResource: "model-manifest", withExtension: "json", subdirectory: "Resources") }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { throw VoiceError.message("Modellverzeichnis fehlt im Paket.") }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

public enum ModelPaths {
    public static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Voice Wispr", isDirectory: true)
    public static let models = support.appendingPathComponent("Models", isDirectory: true)
    public static let speech = models.appendingPathComponent("parakeet", isDirectory: true)
    public static let activity = models.appendingPathComponent("vad/silero-vad-unified-256ms-v6.2.1.mlmodelc", isDirectory: true)
    public static let formatter = models.appendingPathComponent("Qwen3-4B-Instruct-2507-Q4_K_M.gguf")
}

public actor ModelDownloader {
    public typealias Progress = @Sendable (Int64, Int64, String) -> Void
    public let root: URL
    private let manifest: ModelManifest?
    private let sessionConfiguration: URLSessionConfiguration?
    private var current: FileTransfer?
    private let discard: @Sendable (URL) -> Void
    public init(root: URL = ModelPaths.models, manifest: ModelManifest? = nil, sessionConfiguration: URLSessionConfiguration? = nil, discard: @escaping @Sendable (URL) -> Void = { ModelDownloader.trash($0) }) { self.root = root; self.manifest = manifest; self.sessionConfiguration = sessionConfiguration; self.discard = discard }
    /// A rejected model can be 2.5 GB. Keep one fixed quarantine per file and clear
    /// it (plus `.invalid-<UUID>` copies from older builds) before the next attempt.
    static func quarantine(for destination: URL) -> URL { destination.appendingPathExtension("invalid") }
    public static func trash(_ url: URL) {
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { try? FileManager.default.removeItem(at: url) }
    }
    private func clearQuarantine(for destination: URL) {
        let name = Self.quarantine(for: destination).lastPathComponent
        let siblings = (try? FileManager.default.contentsOfDirectory(at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        for url in siblings where url.lastPathComponent == name || url.lastPathComponent.hasPrefix(name + "-") { discard(url) }
    }
    private func activeManifest() throws -> ModelManifest { try manifest ?? ModelManifest.bundled() }
    public func cancel() { current?.cancel() }
    public func installed(includeFormatter: Bool = true) async throws -> Bool {
        for file in try activeManifest().files.filter({ includeFormatter || $0.group != "qwen" }) {
            try Task.checkCancellation()
            let url = root.appendingPathComponent(file.path)
            guard (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(file.size),
                  (try? String(contentsOfFile: url.path + ".verified", encoding: .utf8)) == file.sha256 else { return false }
            let digest = try await Task.detached(priority: .utility) { try Self.digest(url) }.value
            guard digest == file.sha256 else { return false }
        }
        return true
    }
    public func install(includeFormatter: Bool = true, progress: @escaping Progress) async throws {
        let files = try activeManifest().files.filter { includeFormatter || $0.group != "qwen" }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files { clearQuarantine(for: root.appendingPathComponent(file.path)) }
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        var completed: Int64 = 0
        let needed = files.reduce(Int64(0)) { sum, file in
            let existing = (try? root.appendingPathComponent(file.path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let partial = (try? root.appendingPathComponent(file.path + ".partial").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + max(0, file.size - Int64(max(existing, partial)))
        }
        if let capacity = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, capacity < needed + 512 * 1024 * 1024 {
            throw VoiceError.message("Nicht genug Speicherplatz. Bitte mindestens \(ByteCountFormatter.string(fromByteCount: needed + 512 * 1024 * 1024, countStyle: .file)) freimachen.")
        }
        for file in files {
            try Task.checkCancellation()
            let destination = root.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: destination.path) {
                let base = completed
                let transfer = FileTransfer(file: file, destination: destination, configuration: sessionConfiguration) { n in progress(base + n, total, file.group) }
                current = transfer
                try await withTaskCancellationHandler { try await transfer.run() } onCancel: { transfer.cancel() }
                current = nil
            }
            let digest = try await Task.detached(priority: .utility) { try Self.digest(destination) }.value
            guard digest == file.sha256 else {
                clearQuarantine(for: destination)
                try FileManager.default.moveItem(at: destination, to: Self.quarantine(for: destination))
                throw VoiceError.message("Prüfsumme stimmt nicht. Die Datei wurde isoliert; bitte Download erneut starten.")
            }
            try Data(file.sha256.utf8).write(to: URL(fileURLWithPath: destination.path + ".verified"), options: .atomic)
            completed += file.size; progress(completed, total, file.group)
        }
    }
    public static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var sha = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { sha.update(data: data) }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class FileTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let file: ModelFile
    private let destination: URL
    private let partial: URL
    private let progress: @Sendable (Int64) -> Void
    private let configuration: URLSessionConfiguration?
    private var handle: FileHandle?
    private var count: Int64 = 0
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let lock = NSLock()
    private var cancelled = false
    private var failure: Error?
    init(file: ModelFile, destination: URL, configuration: URLSessionConfiguration?, progress: @escaping @Sendable (Int64) -> Void) {
        self.file = file; self.destination = destination; self.partial = URL(fileURLWithPath: destination.path + ".partial"); self.configuration = configuration; self.progress = progress
    }
    func run() async throws {
        if !FileManager.default.fileExists(atPath: partial.path) { FileManager.default.createFile(atPath: partial.path, contents: nil) }
        handle = try FileHandle(forWritingTo: partial)
        count = Int64(try handle!.seekToEnd())
        if count > file.size { try handle!.truncate(atOffset: 0); count = 0 }
        if count == file.size { try handle?.close(); try FileManager.default.moveItem(at: partial, to: destination); return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.lock(); defer { lock.unlock() }
            if cancelled { try? handle?.close(); c.resume(throwing: CancellationError()); return }
            continuation = c
            let config = configuration ?? URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 7200
            session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            var request = URLRequest(url: file.url)
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if count > 0 { request.setValue("bytes=\(count)-", forHTTPHeaderField: "Range") }
            task = session!.dataTask(with: request); task!.resume()
        }
    }
    func cancel() { lock.lock(); cancelled = true; task?.cancel(); lock.unlock() }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, [200, 206].contains(response.statusCode) else {
            lock.lock(); failure = VoiceError.message("Downloadserver hat eine ungültige Antwort geliefert."); lock.unlock()
            completionHandler(.cancel); return
        }
        if response.statusCode == 200 && count > 0 { do { try handle?.truncate(atOffset: 0); try handle?.seek(toOffset: 0); count = 0 } catch { completionHandler(.cancel); return } }
        if response.statusCode == 206 && !(response.value(forHTTPHeaderField: "Content-Range") ?? "").hasPrefix("bytes \(count)-") {
            lock.lock(); failure = VoiceError.message("Der Downloadserver hat den Fortsetzungsbereich abgelehnt."); lock.unlock()
            completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do { guard count + Int64(data.count) <= file.size else { throw VoiceError.message("Unerwartete Downloadgröße.") }; try handle?.write(contentsOf: data); count += Int64(data.count); progress(count) } catch { dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        lock.lock(); let explicitCancel = cancelled; let recordedFailure = failure; lock.unlock()
        var outcome = recordedFailure ?? error
        if outcome is URLError && (outcome as? URLError)?.code == .cancelled {
            outcome = explicitCancel ? CancellationError() : VoiceError.message("Download wurde unerwartet abgebrochen.")
        }
        if outcome == nil {
            do {
                guard count == file.size else { throw VoiceError.message("Download unvollständig. Er wird beim nächsten Start fortgesetzt.") }
                try FileManager.default.moveItem(at: partial, to: destination)
            } catch { outcome = error }
        }
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        if let outcome { c?.resume(throwing: outcome) } else { c?.resume() }
        session.finishTasksAndInvalidate()
    }
}
