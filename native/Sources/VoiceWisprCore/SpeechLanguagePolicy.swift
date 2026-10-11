import Foundation
import NaturalLanguage

/// Language selection is a recognition constraint, independent of interface language.
public protocol SpeechLanguageConfiguring: Sendable {
    func configureLanguages(_ languages: [String], sessionID: UUID) async
}

struct SpeechLanguagePolicy: Sendable {
    let languages: [String]
    init(_ languages: [String]) {
        self.languages = Array(NSOrderedSet(array: languages.map { $0.lowercased().split(separator: "-").first.map(String.init) ?? $0 })) as? [String] ?? []
    }
    var recoveryLanguage: String? { languages.count > 1 ? "auto" : languages.first }
    func resolve(_ candidate: TranscriptSegment, recover: @Sendable (String) async throws -> TranscriptSegment) async throws -> TranscriptSegment {
        guard needsVerification(candidate.text), let language = recoveryLanguage else { return candidate }
        let recovered = try await recover(language)
        try Task.checkCancellation()
        guard recovered.sessionID == candidate.sessionID, recovered.index == candidate.index,
              !recovered.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !needsRecovery(recovered.text) else { throw SpeechLanguageError.mismatch }
        return recovered
    }
    func needsRecovery(_ text: String) -> Bool {
        guard !languages.isEmpty else { return false }
        let cyrillic = text.unicodeScalars.filter { (0x0400...0x052f).contains(Int($0.value)) }.count
        let greek = text.unicodeScalars.filter { (0x0370...0x03ff).contains(Int($0.value)) }.count
        if cyrillic >= 3 && !languages.contains(where: { ["ru", "uk", "bg"].contains($0) }) { return true }
        if greek >= 3 && !languages.contains("el") { return true }
        guard let dominant = confidentlyRecognizedLanguage(text), !languages.contains(dominant) else { return false }
        return true
    }
    func needsVerification(_ text: String) -> Bool {
        if needsRecovery(text) { return true }
        // German/English imports commonly select both. A second acoustic model
        // checks English-looking sentences even though English itself is allowed.
        // Its auto-language mode can retain genuine English without translation.
        return languages.contains("de") && languages.contains("en") && confidentlyRecognizedLanguage(text) == "en"
    }
    private func confidentlyRecognizedLanguage(_ text: String) -> String? {
        // Names, URLs, code, short confirmations and borrowed terms do not provide
        // enough evidence. Never use a single foreign-looking word as a veto.
        let clean = text.replacingOccurrences(of: "https?://\\S+|www\\.\\S+|\\S+@\\S+|`[^`]+`", with: "", options: .regularExpression)
        let tokenizer = NLTokenizer(unit: .word); tokenizer.string = clean
        var count = 0
        tokenizer.enumerateTokens(in: clean.startIndex..<clean.endIndex) { range, _ in
            if clean[range].unicodeScalars.contains(where: CharacterSet.letters.contains) { count += 1 }; return true
        }
        guard count >= 4, clean.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 16 else { return nil }
        let recognizer = NLLanguageRecognizer(); recognizer.processString(clean)
        // No languageHints: hints must not disguise an obviously wrong output.
        guard let dominant = recognizer.dominantLanguage,
              (recognizer.languageHypotheses(withMaximum: 1)[dominant] ?? 0) >= 0.8 else { return nil }
        return dominant.rawValue
    }
}

public enum SpeechLanguageError: LocalizedError, Sendable {
    case mismatch
    public var errorDescription: String? { L10n.text("speech.languageMismatch") }
}
