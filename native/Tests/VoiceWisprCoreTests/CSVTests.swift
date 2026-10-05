import XCTest
@testable import VoiceWisprCore
final class CSVTests: XCTestCase {
    func testQuotesAndMultilineAndBOM() throws {
        let data = Data("\u{feff}phrase,replacement\r\n\"New,York\",\"New York\"\r\n\"Reto\"\"s Name\",\"Zeile 1\nZeile 2\"\r\n".utf8)
        let p = try DictionaryCSV.preview(data: data)
        XCTAssertEqual(p.entries.count, 2); XCTAssertEqual(p.entries[0].phrase, "New,York"); XCTAssertEqual(p.entries[1].replacement, "Zeile 1\nZeile 2")
    }
    func testSemicolonDedupManualWins() throws {
        let p = try DictionaryCSV.preview(data: Data("Wort;Ersetzung\nAInauten;AInauten.com\nainauten;Andere\nMac;Mac\n".utf8))
        let existing = [DictionaryEntry(phrase: "AInauten", replacement: "meine Änderung", manuallyModified: true)]
        let merged = p.merged(with: existing)
        XCTAssertEqual(p.skipped, 1); XCTAssertEqual(merged.added, 1); XCTAssertEqual(merged.entries[0].replacement, "meine Änderung")
        XCTAssertEqual(p.merged(with: merged.entries).added, 0)
    }
    func testMalformedRejectsAndLongWordsSkip() throws {
        XCTAssertThrowsError(try DictionaryCSV.preview(data: Data("word,replacement\n\"unfinished".utf8)))
        XCTAssertThrowsError(try DictionaryCSV.preview(data: Data("word,replacement\na,b,c".utf8)))
        XCTAssertThrowsError(try DictionaryCSV.preview(data: Data("unknown\na".utf8)))
        let p = try DictionaryCSV.preview(data: Data(("word\n" + String(repeating: "x", count: 256) + "\nok\n").utf8))
        XCTAssertEqual(p.skipped, 1); XCTAssertEqual(p.entries.count, 1)
    }
}
