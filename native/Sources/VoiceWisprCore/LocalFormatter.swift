import Foundation
import NaturalLanguage
import llama

private final class GenerationDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    let end = ProcessInfo.processInfo.systemUptime + 8
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var expired: Bool { lock.lock(); defer { lock.unlock() }; return cancelled || ProcessInfo.processInfo.systemUptime >= end }
}

/// A single embedded GGUF model and context; no process, service, or network request.
public actor LocalFormatter: TextFormatting {
    private let modelURL: URL
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var shutDown = false
    public init(modelURL: URL) { self.modelURL = modelURL }
    deinit { if let context { llama_free(context) }; if let model { llama_model_free(model) } }
    /// Explicitly release GPU residency before a process exits. ARC alone can
    /// be delayed by cancelled workers that still retain this shared actor.
    public func shutdown() {
        shutDown = true
        if let context { llama_synchronize(context); llama_free(context); self.context = nil }
        if let model { llama_model_free(model); self.model = nil }
    }
    public func prepare() async throws {
        try Task.checkCancellation()
        guard !shutDown else { throw VoiceError.message("Lokale Formatierung ist beendet") }
        guard context == nil else { return }
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw VoiceError.message("Das lokale Formatierungsmodell fehlt") }
        llama_backend_init()
        llama_log_set({ _, _, _ in }, nil)
        var parameters = llama_model_default_params()
        parameters.n_gpu_layers = 99
        guard let loaded = modelURL.path.withCString({ llama_model_load_from_file($0, parameters) }) else { throw VoiceError.message("Das Formatierungsmodell konnte nicht geladen werden") }
        var cp = llama_context_default_params()
        cp.n_ctx = 4096; cp.n_batch = 512; cp.n_ubatch = 256
        cp.n_threads = Int32(min(8, max(1, ProcessInfo.processInfo.activeProcessorCount - 2)))
        cp.n_threads_batch = cp.n_threads
        guard let ctx = llama_init_from_model(loaded, cp) else { llama_model_free(loaded); throw VoiceError.message("Der lokale Modellkontext konnte nicht erstellt werden") }
        model = loaded; context = ctx
        // Decode a tiny warm-up prompt so the first dictation does not initialize all kernels.
        do { _ = try generate(prompt: "<|im_start|>user\nHallo<|im_end|>\n<|im_start|>assistant\n", maxTokens: 1, deadline: GenerationDeadline(), requireCompletion: false) }
        catch { llama_free(ctx); llama_model_free(loaded); context = nil; model = nil; throw error }
        try Task.checkCancellation()
    }
    public func format(_ text: String, style: TextStyle, context previous: String, vocabulary: [String]) async throws -> String {
        try Task.checkCancellation()
        guard style != .original, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        let text = FormattingGrammar.normalizeSpacing(text)
        guard Self.needsModel(text, style: style) else { return text }
        guard model != nil, context != nil else { throw VoiceError.message("Lokale Formatierung ist nicht vorbereitet") }
        let instruction = "Du bearbeitest ausschließlich den aktuellen Diktatabschnitt. Ändere ausschließlich Großschreibung, Satzzeichen und Absatzumbrüche. Entferne nur eindeutige Fülllaute wie äh oder ähm. Alle anderen Wörter müssen exakt in derselben Reihenfolge bleiben: keine Korrektur, Übersetzung, Zusammenfassung, ausgeschriebenen Zahlen oder neuen Wörter. Bewahre Wortlaut, Sprache, Namen, Zahlen, Negationen, URLs und Bedeutung. Ergänze keine Fakten, Anrede, Grußformel oder Betreff. Kontext ist nur zum Verständnis: gib niemals Kontext erneut aus. Stil \(style.rawValue): \(style == .email ? "Absätze für eine E-Mail" : style == .chat ? "kurze Chat-Absätze" : "lesbare Sätze"). Antworte nur mit dem bearbeiteten Abschnitt. /no_think"
        // ASR full stops often mark breathing pauses. Present the same ordered
        // words without those unreliable anchors, retaining paragraph cues and
        // internal punctuation of numbers, URLs and code identifiers.
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = text
        var sentenceCount = 0
        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in sentenceCount += 1; return sentenceCount < 2 }
        let reconstruct = sentenceCount > 1
        let current = text.components(separatedBy: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? "" : line.split(whereSeparator: \.isWhitespace).flatMap { token -> [String] in
                let atoms = (try? FormattingGrammar.atoms(String(token))) ?? []
                guard let last = atoms.last, let punctuation = token.last, ",?!".contains(punctuation) else { return atoms }
                return Array(atoms.dropLast()) + [last + String(punctuation)]
            }.joined(separator: " ")
        }.joined(separator: "\n")
        let user = reconstruct ? "Wortschatzhinweise (keine zwingenden Großschreibungsregeln): \(vocabulary.prefix(32).joined(separator: ", "))\nBeachte die deutsche Groß-/Kleinschreibung: Satzanfänge, Nomen und tatsächliche Eigennamen groß; gewöhnliche Bindewörter, Pronomen, Adjektive und Adverbien im Satz klein. Schreibe die persönliche Anrede du, dir, dich und dein im Satz immer klein; keine Brief-Großschreibung von Du. Erhalte die Höflichkeitsanrede Sie. Entscheide nach dem Satzkontext, nicht allein nach der Schreibweise eines Hinweises. Satzzeichen der Erkennung können bloße Sprechpausen sein: verbinde grammatisch zusammengehörige Satzfragmente, entferne dafür falsche Punkte und setze passende Kommas. Erhalte echte vollständige Sätze und Fragen. Ein Nebensatz mit indem, was, weil oder wenn gehört zum Hauptsatz; keine alleinstehenden Satzfragmente. Trenne aufgezählte Tätigkeiten oder Begriffe mit Kommas, beispielsweise Design, Veröffentlichung und Test; klebe getrennte Begriffe nicht zu einem neuen Namen zusammen. Setze bei einem Themenwechsel einen Absatz, in längeren Erklärungen etwa nach drei bis vier vollständigen Sätzen. Ein Abschnittsende ist nicht automatisch ein Satzende.\nVorherige zwei Sätze (nur Kontext): \(Self.lastTwoSentences(previous))\nAktueller Abschnitt (Sprechpausen wurden entfernt; Satzzeichen neu setzen):\n\(current)" : "Wortschatzhinweise (keine zwingenden Großschreibungsregeln): \(vocabulary.prefix(32).joined(separator: ", "))\nBeachte die deutsche Groß-/Kleinschreibung: Satzanfänge, Nomen und tatsächliche Eigennamen groß; gewöhnliche Bindewörter, Pronomen, Adjektive und Adverbien im Satz klein. Schreibe die persönliche Anrede du, dir, dich und dein im Satz immer klein; keine Brief-Großschreibung von Du. Erhalte die Höflichkeitsanrede Sie. Entscheide nach dem Satzkontext, nicht allein nach der Schreibweise eines Hinweises. Satzzeichen der Erkennung können bloße Sprechpausen sein: verbinde grammatisch zusammengehörige Satzfragmente, entferne dafür falsche Punkte und setze passende Kommas. Erhalte echte vollständige Sätze und Fragen.\nVorherige zwei Sätze (nur Kontext): \(Self.lastTwoSentences(previous))\nAktueller Abschnitt:\n\(text)"
        let casingHint = "\nGrammatikbeispiele, keine zusätzlichen Ausgabewörter: einen Neuen Mac → einen neuen Mac; Über Nacht auf Am Laufen → über Nacht auf am Laufen. Adjektive vor einem Nomen und Präpositionen im Satz klein schreiben. Substantivierte Verben und Adjektive bleiben groß: am Laufen, das Schöne. Tatsächliche Eigennamen bleiben erhalten: Frau Klein, OpenAI, MIT."
        let prompt = try chatPrompt(system: instruction, user: user + casingHint)
        let grammar = try FormattingGrammar.make(text, vocabulary: vocabulary)
        let deadline = GenerationDeadline()
        let output = try await withTaskCancellationHandler { try generate(prompt: prompt, maxTokens: min(1024, max(64, text.utf8.count / 2 + 64)), deadline: deadline, grammar: grammar) } onCancel: { deadline.cancel() }
        try Task.checkCancellation()
        return ParagraphLayout.apply(try Self.validate(output, original: text, vocabulary: vocabulary, context: previous), style: style)
    }
    private func chatPrompt(system: String, user: String) throws -> String {
        guard let model else { throw VoiceError.message("Modell fehlt") }
        let template = llama_model_chat_template(model, nil)
        return try "system".withCString { role1 in try "user".withCString { role2 in try system.withCString { content1 in try user.withCString { content2 in
            let messages = [llama_chat_message(role: role1, content: content1), llama_chat_message(role: role2, content: content2)]
            var bytes = [CChar](repeating: 0, count: (system.utf8.count + user.utf8.count) * 3 + 1024)
            let count = messages.withUnsafeBufferPointer { m in bytes.withUnsafeMutableBufferPointer { b in llama_chat_apply_template(template, m.baseAddress, m.count, true, b.baseAddress, Int32(b.count)) } }
            guard count > 0, count <= bytes.count else { throw VoiceError.message("Qwen-Chatvorlage ist ungültig") }
            return String(decoding: bytes.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        } } } }
    }
    private func generate(prompt: String, maxTokens: Int, deadline: GenerationDeadline, requireCompletion: Bool = true, grammar: String? = nil) throws -> String {
        guard let model, let context, let vocab = llama_model_get_vocab(model) else { throw VoiceError.message("Modell fehlt") }
        llama_memory_clear(llama_get_memory(context), true)
        let opaqueDeadline = Unmanaged.passUnretained(deadline).toOpaque()
        llama_set_abort_callback(context, { data in guard let data else { return false }; return Unmanaged<GenerationDeadline>.fromOpaque(data).takeUnretainedValue().expired }, opaqueDeadline)
        defer { llama_set_abort_callback(context, nil, nil) }
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 32)
        let count = prompt.withCString { p in tokens.withUnsafeMutableBufferPointer { t in llama_tokenize(vocab, p, Int32(prompt.utf8.count), t.baseAddress, Int32(t.count), true, true) } }
        guard count > 0, Int(count) + maxTokens < 4096 else { throw VoiceError.message("Formatierungsabschnitt überschreitet den Modellkontext") }
        tokens = Array(tokens.prefix(Int(count)))
        for offset in stride(from: 0, to: tokens.count, by: 512) {
            try Task.checkCancellation(); guard !deadline.expired else { throw VoiceError.message("Lokale Formatierung hat das Zeitlimit erreicht") }
            var chunk = Array(tokens[offset..<min(offset + 512, tokens.count)])
            let status = chunk.withUnsafeMutableBufferPointer { llama_decode(context, llama_batch_get_one($0.baseAddress, Int32($0.count))) }
            guard status == 0 else { throw VoiceError.message("Lokale Formatierung wurde abgebrochen") }
        }
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else { throw VoiceError.message("Sampler konnte nicht erstellt werden") }
        defer { llama_sampler_free(sampler) }
        if let grammar {
            guard let constraint = grammar.withCString({ llama_sampler_init_grammar(vocab, $0, "root") }) else {
                throw VoiceError.message("Wortlautbegrenzung konnte nicht erstellt werden")
            }
            llama_sampler_chain_add(sampler, constraint)
        }
        guard let greedy = llama_sampler_init_greedy() else { throw VoiceError.message("Greedy-Sampler konnte nicht erstellt werden") }
        llama_sampler_chain_add(sampler, greedy)
        var output = [UInt8]()
        for _ in 0..<maxTokens {
            try Task.checkCancellation(); guard !deadline.expired else { throw VoiceError.message("Lokale Formatierung hat das Zeitlimit erreicht") }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
            var bytes = [CChar](repeating: 0, count: 256)
            var length = bytes.withUnsafeMutableBufferPointer { llama_token_to_piece(vocab, token, $0.baseAddress, Int32($0.count), 0, false) }
            if length < 0 { bytes = [CChar](repeating: 0, count: Int(-length)); length = bytes.withUnsafeMutableBufferPointer { llama_token_to_piece(vocab, token, $0.baseAddress, Int32($0.count), 0, false) } }
            guard length >= 0 else { throw VoiceError.message("Modelltext konnte nicht gelesen werden") }
            output.append(contentsOf: bytes.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            let status = withUnsafeMutablePointer(to: &token) { llama_decode(context, llama_batch_get_one($0, 1)) }
            guard status == 0 else { throw VoiceError.message("Lokale Formatierung wurde abgebrochen") }
        }
        if !requireCompletion { return String(decoding: output, as: UTF8.self) }
        throw VoiceError.message("Lokale Formatierung lieferte einen unvollständigen Abschnitt")
    }
    /// `validate` lets the model change only capitalisation, punctuation, paragraphs
    /// and the fillers äh/ähm. Parakeet already returns a punctuated sentence, so a
    /// single, filler-free sentence without suspicious capitals can skip
    /// generation. Several apparent sentences can be pause-induced fragments.
    /// E-mail keeps the model for paragraph structure.
    public static func needsModel(_ text: String, style: TextStyle) -> Bool {
        guard style == .cleaned || style == .chat else { return style != .original }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let fillers: Set<String> = ["äh", "ähm", "öh", "ehm", "uh", "um", "erm", "hmm", "mhm"]
        let sentence = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”’»)]}"))
        guard words.count <= 25, !words.contains(where: fillers.contains), !trimmed.contains("\n"),
              let first = sentence.first, first.isUppercase || first.isNumber,
              let last = sentence.last, ".!?".contains(last) else { return true }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed
        var sentenceCount = 0
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { _, _ in
            sentenceCount += 1
            return sentenceCount < 2
        }
        if sentenceCount > 1 { return true }
        return hasUnexpectedWordCapital(in: trimmed)
    }
    private static let casingWords = try? NSRegularExpression(pattern: #"[\p{L}\p{M}]+"#)
    private static let functionWords: Set<String> = ["das", "dass", "du", "dir", "dich", "dein", "deine", "deinen", "deiner", "deinem", "deines", "einige", "einigen", "einiger", "einigem", "einiges", "mit", "ohne", "und", "oder", "aber", "für", "von", "zu", "in", "auf", "an", "aus", "bei", "als", "wenn", "weil", "ob", "denn", "auch", "noch", "nur", "so", "wie", "es", "ist", "sind", "war", "wird", "werden", "ich", "wir", "ihr", "sie", "er", "man", "etwas", "diese", "dieser", "diesem", "diesen", "dieses"]
    private static func hasUnexpectedWordCapital(in text: String) -> Bool {
        guard let casingWords else { return false }
        // Each call owns its tagger: NLTagger queries mutate internal state.
        // Use only on-device assets, and route uncertainty to the existing model.
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let german = tagger.dominantLanguage == .german
        let hasGermanTags = NLTagger.availableTagSchemes(for: .word, language: .german).contains(.lexicalClass)
        if german, hasGermanTags { tagger.setLanguage(.german, range: text.startIndex..<text.endIndex) }
        let normallyLowercase: Set<NLTag> = [.verb, .adjective, .adverb, .pronoun, .determiner, .particle, .preposition, .conjunction]
        let source = text as NSString
        var previousEnd = 0
        for match in casingWords.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let word = source.substring(with: match.range)
            let gap = source.substring(with: NSRange(location: previousEnd, length: match.range.location - previousEnd))
            let startsSentence = previousEnd == 0 || gap.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?:\n\"„“")) != nil
            previousEnd = NSMaxRange(match.range)
            guard !startsSentence,
                  word.first?.isUppercase == true,
                  word == word.prefix(1).uppercased() + word.dropFirst().lowercased() else { continue }
            if functionWords.contains(word.lowercased()) { return true }
            guard german else { continue }
            guard hasGermanTags, let range = Range(match.range, in: text) else { return true }
            let tag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
            if tag == nil || tag.map(normallyLowercase.contains) == true { return true }
            // Classification requests optimization only. Nouns/names, quoted
            // words and nominalized adjectives are never blindly lowercased.
        }
        return false
    }
    static func lastTwoSentences(_ text: String) -> String {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return sentences.suffix(2).joined(separator: ". ").suffix(1200).description
    }
    static func protectedLiterals(_ text: String) -> [String] {
        let pattern = #"https?://[^\s]+|www\.[^\s]+|[\w.+-]+@[\w.-]+\.[\p{L}]{2,}|\b\d+(?:[.,:/-]\d+)*(?:\s?%)?|\b(?:nicht|kein(?:e|en|er|es|em)?|nie|niemals|ohne|not|no|never|without|cannot|can't|don't|doesn't|isn't)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?")) }.sorted()
    }
    static func validate(_ output: String, original: String, vocabulary: [String], context: String = "") throws -> String {
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, !result.contains("<|"), !result.contains("<think>"), protectedLiterals(result) == protectedLiterals(original) else { throw VoiceError.message("Formatierung hat geschützte Angaben verändert") }
        // Losing quote boundaries can turn someone else's statement into the
        // speaker's own claim. Reject it and keep the complete source fallback.
        let quotationMarks: Set<Character> = ["\"", "„", "“", "”", "«", "»"]
        guard result.filter(quotationMarks.contains) == original.filter(quotationMarks.contains) else {
            throw VoiceError.message("Formatierung hat Anführungszeichen verändert")
        }
        for word in vocabulary where original.range(of: word, options: .caseInsensitive) != nil {
            guard result.range(of: word, options: .caseInsensitive) != nil else { throw VoiceError.message("Formatierung hat einen Wörterbucheintrag verändert") }
        }
        guard result.count <= max(original.count + 80, original.count * 2) else { throw VoiceError.message("Formatierung hat den Abschnitt erweitert") }
        let oldWords = original.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let newWords = result.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        // Preserve lexical order, including subjects, tense and singular/plural. A small
        // model cannot reliably certify semantic equivalence for arbitrary rewrites.
        let fillers: Set<String> = ["äh", "ähm", "uh", "erm", "hmm"]
        guard oldWords.filter({ !fillers.contains($0) }) == newWords.filter({ !fillers.contains($0) }) else {
            throw VoiceError.message("Formatierung hat Wörter oder ihre Reihenfolge verändert")
        }
        guard newWords.count >= max(1, oldWords.count * 7 / 10), newWords.count <= oldWords.count else { throw VoiceError.message("Formatierung hat Inhalt entfernt oder ergänzt") }
        let available = Set(oldWords)
        guard newWords.filter({ !available.contains($0) }).count <= max(2, oldWords.count / 10) else { throw VoiceError.message("Formatierung hat zu viel Inhalt verändert") }
        let prior = lastTwoSentences(context).trimmingCharacters(in: .whitespacesAndNewlines)
        if prior.count > 20, result.localizedCaseInsensitiveContains(prior), !original.localizedCaseInsensitiveContains(prior) { throw VoiceError.message("Formatierung hat vorherigen Kontext wiederholt") }
        return result
    }
}
