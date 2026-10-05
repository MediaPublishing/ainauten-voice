import Foundation
import CSQLite

public struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let text: String
    public let original: String
    public let duration: Double
    public let style: TextStyle
    public let appBundleID: String?
    public let appName: String?
    public let usedFallback: Bool
    public let isComplete: Bool
    public let delivery: DeliveryStatus
    public var favorite: Bool
    public var deletedAt: Date?
    public var wordCount: Int { HistoryWords.count(original.isEmpty ? text : original) }

    public init(result: DictationResult, createdAt: Date = Date(), style: TextStyle,
                appBundleID: String? = nil, appName: String? = nil, delivery: DeliveryStatus,
                favorite: Bool = false, deletedAt: Date? = nil) {
        id = result.id
        // Canonical milliseconds round-trip exactly through SQLite's Epoch REAL.
        self.createdAt = Date(timeIntervalSince1970: (createdAt.timeIntervalSince1970 * 1000).rounded() / 1000)
        text = result.text; original = result.original
        duration = result.duration; self.style = style; self.appBundleID = appBundleID; self.appName = appName
        usedFallback = result.usedFallback; isComplete = result.isComplete; self.delivery = delivery
        self.favorite = favorite; self.deletedAt = deletedAt
    }
}

public enum HistoryWords {
    private static let expression = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*"#)
    public static func count(_ text: String) -> Int {
        expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
    public static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }
}

public struct HistoryFilter: Equatable, Sendable {
    public var search: String
    public var since: Date?
    public var favoritesOnly: Bool
    public var trash: Bool
    public init(search: String = "", since: Date? = nil, favoritesOnly: Bool = false, trash: Bool = false) {
        self.search = search; self.since = since; self.favoritesOnly = favoritesOnly; self.trash = trash
    }
    public func includes(_ entry: HistoryEntry) -> Bool {
        guard (entry.deletedAt != nil) == trash, !favoritesOnly || entry.favorite,
              since.map({ entry.createdAt >= $0 }) ?? true else { return false }
        let key = HistoryWords.searchKey(search.trimmingCharacters(in: .whitespacesAndNewlines))
        return key.isEmpty || HistoryWords.searchKey(entry.text + "\n" + entry.original).contains(key)
    }
}

public struct HistoryPage: Sendable {
    public let entries: [HistoryEntry]
    public let total: Int
    public init(entries: [HistoryEntry] = [], total: Int = 0) { self.entries = entries; self.total = total }
}

public struct HistoryUsage: Sendable {
    public let date: Date
    public let words: Int
    public let duration: Double
    public let appID: String
    public let appName: String
    public init(date: Date, words: Int, duration: Double, appID: String = "", appName: String = "Andere Apps") {
        self.date = date; self.words = words; self.duration = duration; self.appID = appID; self.appName = appName
    }
}

public struct HistoryDay: Identifiable, Equatable, Sendable {
    public let date: Date
    public var words: Int = 0
    public var dictations: Int = 0
    public var id: Date { date }
}
public struct HistoryAppUsage: Identifiable, Sendable {
    public let id: String
    public let name: String
    public var words: Int = 0
    public var dictations: Int = 0
}
public struct HistoryStatistics: Sendable {
    public var words = 0
    public var dictations = 0
    public var duration: Double = 0
    public var timedWords = 0
    public var activeDays = 0
    public var currentStreak = 0
    public var days: [HistoryDay] = []
    public var apps: [HistoryAppUsage] = []
    public var wordsPerMinute: Double? { duration > 0 ? Double(timedWords) * 60 / duration : nil }
    public init() {}
    public static func calculate(_ usage: [HistoryUsage], now: Date = Date(), calendar: Calendar = .current) -> Self {
        var result = Self(), daily: [Date: HistoryDay] = [:], apps: [String: HistoryAppUsage] = [:]
        for item in usage {
            result.words += item.words; result.dictations += 1
            if item.duration.isFinite && item.duration > 0 { result.duration += item.duration; result.timedWords += item.words }
            let date = calendar.startOfDay(for: item.date)
            var day = daily[date] ?? HistoryDay(date: date)
            day.words += item.words; day.dictations += 1; daily[date] = day
            var app = apps[item.appID] ?? HistoryAppUsage(id: item.appID, name: item.appName)
            app.words += item.words; app.dictations += 1; apps[item.appID] = app
        }
        result.activeDays = daily.count
        let today = calendar.startOfDay(for: now)
        var cursor = today
        if daily[cursor] == nil { cursor = calendar.date(byAdding: .day, value: -1, to: today) ?? today }
        while daily[cursor] != nil {
            result.currentStreak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor), previous < cursor else { break }
            cursor = previous
        }
        result.days = (-13...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { daily[$0] ?? HistoryDay(date: $0) }
        }
        result.apps = apps.values.sorted { $0.words == $1.words ? $0.name < $1.name : $0.words > $1.words }
        return result
    }
}

/// Single-owner local text storage. SQLite calls run on this actor, never the UI actor.
/// No audio, clipboard contents, window titles, keychain values or error payloads enter this database.
public actor HistoryStore {
    public let url: URL
    private var database: OpaquePointer?
    public init(url: URL) { self.url = url }
    deinit { if let database { sqlite3_close(database) } }

    private func open() throws -> OpaquePointer {
        if let database { return database }
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw storageError() }
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }; throw storageError()
        }
        do {
            sqlite3_busy_timeout(db, 2000)
            let version = try scalar("PRAGMA user_version", db: db)
            guard version <= 1 else { throw VoiceError.message("Der Verlauf stammt aus einer neueren App-Version. Die Datei bleibt unverändert.") }
            if version == 0 {
                try execute("BEGIN IMMEDIATE", db: db)
                do {
                    try execute("""
                        CREATE TABLE dictations (
                        id TEXT PRIMARY KEY NOT NULL, created REAL NOT NULL,
                        text TEXT NOT NULL, original TEXT NOT NULL, duration REAL NOT NULL,
                        style TEXT NOT NULL, bundle TEXT, app_name TEXT,
                        fallback INTEGER NOT NULL, complete INTEGER NOT NULL, delivery TEXT NOT NULL,
                        favorite INTEGER NOT NULL DEFAULT 0, deleted REAL, words INTEGER NOT NULL,
                        search_text TEXT NOT NULL);
                        CREATE INDEX history_date ON dictations(deleted, created DESC, id DESC);
                        CREATE INDEX history_favorite ON dictations(favorite, deleted, created DESC);
                        PRAGMA user_version=1;
                        COMMIT;
                        """, db: db)
                } catch { try? execute("ROLLBACK", db: db); throw error }
            }
            database = db; return db
        } catch { sqlite3_close(db); throw error }
    }

    /// Re-delivery/copying must never duplicate a dictation or reset user flags.
    @discardableResult public func insert(_ entry: HistoryEntry) throws -> Bool {
        guard entry.duration.isFinite, entry.duration >= 0, entry.createdAt.timeIntervalSince1970.isFinite,
              !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              entry.text.utf8.count <= 4_194_304, entry.original.utf8.count <= 4_194_304,
              (entry.appBundleID?.utf8.count ?? 0) <= 512, (entry.appName?.utf8.count ?? 0) <= 512 else { throw storageError() }
        let db = try open()
        let sql = "INSERT OR IGNORE INTO dictations (id,created,text,original,duration,style,bundle,app_name,fallback,complete,delivery,favorite,deleted,words,search_text) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
        let statement = try prepare(sql, db: db); defer { sqlite3_finalize(statement) }
        try bind(entry.id.uuidString, to: 1, statement); sqlite3_bind_double(statement, 2, entry.createdAt.timeIntervalSince1970)
        try bind(entry.text, to: 3, statement); try bind(entry.original, to: 4, statement); sqlite3_bind_double(statement, 5, entry.duration)
        try bind(entry.style.rawValue, to: 6, statement); try bind(entry.appBundleID, to: 7, statement); try bind(entry.appName, to: 8, statement)
        sqlite3_bind_int(statement, 9, entry.usedFallback ? 1 : 0); sqlite3_bind_int(statement, 10, entry.isComplete ? 1 : 0)
        try bind(entry.delivery.rawValue, to: 11, statement); sqlite3_bind_int(statement, 12, entry.favorite ? 1 : 0)
        if let date = entry.deletedAt { sqlite3_bind_double(statement, 13, date.timeIntervalSince1970) } else { sqlite3_bind_null(statement, 13) }
        sqlite3_bind_int64(statement, 14, Int64(entry.wordCount)); try bind(HistoryWords.searchKey(entry.text + "\n" + entry.original), to: 15, statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw storageError() }
        return sqlite3_changes(db) > 0
    }

    public func page(filter: HistoryFilter = .init(), limit: Int = 50, offset: Int = 0) throws -> HistoryPage {
        let db = try open(), (whereSQL, values) = predicate(filter)
        let total = try scalar("SELECT COUNT(*) FROM dictations WHERE " + whereSQL, values: values, db: db)
        let statement = try prepare("SELECT id,created,text,original,duration,style,bundle,app_name,fallback,complete,delivery,favorite,deleted FROM dictations WHERE " + whereSQL + " ORDER BY created DESC,id DESC LIMIT ? OFFSET ?", db: db)
        defer { sqlite3_finalize(statement) }
        try bind(values, statement)
        sqlite3_bind_int(statement, Int32(values.count + 1), Int32(min(500, max(1, limit))))
        sqlite3_bind_int64(statement, Int32(values.count + 2), Int64(max(0, offset)))
        var entries: [HistoryEntry] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw storageError() }
            entries.append(try entry(statement))
        }
        return HistoryPage(entries: entries, total: total)
    }

    public func statistics(since: Date? = nil, now: Date = Date(), calendar: Calendar = .current) throws -> HistoryStatistics {
        let db = try open()
        let statement = try prepare("SELECT created,words,duration,bundle,app_name FROM dictations WHERE deleted IS NULL AND complete=1" + (since == nil ? "" : " AND created>=?"), db: db)
        defer { sqlite3_finalize(statement) }
        if let since { sqlite3_bind_double(statement, 1, since.timeIntervalSince1970) }
        var usage: [HistoryUsage] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw storageError() }
            usage.append(.init(date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)), words: Int(sqlite3_column_int64(statement, 1)), duration: sqlite3_column_double(statement, 2), appID: string(statement, 3) ?? "", appName: string(statement, 4) ?? "Andere Apps"))
        }
        return HistoryStatistics.calculate(usage, now: now, calendar: calendar)
    }

    public func setFavorite(_ id: UUID, _ value: Bool) throws {
        try update("UPDATE dictations SET favorite=? WHERE id=?", number: value ? 1 : 0, id: id)
    }
    public func setDeleted(_ id: UUID, at date: Date?) throws {
        try update("UPDATE dictations SET deleted=? WHERE id=?", number: date?.timeIntervalSince1970, id: id)
    }
    /// Versioned, explicit user export includes active and recoverable trashed text.
    public func export(to destination: URL, includingTrash: Bool = false) throws {
        var active: [HistoryEntry] = [], trashed: [HistoryEntry] = []
        for trash in includingTrash ? [false, true] : [false] {
            var offset = 0
            while true {
                let page = try page(filter: .init(trash: trash), limit: 500, offset: offset)
                if trash { trashed.append(contentsOf: page.entries) } else { active.append(contentsOf: page.entries) }
                offset += page.entries.count
                if offset >= page.total || page.entries.isEmpty { break }
            }
        }
        struct Export: Codable { let version: Int; let entries: [HistoryEntry] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Export(version: 1, entries: active + trashed)).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    /// User-requested reset remains reversible through the macOS Trash.
    public func moveToTrash() throws -> URL? {
        if let database {
            guard sqlite3_close(database) == SQLITE_OK else { throw storageError() }
            self.database = nil
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }

    private func update(_ sql: String, number: Double?, id: UUID) throws {
        let db = try open(), statement = try prepare(sql, db: db); defer { sqlite3_finalize(statement) }
        if let number { sqlite3_bind_double(statement, 1, number) } else { sqlite3_bind_null(statement, 1) }
        try bind(id.uuidString, to: 2, statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw storageError() }
    }
    private func predicate(_ filter: HistoryFilter) -> (String, [String]) {
        var clauses = [filter.trash ? "deleted IS NOT NULL" : "deleted IS NULL"], values: [String] = []
        if filter.favoritesOnly { clauses.append("favorite=1") }
        if let since = filter.since { clauses.append("created>=CAST(? AS REAL)"); values.append(String(since.timeIntervalSince1970)) }
        let key = HistoryWords.searchKey(filter.search.trimmingCharacters(in: .whitespacesAndNewlines))
        if !key.isEmpty {
            clauses.append("search_text LIKE ? ESCAPE '\\'")
            values.append("%" + key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%")
        }
        return (clauses.joined(separator: " AND "), values)
    }
    private func entry(_ statement: OpaquePointer) throws -> HistoryEntry {
        guard let id = string(statement, 0).flatMap(UUID.init(uuidString:)),
              let text = string(statement, 2), let original = string(statement, 3),
              let style = string(statement, 5).flatMap(TextStyle.init(rawValue:)),
              let status = string(statement, 10).flatMap(DeliveryStatus.init(rawValue:)) else { throw storageError() }
        let result = DictationResult(id: id, text: text, original: original, usedFallback: sqlite3_column_int(statement, 8) != 0, duration: sqlite3_column_double(statement, 4), isComplete: sqlite3_column_int(statement, 9) != 0)
        return HistoryEntry(result: result, createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)), style: style, appBundleID: string(statement, 6), appName: string(statement, 7), delivery: status, favorite: sqlite3_column_int(statement, 11) != 0, deletedAt: sqlite3_column_type(statement, 12) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 12)))
    }
    private func string(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        return String(bytes: UnsafeBufferPointer(start: bytes, count: count), encoding: .utf8)
    }
    private func prepare(_ sql: String, db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw storageError() }
        return statement
    }
    private func bind(_ values: [String], _ statement: OpaquePointer) throws {
        for (index, value) in values.enumerated() { try bind(value, to: Int32(index + 1), statement) }
    }
    private func bind(_ value: String?, to index: Int32, _ statement: OpaquePointer) throws {
        guard let value else { sqlite3_bind_null(statement, index); return }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let status = value.withCString { sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count), transient) }
        guard status == SQLITE_OK else { throw storageError() }
    }
    private func scalar(_ sql: String, values: [String] = [], db: OpaquePointer) throws -> Int {
        let statement = try prepare(sql, db: db); defer { sqlite3_finalize(statement) }; try bind(values, statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw storageError() }
        return Int(sqlite3_column_int64(statement, 0))
    }
    private func execute(_ sql: String, db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw storageError() }
    }
    private func storageError() -> VoiceError { .message("Der lokale Textverlauf konnte nicht gelesen oder gespeichert werden. Deine Aufnahme bleibt davon unabhängig.") }
}
