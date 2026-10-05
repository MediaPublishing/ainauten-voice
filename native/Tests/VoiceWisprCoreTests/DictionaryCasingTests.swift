import XCTest
@testable import VoiceWisprCore

private actor CasingSpeech: SpeechTranscribing {
    let text: String
    init(_ text: String) { self.text = text }
    func prepare() async throws {}
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        .init(sessionID: sessionID, index: index, text: text)
    }
}

private actor CasingFormatter: TextFormatting {
    var inputs: [String] = []
    var vocabularies: [[String]] = []
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        inputs.append(text); vocabularies.append(vocabulary)
        return text
    }
}

final class DictionaryCasingTests: XCTestCase {
    private let importedMIT = DictionaryEntry(phrase: "MIT", sourceID: "wispr:fixture-mit")

    func testPersonalAliasesPreserveAddressesFilesAndEngineName() {
        let matcher = DictionaryMatcher([
            .init(phrase: "Wipecoding", replacement: "Vibecoding"),
            .init(phrase: "Whisperflow", replacement: "Wispr Flow"),
            .init(phrase: "Whisper Flow", replacement: "Wispr Flow")
        ])
        XCTAssertEqual(matcher.replace(in: "Wipecoding und Whisperflow, Whisper Flow-Lösung und Whisper."),
                       "Vibecoding und Wispr Flow, Wispr Flow-Lösung und Whisper.")
        for literal in ["https://example.org/Wipecoding", "https://Whisperflow.app", "Whisperflow.app",
                        "Wipecoding@example.org", "Whisperflow.swift", "/tmp/Wipecoding.json", "https://example.org/path#Whisperflow"] {
            XCTAssertEqual(matcher.replace(in: literal), literal)
            XCTAssertEqual(matcher.topVocabulary(in: literal), [])
        }
        XCTAssertEqual(matcher.replace(in: "WipecodingExtra xWhisperflow _Wipecoding"), "WipecodingExtra xWhisperflow _Wipecoding")
    }

    func testExplicitWholeLiteralReplacementRemainsAvailable() {
        let matcher = DictionaryMatcher([
            .init(phrase: "https://old.example/Whisperflow", replacement: "https://new.example/app"),
            .init(phrase: "Whisperflow.swift", replacement: "VoiceWispr.swift"),
            .init(phrase: "old@example.org", replacement: "new@example.org")
        ])
        XCTAssertEqual(matcher.replace(in: "https://old.example/Whisperflow Whisperflow.swift old@example.org"),
                       "https://new.example/app VoiceWispr.swift new@example.org")
    }

    func testSpellingHintsDoNotChangeDomainsOrHideLaterProseMatch() {
        let matcher = DictionaryMatcher([.init(phrase: "OpenAI"), .init(phrase: "Wipecoding", replacement: "Vibecoding")])
        XCTAssertEqual(matcher.replace(in: "https://openai.com openai"), "https://openai.com OpenAI")
        XCTAssertEqual(matcher.topVocabulary(in: "https://example.org/Wipecoding Wipecoding"), ["Wipecoding"])
    }

    func testStreamingLiteralProtectionAtEverySplitPosition() {
        let entries = [DictionaryEntry(phrase: "Wipecoding", replacement: "Vibecoding"),
                       DictionaryEntry(phrase: "Whisperflow", replacement: "Wispr Flow"),
                       DictionaryEntry(phrase: "Whisper Flow", replacement: "Wispr Flow")]
        let text = "Wipecoding: https://example.org/Wipecoding https://Whisperflow.app Wipecoding@example.org /tmp/Whisperflow.swift und Whisper Flow."
        let expected = "Vibecoding: https://example.org/Wipecoding https://Whisperflow.app Wipecoding@example.org /tmp/Whisperflow.swift und Wispr Flow."
        for split in text.indices {
            var matcher = StreamingDictionaryMatcher(entries)
            let output = matcher.process(String(text[..<split])) + matcher.process(String(text[split...]), final: true)
            XCTAssertEqual(output, expected)
        }
    }

    func testStreamingRetainsSchemeBeforeAliasArrives() {
        var matcher = StreamingDictionaryMatcher([.init(phrase: "Whisperflow", replacement: "Wispr Flow")])
        var output = matcher.process("Siehe https:")
        output += matcher.process("//")
        output += matcher.process("Whisperflow")
        output += matcher.process(".app und Whisper")
        output += matcher.process("flow.", final: true)
        XCTAssertEqual(output, "Siehe https://Whisperflow.app und Wispr Flow.")
    }

    func testImportedAcronymDoesNotCapitalizeGermanPreposition() {
        let text = "Mit dem Text arbeite ich mit dem Team am MIT."
        XCTAssertEqual(DictionaryMatcher([importedMIT]).replace(in: text), text)
    }

    func testOtherAcronymsDoNotCapitalizeOrdinaryEnglishWords() {
        let text = "Send it to us. IT and US remain uppercase."
        let matcher = DictionaryMatcher([.init(phrase: "IT"), .init(phrase: "US")])
        XCTAssertEqual(matcher.replace(in: text), text)
    }

    func testExplicitReplacementStillOverridesCase() {
        let matcher = DictionaryMatcher([.init(phrase: "mit", replacement: "MIT")])
        XCTAssertEqual(matcher.replace(in: "mit Mit MIT"), "MIT MIT MIT")
        XCTAssertEqual(matcher.topVocabulary(in: "Mit"), ["mit"])
    }

    func testNamesStillUseDictionarySpelling() {
        let matcher = DictionaryMatcher([.init(phrase: "OpenAI"), .init(phrase: "AInauten")])
        XCTAssertEqual(matcher.replace(in: "openai und ainauten"), "OpenAI und AInauten")
        XCTAssertEqual(Set(matcher.topVocabulary(in: "openai und ainauten")), Set(["OpenAI", "AInauten"]))
    }

    func testAcronymHintsUseTheSameCaseRuleAsReplacement() {
        let matcher = DictionaryMatcher([importedMIT])
        XCTAssertEqual(matcher.topVocabulary(in: "Mit dem Text und mit dem Team."), [])
        XCTAssertEqual(matcher.topVocabulary(in: "Forschung am MIT."), ["MIT"])
        XCTAssertEqual(matcher.topVocabulary(in: "MIT", limit: 0), [])
        XCTAssertEqual(matcher.topVocabulary(in: "MIT", limit: -1), [])
    }

    func testVocabularyHintsRequireCompleteTokens() {
        let matcher = DictionaryMatcher([importedMIT, .init(phrase: "Ann"), .init(phrase: "New York")])
        XCTAssertEqual(matcher.topVocabulary(in: "MITglied Anna xNew York"), [])
        XCTAssertEqual(Set(matcher.topVocabulary(in: "(MIT), ann in new york.")), Set(["new york", "ann", "MIT"]))
        XCTAssertEqual(matcher.topVocabulary(in: "MIT Ann New York", limit: 1), ["New York"])
    }

    func testStreamingPreservesCaseAcrossSegmentBoundaries() {
        var matcher = StreamingDictionaryMatcher([importedMIT])
        var result = matcher.process("Mit dem M")
        result += matcher.process("IT arbeite ich m")
        result += matcher.process("it dem Team.", final: true)
        XCTAssertEqual(result, "Mit dem MIT arbeite ich mit dem Team.")
    }

    func testOriginalAndOptimizedPipelinesReceiveUnchangedPrepositions() async throws {
        let text = "Ich arbeite mit dem Team."
        for style in [TextStyle.original, .cleaned] {
            let formatter = CasingFormatter()
            let pipeline = ProcessingPipeline(speech: CasingSpeech(text), formatter: formatter)
            try await pipeline.start(sessionID: UUID(), style: style, dictionary: [importedMIT])
            try await pipeline.append(samples: Array(repeating: 0.1, count: 16_000))
            let result = try await pipeline.finish()
            XCTAssertEqual(result.original, text)
            XCTAssertEqual(result.text, text)
            XCTAssertFalse(result.usedFallback)
            let inputs = await formatter.inputs
            let vocabularies = await formatter.vocabularies
            XCTAssertEqual(inputs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, style == .original ? [] : [text])
            XCTAssertEqual(vocabularies, style == .original ? [] : [[]])
        }
    }

    func testPlainVocabularyPreservesOrdinaryWordsAndSentenceStarts() {
        let entries = ["Dass", "Das", "Du", "Klein", "Einige"].map { DictionaryEntry(phrase: $0, sourceID: "wispr:fixture-\($0)") }
        let matcher = DictionaryMatcher(entries)
        let first = "Ich habe festgestellt, dass einige Worte im Text, insbesondere kurze Worte, groß geschrieben werden statt klein."
        let second = "In diesem Beispiel hier, das ich angesprochen habe, siehst du, dass einige und klein großgeschrieben wurden, fälschlicherweise."
        XCTAssertEqual(matcher.replace(in: first), first)
        XCTAssertEqual(matcher.replace(in: second), second)
        XCTAssertEqual(matcher.replace(in: "Das passt. Einige Worte bleiben klein."), "Das passt. Einige Worte bleiben klein.")
    }

    func testLowercaseVocabularyDoesNotLowercaseSentenceStarts() {
        let matcher = DictionaryMatcher([.init(phrase: "das"), .init(phrase: "klein")])
        XCTAssertEqual(matcher.replace(in: "Das bleibt klein. Klein beginnt den nächsten Satz."), "Das bleibt klein. Klein beginnt den nächsten Satz.")
    }

    func testPlainVocabularyHintsPreserveRecognizedCase() {
        let matcher = DictionaryMatcher([.init(phrase: "Dass"), .init(phrase: "Du"), .init(phrase: "Klein")])
        XCTAssertEqual(Set(matcher.topVocabulary(in: "Ich sehe, dass du klein schreibst.")), Set(["dass", "du", "klein"]))
        XCTAssertEqual(matcher.topVocabulary(in: "Frau Klein kommt."), ["Klein"])
    }

    func testSurnameAndOrdinaryAdjectiveCanCoexist() {
        let matcher = DictionaryMatcher([.init(phrase: "Klein"), .init(phrase: "Frank")])
        let text = "Die Schrift ist klein. Frau Klein spricht mit Frank. Please be frank."
        XCTAssertEqual(matcher.replace(in: text), text)
    }

    func testPlainVocabularyCannotBlockAnIntentionalSpellingOrReplacement() {
        let matcher = DictionaryMatcher([
            .init(id: "a", phrase: "openai"), .init(id: "z", phrase: "OpenAI"),
            .init(phrase: "mit openai"), .init(phrase: "Das ist klein"),
            .init(phrase: "klein", replacement: "kurz")
        ])
        XCTAssertEqual(matcher.replace(in: "Ich spreche mit openai. Das ist klein."), "Ich spreche mit OpenAI. Das ist kurz.")
    }

    func testPlainVocabularyPreservesCaseAcrossSegmentBoundaries() {
        var matcher = StreamingDictionaryMatcher([.init(phrase: "Dass"), .init(phrase: "Klein")])
        var result = matcher.process("Ich sehe, da")
        result += matcher.process("ss die Schrift kl")
        result += matcher.process("ein bleibt.", final: true)
        XCTAssertEqual(result, "Ich sehe, dass die Schrift klein bleibt.")
    }

    func testPipelineDoesNotInjectPlainVocabularyCapitalization() async throws {
        let text = "Ich sehe, dass du klein schreibst."
        let entries = ["Dass", "Du", "Klein"].map { DictionaryEntry(phrase: $0) }
        let formatter = CasingFormatter()
        let pipeline = ProcessingPipeline(speech: CasingSpeech(text), formatter: formatter)
        try await pipeline.start(sessionID: UUID(), style: .cleaned, dictionary: entries)
        try await pipeline.append(samples: Array(repeating: 0.1, count: 16_000))
        let result = try await pipeline.finish()
        XCTAssertEqual(result.original, text)
        XCTAssertEqual(result.text, text)
        let inputs = await formatter.inputs
        let vocabulary = await formatter.vocabularies
        XCTAssertEqual(inputs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, [text])
        XCTAssertEqual(Set(try XCTUnwrap(vocabulary.first)), Set(["dass", "du", "klein"]))
    }
}
