import XCTest
@testable import VoiceWisprCore

final class InsertionSpacingTests: XCTestCase {
    func testWordBoundariesRespectBothSidesWithoutChangingTheDictation() {
        let cases: [(String, Int, String, String)] = [
            ("Hallo", 5, "Welt", " Welt"),
            ("Hallo.“,", 8, "Weiter.", " Weiter."),
            ("Hallo.“", 7, "Weiter.", " Weiter."),
            ("Hallo.\u{200B}", 7, "Weiter.", " Weiter."),
            ("Hallo.\u{FEFF}", 7, "Weiter.", " Weiter."),
            ("Hallo.\u{00A0}", 7, "Weiter.", "Weiter."),
            ("Hallo.\n", 7, "Weiter.", "Weiter."),
            ("Hallo.\u{2028}", 7, "Weiter.", "Weiter."),
            ("LinksRechts", 5, "Mitte", " Mitte "),
            ("Links Rechts", 6, "Mitte", "Mitte "),
            ("Links Rechts", 5, "Mitte", " Mitte"),
            ("Rechts", 0, "Links.", "Links. "),
            ("(", 1, "Text", "Text"),
            ("\"", 1, "Text", "Text"),
            (" “", 2, "Text", "Text"),
            ("Hallo\"", 6, "Weiter", " Weiter"),
            ("Hallo", 5, ",", ","),
            ("😀Hallo", 7, "Welt", " Welt"),
            ("Vorher", 6, " und Weiter.", " und Weiter."),
            ("Vorher", 6, "Weiter.\n", " Weiter.\n"),
            ("Vorher", 6, "", ""),
            ("Vorher", 6, "\n", "\n")
        ]
        for (baseline, cursor, text, expected) in cases {
            let selection = NSRange(location: cursor, length: 0)
            XCTAssertEqual(DeliveryVerification.insertionText(text, baseline: baseline, selection: selection), expected)
            XCTAssertEqual(DeliveryVerification.insertionText(expected, baseline: baseline, selection: selection), expected)
        }
    }

    func testURLAndDecimalComponentsRemainContiguousAndCaseSensitive() {
        let cases: [(String, Int, String, String)] = [
            ("https://voice.", 14, "AInauten.com", "AInauten.com"),
            ("www.voice.", 10, "ainauten.com", "ainauten.com"),
            ("„www.voice.", 11, "ainauten.com", "ainauten.com"),
            ("\"2.", 3, "5", "5"),
            ("https://example.org/path", 20, "next/", "next/"),
            ("name@", 5, "example.org", "example.org"),
            ("2.", 2, "5", "5"),
            ("12,", 3, "5", "5"),
            ("2.", 2, "5 ", "5 "),
            ("12.5", 3, "7", "7"),
            ("25", 1, ",", ","),
            ("https://example.org", 0, "Besuche", "Besuche "),
            ("Adresse: ", 9, "https://example.org", "https://example.org"),
            ("Hallo.", 6, "2,5", " 2,5")
        ]
        for (baseline, cursor, text, expected) in cases {
            XCTAssertEqual(DeliveryVerification.insertionText(text, baseline: baseline,
                selection: NSRange(location: cursor, length: 0)), expected)
        }
    }

    func testWordReplacementsAndInvalidRangesAreNotExpanded() {
        XCTAssertEqual(DeliveryVerification.insertionText("neu", baseline: "Vorher alt danach",
            selection: NSRange(location: 7, length: 3)), "neu")
        XCTAssertEqual(DeliveryVerification.insertionText("stand", baseline: "verstehen",
            selection: NSRange(location: 3, length: 4)), "stand")
        for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: 20, length: 0),
                      NSRange(location: 1, length: 20), NSRange(location: 1, length: -1)] {
            XCTAssertEqual(DeliveryVerification.insertionText("Text", baseline: "Hallo", selection: range), "Text")
        }
    }

    func testQueueConfirmationIncludesTheNewTrailingSpaceAndStillRejectsCursorMoves() {
        let selection = NSRange(location: 5, length: 0)
        XCTAssertTrue(DeliveryVerification.canAdvanceQueuedInsertion(baseline: "LinksRechts", selection: selection,
            text: "Mitte", observed: "Links Mitte Rechts", caret: NSRange(location: 12, length: 0)))
        XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: "LinksRechts", selection: selection,
            text: "Mitte", observed: "Links Mitte Rechts", caret: NSRange(location: 11, length: 0)))
        XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: "LinksRechts", selection: selection,
            text: "Mitte", observed: "Links Mitte Anderes", caret: NSRange(location: 12, length: 0)))
    }
}
