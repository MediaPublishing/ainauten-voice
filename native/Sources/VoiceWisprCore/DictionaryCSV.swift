import Foundation

public struct DictionaryCSVPreview: Sendable {
    public let entries: [DictionaryEntry]
    public let skipped: Int
    public func merged(with existing: [DictionaryEntry]) -> (entries: [DictionaryEntry], added: Int) {
        var result = existing
        // A manual entry with the same source phrase wins over a CSV replacement.
        var phrases = Set(existing.map { $0.phrase.precomposedStringWithCanonicalMapping.lowercased() })
        for entry in entries where phrases.insert(entry.phrase.precomposedStringWithCanonicalMapping.lowercased()).inserted { result.append(entry) }
        return (result, result.count - existing.count)
    }
}

public enum DictionaryCSV {
    public static func preview(data: Data) throws -> DictionaryCSVPreview {
        guard data.count <= 10 * 1024 * 1024, var text = String(data: data, encoding: .utf8) else { throw VoiceError.message("CSV muss UTF-8 sein und darf höchstens 10 MB groß sein.") }
        if text.first == "\u{feff}" { text.removeFirst() }
        let firstLine = String(text.prefix { $0 != "\n" && $0 != "\r" })
        let delimiter: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","
        let rows = try parse(text, delimiter: delimiter)
        guard let header = rows.first else { throw VoiceError.message("CSV enthält keine Kopfzeile.") }
        let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let phraseIndex = names.firstIndex(where: { ["word", "phrase", "wort", "ausdruck", "original", "source"].contains($0) }) else { throw VoiceError.message("CSV benötigt eine Kopfzeile „word“ oder „phrase“ (auch „Wort“ möglich).") }
        let replacementIndex = names.firstIndex { ["replacement", "replace_with", "replacewith", "ersetzung", "ersetzen durch", "target"].contains($0) }
        var entries: [DictionaryEntry] = [], skipped = 0, seen = Set<String>()
        for row in rows.dropFirst() {
            guard row.count == header.count else { throw VoiceError.message("CSV enthält eine Zeile mit abweichender Spaltenzahl. Es wurde nichts importiert.") }
            let phrase = row[phraseIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = replacementIndex.map { row[$0].trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            guard !phrase.isEmpty, phrase.count <= 255 else { skipped += 1; continue }
            guard (replacement?.utf8.count ?? 0) <= DictionaryEntry.maximumReplacementBytes else { throw VoiceError.message("Eine CSV-Ersetzung ist zu groß.") }
            guard seen.insert(phrase.precomposedStringWithCanonicalMapping.lowercased()).inserted else { skipped += 1; continue }
            entries.append(.init(phrase: phrase, replacement: replacement, manuallyModified: true))
        }
        return .init(entries: entries, skipped: skipped)
    }
    private static func parse(_ text: String, delimiter: Character) throws -> [[String]] {
        let chars = Array(text); var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, closed = false, i = 0
        func commitRow() throws {
            row.append(field); field = ""; closed = false
            if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { rows.append(row) }
            row = []
            guard rows.count <= 100_001 else { throw VoiceError.message("CSV darf höchstens 100.000 Einträge enthalten.") }
        }
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == delimiter { row.append(field); field = ""; closed = false }
            else if c == "\n" || c == "\r" || c == "\r\n" { try commitRow(); if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 } }
            else if c == "\"", field.isEmpty, !closed { quoted = true }
            else { guard !closed, c != "\"" else { throw VoiceError.message("CSV enthält ungültige Anführungszeichen.") }; field.append(c) }
            i += 1
        }
        guard !quoted else { throw VoiceError.message("CSV enthält ein nicht geschlossenes Textfeld.") }
        if !field.isEmpty || !row.isEmpty || closed { try commitRow() }
        return rows
    }
}
