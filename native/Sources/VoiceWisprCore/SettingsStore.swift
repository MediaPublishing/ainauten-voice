import Foundation
import Security

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
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> ExportDocument { try stored().document }
    private func stored() throws -> StoredSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return StoredSettings(ExportDocument(), provenance: nil) }
        let stored = try JSONDecoder().decode(StoredSettings.self, from: Data(contentsOf: url))
        try Self.validate(stored.document)
        return stored
    }
    public func save(_ document: ExportDocument) throws {
        let provenance = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(StoredProvenance.self, from: $0) }?.wisprImport
        try write(document, provenance: provenance)
    }
    private func write(_ document: ExportDocument, provenance: MigrationProvenance?) throws {
        try Self.validate(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Data.atomic handles both the first save and replacement in one same-directory rename.
        try JSONEncoder.pretty.encode(StoredSettings(document, provenance: provenance)).write(to: url, options: .atomic)
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
        let snapshot = try JSONDecoder().decode(StoredSettings.self, from: Data(contentsOf: backup))
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
        var document = try JSONDecoder().decode(ExportDocument.self, from: Data(contentsOf: source))
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
              document.dictionary.count <= 100_000, Set(document.dictionary.map(\.id)).count == document.dictionary.count,
              document.dictionary.allSatisfy({ !$0.id.isEmpty && !$0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.phrase.count <= 255 && ($0.replacement?.utf8.count ?? 0) <= 1_000_000 }) else { throw VoiceError.message("Ungültige Einstellungen oder Wörterbucheinträge") }
        // An unused endpoint may be empty or half-typed; enabling cloud re-validates it.
        if document.settings.cloudEnabled {
            guard let endpoint = URL(string: document.settings.cloudEndpoint), endpoint.host != nil,
                  endpoint.scheme == "https" || (endpoint.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(endpoint.host ?? "")) else { throw VoiceError.message("Cloud-Endpunkt muss HTTPS oder eine lokale Adresse sein") }
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
