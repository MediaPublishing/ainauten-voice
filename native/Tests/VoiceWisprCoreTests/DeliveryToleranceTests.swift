import XCTest
import Foundation
@testable import VoiceWisprCore

final class DeliveryToleranceTests: XCTestCase {
    func testEquivalentComposedAccentsConfirmButDifferentWordsDoNot() {
        let selection = NSRange(location: 0, length: 0)
        XCTAssertTrue(DeliveryVerification.confirmed(baseline: "", selection: selection, insertion: "Änderung für morgen.", observed: "A\u{0308}nderung fu\u{0308}r morgen.", caret: nil))
        XCTAssertFalse(DeliveryVerification.confirmed(baseline: "", selection: selection, insertion: "Änderung für morgen.", observed: "Anderung für morgen.", caret: nil))
    }
    func testRichTextSeparatorsStillConfirmPaste() {
        let empty = NSRange(location: 0, length: 0)
        // contenteditable keeps a trailing paragraph newline and stores line breaks as U+2028.
        XCTAssertTrue(DeliveryVerification.confirmed(baseline: "", selection: empty, insertion: "Erster Satz.\nZweiter Satz.", observed: "Erster Satz.\u{2028}Zweiter Satz.\n", caret: NSRange(location: 26, length: 0)))
        // NBSP for a typed space and CRLF line endings.
        XCTAssertTrue(DeliveryVerification.confirmed(baseline: "Hallo ", selection: NSRange(location: 6, length: 0), insertion: "Welt", observed: "Hallo\u{00A0}Welt", caret: NSRange(location: 10, length: 0)))
        XCTAssertTrue(DeliveryVerification.confirmed(baseline: "", selection: empty, insertion: "a\nb", observed: "a\r\nb", caret: NSRange(location: 4, length: 0)))
    }
    func testToleranceNeverAcceptsDifferentText() {
        let empty = NSRange(location: 0, length: 0)
        XCTAssertFalse(DeliveryVerification.confirmed(baseline: "", selection: empty, insertion: "Erster Satz.", observed: "", caret: empty))
        XCTAssertFalse(DeliveryVerification.confirmed(baseline: "", selection: empty, insertion: "Erster Satz.", observed: "Erster Satz", caret: NSRange(location: 11, length: 0)))
        XCTAssertFalse(DeliveryVerification.confirmed(baseline: "x", selection: NSRange(location: 1, length: 0), insertion: "y", observed: "x", caret: NSRange(location: 1, length: 0)))
    }
    func testCompleteChangedFieldConfirmsMissingAndStaleCaret() {
        for caret in [nil, NSRange(location: 0, length: 0), NSRange(location: 1, length: 2)] {
            XCTAssertTrue(DeliveryVerification.confirmed(baseline: "Vorher: alt.", selection: NSRange(location: 8, length: 3), insertion: "neu", observed: "Vorher: neu.", caret: caret))
            XCTAssertFalse(DeliveryVerification.confirmed(baseline: "Vorher: alt.", selection: NSRange(location: 8, length: 3), insertion: "neu", observed: "neu", caret: caret))
            XCTAssertFalse(DeliveryVerification.confirmed(baseline: "Vorher: alt.", selection: NSRange(location: 8, length: 3), insertion: "neu", observed: "Vorher: alt.", caret: caret))
        }
    }
    func testNoOpTextStillRequiresCaretEvidence() {
        let selected = NSRange(location: 0, length: 4)
        XCTAssertFalse(DeliveryVerification.confirmed(baseline: "Text", selection: selected, insertion: "Text", observed: "Text", caret: nil))
        XCTAssertFalse(DeliveryVerification.confirmed(baseline: "Text", selection: selected, insertion: "Text", observed: "Text", caret: selected))
        XCTAssertTrue(DeliveryVerification.confirmed(baseline: "Text", selection: selected, insertion: "Text", observed: "Text", caret: NSRange(location: 4, length: 0)))
    }
}
