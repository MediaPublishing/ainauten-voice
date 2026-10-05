import Foundation
import NaturalLanguage

/// Final presentation only: no generated words and no additional model pass.
enum ParagraphLayout {
    static func joinSections(_ sections: [String]) -> String {
        var result = "", breakAfterPrevious = false
        for section in sections {
            let text = section.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if !result.isEmpty { result += breakAfterPrevious || section.hasPrefix("\n") ? "\n\n" : " " }
            result += text
            breakAfterPrevious = section.hasSuffix("\n")
        }
        return result
    }
    static func apply(_ text: String, style: TextStyle) -> String {
        if style != .original, text.contains("\n\n") {
            return text.components(separatedBy: "\n\n").map { apply($0, style: style) }.joined(separator: "\n\n")
        }
        guard style != .original, !text.contains("\n"), text.split(whereSeparator: \.isWhitespace).count >= 70 else { return text }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in ranges.append(range); return true }
        guard ranges.count >= 4 else { return text }
        let threshold = style == .chat ? 35 : 55
        var result = "", words = 0, sentences = 0
        for (index, range) in ranges.enumerated() {
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !result.isEmpty { result += " " }
            result += sentence
            words += sentence.split(whereSeparator: \.isWhitespace).count; sentences += 1
            if sentences >= 3, words >= threshold, index < ranges.count - 2 {
                result += "\n\n"; words = 0; sentences = 0
            }
        }
        // Never accept a tokenizer omission as presentation. Only whitespace may
        // change; punctuation, names, symbols, emoji and numbers are byte-preserved.
        guard result.filter({ !$0.isWhitespace }) == text.filter({ !$0.isWhitespace }) else { return text }
        return result.replacingOccurrences(of: "\n\n ", with: "\n\n")
    }
}
