import XCTest
@testable import VoiceWisprCore

final class FocusRetryTests: XCTestCase {
    @MainActor func testFreshChromiumTreeIsRetriedUntilAvailable() async {
        var attempts = 0, pauses = 0
        let value: Int? = await FocusCaptureRetry.capture(expectedPID: 42, foregroundPID: { 42 },
            capture: { attempts += 1; return attempts == 3 ? 7 : nil }, pause: { pauses += 1 })
        XCTAssertEqual(value, 7); XCTAssertEqual(attempts, 3); XCTAssertEqual(pauses, 2)
    }
    @MainActor func testMissingTreeHasABoundedRetryBudget() async {
        var attempts = 0, pauses = 0
        let value: Int? = await FocusCaptureRetry.capture(expectedPID: 42, foregroundPID: { 42 },
            capture: { attempts += 1; return nil }, pause: { pauses += 1 })
        XCTAssertNil(value); XCTAssertEqual(attempts, 6); XCTAssertEqual(pauses, 5)
    }
    @MainActor func testSwitchingAppsDuringWaitStopsCapture() async {
        var pid: Int32 = 42, attempts = 0
        let value: Int? = await FocusCaptureRetry.capture(expectedPID: 42, foregroundPID: { pid },
            capture: { attempts += 1; return nil }, pause: { pid = 43 })
        XCTAssertNil(value); XCTAssertEqual(attempts, 1)
    }
    @MainActor func testSwitchingAppsDuringCaptureDiscardsTheSnapshot() async {
        var pid: Int32 = 42
        let value: Int? = await FocusCaptureRetry.capture(expectedPID: 42, foregroundPID: { pid },
            capture: { pid = 43; return 7 }, pause: {})
        XCTAssertNil(value)
    }
    @MainActor func testCancellationWhileWaitingStopsRetries() async {
        var attempts = 0
        let task = Task { @MainActor in
            await FocusCaptureRetry.capture(expectedPID: 42, foregroundPID: { 42 },
                capture: { () -> Int? in attempts += 1; return nil },
                pause: { throw CancellationError() })
        }
        let value = await task.value
        XCTAssertNil(value); XCTAssertEqual(attempts, 1)
    }
}
