import Foundation

/// A finite, ordered vocabulary for this one dictation section. The sampler can
/// choose casing and punctuation, but cannot invent, reorder or translate words.
/// Internal punctuation in URLs, numbers, compounds and code names stays literal.
enum FormattingGrammar {
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    /// Separate sentence punctuation glued to the next word. Do not interpret
    /// punctuation inside an address, version, path or code identifier as prose.
    static func normalizeSpacing(_ text: String) -> String {
        let extensions: Set<String> = ["swift", "md", "json", "txt", "csv", "pdf", "html", "js", "ts", "py", "app", "sqlite"]
        let separators = try! NSRegularExpression(pattern: #"(?<=[\p{L}\p{M}])(?:([.!?,;:]+)(?=[\p{Lu}])|([!?,;:]+)(?=[\p{L}\p{M}]))"#)
        var result = text
        // Replace ranges from the end so existing whitespace and paragraphs survive.
        let tokens = try! NSRegularExpression(pattern: #"\S+"#)
        let source = text as NSString
        for match in tokens.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let token = source.substring(with: match.range)
            let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:()[]{}\"„“”"))
            let ext = bare.split(separator: ".").last.map(String.init)?.lowercased() ?? ""
            let asciiDomain = bare.range(of: #"^[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,6}$"#, options: .regularExpression) != nil
            let lowered = bare.lowercased() as NSString
            let detectedDomain = bare.contains(".") && linkDetector?.matches(in: lowered as String, range: NSRange(location: 0, length: lowered.length)).contains { $0.range == NSRange(location: 0, length: lowered.length) } == true
            guard !bare.contains("://"), !bare.lowercased().hasPrefix("www."), !bare.contains("@"),
                  !bare.contains(where: \.isNumber), !bare.contains("/"), !bare.contains("\\"),
                  !bare.contains("="), !bare.contains("_"), !bare.contains("\""),
                  !extensions.contains(ext), !asciiDomain, !detectedDomain else { continue }
            let fixed = separators.stringByReplacingMatches(in: token, range: NSRange(location: 0, length: (token as NSString).length), withTemplate: "$1$2 ")
            if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: fixed) }
        }
        return result
    }
    static func atoms(_ text: String, maximumAtoms: Int = 256) throws -> [String] {
        let edges = CharacterSet(charactersIn: ".,!?;:()[]{}\"„“”")
        let atoms = normalizeSpacing(text).split(whereSeparator: \.isWhitespace).map {
            let token = String($0)
            // Brackets and the closing parenthesis belong to an inline link.
            // Removing them makes its protected URL differ and forces fallback.
            let link = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
            if link.contains("://"), link.range(of: #"^\[[^\]\r\n]+\]\(\S+\)$"#, options: .regularExpression) != nil {
                return link
            }
            return token.trimmingCharacters(in: edges)
        }.filter { !$0.isEmpty }
        guard !atoms.isEmpty, atoms.count <= maximumAtoms,
              atoms.allSatisfy({ !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else {
            throw VoiceError.message("Der Abschnitt lässt sich nicht sicher auf seinen Wortlaut begrenzen")
        }
        return atoms
    }

    static func make(_ text: String, vocabulary: [String] = []) throws -> String {
        let original = try atoms(text)
        let tokens = normalizeSpacing(text).split(whereSeparator: \.isWhitespace).map(String.init)
        let edges = CharacterSet(charactersIn: ".,!?;:()[]{}\"„“”")
        let relatives: Set<String> = ["was", "welcher", "welche", "welches", "welchen", "welchem", "indem", "dass"]
        var commas = [Bool](), previous = ""
        for token in tokens {
            let word = token.trimmingCharacters(in: edges)
            if !word.isEmpty { commas.append(previous.hasSuffix(",") && relatives.contains(word.lowercased())) }
            previous = token
        }
        let fillers: Set<String> = ["äh", "ähm", "uh", "erm", "hmm"]
        let filtered = original.filter { word in
            !fillers.contains(word.lowercased()) || vocabulary.contains { $0.range(of: word, options: .caseInsensitive) != nil }
        }
        // Only explicit filler sounds may disappear. Keep an all-filler utterance
        // recoverable and preserve dictionary names that happen to sound like one.
        let words = filtered.count >= max(1, original.count * 7 / 10) ? filtered : original
        let keptIndices = original.indices.filter { wordIndex in
            words.count == original.count || !fillers.contains(original[wordIndex].lowercased()) || vocabulary.contains { $0.range(of: original[wordIndex], options: .caseInsensitive) != nil }
        }
        var root = "root ::= prefix w0"
        for index in words.indices.dropFirst() { root += (commas[keptIndices[index]] ? " comma " : " gap ") + "w\(index)" }
        var rules = [root + " suffix"]
        // Deliberately bounded separators: no unbounded punctuation loop can
        // consume the token budget instead of completing the spoken section.
        let gaps = [" ", ", ", "; ", ": ", ". ", "! ", "? ", "\n", "\n\n", ".\n\n", "!\n\n", "?\n\n", "\n- ", "\n\n- "]
        rules += ["prefix ::= \"\" | \"- \"", "comma ::= \", \"", "gap ::= " + gaps.map(literal).joined(separator: " | "), "suffix ::= \"\" | \".\" | \"!\" | \"?\""]
        for (index, word) in words.enumerated() {
            let isLiteral = word.contains("://") || word.lowercased().hasPrefix("www.") || word.contains("@")
                || word.contains(".")
                || word.contains(where: \.isNumber) || !word.contains(where: \.isLetter) || word.contains("\\") || word.contains("\"")
            var variants = [word]
            if !isLiteral {
                variants += [word.lowercased(), String(word.prefix(1)).uppercased() + word.dropFirst(), word.prefix(1).uppercased() + word.dropFirst().lowercased()]
            }
            var seen = Set<String>()
            let folded = word.lowercased().precomposedStringWithCanonicalMapping
            rules.append("w\(index) ::= " + variants.filter {
                $0.lowercased().precomposedStringWithCanonicalMapping == folded && seen.insert($0).inserted
            }.map(literal).joined(separator: " | "))
        }
        return rules.joined(separator: "\n")
    }

    private static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
}
