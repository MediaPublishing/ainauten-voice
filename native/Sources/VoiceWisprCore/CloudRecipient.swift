import Foundation

/// Recipient approval is protected separately from the user-editable settings.
/// Existing profiles must approve again once; imports cannot grant approval.
public enum CloudRecipient {
    private static var storage: KeychainStorage { KeychainStorage(account: "cloud-approved-recipient") }
    public static func normalized(_ value: String) throws -> String {
        guard var url = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme?.lowercased() == "https" || (url.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())) else {
            throw VoiceError.message("Cloud-Adresse muss HTTPS oder eine lokale Adresse ohne Zugangsdaten, Query oder Fragment sein.")
        }
        url.scheme = url.scheme?.lowercased(); url.host = host.lowercased()
        if (url.scheme == "https" && url.port == 443) || (url.scheme == "http" && url.port == 80) { url.port = nil }
        while url.path.hasSuffix("/") { url.path.removeLast() }
        guard let result = url.string, result.utf8.count <= 2048 else { throw VoiceError.message("Ungültige Cloud-Adresse") }
        return result
    }
    public static func approve(_ endpoint: String) throws { try storage.setKey(normalized(endpoint)) }
    public static func isApproved(_ endpoint: URL) throws -> Bool {
        try storage.key() == normalized(endpoint.absoluteString)
    }
    public static func authorizedKey(for endpoint: URL) throws -> String {
        guard try isApproved(endpoint), let key = try KeychainStorage().key() else {
            throw VoiceError.message("Bitte diese Cloud-Adresse in den Einstellungen erneut bestätigen. Der Text bleibt lokal.")
        }
        return key
    }
}
