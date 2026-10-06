import Foundation
import VoiceWisprCore

/// Real URLSession download transport; only an explicitly owned loopback fixture.
@main struct DownloadTransportChecks {
    final class ProgressState: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes: Int64 = 0
        func update(_ value: Int64) { lock.lock(); bytes = value; lock.unlock() }
        func current() -> Int64 { lock.lock(); defer { lock.unlock() }; return bytes }
    }
    static func manifest(_ base: URL, _ endpoint: String, _ hash: String, _ size: Int) throws -> ModelManifest {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "files": [[
            "path": "payload.bin", "url": base.appendingPathComponent(endpoint).absoluteString,
            "sha256": hash, "size": size, "group": "speech"]]])
        return try JSONDecoder().decode(ModelManifest.self, from: data)
    }
    static func seconds(_ start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
    static func main() async throws {
        guard CommandLine.arguments.count == 5,
              let base = URL(string: CommandLine.arguments[1]), base.scheme == "http", base.host == "127.0.0.1",
              let size = Int(CommandLine.arguments[4]), size == 1_048_576 else { return }
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).standardizedFileURL
        guard root.lastPathComponent.hasPrefix("AInauten-Voice-Downloads-"),
              root.path.contains("/native/artifacts/"), !FileManager.default.fileExists(atPath: root.path) else { return }
        let hash = CommandLine.arguments[3]
        guard hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var results: [[String: Any]] = []
        for name in ["success", "interruptedResume", "cancelResume", "wrongRange", "reset200", "badHash", "sameSizeCorruption", "oversized"] {
            let destination = root.appendingPathComponent(name, isDirectory: true)
            let endpoint = name
            let downloader = ModelDownloader(root: destination, manifest: try manifest(base, endpoint, hash, size), discard: { url in
                // Preserve any own rejected fixture instead of permanently deleting.
                let archive = url.appendingPathExtension("retained-" + UUID().uuidString)
                try? FileManager.default.moveItem(at: url, to: archive)
            })
            let file = destination.appendingPathComponent("payload.bin")
            let partial = destination.appendingPathComponent("payload.bin.partial")
            let marker = destination.appendingPathComponent("payload.bin.verified")
            let start = ContinuousClock.now
            var passed = false, details: [String: Any] = [:]
            do {
                switch name {
                case "interruptedResume":
                    var rejected = false
                    do { try await downloader.install { _, _, _ in } } catch { rejected = true }
                    let retained = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let noPrematureInstall = !FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: marker.path)
                    try await downloader.install { _, _, _ in }
                    let installed = try await downloader.installed()
                    passed = rejected && retained > 0 && retained < size && noPrematureInstall && installed
                    details = ["interruptionRejected": rejected, "retainedBytes": retained, "noPrematureInstall": noPrematureInstall]
                case "cancelResume":
                    let state = ProgressState()
                    let task = Task { try await downloader.install { count, _, _ in state.update(count) } }
                    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
                    while state.current() == 0 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
                    let hadProgress = state.current() > 0
                    let cancelledAt = ContinuousClock.now
                    await downloader.cancel()
                    var cancellation = false
                    do { try await task.value } catch { cancellation = error is CancellationError }
                    let cancelSeconds = seconds(cancelledAt)
                    let retained = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let noPrematureInstall = !FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: marker.path)
                    try await downloader.install { _, _, _ in }
                    let installed = try await downloader.installed()
                    passed = hadProgress && cancellation && cancelSeconds < 1 && retained > 0 && retained < size && noPrematureInstall && installed
                    details = ["cancelAfterActualProgress": hadProgress, "cancellationError": cancellation,
                               "secondsAfterCancel": cancelSeconds, "retainedBytes": retained, "noPrematureInstall": noPrematureInstall]
                case "wrongRange", "reset200":
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    let prefix = Data((0..<4096).map { UInt8($0 % 251) })
                    try prefix.write(to: partial)
                    if name == "wrongRange" {
                        var rejected = false
                        do { try await downloader.install { _, _, _ in } }
                        catch { rejected = error.localizedDescription.contains("Fortsetzungsbereich") }
                        let partialMatches = try Data(contentsOf: partial) == prefix
                        passed = rejected && partialMatches && !FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: marker.path)
                        details = ["rangeRejected": rejected, "partialUnchanged": partialMatches]
                    } else {
                        try await downloader.install { _, _, _ in }
                        passed = try await downloader.installed()
                        details = ["stalePartialReset": passed]
                    }
                case "badHash":
                    var rejected = false
                    do { try await downloader.install { _, _, _ in } }
                    catch { rejected = error.localizedDescription.contains("Prüfsumme") }
                    let isolated = destination.appendingPathComponent("payload.bin.invalid")
                    let installed = try await downloader.installed()
                    passed = rejected && FileManager.default.fileExists(atPath: isolated.path)
                        && !FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: marker.path)
                        && !installed
                    details = ["hashRejected": rejected, "isolated": FileManager.default.fileExists(atPath: isolated.path)]
                case "sameSizeCorruption":
                    try await downloader.install { _, _, _ in }
                    let good = try await downloader.installed()
                    let handle = try FileHandle(forWritingTo: file)
                    try handle.write(contentsOf: Data([255])); try handle.close()
                    let unchangedSize = (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) == size
                    let stillInstalled = try await downloader.installed()
                    passed = good && unchangedSize && FileManager.default.fileExists(atPath: marker.path) && !stillInstalled
                    details = ["initiallyVerified": good, "sameSize": unchangedSize, "staleVerifiedMarkerRejected": passed]
                case "oversized":
                    var rejected = false
                    do { try await downloader.install { _, _, _ in } } catch { rejected = true }
                    passed = rejected && !FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: marker.path)
                    details = ["oversizedRejected": rejected]
                default:
                    try await downloader.install { _, _, _ in }
                    passed = try await downloader.installed()
                }
                if ["success", "interruptedResume", "cancelResume", "reset200"].contains(name) {
                    let digestMatches = try ModelDownloader.digest(file) == hash
                    let sizeMatches = (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) == size
                    passed = passed && digestMatches && sizeMatches
                    details["finalDigestMatches"] = digestMatches
                }
            } catch {
                passed = false
                details["errorType"] = String(describing: type(of: error))
                details["error"] = error.localizedDescription
            }
            results.append(["name": name, "passed": passed, "seconds": seconds(start), "details": details])
        }
        let report: [String: Any] = ["cases": results, "allPassed": results.count == 8 && results.allSatisfy { $0["passed"] as? Bool == true },
            "actualModelsUsed": false, "userModelDirectoryTouched": false, "applicationChanged": false,
            "scope": "Actual macOS Foundation HTTP and tiny fixture filesystem; no full model, production provider, installed app onboarding, denied network or physical interruption acceptance."]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
    }
}
