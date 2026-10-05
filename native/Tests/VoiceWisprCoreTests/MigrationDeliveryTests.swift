import XCTest
import Foundation
import ApplicationServices
import CSQLite
@testable import VoiceWisprCore

final class MigrationDeliveryTests: XCTestCase {
    @MainActor func testWisprScanBoundsEveryAXQueryAndEndsQuicklyForUnavailableApp() {
        // No live hung app in CI: this pins the bound and the scan exit, not Electron itself.
        XCTAssertEqual(WisprSwitch.messagingTimeout, 0.25)
        let switcher = WisprSwitch(applicationURL: URL(fileURLWithPath: "/nonexistent/Wispr Flow.app"), configURL: URL(fileURLWithPath: "/nonexistent/config.json"))
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertNil(switcher.find(AXUIElementCreateApplication(Int32.max), role: nil, labels: ["Settings"]))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 1)
    }
    func testTransientSourceReadRetriesWithFreshAttempt() throws {
        var attempts = 0, pauses: [TimeInterval] = []
        let value = try WisprSourceRead.withRetries(pause: { pauses.append($0) }) {
            attempts += 1
            if attempts < 3 { throw WisprSQLiteReadError(code: attempts == 1 ? SQLITE_IOERR | (1 << 8) : SQLITE_READONLY | (5 << 8)) }
            return 7
        }
        XCTAssertEqual(value, 7); XCTAssertEqual(attempts, 3); XCTAssertEqual(pauses, [0.08, 0.2])
    }
    func testSourceReadRetriesAreBoundedAndCorruptionIsNotRetried() {
        var attempts = 0
        do {
            let _: Int = try WisprSourceRead.withRetries(pause: { _ in }) { attempts += 1; throw WisprSQLiteReadError(code: SQLITE_CANTOPEN) }
            XCTFail("Unavailable source accepted")
        } catch { XCTAssertEqual((error as? WisprSQLiteReadError)?.code, SQLITE_CANTOPEN) }
        XCTAssertEqual(attempts, 3)
        attempts = 0
        do {
            let _: Int = try WisprSourceRead.withRetries(pause: { _ in XCTFail("Corruption retried") }) { attempts += 1; throw WisprSQLiteReadError(code: SQLITE_CORRUPT) }
            XCTFail("Corrupt source accepted")
        } catch { XCTAssertEqual((error as? WisprSQLiteReadError)?.code, SQLITE_CORRUPT) }
        XCTAssertEqual(attempts, 1)
    }
    func testTemporarySourceLockRecoversDuringPreview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wispr-recover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.json"), url = root.appendingPathComponent("flow.sqlite")
        try Data(#"{"prefs":{"user":{}}}"#.utf8).write(to: config)
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let writer = try XCTUnwrap(db); defer { sqlite3_close(writer) }
        XCTAssertEqual(sqlite3_exec(writer, "CREATE TABLE Dictionary(id TEXT, phrase TEXT, replacement TEXT, isDeleted INTEGER, isSnippet INTEGER, replacementHtml TEXT); INSERT INTO Dictionary VALUES('one','Test',NULL,0,0,NULL); BEGIN EXCLUSIVE;", nil, nil, nil), SQLITE_OK)
        let released = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.45) {
            sqlite3_exec(writer, "ROLLBACK", nil, nil, nil); released.signal()
        }
        let preview = WisprMigrationService(configURL: config, databaseURL: url).preview()
        XCTAssertEqual(released.wait(timeout: .now() + 2), .success)
        XCTAssertFalse(preview.isPartial); XCTAssertEqual(preview.words, 1)
    }
    func testCorruptSourceLeavesSettingsAndUndoUntouched() async throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        let source = root.appendingPathComponent("corrupt.sqlite")
        try Data("not a database".utf8).write(to: source)
        let url = root.appendingPathComponent("target/settings.json"), store = SettingsStore(url: url)
        let existing = ExportDocument(dictionary: [DictionaryEntry(phrase: "Keep", manuallyModified: true)])
        try await store.save(existing)
        let before = try Data(contentsOf: url)
        let result = try await store.applyWisprImport(WisprMigrationService(configURL: config, databaseURL: source))
        XCTAssertTrue(result.preview.isPartial); XCTAssertEqual(result.imported, 0)
        XCTAssertTrue(result.preview.errors.contains { $0.contains("SQLite-Code 26") })
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("wispr-import-undo.json").path))
    }
    func testUnsupportedSettingsDoNotReplaceExistingUndo() async throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        let url = root.appendingPathComponent("target/settings.json"), store = SettingsStore(url: url)
        let service = WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite"))
        _ = try await store.applyWisprImport(service)
        let undo = url.deletingLastPathComponent().appendingPathComponent("wispr-import-undo.json")
        let before = try Data(contentsOf: url), undoBefore = try Data(contentsOf: undo)
        let shortcuts = Dictionary(uniqueKeysWithValues: (0..<33).map { ("55+\($0)", "ptt") })
        try JSONSerialization.data(withJSONObject: ["prefs": ["user": ["shortcuts": shortcuts]]]).write(to: config)
        do { _ = try await store.applyWisprImport(service); XCTFail("Too many shortcuts accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), before); XCTAssertEqual(try Data(contentsOf: undo), undoBefore)
    }
    func testDuplicateSourceRowsAreNotReportedAsManualEdits() throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        // Different casing follows the content-dedup path, not the identical fingerprint path.
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO Dictionary VALUES('zzalias','ainauten',NULL,0,0,NULL)", nil, nil, nil), SQLITE_OK)
        let service = WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite"))
        let first = service.apply(to: ExportDocument())
        XCTAssertEqual(first.result.preview.sourceDuplicates, 1); XCTAssertEqual(first.result.preview.uniqueEntries, 2)
        XCTAssertEqual(first.document.dictionary.count, 2)
        let repeatImport = service.apply(to: first.document, provenance: first.provenance)
        XCTAssertEqual(repeatImport.result.imported, 0); XCTAssertEqual(repeatImport.result.preserved, 0)
        XCTAssertTrue(repeatImport.result.summary(savedCount: 2).contains("2 Wörterbucheinträge"))
        XCTAssertFalse(repeatImport.result.summary(savedCount: 2).contains("lokal geänderte"))
        var removed = first.document; removed.dictionary.removeAll { $0.sourceID == "wispr:word" }
        let preserved = service.apply(to: removed, provenance: first.provenance)
        XCTAssertEqual(preserved.result.imported, 0); XCTAssertEqual(preserved.document.dictionary.count, 1)
        XCTAssertEqual(preserved.result.preserved, 2)
    }
    func testImportedFormatMatchesSupportedWisprFlowValues() throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        let service = WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite"))
        for (format, style) in [("Apply AI formatting", TextStyle.cleaned), ("No AI formatting", .original), ("Verbatim", .original), ("Casual messaging", .chat)] {
            try JSONSerialization.data(withJSONObject: ["prefs": ["user": ["defaultTranscriptionFormat": format]]]).write(to: config)
            let imported = service.apply(to: ExportDocument())
            XCTAssertEqual(imported.document.settings.defaultStyle, style)
            XCTAssertNil(imported.result.preview.unsupportedCounts["format"])
        }
        try Data(#"{"prefs":{"user":{"defaultTranscriptionFormat":"All lowercase"}}}"#.utf8).write(to: config)
        XCTAssertEqual(service.preview().unsupportedCounts["format"], 1)
    }
    @MainActor func testBrowserAndElectronFieldsUsePasteOnFirstAttempt() {
        for bundleID in ["ai.perplexity.comet", "com.tinyspeck.slackmacgap", "com.openai.codex", "com.apple.Safari"] {
            XCTAssertFalse(DeliveryCoordinator.usesDirectSelection(bundleID: bundleID, role: "AXTextArea"))
            XCTAssertFalse(DeliveryCoordinator.usesDirectSelection(bundleID: bundleID, role: "AXTextField"))
        }
        XCTAssertFalse(DeliveryCoordinator.usesDirectSelection(bundleID: nil, role: "AXTextArea"))
        XCTAssertTrue(DeliveryCoordinator.usesDirectSelection(bundleID: "com.apple.TextEdit", role: "AXTextArea"))
        XCTAssertFalse(DeliveryCoordinator.usesDirectSelection(bundleID: "com.apple.TextEdit", role: "AXWebArea"))
    }
    func testAllSupportedBindingsImportFnAndKeepManualChanges() throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        try Data(#"{"prefs":{"user":{"shortcuts":{"56+59":"ptt","58+59":"ptt","49+63":"popo","55+59+8":"copy_last_text","55+59+9":"paste_last_text","53":"dismiss","59+63":"lens","46+58":"open_meeting_recorder"}}}}"#.utf8).write(to: config)
        let service = WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite"))
        let first = service.apply(to: ExportDocument())
        let bindings = try XCTUnwrap(first.document.settings.shortcutBindings)
        XCTAssertEqual(first.document.settings.shortcut, Shortcut(keyCode: nil, modifiers: (1 << 17) | (1 << 18)))
        XCTAssertEqual(bindings.holdExtras, [Shortcut(keyCode: nil, modifiers: (1 << 19) | (1 << 18))])
        XCTAssertEqual(bindings.handsFree, [Shortcut(keyCode: 49, modifiers: 1 << 23)])
        XCTAssertEqual(bindings.copyLast, [Shortcut(keyCode: 8, modifiers: (1 << 20) | (1 << 18))])
        XCTAssertEqual(bindings.pasteLast, [Shortcut(keyCode: 9, modifiers: (1 << 20) | (1 << 18))])
        XCTAssertEqual(bindings.cancel, [Shortcut(keyCode: 53, modifiers: 0)])
        XCTAssertEqual(first.result.preview.unsupportedCounts["actions"], 2)
        try SettingsStore.validate(first.document)
        let repeated = service.apply(to: first.document, provenance: first.provenance)
        XCTAssertEqual(repeated.document, first.document); XCTAssertEqual(repeated.result.imported, 0)
        var manual = first.document; manual.settings.shortcutBindings?.handsFree = [Shortcut(keyCode: 49, modifiers: 1 << 20)]
        XCTAssertEqual(service.apply(to: manual, provenance: first.provenance).document.settings.shortcutBindings, manual.settings.shortcutBindings)
    }
    func testBusyDatabaseIsNotReportedAsUnknownSchema() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wispr-busy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.json")
        try Data(#"{"prefs":{"user":{}}}"#.utf8).write(to: config)
        let url = root.appendingPathComponent("flow.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE Dictionary(id TEXT, phrase TEXT, replacement TEXT, isDeleted INTEGER, isSnippet INTEGER, replacementHtml TEXT); BEGIN EXCLUSIVE;", nil, nil, nil), SQLITE_OK)
        let preview = WisprMigrationService(configURL: config, databaseURL: url).preview()
        XCTAssertTrue(preview.isPartial)
        XCTAssertTrue(preview.errors.contains { $0.contains("belegt") })
        XCTAssertFalse(preview.errors.contains { $0.contains("Schema") })
        XCTAssertEqual(sqlite3_exec(db, "ROLLBACK", nil, nil, nil), SQLITE_OK)
    }
    private func fixture() throws -> (URL, URL, OpaquePointer) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voice-wispr-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.json")
        try Data(#"{"prefs":{"user":{"selectedLanguages":["en","de"],"shortcuts":{"56+59":"ptt","49+63":"popo"},"modifierShortcut":48,"defaultTranscriptionFormat":"Apply AI formatting","userVoices":{"email":{"source":"builtIn","appNames":["Microsoft Outlook","Gmail"]}}}}}"#.utf8).write(to: config)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("flow.sqlite").path, &db), SQLITE_OK)
        let connection = try XCTUnwrap(db)
        let sql = """
        PRAGMA journal_mode=WAL;
        CREATE TABLE Dictionary(id TEXT PRIMARY KEY, phrase TEXT NOT NULL, replacement TEXT, isDeleted INTEGER, isSnippet INTEGER, replacementHtml TEXT);
        INSERT INTO Dictionary VALUES('word','AInauten',NULL,0,0,NULL),('replacement','voice whisper','Voice Wispr',0,0,NULL),('deleted','Removed',NULL,1,0,NULL),('snippet','Snippet','ignore',0,1,NULL),('html','Rich','ignore',0,0,'<b>rich</b>');
        """
        XCTAssertEqual(sqlite3_exec(connection, sql, nil, nil, nil), SQLITE_OK)
        // Keep the writer open so the importer must observe the active WAL snapshot.
        return (root, config, connection)
    }
    func testReadOnlySnapshotIncludesWALExcludesDeletedAndSnippets() throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        let service = WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite"))
        let preview = service.preview()
        XCTAssertFalse(preview.isPartial)
        XCTAssertEqual(preview.words, 1); XCTAssertEqual(preview.replacements, 1); XCTAssertEqual(preview.deleted, 1)
        XCTAssertEqual(preview.unsupportedCounts["snippets"], 2)
        XCTAssertEqual(preview.shortcut, Shortcut(keyCode: nil, modifiers: (1 << 17) | (1 << 18)))
        XCTAssertEqual(preview.languages, ["en", "de"])
        XCTAssertEqual(preview.appStyles["com.microsoft.Outlook"], .email)
        let applied = service.apply(to: ExportDocument())
        XCTAssertEqual(applied.result.imported, 2)
        XCTAssertEqual(applied.document.dictionary.count, 2)
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO Dictionary VALUES('late','After snapshot',NULL,0,0,NULL)", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(service.preview().words, 2)
    }
    func testClosedWALImportsWithoutCreatingSidecarsAndEscapesFileURI() throws {
        let (root, config, db) = try fixture()
        let source = root.appendingPathComponent("flow.sqlite")
        try closeFixtureWAL(db, at: source)
        let url = root.appendingPathComponent("flow space ? # %.sqlite")
        try FileManager.default.moveItem(at: source, to: url)
        let before = try Data(contentsOf: url)
        let fence = try XCTUnwrap(WisprClosedWALSnapshot.capture(url))
        let service = WisprMigrationService(configURL: config, databaseURL: url)
        let result = service.apply(to: ExportDocument())
        XCTAssertFalse(result.result.preview.isPartial)
        XCTAssertEqual(result.result.preview.words, 1)
        XCTAssertEqual(result.result.preview.replacements, 1)
        XCTAssertEqual(result.result.preview.deleted, 1)
        XCTAssertEqual(result.document.dictionary.count, 2)
        XCTAssertEqual(try Data(contentsOf: url), before)
        for suffix in ["-wal", "-shm", "-journal"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + suffix))
        }
        try fence.validate()
        let repeated = service.apply(to: result.document, provenance: result.provenance)
        XCTAssertFalse(repeated.result.preview.isPartial)
        XCTAssertEqual(repeated.document, result.document)
        XCTAssertEqual(repeated.result.imported, 0)
    }
    func testClosedWALFenceRejectsSourceMutation() throws {
        let (root, _, db) = try fixture()
        let url = root.appendingPathComponent("flow.sqlite")
        try closeFixtureWAL(db, at: url)
        let fence = try XCTUnwrap(WisprClosedWALSnapshot.capture(url))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        do { try fence.validate(); XCTFail("Changed source accepted") }
        catch let error as WisprSQLiteReadError { XCTAssertEqual(error.primaryCode, SQLITE_BUSY) }
    }
    func testClosedWALFenceRejectsNewSidecarAndLiveWALUsesNormalRead() throws {
        let (root, config, db) = try fixture()
        let url = root.appendingPathComponent("flow.sqlite")
        XCTAssertNil(try WisprClosedWALSnapshot.capture(url))
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO Dictionary VALUES('live','Newest word',NULL,0,0,NULL)", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(WisprMigrationService(configURL: config, databaseURL: url).preview().words, 2)
        try closeFixtureWAL(db, at: url)
        let fence = try XCTUnwrap(WisprClosedWALSnapshot.capture(url))
        try Data().write(to: URL(fileURLWithPath: url.path + "-wal"))
        do { try fence.validate(); XCTFail("New WAL accepted") }
        catch let error as WisprSQLiteReadError { XCTAssertEqual(error.primaryCode, SQLITE_BUSY) }
        XCTAssertNil(try WisprClosedWALSnapshot.capture(url))
    }
    func testClosedWALFenceRejectsReplacedPhysicalFile() throws {
        let (root, _, db) = try fixture()
        let url = root.appendingPathComponent("flow.sqlite")
        try closeFixtureWAL(db, at: url)
        let before = try Data(contentsOf: url)
        let fence = try XCTUnwrap(WisprClosedWALSnapshot.capture(url))
        try FileManager.default.moveItem(at: url, to: root.appendingPathComponent("original.sqlite"))
        try before.write(to: url)
        do { try fence.validate(); XCTFail("Replaced source accepted") }
        catch let error as WisprSQLiteReadError { XCTAssertEqual(error.primaryCode, SQLITE_BUSY) }
    }
    func testFailedMigrationSummaryDoesNotClaimSuccessfulImport() {
        var preview = ImportPreview(); preview.errors = ["Quelle nicht lesbar"]
        let summary = MigrationResult(preview: preview).summary(savedCount: 2728)
        XCTAssertTrue(summary.contains("Import nicht ausgeführt"))
        XCTAssertTrue(summary.contains("Quelle nicht lesbar"))
        XCTAssertFalse(summary.contains("Import abgeschlossen"))
    }
    private func closeFixtureWAL(_ db: OpaquePointer, at url: URL) throws {
        // macOS SQLite may retain empty sidecars after close. Checkpoint every
        // synthetic row, close the sole writer, then preserve retained sidecars
        // outside the source path to reproduce Flow's closed-file state safely.
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(db), SQLITE_OK)
        let archive = url.deletingLastPathComponent().appendingPathComponent("closed-sidecars")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try FileManager.default.moveItem(at: sidecar, to: archive.appendingPathComponent(sidecar.lastPathComponent))
            }
        }
    }
    func testReimportPreservesManualEditsAndLocalDeletion() throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        let service = WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite"))
        let first = service.apply(to: ExportDocument())
        var changed = first.document
        changed.dictionary.removeAll { $0.sourceID == "wispr:word" }
        changed.dictionary[0].replacement = "Manual change" // Detect manual changes even without flag.
        changed.settings.languages = ["fr"]
        changed.settings.shortcut = Shortcut(keyCode: 49, modifiers: 1 << 20)
        changed.settings.appStyles["com.microsoft.Outlook"] = .original
        let reimport = service.apply(to: changed, provenance: first.provenance)
        XCTAssertEqual(reimport.result.imported, 0); XCTAssertEqual(reimport.result.preserved, 2)
        XCTAssertEqual(reimport.document.dictionary.count, 1)
        XCTAssertEqual(reimport.document.dictionary[0].replacement, "Manual change")
        XCTAssertEqual(reimport.document.settings.languages, ["fr"])
        XCTAssertEqual(reimport.document.settings.shortcut, changed.settings.shortcut)
        XCTAssertEqual(reimport.document.settings.appStyles["com.microsoft.Outlook"], .original)
    }
    func testLiveSettingsArePreservedWhenFlushedBeforeImportAndUndo() async throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        let store = SettingsStore(url: root.appendingPathComponent("target/settings.json"))
        try await store.save(ExportDocument())
        var live = ExportDocument(dictionary: [DictionaryEntry(phrase: "Keep my word", manuallyModified: true)])
        live.settings.languages = ["fr"]
        live.settings.shortcut = Shortcut(keyCode: 49, modifiers: 1 << 20)
        live.settings.defaultStyle = .original
        try await store.save(live)
        let result = try await store.applyWisprImport(WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite")))
        XCTAssertFalse(result.preview.isPartial)
        XCTAssertEqual(result.imported, 2)
        let imported = try await store.load()
        XCTAssertEqual(imported.settings.languages, live.settings.languages)
        XCTAssertEqual(imported.settings.shortcut, live.settings.shortcut)
        XCTAssertEqual(imported.settings.defaultStyle, .original)
        XCTAssertTrue(imported.dictionary.contains { $0.phrase == "Keep my word" })
        try await store.undoWisprImport()
        let restored = try await store.load()
        XCTAssertEqual(restored, live)
    }
    func testContentDedupTracksUpdatedSourceAndRemainingManualDuplicate() throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        let service = WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite"))
        let first = service.apply(to: ExportDocument())
        XCTAssertEqual(sqlite3_exec(db, "UPDATE Dictionary SET phrase='New name' WHERE id='word'; INSERT INTO Dictionary VALUES('zzz','AInauten',NULL,0,0,NULL)", nil, nil, nil), SQLITE_OK)
        let changed = service.apply(to: first.document, provenance: first.provenance)
        XCTAssertEqual(changed.result.imported, 1)
        XCTAssertEqual(changed.document.dictionary.count, 3)
        var withManual = first.document
        withManual.dictionary.append(DictionaryEntry(phrase: "ainauten", manuallyModified: true))
        let deduplicated = service.apply(to: withManual, provenance: first.provenance)
        XCTAssertEqual(deduplicated.result.imported, 0)
        XCTAssertEqual(deduplicated.document.dictionary.count, 3)
        XCTAssertTrue(deduplicated.document.dictionary.contains { $0.phrase == "New name" })
        XCTAssertTrue(deduplicated.document.dictionary.contains { $0.phrase == "ainauten" && $0.manuallyModified })
    }
    func testSchemaFailureIsNotSuccessfulEmptyImport() throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "ALTER TABLE Dictionary RENAME COLUMN isSnippet TO mystery", nil, nil, nil), SQLITE_OK)
        let existing = [DictionaryEntry(phrase: "Keep")]
        let (result, output) = WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite")).apply(to: existing)
        XCTAssertTrue(result.preview.isPartial); XCTAssertEqual(result.imported, 0); XCTAssertEqual(output, existing)
    }
    func testStableDeduplicationAndNoCascadingReplacement() {
        let matcher = DictionaryMatcher([DictionaryEntry(phrase: "New York", replacement: "NY"), DictionaryEntry(phrase: "New", replacement: "Fresh"), DictionaryEntry(phrase: "NY", replacement: "Wrong"), DictionaryEntry(phrase: "café", replacement: "coffee")])
        XCTAssertEqual(matcher.replace(in: "New York, New and café. xNew caféine"), "NY, Fresh and coffee. xNew caféine")
        XCTAssertEqual(WisprMigrationService.fingerprint("AInauten", nil), WisprMigrationService.fingerprint("AInauten", ""))
    }
    func testStreamingMatchesCrossSegmentPhraseAndPreservesWhitespace() {
        let entries = [DictionaryEntry(phrase: "New York", replacement: "NY"), DictionaryEntry(phrase: "AInauten", replacement: "AInauten.com")]
        var stream = StreamingDictionaryMatcher(entries)
        var output = stream.process("Start  New ")
        output += stream.process("York\nAIn")
        output += stream.process("auten and enough extra words to release a prefix ")
        XCTAssertFalse(output.isEmpty)
        output += stream.process("done", final: true)
        XCTAssertEqual(output, DictionaryMatcher(entries).replace(in: "Start  New York\nAInauten and enough extra words to release a prefix done"))
    }
    func testDeliveryRequiresWholeExpectedBaseline() {
        let range = NSRange(location: 6, length: 3)
        XCTAssertEqual(DeliveryVerification.expectedValue(baseline: "Hello old world", selection: range, insertion: "new"), "Hello new world")
        XCTAssertTrue(DeliveryVerification.confirmed(baseline: "Hello old world", selection: range, insertion: "new", observed: "Hello new world", caret: NSRange(location: 9, length: 0)))
        XCTAssertFalse(DeliveryVerification.confirmed(baseline: "Hello old world", selection: range, insertion: "new", observed: "new", caret: NSRange(location: 9, length: 0)))
        XCTAssertTrue(DeliveryVerification.confirmed(baseline: "Hello old world", selection: range, insertion: "new", observed: "Hello new world", caret: range))
        XCTAssertNil(DeliveryVerification.expectedValue(baseline: "abc", selection: NSRange(location: 2, length: 3), insertion: "x"))
        XCTAssertEqual(DeliveryVerification.expectedValue(baseline: "😀 old", selection: NSRange(location: 3, length: 3), insertion: "neu"), "😀 neu")
    }
    func testClipboardNewCopyWinsEvenWhenTextIsIdentical() {
        let nonce = UUID(), owned = ClipboardOwnership(nonce: nonce, changeCount: 12)
        XCTAssertTrue(owned.owns(changeCount: 12, nonce: nonce))
        XCTAssertFalse(owned.owns(changeCount: 13, nonce: nonce))
        XCTAssertFalse(owned.owns(changeCount: 12, nonce: UUID()))
        XCTAssertFalse(owned.owns(changeCount: 12, nonce: nil))
    }
    func testUnsupportedShortcutNeverGuessed() {
        XCTAssertEqual(WisprMigrationService.decodeShortcut("49+63"), Shortcut(keyCode: 49, modifiers: 1 << 23))
        XCTAssertNil(WisprMigrationService.decodeShortcut("48+999"))
        XCTAssertEqual(WisprMigrationService.decodeShortcut("56+59"), Shortcut(keyCode: nil, modifiers: (1 << 17) | (1 << 18)))
    }
    func testFirstSaveAndVersionValidation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-wispr-settings-\(UUID().uuidString)/settings.json")
        let store = SettingsStore(url: url)
        let document = ExportDocument(dictionary: [DictionaryEntry(phrase: "AInauten")])
        try await store.save(document)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, document)
        var invalid = document; invalid.version = 2
        do { try await store.save(invalid); XCTFail("Unknown version accepted") } catch {}
        let unchanged = try await store.load(); XCTAssertEqual(unchanged, document)
    }
    func testImportedSettingsCannotActivateCloudOrNewRecipient() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voice-import-consent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("export.json")
        var external = ExportDocument(dictionary: [DictionaryEntry(phrase: "AInauten")])
        external.settings.cloudEnabled = true
        external.settings.cloudEndpoint = "https://new-recipient.invalid/v1"
        try JSONEncoder().encode(external).write(to: source)
        let store = SettingsStore(url: root.appendingPathComponent("settings.json"))
        let imported = try await store.importDocument(from: source)
        XCTAssertFalse(imported.settings.cloudEnabled)
        XCTAssertEqual(imported.settings.cloudEndpoint, external.settings.cloudEndpoint)
        XCTAssertEqual(imported.dictionary, external.dictionary)
        XCTAssertEqual(imported.settings.languages, external.settings.languages)
        let unchanged = try JSONDecoder().decode(ExportDocument.self, from: Data(contentsOf: source))
        XCTAssertTrue(unchanged.settings.cloudEnabled)
    }
    func testSaveNeverBlocksOnCorruptOrNewerFileAndKeepsReadableProvenance() async throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        let url = root.appendingPathComponent("target/settings.json"), store = SettingsStore(url: url)
        _ = try await store.applyWisprImport(WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite")))
        func json() throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) }
        var newer = try json(); newer["version"] = 2
        try JSONSerialization.data(withJSONObject: newer).write(to: url)
        do { _ = try await store.load(); XCTFail("Newer file must not load as version 1") } catch {}
        let document = ExportDocument(dictionary: [DictionaryEntry(phrase: "Neu")])
        try await store.save(document)
        let saved = try await store.load(); XCTAssertEqual(saved, document)
        let provenance = try XCTUnwrap(try json()["wisprImport"] as? [String: Any])
        XCTAssertFalse((provenance["sourceIDs"] as? [String] ?? []).isEmpty) // Readable provenance survives.
        try Data("{ kaputt".utf8).write(to: url)
        try await store.save(document)
        let repaired = try await store.load(); XCTAssertEqual(repaired, document); XCTAssertNil(try json()["wisprImport"])
    }
    func testUnusedEmptyCloudEndpointNeverBlocksSaving() async throws {
        var document = ExportDocument(); document.settings.cloudEndpoint = ""
        try SettingsStore.validate(document)
        document.settings.cloudEndpoint = "http://example.com/v1"; try SettingsStore.validate(document)
        document.settings.cloudEnabled = true
        XCTAssertThrowsError(try SettingsStore.validate(document))
        document.settings.cloudEndpoint = ""; XCTAssertThrowsError(try SettingsStore.validate(document))
        document.settings.cloudEndpoint = "https://api.example.com/v1"; try SettingsStore.validate(document)
        let store = SettingsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("voice-endpoint-\(UUID().uuidString)/settings.json"))
        var cleared = ExportDocument(); cleared.settings.cloudEndpoint = ""
        try await store.save(cleared)
        let loaded = try await store.load(); XCTAssertEqual(loaded, cleared)
    }
    func testUndoKeepsCurrentCloudAndCameraChoicesAndRunsOnce() async throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        let url = root.appendingPathComponent("target/settings.json"), store = SettingsStore(url: url)
        let undo = url.deletingLastPathComponent().appendingPathComponent("wispr-import-undo.json")
        var before = ExportDocument(dictionary: [DictionaryEntry(phrase: "Vorher", manuallyModified: true)])
        before.settings.cloudEnabled = true; before.settings.cloudEndpoint = "https://old.example/v1"
        before.settings.lipReadingEnabled = true; before.settings.lipReadingLanguage = "en"
        try await store.save(before)
        _ = try await store.applyWisprImport(WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite")))
        // After the import the user withdraws both consents and clears the endpoint.
        var current = try await store.load()
        XCTAssertTrue(current.settings.languages != before.settings.languages) // The import did change settings.
        current.settings.cloudEnabled = false; current.settings.cloudEndpoint = ""; current.settings.cloudModel = "lokal"
        current.settings.lipReadingEnabled = false; current.settings.lipReadingLanguage = "de"
        try await store.save(current)
        try await store.undoWisprImport()
        let restored = try await store.load()
        XCTAssertEqual(restored.dictionary, before.dictionary)
        XCTAssertEqual(restored.settings.languages, before.settings.languages); XCTAssertEqual(restored.settings.shortcut, before.settings.shortcut)
        XCTAssertFalse(restored.settings.cloudEnabled); XCTAssertEqual(restored.settings.cloudEndpoint, ""); XCTAssertEqual(restored.settings.cloudModel, "lokal")
        XCTAssertEqual(restored.settings.lipReadingEnabled, false); XCTAssertEqual(restored.settings.lipReadingLanguage, "de")
        XCTAssertFalse(FileManager.default.fileExists(atPath: undo.path))
        let after = try Data(contentsOf: url)
        do { try await store.undoWisprImport(); XCTFail("A second undo must not roll back later edits") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), after)
    }
    func testProvenancePersistsAcrossStoreReloadAndUndo() async throws {
        let (root, config, db) = try fixture(); defer { sqlite3_close(db) }
        let url = root.appendingPathComponent("target/settings.json"), store = SettingsStore(url: url)
        let service = WisprMigrationService(configURL: config, databaseURL: root.appendingPathComponent("flow.sqlite"))
        let first = try await store.applyWisprImport(service); XCTAssertEqual(first.imported, 2)
        var document = try await store.load(); document.dictionary = []
        try await store.save(document)
        let reload = SettingsStore(url: url)
        let next = try await reload.applyWisprImport(service)
        XCTAssertEqual(next.imported, 0); XCTAssertEqual(next.preserved, 2)
        let after = try await reload.load(); XCTAssertTrue(after.dictionary.isEmpty)
        try await reload.undoWisprImport()
        let undone = try await reload.load(); XCTAssertEqual(undone, document)
    }
}
