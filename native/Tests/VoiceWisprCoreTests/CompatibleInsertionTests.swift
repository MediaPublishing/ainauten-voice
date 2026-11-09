import XCTest
import Foundation
@testable import VoiceWisprCore

final class CompatibleInsertionTests: XCTestCase {
    func testUnmappedEditorPositionsPreserveDictatedTextWithoutSpacing() {
        let cases: [(String?, NSRange?)] = [
            (".", NSRange(location: 2, length: 0)),
            (".", nil),
            (nil, NSRange(location: 0, length: 0)),
            (nil, nil),
            (".", NSRange(location: NSNotFound, length: 0)),
            (".", NSRange(location: 1, length: 2))
        ]
        for (baseline, selection) in cases {
            XCTAssertEqual(DeliveryVerification.insertionText("Weiter.", baseline: baseline, selection: selection), "Weiter.")
            XCTAssertEqual(DeliveryVerification.queuedContinuationText("Weiter.", baseline: baseline, selection: selection), "Weiter.")
            XCTAssertNil(DeliveryVerification.expectedValue(baseline: baseline, selection: selection, insertion: "Weiter."))
            XCTAssertFalse(DeliveryVerification.confirmed(baseline: baseline, selection: selection,
                insertion: "Weiter.", observed: ".Weiter.", caret: NSRange(location: 8, length: 0)))
            XCTAssertFalse(DeliveryVerification.canAdvanceQueuedInsertion(baseline: baseline, selection: selection,
                text: "Weiter.", observed: ".Weiter.", caret: NSRange(location: 8, length: 0)))
        }
    }
}
