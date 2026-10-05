import XCTest
import Foundation
import CSQLite
@testable import VoiceWisprCore

final class HistoryTests: XCTestCase {
    private func location() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("voice-wispr-history-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("history.sqlite")
    }
    private func entry(_ text: String = "Ein kurzer Test.", original: String? = nil, duration: Double = 3, date: Date = Date(), complete: Bool = true, id: UUID = UUID()) -> HistoryEntry {
        .init(result: .init(id: id, text: text, original: original ?? text, usedFallback: false, duration: duration, isComplete: complete), createdAt: date, style: .cleaned, appBundleID: "com.apple.TextEdit", appName: "TextEdit", delivery: .uncertain)
    }
    func testUnicodeWordCountingAndEmptyInput() {
        XCTAssertEqual(HistoryWords.count("„Übermäßig schön“: E-Mail, OpenAI und l’été – 42."), 7)
        XCTAssertEqual(HistoryWords.count("… \n • --"), 0)
        XCTAssertEqual(HistoryWords.count("one-two don't zweimal"), 3)
        XCTAssertEqual(entry("Drei kleine Wörter", original: "").wordCount, 3)
        XCTAssertEqual(entry("Kurz", original: "Fünf Wörter sind hier gesprochen").wordCount, 5)
    }
    func testSettingsWithoutHistoryFieldDecode() throws {
        let data = try JSONEncoder().encode(Settings())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "historyEnabled")
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.historyEnabled)
        XCTAssertEqual(decoded.historyEnabled ?? true, true)
    }
    func testPersistentReopenPreservesCompleteMetadataAndNULText() async throws {
        let url = try location(), item = entry("Grüße\0mit Text.", original: "Der Originaltext.")
        let writer = HistoryStore(url: url)
        let inserted = try await writer.insert(item); XCTAssertTrue(inserted)
        let reader = HistoryStore(url: url), page = try await reader.page()
        XCTAssertEqual(page.entries, [item]); XCTAssertEqual(page.total, 1)
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(mode.intValue, 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + "-shm"))
    }
    func testRepeatedIDDoesNotResetFavoriteOrTrash() async throws {
        let store = HistoryStore(url: try location()), item = entry()
        let first = try await store.insert(item); XCTAssertTrue(first)
        try await store.setFavorite(item.id, true); try await store.setDeleted(item.id, at: Date())
        let repeated = try await store.insert(item), active = try await store.page()
        XCTAssertFalse(repeated); XCTAssertEqual(active.total, 0)
        let trash = try await store.page(filter: .init(trash: true))
        XCTAssertEqual(trash.total, 1); XCTAssertTrue(try XCTUnwrap(trash.entries.first).favorite)
    }
    func testSearchUsesOriginalUnicodeAndLiteralWildcards() async throws {
        let store = HistoryStore(url: try location())
        try await store.insert(entry("Die Ausgabe.", original: "Grüße mit 50% und A_B"))
        try await store.insert(entry("Andere 50 Prozent und ACB."))
        let upper = try await store.page(filter: .init(search: " GRÜSSE ")), german = try await store.page(filter: .init(search: " GRÜßE "))
        let percent = try await store.page(filter: .init(search: "50%")), underscore = try await store.page(filter: .init(search: "A_B"))
        let escaped = try await store.page(filter: .init(search: "' OR 1=1 --"))
        XCTAssertEqual(upper.total, 1); XCTAssertEqual(german.total, 1)
        XCTAssertEqual(percent.total, 1); XCTAssertEqual(underscore.total, 1); XCTAssertEqual(escaped.total, 0)
    }
    func testPaginationStableForEqualDates() async throws {
        let store = HistoryStore(url: try location()), date = Date()
        for _ in 0..<125 { try await store.insert(entry(date: date)) }
        let first = try await store.page(limit: 50), second = try await store.page(limit: 50, offset: 50), third = try await store.page(limit: 50, offset: 100)
        XCTAssertEqual(first.total, 125); XCTAssertEqual(third.entries.count, 25)
        XCTAssertEqual(Set((first.entries + second.entries + third.entries).map(\.id)).count, 125)
        let repeated = try await store.page(limit: 50); XCTAssertEqual(repeated.entries, first.entries)
    }
    func testFavoriteTrashRestoreAndStatisticsExclusion() async throws {
        let store = HistoryStore(url: try location()), item = entry("Drei kleine Wörter", duration: 30)
        try await store.insert(item); try await store.setFavorite(item.id, true)
        let favorites = try await store.page(filter: .init(favoritesOnly: true)), before = try await store.statistics()
        XCTAssertEqual(favorites.total, 1); XCTAssertEqual(before.words, 3)
        try await store.setDeleted(item.id, at: Date())
        let deleted = try await store.statistics(); XCTAssertEqual(deleted.dictations, 0)
        try await store.setDeleted(item.id, at: nil)
        let restored = try await store.statistics(), page = try await store.page()
        XCTAssertEqual(restored.dictations, 1); XCTAssertTrue(try XCTUnwrap(page.entries.first).favorite)
    }
    func testIncompleteResultsRecoverableButNotCounted() async throws {
        let store = HistoryStore(url: try location())
        try await store.insert(entry("Dieser Teil bleibt erreichbar", complete: false))
        let page = try await store.page(), stats = try await store.statistics()
        XCTAssertEqual(page.total, 1); XCTAssertFalse(try XCTUnwrap(page.entries.first).isComplete)
        XCTAssertEqual(stats.words, 0)
    }
    func testWeightedSpeakingSpeedExcludesInvalidTime() {
        let now = Date()
        let stats = HistoryStatistics.calculate([.init(date: now, words: 60, duration: 30), .init(date: now, words: 120, duration: 120), .init(date: now, words: 80, duration: 0)])
        XCTAssertEqual(stats.words, 260); XCTAssertEqual(stats.duration, 150); XCTAssertEqual(stats.wordsPerMinute, 72)
        XCTAssertNil(HistoryStatistics.calculate([.init(date: now, words: 80, duration: 0)]).wordsPerMinute)
    }
    func testCalendarBoundariesAndStreakAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 10)))
        let today = calendar.startOfDay(for: date), yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today)), previous = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: yesterday))
        let stats = HistoryStatistics.calculate([.init(date: today, words: 3, duration: 2), .init(date: yesterday, words: 4, duration: 2), .init(date: previous, words: 5, duration: 2)], now: date, calendar: calendar)
        XCTAssertEqual(stats.currentStreak, 3); XCTAssertEqual(stats.activeDays, 3); XCTAssertEqual(stats.days.count, 14)
        XCTAssertEqual(stats.days.suffix(3).map(\.words), [5, 4, 3])
        XCTAssertEqual(HistoryStatistics.calculate([.init(date: yesterday, words: 4, duration: 2)], now: date, calendar: calendar).currentStreak, 1)
    }
    func testSinceFilterAppliesIdenticallyToListAndStats() async throws {
        let store = HistoryStore(url: try location()), now = Date()
        try await store.insert(entry(date: now.addingTimeInterval(-86400)))
        try await store.insert(entry(date: now))
        let page = try await store.page(filter: .init(since: now.addingTimeInterval(-1))), stats = try await store.statistics(since: now.addingTimeInterval(-1))
        XCTAssertEqual(page.total, 1); XCTAssertEqual(stats.dictations, 1)
    }
    func testVersionedExportExcludesTrashAndContainsOriginal() async throws {
        let url = try location(), store = HistoryStore(url: url), item = entry("Text", original: "Original")
        try await store.insert(item)
        let removed = entry("Entfernt"); try await store.insert(removed); try await store.setDeleted(removed.id, at: Date())
        let export = url.deletingLastPathComponent().appendingPathComponent("export.json")
        try await store.export(to: export)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: export)) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 1)
        let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1); XCTAssertEqual(entries.first?["original"] as? String, "Original")
        XCTAssertEqual(entries.first?["delivery"] as? String, "uncertain")
        XCTAssertNil(entries.first?["audio"])
        try await store.export(to: export, includingTrash: true)
        let withTrash = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: export)) as? [String: Any])
        XCTAssertEqual((withTrash["entries"] as? [[String: Any]])?.count, 2)
    }
    func testFutureSchemaIsNotModified() async throws {
        let url = try location(); var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let before = try Data(contentsOf: url), store = HistoryStore(url: url)
        do { _ = try await store.page(); XCTFail("Newer schema must not open") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
    func testInvalidCaptureMetadataRejectedBeforeWriting() async throws {
        let store = HistoryStore(url: try location())
        for item in [entry(" "), entry(duration: -.infinity), entry(duration: -2), entry(duration: .nan)] {
            do { _ = try await store.insert(item); XCTFail("Invalid record should not be written") } catch {}
        }
        let page = try await store.page(); XCTAssertEqual(page.total, 0)
    }
    func testAppUsageKeepsStableBundleIdentity() {
        let stats = HistoryStatistics.calculate([.init(date: Date(), words: 2, duration: 5, appID: "app.a", appName: "App"), .init(date: Date(), words: 3, duration: 5, appID: "app.a", appName: "App neu"), .init(date: Date(), words: 4, duration: 5, appID: "app.b", appName: "App")])
        XCTAssertEqual(stats.apps.count, 2); XCTAssertEqual(stats.apps.first?.words, 5); XCTAssertEqual(stats.apps.first?.dictations, 2)
    }
    func testResetMovesDatabaseToTrashAndReopensEmpty() async throws {
        let url = try location(), store = HistoryStore(url: url)
        try await store.insert(entry("Nur ein öffentlicher Prüftext."))
        let removed = try await store.moveToTrash(), trashed = try XCTUnwrap(removed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path))
        let empty = try await store.page(); XCTAssertEqual(empty.total, 0)
        // Keep the test backup without leaving it in the user's Trash.
        let backup = url.deletingLastPathComponent().appendingPathComponent("restored.sqlite")
        try FileManager.default.moveItem(at: trashed, to: backup)
        let restored = try await HistoryStore(url: backup).page(); XCTAssertEqual(restored.total, 1)
    }
}
