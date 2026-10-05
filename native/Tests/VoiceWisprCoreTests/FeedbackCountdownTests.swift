import XCTest
@testable import VoiceWisprCore

final class FeedbackCountdownTests: XCTestCase {
    func testClosesAfterFiveSecondsIncludingDelayedTimerTick() {
        let countdown = FeedbackCountdown(now: 100)
        XCTAssertEqual(countdown.remaining(at: 100), 5)
        XCTAssertFalse(countdown.expired(at: 104.99))
        XCTAssertTrue(countdown.expired(at: 105))
        XCTAssertTrue(countdown.expired(at: 500))
        XCTAssertEqual(countdown.remaining(at: 500), 0)
    }
    func testReadingPauseFreezesRemainingTimeAndResumesWithoutReset() {
        var countdown = FeedbackCountdown(now: 100)
        countdown.setPaused(true, at: 102)
        XCTAssertEqual(countdown.remaining(at: 160), 3)
        XCTAssertFalse(countdown.expired(at: 160))
        countdown.setPaused(true, at: 160)
        countdown.setPaused(false, at: 200)
        XCTAssertEqual(countdown.remaining(at: 202), 1)
        XCTAssertFalse(countdown.expired(at: 202))
        XCTAssertTrue(countdown.expired(at: 203))
    }
    func testRepeatedUnpauseDoesNotKeepFeedbackOpen() {
        var countdown = FeedbackCountdown(now: 10)
        for time in [10.5, 11, 12, 14.9] { countdown.setPaused(false, at: time) }
        XCTAssertTrue(countdown.expired(at: 15))
        XCTAssertEqual(countdown.remaining(at: 9), 5)
    }
    func testHoverAfterExpiryCannotKeepAnEmptyRingOpen() {
        var countdown = FeedbackCountdown(now: 10)
        countdown.setPaused(true, at: 15)
        XCTAssertFalse(countdown.isPaused)
        XCTAssertTrue(countdown.expired(at: 15))
    }
}
