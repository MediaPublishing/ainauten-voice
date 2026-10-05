import XCTest
import Foundation
import CSQLite
@testable import VoiceWisprCore

final class MigrationRejectedRowsTests: XCTestCase {
    func testMalformedRowsAreSkippedWithoutBlockingValidRows() throws {
        let (root, service, db) = try fixture(); defer { sqlite3_close(db) }
        try insert(db, id: "good", phrase: "Keep")
        try insert(db, id: "alias", phrase: "keep")
        try insert(db, id: "replacement", phrase: "voice whisper", replacement: "Voice Wispr")
        try insert(db, id: "null-phrase", phrase: nil)
        try insert(db, id: "empty-phrase", phrase: "")
        try insert(db, id: "blank-phrase", phrase: " \t\n")
        try insert(db, id: nil, phrase: "Missing ID")
        try insert(db, id: "", phrase: "Empty ID")
        try insert(db, id: " \t", phrase: "Blank ID")
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO Dictionary VALUES('deleted',NULL,NULL,1,0,NULL),('snippet',NULL,NULL,0,1,NULL)", nil, nil, nil), SQLITE_OK)
        let sourceBefore = try Data(contentsOf: root.appendingPathComponent("flow.sqlite-wal"))
        let result = service.apply(to: ExportDocument())
        XCTAssertFalse(result.result.preview.isPartial)
        XCTAssertEqual(result.result.preview.unsupportedCounts["invalidDictionaryEntries"], 6)
        XCTAssertEqual(result.result.preview.words, 2)
        XCTAssertEqual(result.result.preview.replacements, 1)
        XCTAssertEqual(result.result.preview.deleted, 1)
        XCTAssertEqual(result.result.preview.unsupportedCounts["snippets"], 1)
        XCTAssertEqual(result.result.preview.sourceDuplicates, 1)
        XCTAssertEqual(result.result.preview.uniqueEntries, 2)
        XCTAssertEqual(result.result.imported, 2)
        XCTAssertEqual(result.result.skipped, 7)
        XCTAssertEqual(result.document.dictionary.count, 2)
        XCTAssertTrue(result.result.preview.unsupported.contains("Leere oder ungültige Wörterbucheinträge (6)"))
        XCTAssertTrue(result.result.summary(savedCount: 2).contains("6 leere oder ungültige Wörterbucheinträge ausgelassen"))
        try SettingsStore.validate(result.document)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("flow.sqlite-wal")), sourceBefore)
    }

    func testPhraseLimitUsesCharactersAndKeepsExactBoundary() throws {
        let (_, service, db) = try fixture(); defer { sqlite3_close(db) }
        let boundary = String(repeating: "e\u{301}", count: 255)
        try insert(db, id: "boundary", phrase: boundary)
        try insert(db, id: "too-long", phrase: String(repeating: "x", count: 256))
        try insert(db, id: "too-many-emoji", phrase: String(repeating: "😀", count: 256))
        let result = service.apply(to: ExportDocument())
        XCTAssertFalse(result.result.preview.isPartial)
        XCTAssertEqual(result.result.preview.words, 1)
        XCTAssertEqual(result.result.preview.unsupportedCounts["overlongPhrases"], 2)
        XCTAssertEqual(result.result.imported, 1)
        XCTAssertEqual(result.result.skipped, 2)
        XCTAssertEqual(result.document.dictionary.first?.phrase, boundary)
        XCTAssertTrue(result.result.summary(savedCount: 1).contains("2 Ausdrücke über 255 Zeichen ausgelassen"))
        try SettingsStore.validate(result.document)
    }

    func testReplacementByteLimitSkipsOnlyOversizedRows() throws {
        let (_, service, db) = try fixture(); defer { sqlite3_close(db) }
        try insert(db, id: "boundary", phrase: "Allowed", replacement: String(repeating: "é", count: 500_000))
        try insert(db, id: "too-large", phrase: "Excluded", replacement: String(repeating: "é", count: 500_001))
        let result = service.apply(to: ExportDocument())
        XCTAssertFalse(result.result.preview.isPartial)
        XCTAssertEqual(result.result.preview.replacements, 1)
        XCTAssertEqual(result.result.preview.unsupportedCounts["oversizedReplacements"], 1)
        XCTAssertEqual(result.result.imported, 1)
        XCTAssertEqual(result.result.skipped, 1)
        XCTAssertEqual(result.document.dictionary.first?.replacement?.utf8.count, 1_000_000)
        XCTAssertTrue(result.result.summary(savedCount: 1).contains("1 Ersetzung über 1 MB ausgelassen"))
        try SettingsStore.validate(result.document)
    }

    func testRejectedRowsCanBeCorrectedWithoutLosingStoredEntriesOrUndo() async throws {
        let (root, service, db) = try fixture(); defer { sqlite3_close(db) }
        try insert(db, id: "good", phrase: "Imported word")
        try insert(db, id: "empty", phrase: "")
        try insert(db, id: "long", phrase: String(repeating: "x", count: 256))
        var existing = ExportDocument(dictionary: [DictionaryEntry(phrase: "My word", replacement: "My spelling", manuallyModified: true)])
        existing.settings.languages = ["fr"]; existing.settings.defaultStyle = .original
        var bindings = ShortcutBindings(); bindings.handsFree = [Shortcut(keyCode: 49, modifiers: 1 << 20)]
        existing.settings.shortcutBindings = bindings
        let store = SettingsStore(url: root.appendingPathComponent("target/settings.json"))
        try await store.save(existing)
        let first = try await store.applyWisprImport(service)
        XCTAssertFalse(first.preview.isPartial); XCTAssertEqual(first.imported, 1); XCTAssertEqual(first.skipped, 2)
        let stored = try await store.load()
        XCTAssertEqual(stored.dictionary.count, 2)
        XCTAssertEqual(stored.settings, existing.settings)
        let repeated = try await store.applyWisprImport(service)
        XCTAssertEqual(repeated.imported, 0); XCTAssertEqual(repeated.skipped, 3)
        let repeatedDocument = try await store.load(); XCTAssertEqual(repeatedDocument, stored)
        XCTAssertEqual(sqlite3_exec(db, "UPDATE Dictionary SET phrase='Corrected empty' WHERE id='empty'; UPDATE Dictionary SET phrase='Corrected long' WHERE id='long'; UPDATE Dictionary SET phrase='\(String(repeating: "y", count: 256))' WHERE id='good';", nil, nil, nil), SQLITE_OK)
        let corrected = try await store.applyWisprImport(service)
        XCTAssertFalse(corrected.preview.isPartial); XCTAssertEqual(corrected.imported, 2)
        XCTAssertEqual(corrected.preview.unsupportedCounts["overlongPhrases"], 1)
        let final = try await store.load()
        XCTAssertEqual(final.dictionary.count, 4)
        XCTAssertEqual(final.settings, existing.settings)
        XCTAssertTrue(final.dictionary.contains { $0.phrase == "Imported word" })
        XCTAssertTrue(final.dictionary.contains { $0.phrase == "My word" && $0.replacement == "My spelling" && $0.manuallyModified })
        try await store.undoWisprImport()
        let restored = try await store.load(); XCTAssertEqual(restored, stored)
    }

    private func fixture() throws -> (URL, WisprMigrationService, OpaquePointer) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wispr-rejected-rows-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.json"), database = root.appendingPathComponent("flow.sqlite")
        try Data(#"{"prefs":{"user":{}}}"#.utf8).write(to: config)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &db), SQLITE_OK)
        let writer = try XCTUnwrap(db)
        XCTAssertEqual(sqlite3_exec(writer, "PRAGMA journal_mode=WAL; CREATE TABLE Dictionary(id TEXT, phrase TEXT, replacement TEXT, isDeleted INTEGER, isSnippet INTEGER, replacementHtml TEXT);", nil, nil, nil), SQLITE_OK)
        return (root, WisprMigrationService(configURL: config, databaseURL: database), writer)
    }

    private func insert(_ db: OpaquePointer, id: String?, phrase: String?, replacement: String? = nil) throws {
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "INSERT INTO Dictionary VALUES(?,?,?,0,0,NULL)", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        for (index, value) in [id, phrase, replacement].enumerated() {
            if let value {
                let status = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                XCTAssertEqual(status, SQLITE_OK)
            } else { XCTAssertEqual(sqlite3_bind_null(statement, Int32(index + 1)), SQLITE_OK) }
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }
}
