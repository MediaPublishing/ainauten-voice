import Foundation

/// Completed, validated formatting is reusable only at monotonic identical words.
/// The final ASR text remains authoritative; no old recognized word is inserted.
enum FormattingRevision {
    struct Cache: Sendable { let input: String; let output: String; let formatted: Bool }
    enum Piece: Sendable { case reuse(String); case revise(String) }
    struct Plan: Sendable {
        let pieces: [Piece]
        let reusedWords: Int
        let revisedWords: Int
        // A revision ends before a retained word, rather than at dictation end.
        // Only an unchanged consecutive cache pair can authorize this separator.
        var trailingSeparators: [Int: String] = [:]
    }
    /// Only used while recording, when an initial verified prefix has no useful cache.
    /// Finish never falls back to reformatting the entire final dictation.
    static func coldPlan(target: String, maximumWords: Int = 40) -> Plan {
        precondition(maximumWords >= 4)
        let tokens = words(target), source = target as NSString
        guard tokens.count <= 8192 else { return Plan(pieces: [], reusedWords: 0, revisedWords: tokens.count) }
        let pieces: [Piece] = stride(from: 0, to: tokens.count, by: maximumWords).map { start in
            let last = min(tokens.count, start + maximumWords) - 1
            let range = NSRange(location: tokens[start].range.location, length: NSMaxRange(tokens[last].range) - tokens[start].range.location)
            return .revise((tokens[start].leading.contains("\n") ? "\n\n" : " ") + source.substring(with: range))
        }
        return Plan(pieces: pieces, reusedWords: 0, revisedWords: tokens.count)
    }
    static func render(plan: Plan, target: String, formatter: TextFormatting, style: TextStyle, dictionary: DictionaryMatcher) async throws -> (String, Bool) {
        var output = "", failed = false
        for (index, piece) in plan.pieces.enumerated() {
            try Task.checkCancellation()
            switch piece {
            case .reuse(let text): output += text
            case .revise(let text):
                do {
                    let window = FormattingWindow.continuation(previous: .init(input: output, output: output, formatted: true), next: text, preservePrefix: true)
                    let input = window?.input ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
                    var formatted = try await formatter.format(input, style: style, context: LocalFormatter.lastTwoSentences(window?.prefixOutput ?? output), vocabulary: dictionary.topVocabulary(in: input))
                    _ = try LocalFormatter.validate(formatted, original: input, vocabulary: dictionary.topVocabulary(in: input))
                    if let separator = plan.trailingSeparators[index], index + 1 < plan.pieces.count,
                       let boundary = simpleWordBoundary(formatted.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).last.map(String.init) ?? "") {
                        formatted = String(formatted.trimmingCharacters(in: .whitespacesAndNewlines).dropLast(boundary.separator.count)) + separator
                        _ = try LocalFormatter.validate(formatted, original: input, vocabulary: dictionary.topVocabulary(in: input))
                    }
                    // A revision may stop immediately before a retained relative
                    // clause. Its source comma is outside the sampler's word gaps;
                    // do not replace it with an invented full stop at this cut.
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(","), index + 1 < plan.pieces.count {
                        let following: String
                        switch plan.pieces[index + 1] { case .reuse(let s), .revise(let s): following = s }
                        let relatives: Set<String> = ["was", "welcher", "welche", "welches", "welchen", "welchem", "indem", "dass"]
                        if let first = try? FormattingGrammar.atoms(following, maximumAtoms: 8192).first,
                           relatives.contains(first.lowercased()) {
                            formatted = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let last = formatted.last, ".!?".contains(last) { formatted.removeLast() }
                            if !formatted.hasSuffix(",") { formatted += "," }
                            _ = try LocalFormatter.validate(formatted, original: input, vocabulary: dictionary.topVocabulary(in: input))
                        }
                    }
                    if let window { output = ParagraphLayout.joinSections([window.prefixOutput, formatted]) }
                    else { output += (text.hasPrefix("\n") ? "\n\n" : " ") + formatted }
                } catch is CancellationError { throw CancellationError() }
                catch { output += text; failed = true }
            }
        }
        try Task.checkCancellation()
        do { return (try LocalFormatter.validate(output, original: target, vocabulary: dictionary.topVocabulary(in: target)), failed) }
        catch { return (target, true) }
    }
    private struct Word {
        let text: String
        let key: String
        let leading: String
        let range: NSRange
    }
    /// Literal punctuation inside URLs, decimals, abbreviations and quoted words
    /// is not a sentence separator and cannot authorize boundary replacement.
    private static func simpleWordBoundary(_ token: String) -> (word: String, separator: String)? {
        let separator = String(token.reversed().prefix { ".,!?;:".contains($0) }.reversed())
        let word = String(token.dropLast(separator.count))
        guard word.first?.isLetter == true, word.last?.isLetter == true,
              word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) else { return nil }
        return (word, separator)
    }
    private static func words(_ text: String, preserveListMarkers: Bool = false) -> [Word] {
        let source = text as NSString
        let regex = try! NSRegularExpression(pattern: #"\S+"#)
        let edges = CharacterSet(charactersIn: ".,!?;:()[]{}\"„“”")
        var end = 0
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let token = source.substring(with: match.range)
            let stripped = token.trimmingCharacters(in: edges)
            if preserveListMarkers, token == "-" {
                let prefix = source.substring(to: match.range.location)
                let line = prefix.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
                if line.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            }
            // Only sentence punctuation is ignorable. Mentions, emoji, currency
            // and signs must match explicitly rather than hitchhike in a prefix.
            guard !stripped.isEmpty else { return nil }
            let literal = stripped.contains(where: \.isNumber) || stripped.contains(where: { !$0.isLetter && $0 != "'" && $0 != "’" })
            let key = literal ? stripped.lowercased().precomposedStringWithCanonicalMapping
                : ProcessingPipeline.lexicalSequence(stripped).joined(separator: "\u{1f}")
            let leading = source.substring(with: NSRange(location: end, length: match.range.location - end))
            end = NSMaxRange(match.range)
            return Word(text: token, key: key.isEmpty ? stripped : key, leading: leading, range: match.range)
        }
    }
    static func plan(target: String, cache: [Cache], maximumWords: Int = 40) -> Plan? {
        precondition(maximumWords >= 4)
        let final = words(target)
        guard !final.isEmpty, final.count <= 8192 else { return nil }
        var old: [Word] = []
        for entry in cache where entry.formatted {
            // A cache from a different/unreliable formatter can never authorize reuse.
            guard (try? LocalFormatter.validate(entry.output, original: entry.input, vocabulary: [])) != nil else { continue }
            // Only formatter-added bullets are presentation. A spoken standalone
            // minus remains a literal and must never return from stale recognition.
            let permitsBullets = !entry.input.split(whereSeparator: \.isWhitespace).contains("-")
            old += words(entry.output, preserveListMarkers: permitsBullets)
        }
        guard !old.isEmpty, old.count <= 8192 else { return nil }
        let n = old.count, m = final.count
        guard n * m <= 64_000_000 else { return nil }
        // Two score rows and one byte per decision keep the 20-minute bound modest.
        var previous = [UInt16](repeating: 0, count: m + 1)
        var decisions = [UInt8](repeating: 0, count: (n + 1) * (m + 1))
        for row in 1...n {
            var current = [UInt16](repeating: 0, count: m + 1)
            for column in 1...m {
                let index = row * (m + 1) + column
                if old[row - 1].key == final[column - 1].key {
                    current[column] = previous[column - 1] + 1; decisions[index] = 3
                } else if previous[column] >= current[column - 1] {
                    current[column] = previous[column]; decisions[index] = 1
                } else {
                    current[column] = current[column - 1]; decisions[index] = 2
                }
            }
            previous = current
        }
        var matches: [Int: Int] = [:], row = n, column = m
        while row > 0 && column > 0 {
            switch decisions[row * (m + 1) + column] {
            case 3: matches[column - 1] = row - 1; row -= 1; column -= 1
            case 2: column -= 1
            default: row -= 1
            }
        }
        // If recognition changed almost entirely, do not disguise a full second AI pass.
        guard matches.count * 5 >= final.count else { return nil }
        let offsets = FormattingWindow.languageBoundaryOffsets(in: target)
        let boundaries = Set(final.indices.filter { offsets.contains(final[$0].range.location) })
        var revised = Set<Int>()
        for index in final.indices where matches[index] == nil {
            for adjacent in max(0, index - 2)...min(m - 1, index + 2) {
                if !boundaries.contains(where: { $0 > min(index, adjacent) && $0 <= max(index, adjacent) }) { revised.insert(adjacent) }
            }
        }
        guard revised.count < m else { return nil }
        var pieces: [Piece] = [], separators: [Int: String] = [:], cursor = 0
        let source = target as NSString
        while cursor < m {
            let start = cursor
            let needsRevision = revised.contains(cursor)
            if needsRevision {
                while cursor < m, revised.contains(cursor), cursor - start < maximumWords { cursor += 1 }
                let range = NSRange(location: final[start].range.location, length: NSMaxRange(final[cursor - 1].range) - final[start].range.location)
                let prefix = final[start].leading.contains("\n") ? "\n\n" : " "
                if cursor < m, !revised.contains(cursor),
                   let last = matches[cursor - 1], let next = matches[cursor], next == last + 1,
                   !old[next].leading.contains("\n"), !final[cursor].leading.contains("\n"),
                   simpleWordBoundary(final[cursor - 1].text) != nil,
                   simpleWordBoundary(final[cursor].text) != nil,
                   simpleWordBoundary(old[next].text) != nil,
                   let boundary = simpleWordBoundary(old[last].text) {
                    separators[pieces.count] = boundary.separator
                }
                pieces.append(.revise(prefix + source.substring(with: range)))
            } else {
                var text = ""
                while cursor < m, !revised.contains(cursor), let index = matches[cursor] {
                    let word = old[index]
                    text += (word.leading.isEmpty ? " " : word.leading) + word.text
                    cursor += 1
                }
                guard cursor > start else { return nil }
                pieces.append(.reuse(text))
            }
        }
        return Plan(pieces: pieces, reusedWords: m - revised.count, revisedWords: revised.count, trailingSeparators: separators)
    }
}
