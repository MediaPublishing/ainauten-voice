import Foundation
import CryptoKit
import CSQLite
import Darwin

public struct ImportPreview: Sendable, Equatable {
    public var words = 0
    public var replacements = 0
    public var deleted = 0
    public var sourceDuplicates = 0
    public var uniqueEntries: Int { words + replacements - sourceDuplicates }
    public var unsupported: [String] = []
    public var unsupportedCounts: [String: Int] = [:]
    public var excludedDictionaryEntries: Int {
        ["invalidDictionaryEntries", "overlongPhrases", "oversizedReplacements"].reduce(0) { $0 + (unsupportedCounts[$1] ?? 0) }
    }
    public var errors: [String] = []
    public var languages: [String] = []
    public var shortcut: Shortcut?
    public var shortcutBindings = ShortcutBindings()
    public var defaultStyle: TextStyle?
    public var appStyles: [String: TextStyle] = [:]
    public var supportedUserStyles: [String] = []
    public var isPartial: Bool { !errors.isEmpty }
    public init() {}
}
public typealias MigrationPreview = ImportPreview
public struct MigrationResult: Sendable, Equatable {
    public var imported = 0
    public var skipped = 0
    public var preserved = 0
    public var updated = 0
    public var preview: ImportPreview
    public init(imported: Int = 0, skipped: Int = 0, preserved: Int = 0, updated: Int = 0, preview: ImportPreview) {
        self.imported = imported; self.skipped = skipped; self.preserved = preserved; self.updated = updated; self.preview = preview
    }
    public func summary(savedCount: Int) -> String {
        guard !preview.isPartial else {
            return "Import nicht ausgeführt. Deine bisherigen Einstellungen bleiben erhalten. " + preview.errors.joined(separator: " ")
        }
        var text = "Import abgeschlossen: \(savedCount) Wörterbucheinträge gespeichert. \(imported) neu, \(updated) aktualisiert."
        if preview.sourceDuplicates > 0 { text += " \(preview.sourceDuplicates) doppelte Wispr-Flow-Einträge zusammengeführt." }
        for (key, singular, plural) in [
            ("invalidDictionaryEntries", "leerer oder ungültiger Wörterbucheintrag", "leere oder ungültige Wörterbucheinträge"),
            ("overlongPhrases", "Ausdruck über 255 Zeichen", "Ausdrücke über 255 Zeichen"),
            ("oversizedReplacements", "Ersetzung über 16 KB", "Ersetzungen über 16 KB")
        ] {
            let count = preview.unsupportedCounts[key] ?? 0
            if count > 0 { text += " \(count) \(count == 1 ? singular : plural) ausgelassen." }
        }
        if preserved > 0 { text += " \(preserved) lokal geänderte oder entfernte Quelleinträge beibehalten." }
        return text
    }
}
public struct MigrationProvenance: Codable, Sendable, Equatable {
    public var sourceIDs: Set<String> = []
    public var languages: [String]?
    public var shortcut: Shortcut?
    public var shortcutBindings: ShortcutBindings?
    public var defaultStyle: TextStyle?
    public var appStyles: [String: TextStyle] = [:]
    public init() {}
}
public struct MigrationApplication: Sendable {
    public let result: MigrationResult
    public let document: ExportDocument
    public let provenance: MigrationProvenance
}

public struct WisprMigrationService: Sendable {
    public let configURL: URL
    public let databaseURL: URL
    public init(configURL: URL = URL(fileURLWithPath: ("~/Library/Application Support/Wispr Flow/config.json" as NSString).expandingTildeInPath), databaseURL: URL = URL(fileURLWithPath: ("~/Library/Application Support/Wispr Flow/flow.sqlite" as NSString).expandingTildeInPath)) {
        self.configURL = configURL; self.databaseURL = databaseURL
    }
    public func preview() -> ImportPreview { snapshot().0 }
    public func apply(to existing: [DictionaryEntry]) -> (MigrationResult, [DictionaryEntry]) {
        let applied = apply(to: ExportDocument(dictionary: existing), provenance: MigrationProvenance())
        return (applied.result, applied.document.dictionary)
    }
    public func apply(to existing: ExportDocument, provenance: MigrationProvenance = MigrationProvenance()) -> MigrationApplication {
        let (preview, rows) = snapshot()
        guard !preview.isPartial else { return MigrationApplication(result: MigrationResult(preview: preview), document: existing, provenance: provenance) }
        var document = existing, history = provenance
        var imported = 0, skipped = preview.excludedDictionaryEntries, preserved = 0, updated = 0
        var contentCounts: [String: Int] = [:]
        for entry in document.dictionary { contentCounts[Self.contentFingerprint(entry.phrase, entry.replacement), default: 0] += 1 }
        for row in rows {
            let rowFingerprint = row.fingerprint
            let rowContent = Self.contentFingerprint(row.phrase, row.replacement)
            let index = document.dictionary.firstIndex { $0.sourceID == row.id || $0.sourceFingerprint == rowFingerprint }
            if let index {
                let old = document.dictionary[index]
                if old.manuallyModified || (old.sourceFingerprint != nil && Self.fingerprint(old.phrase, old.replacement) != old.sourceFingerprint) {
                    preserved += 1
                } else {
                    if old.phrase != row.phrase || old.replacement != row.replacement { updated += 1 }
                    let oldContent = Self.contentFingerprint(old.phrase, old.replacement)
                    contentCounts[oldContent, default: 0] -= 1
                    contentCounts[rowContent, default: 0] += 1
                    document.dictionary[index].phrase = row.phrase
                    document.dictionary[index].replacement = row.replacement
                    document.dictionary[index].sourceID = row.id
                    document.dictionary[index].sourceFingerprint = rowFingerprint
                }
                skipped += 1
            } else if history.sourceIDs.contains(row.id) {
                // A previously imported item removed locally is a tombstone, not a new item.
                // Collapsed source duplicates are also in history, but are not local edits.
                if contentCounts[rowContent, default: 0] == 0 { preserved += 1 }
                skipped += 1
            } else if contentCounts[rowContent, default: 0] > 0 {
                skipped += 1
            } else {
                document.dictionary.append(DictionaryEntry(phrase: row.phrase, replacement: row.replacement, sourceID: row.id, sourceFingerprint: rowFingerprint))
                contentCounts[rowContent, default: 0] += 1
                imported += 1
            }
            history.sourceIDs.insert(row.id)
        }
        let defaults = Settings()
        if !preview.languages.isEmpty, document.settings.languages == (history.languages ?? defaults.languages) {
            document.settings.languages = preview.languages; history.languages = preview.languages
        }
        if let shortcut = preview.shortcut, document.settings.shortcut == (history.shortcut ?? defaults.shortcut) {
            document.settings.shortcut = shortcut; document.settings.importedWisprShortcut = true; history.shortcut = shortcut
        }
        if document.settings.shortcutBindings == history.shortcutBindings {
            document.settings.shortcutBindings = preview.shortcutBindings
            history.shortcutBindings = preview.shortcutBindings
        }
        if let style = preview.defaultStyle, document.settings.defaultStyle == (history.defaultStyle ?? defaults.defaultStyle) {
            document.settings.defaultStyle = style; history.defaultStyle = style
        }
        for (app, style) in preview.appStyles where document.settings.appStyles[app] == history.appStyles[app] {
            document.settings.appStyles[app] = style; history.appStyles[app] = style
        }
        return MigrationApplication(result: MigrationResult(imported: imported, skipped: skipped, preserved: preserved, updated: updated, preview: preview), document: document, provenance: history)
    }
    static func fingerprint(_ phrase: String, _ replacement: String?) -> String {
        // Stable across launches; randomized Swift hashValue is not a source fingerprint.
        let normalized = phrase.precomposedStringWithCanonicalMapping
        let payload = [normalized, replacement ?? ""].map { "\(($0 as NSString).length):\($0)" }.joined()
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func contentFingerprint(_ phrase: String, _ replacement: String?) -> String {
        fingerprint(phrase.lowercased(), replacement)
    }
    private func snapshot() -> (ImportPreview, [WisprRow]) {
        var preview = ImportPreview(), rows: [WisprRow] = []
        do { let source = try WisprSourceRead.withRetries { try WisprSQLite.snapshot(databaseURL) }; preview.words = source.words; preview.replacements = source.replacements; preview.deleted = source.deleted; rows = source.rows
            preview.sourceDuplicates = rows.count - Set(rows.map { Self.contentFingerprint($0.phrase, $0.replacement) }).count
            for (key, label, count) in [
                ("invalidDictionaryEntries", "Leere oder ungültige Wörterbucheinträge", source.invalidRows),
                ("overlongPhrases", "Ausdrücke über 255 Zeichen", source.overlongPhrases),
                ("oversizedReplacements", "Ersetzungen über 16 KB", source.oversizedReplacements)
            ] where count > 0 {
                preview.unsupported.append("\(label) (\(count))"); preview.unsupportedCounts[key] = count
            }
            if source.snippets > 0 { preview.unsupported.append("Textbausteine (\(source.snippets))"); preview.unsupportedCounts["snippets"] = source.snippets }
        } catch { preview.errors.append(error.localizedDescription) }
        do { try readPreferences(into: &preview) } catch { preview.errors.append(error.localizedDescription) }
        return (preview, rows)
    }
    private func readPreferences(into preview: inout ImportPreview) throws {
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any],
              let prefs = root["prefs"] as? [String: Any], let user = prefs["user"] as? [String: Any] else { throw VoiceError.message("Wispr-Einstellungen haben ein unbekanntes Format") }
        // Never read identity, transcript, OCR, account or cloud fields.
        if let languages = user["selectedLanguages"] as? [String] {
            preview.languages = Array(NSOrderedSet(array: languages.filter { $0.range(of: "^[a-z]{2,3}(-[A-Za-z]{2,8})?$", options: .regularExpression) != nil })) as? [String] ?? []
        }
        if let shortcuts = user["shortcuts"] as? [String: String] {
            for (binding, action) in shortcuts.sorted(by: { $0.key < $1.key }) {
                guard ["ptt", "popo", "dismiss", "copy_last_text", "paste_last_text"].contains(action) else {
                    preview.unsupportedCounts["actions", default: 0] += 1; continue
                }
                guard let shortcut = Self.decodeShortcut(binding) else {
                    preview.unsupported.append("Tastenkürzel nicht unterstützt: \(binding)"); preview.unsupportedCounts["shortcut", default: 0] += 1; continue
                }
                switch action {
                case "ptt": if preview.shortcut == nil { preview.shortcut = shortcut } else { preview.shortcutBindings.holdExtras.append(shortcut) }
                case "popo": preview.shortcutBindings.handsFree.append(shortcut)
                case "dismiss": preview.shortcutBindings.cancel.append(shortcut)
                case "copy_last_text": preview.shortcutBindings.copyLast.append(shortcut)
                case "paste_last_text": preview.shortcutBindings.pasteLast.append(shortcut)
                default: break
                }
            }
            if let unsupported = preview.unsupportedCounts["actions"] { preview.unsupported.append("Meetings oder Computersteuerung (\(unsupported))") }
        }
        if let internalCode = user["modifierShortcut"] as? Int {
            preview.unsupported.append("Interner Modifier-Code \(internalCode) ist nicht dokumentiert; Tastenkürzel separat geprüft.")
            preview.unsupportedCounts["modifierShortcut"] = 1
        }
        if let format = user["defaultTranscriptionFormat"] as? String {
            if format == "Apply AI formatting" { preview.defaultStyle = .cleaned }
            else if format == "Verbatim" || format == "No AI formatting" { preview.defaultStyle = .original }
            else if format == "Casual messaging" { preview.defaultStyle = .chat }
            else { preview.unsupported.append("Unbekanntes Transkriptionsformat"); preview.unsupportedCounts["format"] = 1 }
        }
        let bundles: [String: String] = ["Slack": "com.tinyspeck.slackmacgap", "Microsoft Teams": "com.microsoft.teams2", "Microsoft Outlook": "com.microsoft.Outlook", "Superhuman": "com.superhuman.desktop", "Messages": "com.apple.MobileSMS", "WhatsApp": "net.whatsapp.WhatsApp", "WeChat": "com.tencent.xinWeChat", "Messenger": "com.facebook.archon"]
        if let voices = user["userVoices"] as? [String: [String: Any]] {
            for (key, voice) in voices.sorted(by: { $0.key < $1.key }) {
                let style: TextStyle?
                switch key { case "email": style = .email; case "work", "personal": style = .chat; case "other": style = .cleaned; default: style = nil }
                guard voice["source"] as? String == "builtIn", let style else {
                    preview.unsupportedCounts["customUserStyles", default: 0] += 1; continue
                }
                preview.supportedUserStyles.append(key)
                for name in voice["appNames"] as? [String] ?? [] {
                    if let bundle = bundles[name] { preview.appStyles[bundle] = style }
                    else { preview.unsupportedCounts["unmappedApps", default: 0] += 1 }
                }
            }
        }
        if let formats = user["appTranscriptionFormats"] as? [Any], !formats.isEmpty { preview.unsupportedCounts["appTranscriptionFormats"] = formats.count }
        for key in ["customUserStyles", "unmappedApps", "appTranscriptionFormats"] {
            if let count = preview.unsupportedCounts[key] { preview.unsupported.append("\(key) (\(count))") }
        }
    }
    public static func decodeShortcut(_ binding: String) -> Shortcut? {
        let parts = binding.split(separator: "+").compactMap { UInt16($0) }
        guard parts.count == binding.split(separator: "+").count, !parts.isEmpty, Set(parts).count == parts.count else { return nil }
        let modifiers: [UInt16: UInt64] = [55: 1 << 20, 54: 1 << 20, 56: 1 << 17, 60: 1 << 17, 58: 1 << 19, 61: 1 << 19, 59: 1 << 18, 62: 1 << 18, 63: 1 << 23]
        let keys = parts.filter { modifiers[$0] == nil }
        guard keys.count <= 1, keys.first.map({ $0 <= 126 }) ?? true else { return nil }
        let flags = parts.reduce(UInt64(0)) { $0 | (modifiers[$1] ?? 0) }
        guard flags != 0 || !keys.isEmpty else { return nil }
        return Shortcut(keyCode: keys.first, modifiers: flags)
    }
}

private struct WisprRow { let id: String; let phrase: String; let replacement: String?; var fingerprint: String { WisprMigrationService.fingerprint(phrase, replacement) } }

// Retry only transient SQLite failures. Each attempt reopens a read-only connection
// and starts a fresh snapshot. Live WAL reads use normal SQLite locking. Closed
// WAL databases without sidecars use a fenced immutable read below. No rows from
// a failed or changed-source attempt are committed; never copy the main DB alone.
struct WisprSQLiteReadError: LocalizedError {
    let code: Int32
    var primaryCode: Int32 { code & 0xff }
    var isTransient: Bool { [SQLITE_BUSY, SQLITE_LOCKED, SQLITE_READONLY, SQLITE_CANTOPEN, SQLITE_IOERR, SQLITE_PROTOCOL].contains(primaryCode) }
    var errorDescription: String? {
        if primaryCode == SQLITE_BUSY || primaryCode == SQLITE_LOCKED {
            return "Die Wispr-Flow-Datenbank ist noch belegt. Bitte erneut importieren."
        }
        if isTransient {
            return "Die Wispr-Flow-Datenbank ist vorübergehend nicht lesbar (SQLite-Code \(code)). Bitte erneut importieren."
        }
        return "Die Wispr-Flow-Datenbank konnte nicht vollständig gelesen werden (SQLite-Code \(code)). Deine bisherigen Einstellungen bleiben erhalten."
    }
}

enum WisprSourceRead {
    static func withRetries<T>(pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }, operation: () throws -> T) throws -> T {
        let delays: [TimeInterval] = [0.08, 0.2]
        var attempt = 0
        while true {
            do { return try operation() }
            catch let error as WisprSQLiteReadError where error.isTransient && attempt < delays.count {
                pause(delays[attempt]); attempt += 1
            }
        }
    }
}

// SQLite cannot always open a closed WAL-mode database read-only without creating
// sidecars. Immutable is safe here only while the same physical file stays stable
// and all journal sidecars remain absent. Recheck after every dictionary read.
struct WisprClosedWALSnapshot {
    let url: URL
    private let identity: Identity
    private struct Identity: Equatable {
        let device: dev_t, inode: ino_t, size: off_t
        let modifiedSeconds: Int, modifiedNanos: Int, changedSeconds: Int, changedNanos: Int
        init(_ info: stat) {
            device = info.st_dev; inode = info.st_ino; size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanos = info.st_mtimespec.tv_nsec
            changedSeconds = info.st_ctimespec.tv_sec; changedNanos = info.st_ctimespec.tv_nsec
        }
    }
    private static func hasSidecars(_ url: URL) -> Bool {
        ["-wal", "-shm", "-journal"].contains { FileManager.default.fileExists(atPath: url.path + $0) }
    }
    private static func inspect(_ url: URL) throws -> (Identity, Data) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0 else { throw WisprSQLiteReadError(code: SQLITE_IOERR) }
        return (Identity(info), try handle.read(upToCount: 20) ?? Data())
    }
    static func capture(_ original: URL) throws -> WisprClosedWALSnapshot? {
        let url = original.resolvingSymlinksInPath()
        guard !hasSidecars(url) else { return nil }
        let (identity, header) = try inspect(url)
        guard header.count == 20, header.prefix(16) == Data("SQLite format 3\0".utf8), header[18] == 2, header[19] == 2 else { return nil }
        let snapshot = WisprClosedWALSnapshot(url: url, identity: identity)
        try snapshot.validate()
        return snapshot
    }
    var sqliteURI: String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "mode", value: "ro"), URLQueryItem(name: "immutable", value: "1")]
        return components.string!
    }
    func validate() throws {
        guard !Self.hasSidecars(url), let current = try? Self.inspect(url), current.0 == identity,
              !Self.hasSidecars(url) else { throw WisprSQLiteReadError(code: SQLITE_BUSY) }
    }
}

private struct WisprSQLite {
    var words = 0, replacements = 0, deleted = 0, snippets = 0
    var invalidRows = 0, overlongPhrases = 0, oversizedReplacements = 0
    var rows: [WisprRow] = []
    static func snapshot(_ url: URL) throws -> WisprSQLite {
        guard FileManager.default.fileExists(atPath: url.path) else { throw VoiceError.message("Die Wispr-Flow-Datenbank wurde nicht gefunden. Deine bisherigen Einstellungen bleiben erhalten.") }
        let closedWAL = try WisprClosedWALSnapshot.capture(url)
        var db: OpaquePointer?
        let opened = sqlite3_open_v2(closedWAL?.sqliteURI ?? url.path, &db,
                                    SQLITE_OPEN_READONLY | (closedWAL == nil ? 0 : SQLITE_OPEN_URI), nil)
        guard opened == SQLITE_OK else {
            let code = db.map { sqlite3_extended_errcode($0) } ?? opened
            if db != nil { sqlite3_close(db) }
            throw WisprSQLiteReadError(code: code)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 350)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw WisprSQLiteReadError(code: sqlite3_extended_errcode(db)) }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        var schema: OpaquePointer?
        let schemaStatus = sqlite3_prepare_v2(db, "PRAGMA table_info(Dictionary)", -1, &schema, nil)
        guard schemaStatus == SQLITE_OK else {
            let code = sqlite3_extended_errcode(db)
            sqlite3_finalize(schema)
            throw WisprSQLiteReadError(code: code)
        }
        var columns: Set<String> = []
        var schemaStep = sqlite3_step(schema)
        while schemaStep == SQLITE_ROW {
            if let name = sqlite3_column_text(schema, 1) { columns.insert(String(cString: name)) }
            schemaStep = sqlite3_step(schema)
        }
        let schemaCode = sqlite3_extended_errcode(db)
        sqlite3_finalize(schema)
        guard schemaStep == SQLITE_DONE else { throw WisprSQLiteReadError(code: schemaCode) }
        guard Set(["id", "phrase", "replacement", "isDeleted", "isSnippet", "replacementHtml"]).isSubset(of: columns) else { throw VoiceError.message("Unbekanntes Wispr-Wörterbuchschema; Import nicht ausgeführt") }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT id, phrase, replacement, isDeleted, isSnippet, replacementHtml FROM Dictionary ORDER BY id", -1, &statement, nil) == SQLITE_OK else { throw WisprSQLiteReadError(code: sqlite3_extended_errcode(db)) }
        var result = WisprSQLite()
        func string(_ index: Int32) -> String? { sqlite3_column_text(statement, index).map { String(cString: $0) } }
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw WisprSQLiteReadError(code: sqlite3_extended_errcode(db)) }
            if sqlite3_column_int(statement, 3) != 0 { result.deleted += 1; continue }
            if sqlite3_column_int(statement, 4) != 0 || !(string(5) ?? "").isEmpty { result.snippets += 1; continue }
            // Reject individual rows before deduplication/provenance. A corrected
            // source row remains eligible on reimport; database failures still throw.
            guard let id = string(0), !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let phrase = string(1), !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                result.invalidRows += 1; continue
            }
            // Match SettingsStore's character/byte bounds without truncating content.
            guard phrase.count <= 255 else { result.overlongPhrases += 1; continue }
            let replacement = string(2).flatMap { $0.isEmpty ? nil : $0 }
            guard (replacement?.utf8.count ?? 0) <= DictionaryEntry.maximumReplacementBytes else { result.oversizedReplacements += 1; continue }
            if replacement == nil { result.words += 1 } else { result.replacements += 1 }
            result.rows.append(WisprRow(id: "wispr:\(id)", phrase: phrase, replacement: replacement))
        }
        try closedWAL?.validate()
        return result
    }
}
