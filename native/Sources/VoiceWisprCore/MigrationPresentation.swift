import Foundation

extension MigrationResult {
    /// UI receipt only. The canonical export, source and import transaction are unchanged.
    public func interfaceSummary(savedCount: Int) -> LocalizedMessage {
        guard !preview.isPartial else {
            return .joined([.key("migration.summary.notPerformed", [])] + preview.errors.map(L10n.message), " ")
        }
        var messages: [LocalizedMessage] = [.key("migration.summary.complete", [savedCount.formatted(), imported.formatted(), updated.formatted()])]
        if preview.sourceDuplicates > 0 { messages.append(.key("migration.summary.duplicates", [preview.sourceDuplicates.formatted()])) }
        for (code, key) in [("invalidDictionaryEntries", "invalid"), ("overlongPhrases", "overlong"), ("oversizedReplacements", "oversized")] {
            let count = preview.unsupportedCounts[code] ?? 0
            if count > 0 { messages.append(.key("migration.summary.\(key).\(count == 1 ? "one" : "other")", [count.formatted()])) }
        }
        if preserved > 0 { messages.append(.key("migration.summary.preserved", [preserved.formatted()])) }
        return .joined(messages, " ")
    }
}

extension WisprSwitchOutcome {
    public var interfaceReason: LocalizedMessage {
        let suffix = " Settings → System → Launch app at login prüfen; anschließend Wispr Flow regulär beenden."
        if reason.hasSuffix(suffix) {
            return .joined([L10n.message(String(reason.dropLast(suffix.count))), .key("switch.reason.pendingHelp", [])], " ")
        }
        return L10n.message(reason)
    }
}
