import Foundation
import NaturalLanguage

/// Re-open the end of the preceding section when new speech supplies the missing
/// clause. Only a bounded suffix is generated again; earlier text stays intact.
enum FormattingWindow {
    struct Window {
        let prefixInput: String
        let prefixOutput: String
        let input: String
    }
    /// A complete sentence followed by confidently different-language speech is
    /// not a breathing-pause fragment. Ambiguous or short text keeps the old path.
    static func hasLanguageBoundary(previous: String, next: String) -> Bool {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = previous
        var last = previous
        tokenizer.enumerateTokens(in: previous.startIndex..<previous.endIndex) { range, _ in
            last = String(previous[range]); return true
        }
        tokenizer.string = next
        var first = next
        tokenizer.enumerateTokens(in: next.startIndex..<next.endIndex) { range, _ in
            first = String(next[range]); return false
        }
        let end = last.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”’»)]}"))
        guard let punctuation = end.last, ".!?".contains(punctuation),
              first.first(where: \.isLetter)?.isUppercase == true,
              let before = confidentLanguage(last), let after = confidentLanguage(first), before != after else { return false }
        return true
    }
    private static func confidentLanguage(_ text: String) -> NLLanguage? {
        guard text.split(whereSeparator: \.isWhitespace).filter({ $0.contains(where: \.isLetter) }).count >= 8 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        guard let best = hypotheses.max(by: { $0.value < $1.value }), best.value >= 0.9,
              best.key != .undetermined else { return nil }
        return best.key
    }
    /// UTF-16 offsets match the final revision planner's token ranges.
    static func languageBoundaryOffsets(in text: String) -> Set<Int> {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var previous: String?, offsets = Set<Int>()
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
            if let previous, hasLanguageBoundary(previous: previous, next: sentence) {
                offsets.insert(NSRange(range, in: text).location)
            }
            previous = sentence
            return true
        }
        return offsets
    }
    static func continuation(previous: FormattingRevision.Cache, next: String, maximumWords: Int = 80, preservePrefix: Bool = false) -> Window? {
        guard previous.formatted,
              previous.output.rangeOfCharacter(from: CharacterSet(charactersIn: "[]{}<>`")) == nil,
              (try? LocalFormatter.validate(previous.output, original: previous.input, vocabulary: [])) != nil else { return nil }
        let input = FormattingGrammar.normalizeSpacing(previous.input)
        let output = FormattingGrammar.normalizeSpacing(previous.output)
        let next = FormattingGrammar.normalizeSpacing(next).trimmingCharacters(in: .whitespacesAndNewlines)
        if hasLanguageBoundary(previous: input, next: next),
           output.trimmingCharacters(in: .whitespacesAndNewlines).last.map({ ".!?".contains($0) }) == true { return nil }
        guard let old = try? FormattingGrammar.atoms(input, maximumAtoms: 8192), let new = try? FormattingGrammar.atoms(next),
              !new.isEmpty, new.count < maximumWords else { return nil }
        let available = maximumWords - new.count
        // A cut must be a sentence boundary, never the middle of a URL, number or
        // clause. If the preceding sentence is too large, keep the existing pass.
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = output
        var starts: [String.Index] = []
        tokenizer.enumerateTokens(in: output.startIndex..<output.endIndex) { range, _ in starts.append(range.lowerBound); return true }
        if old.count <= available, !preservePrefix, starts.count <= 2 {
            return Window(prefixInput: "", prefixOutput: "", input: input.trimmingCharacters(in: .whitespacesAndNewlines) + " " + next)
        }
        for start in starts.suffix(2) {
            if preservePrefix, start == output.startIndex { continue }
            let suffix = String(output[start...])
            guard let suffixAtoms = try? FormattingGrammar.atoms(suffix), suffixAtoms.count <= available,
                  let prefixAtoms = try? FormattingGrammar.atoms(String(output[..<start]), maximumAtoms: 8192) else { continue }
            let filler: Set<String> = ["äh", "ähm", "uh", "erm", "hmm"]
            // Formatter-added bullets are presentation; a spoken standalone minus
            // remains a source atom and is counted on both sides.
            let generatedBullets = !input.split(whereSeparator: \.isWhitespace).contains("-")
            let prefixCount = prefixAtoms.filter { !generatedBullets || $0 != "-" }.count
            guard let outputAtoms = try? FormattingGrammar.atoms(output, maximumAtoms: 8192) else { continue }
            let alignedOutput = outputAtoms.filter { !generatedBullets || $0 != "-" }
            let regex = try! NSRegularExpression(pattern: #"\S+"#)
            let source = input as NSString
            var words = 0
            for match in regex.matches(in: input, range: NSRange(location: 0, length: source.length)) {
                let token = source.substring(with: match.range)
                guard let atoms = try? FormattingGrammar.atoms(token), atoms.count == 1 else { continue }
                let word = atoms[0].lowercased().precomposedStringWithCanonicalMapping
                guard words < alignedOutput.count else { break }
                if word != alignedOutput[words].lowercased().precomposedStringWithCanonicalMapping {
                    if filler.contains(word) { continue }
                    return nil
                }
                if words == prefixCount {
                    return Window(prefixInput: source.substring(to: match.range.location),
                                  prefixOutput: String(output[..<start]),
                                  input: source.substring(from: match.range.location).trimmingCharacters(in: .whitespacesAndNewlines) + " " + next)
                }
                words += 1
            }
        }
        return nil
    }
}
