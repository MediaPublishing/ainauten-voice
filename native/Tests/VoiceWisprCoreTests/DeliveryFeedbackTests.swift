import XCTest
@testable import VoiceWisprCore

final class DeliveryFeedbackTests: XCTestCase {
    func testConfirmedInsertionNeverOpensTextRecovery() {
        XCTAssertFalse(DeliveryOutcome(.confirmed).shouldShowRecovery)
        XCTAssertFalse(DeliveryOutcome(.confirmed, inputWasSubmitted: true).shouldShowRecovery)
    }
    func testSubmittedButUnverifiedInputDoesNotClaimSuccessOrOpenTextOverlay() {
        let outcome = DeliveryOutcome(.uncertain, reason: "Readback unavailable", inputWasSubmitted: true)
        XCTAssertEqual(outcome.status, .uncertain)
        XCTAssertFalse(outcome.shouldShowRecovery)
    }
    func testUnknownPreflightAndActualFailuresStillOfferRecovery() {
        XCTAssertTrue(DeliveryOutcome(.uncertain).shouldShowRecovery)
        for status in [DeliveryStatus.notAttempted, .failed] {
            XCTAssertTrue(DeliveryOutcome(status).shouldShowRecovery)
            XCTAssertTrue(DeliveryOutcome(status, inputWasSubmitted: true).shouldShowRecovery)
        }
    }
}
