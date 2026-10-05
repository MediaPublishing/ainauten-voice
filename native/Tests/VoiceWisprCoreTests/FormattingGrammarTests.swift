import XCTest
@testable import VoiceWisprCore

final class FormattingGrammarTests: XCTestCase {
    func testInlineMarkdownLinkRetainsBracketsAndTarget() throws {
        let link = "[Download](https://example.org/a)"
        XCTAssertEqual(try FormattingGrammar.atoms("Du findest sie hier: " + link + "."),
                       ["Du", "findest", "sie", "hier", link])
        XCTAssertTrue(try FormattingGrammar.make("Du findest sie hier: " + link + ".").contains("w4 ::= \"" + link + "\""))
        XCTAssertEqual(try FormattingGrammar.atoms("Öffne [Info.plist](https://example.org/a?q=2&x=3)!"),
                       ["Öffne", "[Info.plist](https://example.org/a?q=2&x=3)"])
    }
    func testQuotedStatementsCannotSilentlyLoseTheirBoundaries() throws {
        let source = "Er sagte: „Bitte Nicht senden.“ Danach hat er die App geschlossen."
        XCTAssertThrowsError(try LocalFormatter.validate("Er sagte bitte, nicht senden. Danach hat er die App geschlossen.", original: source, vocabulary: []))
        let corrected = "Er sagte: „Bitte nicht senden.“ Danach hat er die App geschlossen."
        XCTAssertEqual(try LocalFormatter.validate(corrected, original: source, vocabulary: []), corrected)
        XCTAssertThrowsError(try LocalFormatter.validate("Der Entwurf heißt Fertig.", original: "Der Entwurf heißt \"Fertig\".", vocabulary: []))
        XCTAssertEqual(try LocalFormatter.validate("Don't send it.", original: "Don't send it", vocabulary: []), "Don't send it.")
    }
    func testGermanDictationCannotBeTranslatedEvenWithEnglishContext() throws {
        let german = "Dies ist ein kurzer Test der Spracherkennung"
        let english = "This is a short test of speech recognition."
        XCTAssertThrowsError(try LocalFormatter.validate(english, original: german, vocabulary: [], context: "Please keep the report in English."))
        XCTAssertEqual(try LocalFormatter.validate(german + ".", original: german, vocabulary: [], context: "Please keep the report in English."), german + ".")
    }
    func testOnlyExplicitFillersCanDisappearAndDictionaryNamesWin() throws {
        let grammar = try FormattingGrammar.make("Ähm bitte nicht senden äh")
        XCTAssertFalse(grammar.contains("\"Ähm\""))
        XCTAssertFalse(grammar.contains("\"äh\""))
        XCTAssertTrue(grammar.contains("w1 ::= \"nicht\""))
        XCTAssertTrue(try FormattingGrammar.make("Ähm Han schreibt morgen", vocabulary: ["Ähm Han"]).contains("\"Ähm\""))
        XCTAssertTrue(try FormattingGrammar.make("ähm").contains("\"ähm\""))
    }
    func testInternalLiteralsAndUnicodeRemainWhole() throws {
        XCTAssertEqual(try FormattingGrammar.atoms("Änne, Qwen3-4B can't C++ 12,5% https://example.org/a?q=2&x=3. reto@example.org!"),
                       ["Änne", "Qwen3-4B", "can't", "C++", "12,5%", "https://example.org/a?q=2&x=3", "reto@example.org"])
    }
    func testGluedSentencesBecomeSeparateOrderedWords() throws {
        XCTAssertEqual(try FormattingGrammar.atoms("Ganzen.Dafür findest.Danach"),
                       ["Ganzen", "Dafür", "findest", "Danach"])
        XCTAssertEqual(FormattingGrammar.normalizeSpacing("Ganzen.Dafür\n\nfindest.Danach"), "Ganzen. Dafür\n\nfindest. Danach")
    }
    func testSpacingRepairDoesNotSplitProtectedAddressesVersionsOrCode() throws {
        let source = "https://example.org/a?b=c,d=x. a@example.org example.org AInauten.de AINAUTEN.DE Info.plist Cargo.toml Package.resolved 12,5% 1.2.3 README.md App.swift a\\b c_name w0::=oops"
        XCTAssertEqual(FormattingGrammar.normalizeSpacing(source), source)
    }
    func testRelativeCommaCannotBecomeFalseSentenceEnd() throws {
        let grammar = try FormattingGrammar.make("Wir lassen Verbesserungen vorschlagen, Was dann hilft.")
        XCTAssertTrue(grammar.contains("w3 comma w4"))
        XCTAssertTrue(grammar.contains("comma ::= \", \""))
    }
    func testRepeatedWordsStayAtSeparateOrderedPositions() throws {
        let grammar = try FormattingGrammar.make("nicht nicht übernehmen 12 3")
        XCTAssertTrue(grammar.hasPrefix("root ::= prefix w0 gap w1 gap w2 gap w3 gap w4 suffix"))
        XCTAssertTrue(grammar.contains("w0 ::= \"nicht\""))
        XCTAssertTrue(grammar.contains("w1 ::= \"nicht\""))
        XCTAssertTrue(grammar.contains("w3 ::= \"12\""))
        XCTAssertTrue(grammar.contains("w4 ::= \"3\""))
        // Negations may start a capitalized sentence; their lexical identity stays fixed.
        XCTAssertTrue(grammar.contains("\"Nicht\""))
    }
    func testUserTextCannotInjectGrammarRules() throws {
        let grammar = try FormattingGrammar.make("a\\b\"c w0::=oops")
        XCTAssertTrue(grammar.contains("\"a\\\\b\\\"c\""))
        XCTAssertEqual(grammar.components(separatedBy: "\n").filter { $0.hasPrefix("w0 ::=") }.count, 1)
        XCTAssertTrue(grammar.contains("\"w0::=oops\""))
    }
    func testEmptyPunctuationAndOversizedSectionsFailSafely() {
        XCTAssertThrowsError(try FormattingGrammar.make("... !?"))
        XCTAssertThrowsError(try FormattingGrammar.make(Array(repeating: "Wort", count: 257).joined(separator: " ")))
        XCTAssertThrowsError(try FormattingGrammar.make("Wort\u{0}laut"))
    }
    func testProtectedContentValidationStillAppliesAfterSampling() throws {
        XCTAssertThrowsError(try LocalFormatter.validate("12 Euro, nicht 30.", original: "12 Euro nicht 3", vocabulary: []))
        XCTAssertThrowsError(try LocalFormatter.validate("Nicht bestätigen.", original: "nicht übernehmen", vocabulary: []))
        XCTAssertEqual(try LocalFormatter.validate("Änne schreibt.\n\nBitte nicht übernehmen!", original: "Änne schreibt bitte nicht übernehmen", vocabulary: ["Änne"]), "Änne schreibt.\n\nBitte nicht übernehmen!")
    }
}
