import XCTest
import Foundation
@testable import VoiceWisprCore

final class DownloadTests: XCTestCase {
    func testOptionalSwissGroupDoesNotChangeDefaultInstallation() async throws {
        Self.FixtureProtocol.reset()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swiss-groups-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let hash = root.appendingPathComponent("hash"); try Self.FixtureProtocol.payload.write(to: hash)
        let sha = try ModelDownloader.digest(hash)
        let base = ModelFile(path: "base.bin", url: URL(string: "fixture://base")!, sha256: sha, size: 10, group: "vad")
        let formatter = ModelFile(path: "formatter.bin", url: URL(string: "fixture://formatter")!, sha256: sha, size: 10, group: "qwen")
        let swiss = ModelFile(path: "swiss/model.bin", url: URL(string: "fixture://swiss")!, sha256: sha, size: 10, group: SwissGermanModel.group)
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [Self.FixtureProtocol.self]
        let downloader = ModelDownloader(root: root, manifest: .init(version: 1, files: [base, formatter, swiss]), sessionConfiguration: cfg)
        try await downloader.install(includeFormatter: false) { _, _, _ in }
        let originalReady = try await downloader.installed(includeFormatter: false)
        XCTAssertTrue(originalReady)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(swiss.path).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(formatter.path).path))
        try await downloader.install(groups: [SwissGermanModel.group]) { _, _, group in XCTAssertEqual(group, SwissGermanModel.group) }
        let swissReady = try await downloader.installed(groups: [SwissGermanModel.group])
        XCTAssertTrue(swissReady)
        let empty = try await downloader.installed(groups: [])
        let unknown = try await downloader.installed(groups: [SwissGermanModel.group, "missing"])
        XCTAssertFalse(empty); XCTAssertFalse(unknown)
        do { try await downloader.install(groups: ["missing"]) { _, _, _ in }; XCTFail("Unknown group must not succeed") } catch { }
        try await downloader.install { _, _, group in XCTAssertFalse(group == SwissGermanModel.group) }
        let defaultReady = try await downloader.installed()
        XCTAssertTrue(defaultReady)
    }
    func testConcurrentInstallCannotReplaceTheCancelableTransfer() async throws {
        Self.FixtureProtocol.reset(); Self.FixtureProtocol.delay = true
        defer { Self.FixtureProtocol.reset() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swiss-concurrent-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let hash = root.appendingPathComponent("hash"); try Self.FixtureProtocol.payload.write(to: hash)
        let file = ModelFile(path: "model.bin", url: URL(string: "fixture://concurrent")!, sha256: try ModelDownloader.digest(hash), size: 10, group: "vad")
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [Self.FixtureProtocol.self]
        let downloader = ModelDownloader(root: root, manifest: .init(version: 1, files: [file]), sessionConfiguration: cfg)
        let first = Task { try await downloader.install { _, _, _ in } }
        try await Task.sleep(for: .milliseconds(40))
        do { try await downloader.install { _, _, _ in }; XCTFail("Concurrent transfer must be rejected") } catch { }
        await downloader.cancel()
        do { try await first.value; XCTFail("Expected cancellation of the original transfer") } catch { XCTAssertTrue(error is CancellationError) }
    }
    final class FixtureProtocol: URLProtocol {
        static var payload = Data("0123456789".utf8)
        static var wrongRange = false
        static var delay = false
        static var force200ForRange = false
        static var truncateResponse = false
        static var oversizedResponse = false
        static func reset() {
            payload = Data("0123456789".utf8)
            wrongRange = false; delay = false; force200ForRange = false
            truncateResponse = false; oversizedResponse = false
        }
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if Self.delay { Thread.sleep(forTimeInterval: 0.4) }
            let range = request.value(forHTTPHeaderField: "Range")
            let start = Int(range?.split(separator: "=").last?.split(separator: "-").first ?? "0") ?? 0
            let offset = Self.force200ForRange ? 0 : min(start, Self.payload.count)
            let body = Self.payload.subdata(in: offset..<Self.payload.count)
            let status = (start > 0 && !Self.force200ForRange) ? 206 : 200
            let headerStart = Self.wrongRange ? start + 1 : start
            let headers = ["Content-Length": "\(body.count)", "Content-Range": "bytes \(headerStart)-\(Self.payload.count - 1)/\(Self.payload.count)"]
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            let responseBody = Self.oversizedResponse ? body + Data(repeating: 0xAA, count: 2) : (Self.truncateResponse ? body.prefix(max(1, body.count / 2)) : body)
            client?.urlProtocol(self, didLoad: Data(responseBody)); client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func testResumesPartialRangeAndRejectsWrongContentRange() async throws {
        Self.FixtureProtocol.reset()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voice-wispr-dl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data("0123456789".utf8); Self.FixtureProtocol.payload = payload; Self.FixtureProtocol.wrongRange = false
        let hashURL = root.appendingPathComponent("hash-input"); try payload.write(to: hashURL)
        let file = ModelFile(path: "tiny.bin", url: URL(string: "fixture://tiny")!, sha256: try ModelDownloader.digest(hashURL), size: Int64(payload.count), group: "speech")
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [Self.FixtureProtocol.self]
        let downloader = ModelDownloader(root: root, manifest: ModelManifest(version: 1, files: [file]), sessionConfiguration: cfg)
        try Data(payload.prefix(4)).write(to: root.appendingPathComponent("tiny.bin.partial"))
        try await downloader.install { _, _, _ in }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("tiny.bin")), payload)
        try? FileManager.default.removeItem(at: root.appendingPathComponent("tiny.bin"))
        try? FileManager.default.removeItem(at: root.appendingPathComponent("tiny.bin.verified"))
        try Data(payload.prefix(4)).write(to: root.appendingPathComponent("tiny.bin.partial"))
        Self.FixtureProtocol.wrongRange = true
        do { try await downloader.install { _, _, _ in }; XCTFail("expected range error") } catch { XCTAssertTrue(String(describing: error).contains("Fortsetzungsbereich")) }
    }

    func testExplicitCancelBecomesCancellationErrorAndKeepsPartial() async throws {
        Self.FixtureProtocol.reset()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voice-wispr-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data("0123456789".utf8); Self.FixtureProtocol.payload = payload; Self.FixtureProtocol.wrongRange = false; Self.FixtureProtocol.delay = true
        defer { Self.FixtureProtocol.delay = false }
        let hashURL = root.appendingPathComponent("hash-input"); try payload.write(to: hashURL)
        let file = ModelFile(path: "tiny.bin", url: URL(string: "fixture://cancel")!, sha256: try ModelDownloader.digest(hashURL), size: Int64(payload.count), group: "speech")
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [Self.FixtureProtocol.self]
        let downloader = ModelDownloader(root: root, manifest: ModelManifest(version: 1, files: [file]), sessionConfiguration: cfg)
        let task = Task { try await downloader.install { _, _, _ in } }
        try await Task.sleep(for: .milliseconds(30)); await downloader.cancel()
        do { try await task.value; XCTFail("expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("tiny.bin.partial").path))
    }

    func testInstalledRejectsSameSizeCorruption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voice-wispr-installed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data("0123456789".utf8), hashURL = root.appendingPathComponent("hash-input"); try payload.write(to: hashURL)
        let file = ModelFile(path: "tiny.bin", url: URL(string: "fixture://installed")!, sha256: try ModelDownloader.digest(hashURL), size: Int64(payload.count), group: "speech")
        let manifest = ModelManifest(version: 1, files: [file]); let destination = root.appendingPathComponent(file.path)
        try payload.write(to: destination); try Data(file.sha256.utf8).write(to: URL(fileURLWithPath: destination.path + ".verified"))
        let downloader = ModelDownloader(root: root, manifest: manifest)
        let validInstalled = try await downloader.installed()
        XCTAssertTrue(validInstalled)
        try Data(repeating: 0xFF, count: payload.count).write(to: destination)
        let corruptedInstalled = try await downloader.installed()
        XCTAssertFalse(corruptedInstalled)
    }

    func testHTTP200ResetsAStalePartialAndCompletes() async throws {
        Self.FixtureProtocol.reset()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voice-wispr-200-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data("0123456789".utf8); Self.FixtureProtocol.payload = payload; Self.FixtureProtocol.force200ForRange = true; defer { Self.FixtureProtocol.force200ForRange = false }
        let hashURL = root.appendingPathComponent("hash"); try payload.write(to: hashURL)
        let file = ModelFile(path: "tiny.bin", url: URL(string: "fixture://reset")!, sha256: try ModelDownloader.digest(hashURL), size: Int64(payload.count), group: "speech"); let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [Self.FixtureProtocol.self]
        try Data("stale".utf8).write(to: root.appendingPathComponent("tiny.bin.partial")); try await ModelDownloader(root: root, manifest: ModelManifest(version: 1, files: [file]), sessionConfiguration: cfg).install { _,_,_ in }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("tiny.bin")), payload)
    }

    func testTruncatedResponseResumesAndOversizedResponseFails() async throws {
        Self.FixtureProtocol.reset()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voice-wispr-trunc-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data("0123456789".utf8); Self.FixtureProtocol.payload = payload; Self.FixtureProtocol.truncateResponse = true
        let hashURL = root.appendingPathComponent("hash"); try payload.write(to: hashURL); let file = ModelFile(path: "tiny.bin", url: URL(string: "fixture://trunc")!, sha256: try ModelDownloader.digest(hashURL), size: Int64(payload.count), group: "speech"); let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [Self.FixtureProtocol.self]; let downloader = ModelDownloader(root: root, manifest: ModelManifest(version: 1, files: [file]), sessionConfiguration: cfg)
        do { try await downloader.install { _,_,_ in }; XCTFail("expected incomplete response") } catch { }
        Self.FixtureProtocol.truncateResponse = false; try await downloader.install { _,_,_ in }; XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("tiny.bin")), payload)
        Self.FixtureProtocol.oversizedResponse = true; try? FileManager.default.removeItem(at: root.appendingPathComponent("tiny.bin")); try? FileManager.default.removeItem(at: root.appendingPathComponent("tiny.bin.verified")); do { try await downloader.install { _,_,_ in }; XCTFail("expected oversized response") } catch { }
        Self.FixtureProtocol.oversizedResponse = false
    }

    func testBadHashKeepsOneQuarantinePerFileAndClearsOlderOnes() async throws {
        Self.FixtureProtocol.reset()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voice-wispr-hash-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data("bad-payload".utf8); Self.FixtureProtocol.payload = payload; let expected = Data("expected".utf8); let hashURL = root.appendingPathComponent("hash"); try expected.write(to: hashURL)
        final class Discarded: @unchecked Sendable { let lock = NSLock(); var names: [String] = []; func add(_ url: URL) { lock.lock(); names.append(url.lastPathComponent); lock.unlock(); try? FileManager.default.removeItem(at: url) } }
        let discarded = Discarded(), legacy = root.appendingPathComponent("tiny.bin.invalid-\(UUID().uuidString)"); try payload.write(to: legacy)
        let file = ModelFile(path: "tiny.bin", url: URL(string: "fixture://hash")!, sha256: try ModelDownloader.digest(hashURL), size: Int64(payload.count), group: "speech"); let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [Self.FixtureProtocol.self]; let downloader = ModelDownloader(root: root, manifest: ModelManifest(version: 1, files: [file]), sessionConfiguration: cfg, discard: { discarded.add($0) })
        func quarantined() throws -> [String] { try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).map(\.lastPathComponent).filter { $0.contains("invalid") } }
        do { try await downloader.install { _,_,_ in }; XCTFail("expected hash error") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("tiny.bin").path))
        XCTAssertEqual(try quarantined(), ["tiny.bin.invalid"]); XCTAssertEqual(discarded.names, [legacy.lastPathComponent])
        do { try await downloader.install { _,_,_ in }; XCTFail("expected hash error") } catch { }
        XCTAssertEqual(try quarantined(), ["tiny.bin.invalid"]); XCTAssertEqual(discarded.names, [legacy.lastPathComponent, "tiny.bin.invalid"])
    }
    func testInjectedManifestAndDigestUseSmallFixture() throws {
        let bytes = Data("voice-wispr-fixture\n".utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-wispr-download-\(UUID().uuidString)")
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let digest = try ModelDownloader.digest(url)
        XCTAssertEqual(digest, "ecb6f9486afcfd90c3108a8ce0788e1d3498210a8165f4ebd8a429b0ea2d27b3")
    }

    func testInjectedManifestRoundTripsWithoutBundledModels() throws {
        let file = ModelFile(path: "tiny.bin", url: URL(string: "http://127.0.0.1/tiny.bin")!, sha256: String(repeating: "0", count: 64), size: 3, group: "speech")
        let manifest = ModelManifest(version: 1, files: [file])
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(ModelManifest.self, from: data)
        XCTAssertEqual(decoded.files.first?.path, "tiny.bin")
        XCTAssertEqual(decoded.files.first?.size, 3)
        _ = ModelDownloader(root: FileManager.default.temporaryDirectory, manifest: decoded)
    }
}
