import XCTest
import Foundation
import Darwin
@testable import VoiceWisprCore

final class SecuritySettingsTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-security-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testBoundedLoaderRejectsSparseOversizedFilesLinksAndPipes() throws {
        let root = try directory(), large = root.appendingPathComponent("large.json")
        FileManager.default.createFile(atPath: large.path, contents: Data())
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(SettingsStore.maximumFileBytes + 1)); try handle.close()
        XCTAssertThrowsError(try SettingsStore.boundedData(from: large))
        let regular = root.appendingPathComponent("regular.json")
        try Data("{}".utf8).write(to: regular)
        let link = root.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: regular)
        XCTAssertThrowsError(try SettingsStore.boundedData(from: link))
        let pipe = root.appendingPathComponent("pipe.json")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertThrowsError(try SettingsStore.boundedData(from: pipe))
        XCTAssertEqual(try SettingsStore.boundedData(from: regular), Data("{}".utf8))
    }
    func testMalformedStartupStateIsPreservedBeforeSafeDefaultSave() async throws {
        let root = try directory(), url = root.appendingPathComponent("settings.json")
        let malformed = Data("not json".utf8); try malformed.write(to: url)
        let store = SettingsStore(url: url)
        do { _ = try await store.load(); XCTFail("Malformed settings accepted") } catch {}
        let saved = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(saved.count, 1); XCTAssertTrue(saved[0].lastPathComponent.hasPrefix("settings-quarantine-"))
        XCTAssertEqual(try Data(contentsOf: saved[0]), malformed)
        try await store.save(ExportDocument()); _ = try await store.load()
    }
    func testCollectionAndAggregateWorkBounds() throws {
        var document = ExportDocument()
        document.dictionary = (0..<10_001).map { DictionaryEntry(id: String($0), phrase: "Wort") }
        XCTAssertThrowsError(try SettingsStore.validate(document))
        document.dictionary = (0..<140).map { DictionaryEntry(id: String($0), phrase: "Wort", replacement: String(repeating: "x", count: 16_384)) }
        XCTAssertThrowsError(try SettingsStore.validate(document))
        document.dictionary = []; document.settings.cloudEndpoint = String(repeating: "x", count: 2049)
        XCTAssertThrowsError(try SettingsStore.validate(document))
        document = ExportDocument(dictionary: [DictionaryEntry(phrase: "AInauten")]); try SettingsStore.validate(document)
    }
    func testCloudRecipientNormalizationPreservesRecipientBoundaries() throws {
        XCTAssertEqual(try CloudRecipient.normalized(" HTTPS://API.EXAMPLE.COM:443/v1/ "), "https://api.example.com/v1")
        XCTAssertTrue(try CloudRecipient.normalized("https://api.example.com/v1") != CloudRecipient.normalized("https://api.example.com/v2"))
        XCTAssertTrue(try CloudRecipient.normalized("https://api.example.com/v1") != CloudRecipient.normalized("https://other.example.com/v1"))
        var credentialFixture = URLComponents(string: "https://api.example/v1")!
        credentialFixture.user = "user"; credentialFixture.password = "synthetic-invalid-fixture"
        for value in ["http://external.example/v1", credentialFixture.string!, "https://api.example/v1?secret=x", "https://api.example/v1#other"] {
            XCTAssertThrowsError(try CloudRecipient.normalized(value))
        }
    }
}
