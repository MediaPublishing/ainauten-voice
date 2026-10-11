import XCTest
import Foundation
import Darwin
@testable import VoiceWisprCore

final class SecuritySettingsTests: XCTestCase {
    func testPrivacySettingsKeepVersionSpecificPermissionNamesAndTCCDestinations() {
        XCTAssertEqual(PrivacySettings.accessibilityKey("permissions.accessibility", modern: false), "permissions.accessibility")
        XCTAssertEqual(PrivacySettings.accessibilityKey("permissions.steps", modern: true), "permissions.steps.macOS27")
        for permission in ["Accessibility", "Microphone", "Camera"] {
            let destination = PrivacySettings.destination(permission)
            XCTAssertEqual(destination.scheme, "x-apple.systempreferences")
            XCTAssertEqual(destination.absoluteString, "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_" + permission)
        }
    }
    func testClipboardDefaultEnablesNewProfilesAndPreservesSavedChoices() throws {
        XCTAssertTrue(Settings().usesClipboardForInsertion)
        for choice in [true, false] {
            var settings = Settings(); settings.clipboardCompatibility = choice
            let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(restored.clipboardCompatibility, choice)
            XCTAssertEqual(restored.usesClipboardForInsertion, choice)
        }
    }
    func testClipboardLegacyMissingAndNullStayDisabledAcrossSave() throws {
        let encoded = try JSONEncoder().encode(Settings())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for value in [nil, NSNull()] as [Any?] {
            object["clipboardCompatibility"] = value
            let legacy = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(legacy.clipboardCompatibility)
            XCTAssertFalse(legacy.usesClipboardForInsertion)
            let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(legacy))
            XCTAssertFalse(restored.usesClipboardForInsertion)
        }
    }
    func testClipboardFreshStorePersistsDefaultAndExplicitDisable() async throws {
        let root = try directory()
        let store = SettingsStore(url: root.appendingPathComponent("settings.json"))
        var document = try await store.load()
        XCTAssertTrue(document.settings.usesClipboardForInsertion)
        try await store.save(document)
        var restored = try await store.load()
        XCTAssertTrue(restored.settings.usesClipboardForInsertion)
        document.settings.clipboardCompatibility = false
        try await store.save(document)
        restored = try await store.load()
        XCTAssertFalse(restored.settings.usesClipboardForInsertion)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-security-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testMenuBarOnlyPreservesLegacyDefaultAndSurvivesSave() async throws {
        let legacy = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(Settings()))
        XCTAssertNil(legacy.menuBarOnly)
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(url: root.appendingPathComponent("settings.json"))
        for enabled in [true, false] {
            var document = ExportDocument(settings: legacy)
            document.settings.menuBarOnly = enabled
            try await store.save(document)
            let restored = try await store.load()
            XCTAssertEqual(restored.settings.menuBarOnly, enabled)
            XCTAssertEqual(restored.settings.shortcut, legacy.shortcut)
            XCTAssertEqual(restored.settings.languages, legacy.languages)
        }
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
