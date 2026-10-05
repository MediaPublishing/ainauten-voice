import Foundation

public struct DictionaryMatcher: Sendable {
    private static let links = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let files = try? NSRegularExpression(pattern: #"[^\s<>\"()]+\.(?:swift|md|json|txt|csv|pdf|html|js|ts|py|app|sqlite|plist|toml)\b"#, options: .caseInsensitive)
    public let entries: [DictionaryEntry]
    fileprivate let patterns: [(entry: DictionaryEntry, expression: NSRegularExpression, forcesSpelling: Bool)]
    public init(_ entries: [DictionaryEntry]) {
        self.entries = entries.filter { !$0.phrase.isEmpty }.sorted { $0.phrase.count == $1.phrase.count ? $0.id < $1.id : $0.phrase.count > $1.phrase.count }
        self.patterns = self.entries.compactMap { entry in
            let pattern = "(?<![\\p{L}\\p{N}\\p{M}_])" + NSRegularExpression.escapedPattern(for: entry.phrase) + "(?![\\p{L}\\p{N}\\p{M}_])"
            // Vocabulary-only acronyms must not turn ordinary words (mit, it,
            // us) into uppercase abbreviations. An explicit replacement can
            // still request that spelling regardless of the recognized case.
            let acronym = entry.replacement == nil
                && entry.phrase == entry.phrase.uppercased()
                && entry.phrase != entry.phrase.lowercased()
            let options: NSRegularExpression.Options = acronym ? [] : .caseInsensitive
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
            // Ordinary/title-cased vocabulary is a word hint, not a casing
            // replacement: Klein can be a surname or the adjective klein.
            let distinctiveCase = entry.phrase.split(whereSeparator: { !$0.isLetter }).contains { word in
                word.contains(where: \.isLowercase) && word.dropFirst().contains(where: \.isUppercase)
            }
            return (entry, expression, entry.replacement != nil || distinctiveCase)
        }
    }
    public func replace(in text: String) -> String {
        guard !patterns.isEmpty else { return text }
        let source = text as NSString
        let protected = Self.protectedRanges(in: text)
        var matches: [(NSRange, String)] = []
        // Word hints are transparent to replacement rules, including overlaps.
        // A longer plain phrase must not suppress an explicit shorter change.
        for (entry, expression, forcesSpelling) in patterns where forcesSpelling {
            for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                guard Self.allows(match.range, entry: entry, protected: protected) else { continue }
                if !matches.contains(where: { NSIntersectionRange($0.0, match.range).length > 0 }) {
                    matches.append((match.range, entry.replacement ?? entry.phrase))
                }
            }
        }
        let output = NSMutableString(string: text)
        for (range, replacement) in matches.sorted(by: { $0.0.location > $1.0.location }) { output.replaceCharacters(in: range, with: replacement) }
        return output as String
    }
    public func topVocabulary(in text: String, limit: Int = 32) -> [String] {
        guard limit > 0, !patterns.isEmpty else { return [] }
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        let protected = Self.protectedRanges(in: text)
        return Array(patterns.lazy.compactMap { entry, expression, forcesSpelling -> String? in
            guard let match = expression.matches(in: text, range: range).first(where: {
                Self.allows($0.range, entry: entry, protected: protected)
            }) else { return nil }
            return forcesSpelling ? entry.phrase : source.substring(with: match.range)
        }.prefix(max(0, limit)))
    }
    private static func protectedRanges(in text: String) -> [NSRange] {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return (links?.matches(in: text, range: range).map(\.range) ?? [])
            + (files?.matches(in: text, range: range).map(\.range) ?? [])
    }
    private static func allows(_ match: NSRange, entry: DictionaryEntry, protected: [NSRange]) -> Bool {
        // A user can deliberately replace an entire address/file. A word rule
        // or spelling hint must never change only part of a protected literal.
        protected.allSatisfy { literal in
            NSIntersectionRange(match, literal).length == 0
                || (entry.replacement != nil && match.location <= literal.location && NSMaxRange(match) >= NSMaxRange(literal))
        }
    }
}

public struct StreamingDictionaryMatcher: Sendable {
    private let matcher: DictionaryMatcher
    private var pending = ""
    private let retention: Int
    public init(_ entries: [DictionaryEntry]) {
        matcher = DictionaryMatcher(entries)
        retention = max(1, entries.map { ($0.phrase as NSString).length }.max() ?? 1) + 1
    }
    public mutating func process(_ segment: String, final: Bool = false) -> String {
        pending += segment
        if final { defer { pending = "" }; return matcher.replace(in: pending) }
        guard !matcher.entries.isEmpty else { defer { pending = "" }; return pending }
        let ns = pending as NSString
        var cut = ns.length
        // Keep literal context when a URL/mail/path is split between ASR
        // portions. Otherwise an isolated suffix can look like a normal word.
        let start = pending.lastIndex(where: \.isWhitespace).map({ pending.index(after: $0) }) ?? pending.startIndex
        if start < pending.endIndex {
            let tail = String(pending[start...])
            let internalDot = tail.dropLast().contains(".")
            let marker = tail.contains("@") || tail.contains("/") || tail.contains("\\") || tail.contains(":") || internalDot
            let potentialDomain = tail.hasSuffix(".") && matcher.entries.contains {
                ($0.replacement != nil || $0.phrase.dropFirst().contains(where: \.isUppercase))
                    && $0.phrase.caseInsensitiveCompare(String(tail.dropLast())) == .orderedSame
            }
            if marker || potentialDomain { cut = start.utf16Offset(in: pending) }
        }
        // Hold only a suffix that can actually be the beginning of a source phrase.
        // Unrelated sentence endings must not become a separate LLM job.
        for index in pending.indices {
            let offset = index.utf16Offset(in: pending)
            guard ns.length - offset <= retention else { continue }
            if index != pending.startIndex {
                let previous = pending[pending.index(before: index)]
                guard !previous.isLetter && !previous.isNumber && previous != "_" else { continue }
            }
            let suffix = String(pending[index...])
            if matcher.entries.contains(where: { $0.phrase.range(of: suffix, options: [.anchored, .caseInsensitive]) != nil }) {
                cut = min(cut, offset)
            }
        }
        guard cut > 0 else { return "" }
        let ready = ns.substring(to: cut)
        pending = ns.substring(from: cut)
        return matcher.replace(in: ready)
    }
}
