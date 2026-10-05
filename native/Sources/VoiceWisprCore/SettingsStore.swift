import Foundation
import Security
import Darwin

private struct StoredSettings: Codable {
    var version: Int
    var settings: Settings
    var dictionary: [DictionaryEntry]
    var wisprImport: MigrationProvenance?
    init(_ document: ExportDocument, provenance: MigrationProvenance?) { version = document.version; settings = document.settings; dictionary = document.dictionary; wisprImport = provenance }
    var document: ExportDocument { var result = ExportDocument(settings: settings, dictionary: dictionary); result.version = version; return result }
}
/// Only the re-import bookkeeping; a corrupt or newer file must never block saving.
private struct StoredProvenance: Decodable { var wisprImport: MigrationProvenance? }

public actor SettingsStore {
    private var quarantinedProvenance: MigrationProvenance?
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> ExportDocument {
        do { return try stored().document }
        catch {
            // Provenance is bookkeeping only; retain bounded readable metadata.
            quarantinedProvenance = (try? Self.boundedData(from: url)).flatMap { try? JSONDecoder().decode(StoredProvenance.self, from: $0) }?.wisprImport
            // Preserve malformed startup state before any later safe-default save.
            if FileManager.default.fileExists(atPath: url.path) {
                let quarantine = url.deletingLastPathComponent().appendingPathComponent("settings-quarantine-" + UUID().uuidString + ".json")
                try? FileManager.default.moveItem(at: url, to: quarantine)
            }
            throw error
        }
    }
    public static let maximumFileBytes = 8 * 1024 * 1024
    /// One descriptor, no links, bounded allocation even if the file grows while reading.
    public static func boundedData(from source: URL, maximumBytes: Int = maximumFileBytes) throws -> Data {
        guard maximumBytes > 0, maximumBytes <= maximumFileBytes else { throw VoiceError.message("Ungültige Dateigrenze") }
        let fd = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw VoiceError.message("Einstellungsdatei ist nicht sicher lesbar") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var status = stat()
        guard fstat(fd, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
              status.st_size >= 0, status.st_size <= maximumBytes else { throw VoiceError.message("Einstellungsdatei ist zu groß oder keine reguläre Datei") }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw VoiceError.message("Einstellungsdatei ist zu groß") }
        return data
    }
    private func stored() throws -> StoredSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return StoredSettings(ExportDocument(), provenance: nil) }
        let stored = try JSONDecoder().decode(StoredSettings.self, from: Self.boundedData(from: url))
        try Self.validate(stored.document)
        return stored
    }
    public func save(_ document: ExportDocument) throws {
        let provenance = (try? Self.boundedData(from: url)).flatMap { try? JSONDecoder().decode(StoredProvenance.self, from: $0) }?.wisprImport ?? quarantinedProvenance
        try write(document, provenance: provenance)
        quarantinedProvenance = nil
    }
    private func write(_ document: ExportDocument, provenance: MigrationProvenance?) throws {
        try Self.validate(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Data.atomic handles both the first save and replacement in one same-directory rename.
        let data = try JSONEncoder.pretty.encode(StoredSettings(document, provenance: provenance))
        guard data.count <= Self.maximumFileBytes else { throw VoiceError.message("Einstellungen überschreiten die Dateigrenze") }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func applyWisprImport(_ service: WisprMigrationService) throws -> MigrationResult {
        let before = try stored()
        let applied = service.apply(to: before.document, provenance: before.wisprImport ?? MigrationProvenance())
        guard !applied.result.preview.isPartial else { return applied.result }
        // Reject unsupported source values before touching either target or undo.
        try Self.validate(applied.document)
        // Keep an undo snapshot before committing the single document/provenance transaction.
        let backup = url.deletingLastPathComponent().appendingPathComponent("wispr-import-undo.json")
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.pretty.encode(before).write(to: backup, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        try write(applied.document, provenance: applied.provenance)
        return applied.result
    }
    public func undoWisprImport() throws {
        let backup = url.deletingLastPathComponent().appendingPathComponent("wispr-import-undo.json")
        guard FileManager.default.fileExists(atPath: backup.path) else { throw VoiceError.message("Es gibt keinen Wispr-Import, der rückgängig gemacht werden kann.") }
        let snapshot = try JSONDecoder().decode(StoredSettings.self, from: Self.boundedData(from: backup))
        // The import never touches cloud or camera choices. An old snapshot must not
        // re-enable a recipient or the camera beta, so those stay as they are now.
        let current = try stored().document.settings
        var document = snapshot.document
        document.settings.cloudEnabled = current.cloudEnabled; document.settings.cloudEndpoint = current.cloudEndpoint; document.settings.cloudModel = current.cloudModel
        document.settings.lipReadingEnabled = current.lipReadingEnabled; document.settings.lipReadingLanguage = current.lipReadingLanguage; document.settings.lipReadingShortcut = current.lipReadingShortcut
        // Neither does it touch setup progress, pause or history. Undo must not re-enable a history the user turned off.
        document.settings.onboardingComplete = current.onboardingComplete; document.settings.practiceCompleted = current.practiceCompleted
        document.settings.paused = current.paused; document.settings.historyEnabled = current.historyEnabled
        try write(document, provenance: snapshot.wisprImport)
        // One undo per import; repeating it would roll back later edits again.
        try? FileManager.default.removeItem(at: backup)
    }
    public func export(to destination: URL) throws { try JSONEncoder.pretty.encode(try load()).write(to: destination, options: .atomic) }
    public func importDocument(from source: URL) throws -> ExportDocument {
        var document = try JSONDecoder().decode(ExportDocument.self, from: Self.boundedData(from: source))
        // Imported files cannot authorize a new recipient or reuse a stored key there.
        document.settings.cloudEnabled = false
        document.settings.lipReadingEnabled = false
        try Self.validate(document)
        return document
    }
    public static func validate(_ document: ExportDocument) throws {
        guard document.version == 1 else { throw VoiceError.message("Unbekannte Exportversion") }
        guard !document.settings.languages.isEmpty, document.settings.languages.count <= 64,
              document.settings.languages.allSatisfy({ $0.range(of: "^[a-z]{2,3}(-[A-Za-z]{2,8})?$", options: .regularExpression) != nil }),
              document.dictionary.count <= 10_000,
              document.settings.appStyles.count <= 512,
              document.settings.appStyles.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 }),
              document.settings.cloudEndpoint.utf8.count <= 2048, document.settings.cloudModel.utf8.count <= 255,
              document.dictionary.reduce(0, { $0 + $1.phrase.utf8.count + ($1.replacement?.utf8.count ?? 0) + $1.id.utf8.count + ($1.sourceID?.utf8.count ?? 0) + ($1.sourceFingerprint?.utf8.count ?? 0) }) <= 2 * 1024 * 1024, Set(document.dictionary.map(\.id)).count == document.dictionary.count,
              document.dictionary.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 128 && ($0.sourceID?.utf8.count ?? 0) <= 128 && ($0.sourceFingerprint?.utf8.count ?? 0) <= 256 && !$0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.phrase.count <= 255 && ($0.replacement?.utf8.count ?? 0) <= 16_384 }) else { throw VoiceError.message("Ungültige Einstellungen oder Wörterbucheinträge") }
        // An unused endpoint may be empty or half-typed; enabling cloud re-validates it.
        if document.settings.cloudEnabled {
            guard (try? CloudRecipient.normalized(document.settings.cloudEndpoint)) != nil else { throw VoiceError.message("Cloud-Endpunkt muss HTTPS oder eine lokale Adresse sein") }
        }
        let allowedFlags: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 23)
        guard document.settings.lipReadingLanguage == nil || ["en", "de"].contains(document.settings.lipReadingLanguage!) else { throw VoiceError.message("Unbekannte Lippenlese-Sprache") }
        let shortcuts = [document.settings.shortcut] + (document.settings.shortcutBindings?.all ?? []) + (document.settings.lipReadingShortcut.map { [$0] } ?? [])
        guard shortcuts.count <= 32, shortcuts.allSatisfy({ $0.modifiers & ~allowedFlags == 0 && ($0.keyCode.map { $0 <= 126 } ?? ($0.modifiers != 0)) }) else { throw VoiceError.message("Ungültiges Tastenkürzel") }
    }
}

public struct KeychainStorage: Sendable {
    public let service: String
    public let account: String
    public init(service: String = "com.mediapublishing.VoiceWispr", account: String = "cloud-api-key") { self.service = service; self.account = account }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    public func setKey(_ key: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { try deleteKey(); return }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    public func key() throws -> String? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = value as? Data, let result = String(data: data, encoding: .utf8) else { throw VoiceError.message("API-Schlüssel im Schlüsselbund ist nicht lesbar") }
        return result
    }
    public func deleteKey() throws { let status = SecItemDelete(query as CFDictionary); if status != errSecItemNotFound { try check(status) } }
    private func check(_ status: OSStatus) throws { guard status == errSecSuccess else { throw VoiceError.message("Schlüsselbund-Zugriff fehlgeschlagen (\(status))") } }
}
private extension JSONEncoder { static var pretty: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e } }
