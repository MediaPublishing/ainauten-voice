import XCTest
@testable import VoiceWisprCore

final class FocusRecoveryTests: XCTestCase {
    @MainActor func testDeliveryPermissionRevokedDuringRecordingWaitDoesNotSubmit() async {
        var permissionChecks = 0, recordingChecks = 0
        let outcome = await DeliveryCoordinator().deliver(text: "Keep this for recovery", to: nil,
            recordingInProgress: { recordingChecks += 1; return true },
            insertionAllowed: { permissionChecks += 1; return permissionChecks == 1 })
        XCTAssertEqual(outcome.status, .notAttempted)
        XCTAssertFalse(outcome.inputWasSubmitted)
        XCTAssertEqual(permissionChecks, 2)
        XCTAssertEqual(recordingChecks, 1)
    }
    @MainActor func testRevokedDeliveryPermissionDoesNotReadRecordingState() async {
        var recordingChecks = 0
        let outcome = await DeliveryCoordinator().deliver(text: "Keep this for recovery", to: nil,
            recordingInProgress: { recordingChecks += 1; return false },
            insertionAllowed: { false })
        XCTAssertEqual(outcome.status, .notAttempted)
        XCTAssertFalse(outcome.inputWasSubmitted)
        XCTAssertEqual(recordingChecks, 0)
    }
    @MainActor func testMissingEditableFieldFailsClosedWithBoundedReadOnlyRetries() async {
        var reads = 0, pauses = 0
        let target: String? = await FocusCaptureRetry.capture(expectedPID: 42,
            foregroundPID: { 42 }, targetUnchanged: { true },
            capture: { reads += 1; return nil }, pause: { pauses += 1 })
        XCTAssertNil(target)
        XCTAssertEqual(reads, 6)
        XCTAssertEqual(pauses, 5)
    }
    @MainActor func testOriginallyFocusedFieldMayBecomeReadableWithoutTyping() async {
        var reads = 0
        let target: String? = await FocusCaptureRetry.capture(expectedPID: 42,
            foregroundPID: { 42 }, targetUnchanged: { true },
            capture: { reads += 1; return reads == 2 ? "original field" : nil }, pause: {})
        XCTAssertEqual(target, "original field")
        XCTAssertEqual(reads, 2)
    }
    @MainActor func testChangedControlPreventsEvenTheFirstRead() async {
        var reads = 0
        let target: String? = await FocusCaptureRetry.capture(expectedPID: 42,
            foregroundPID: { 42 }, targetUnchanged: { false },
            capture: { reads += 1; return "different field" }, pause: {})
        XCTAssertNil(target)
        XCTAssertEqual(reads, 0)
    }
    @MainActor func testWindowOrControlChangeDuringReadDiscardsSnapshot() async {
        var unchanged = true
        let target: String? = await FocusCaptureRetry.capture(expectedPID: 42,
            foregroundPID: { 42 }, targetUnchanged: { unchanged },
            capture: { unchanged = false; return "different target" }, pause: {})
        XCTAssertNil(target)
    }
    @MainActor func testFocusChangeWhileWaitingStopsRecoveryInTheSameApplication() async {
        var unchanged = true, reads = 0
        let target: String? = await FocusCaptureRetry.capture(expectedPID: 42,
            foregroundPID: { 42 }, targetUnchanged: { unchanged },
            capture: { reads += 1; return nil }, pause: { unchanged = false })
        XCTAssertNil(target)
        XCTAssertEqual(reads, 1)
    }
    @MainActor func testCancellationBeforeRecoveryDoesNotReadOrAdoptTarget() async {
        var reads = 0
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await FocusCaptureRetry.capture(expectedPID: 42,
                foregroundPID: { 42 }, targetUnchanged: { true },
                capture: { reads += 1; return "target" }, pause: {})
        }
        let target = await task.value
        XCTAssertNil(target)
        XCTAssertEqual(reads, 0)
    }
    @MainActor func testCancellationDuringReadDiscardsSnapshot() async {
        let task = Task { @MainActor in
            await FocusCaptureRetry.capture(expectedPID: 42,
                foregroundPID: { 42 }, targetUnchanged: { true },
                capture: {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return "target"
                }, pause: {})
        }
        let target = await task.value
        XCTAssertNil(target)
    }
    @MainActor func testEmptyOrCancelledDeliveryNeverSubmitsInput() async {
        let empty = await DeliveryCoordinator().deliver(text: "", to: nil)
        XCTAssertEqual(empty.status, .notAttempted)
        XCTAssertFalse(empty.inputWasSubmitted)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await DeliveryCoordinator().deliver(text: "Synthetic text", to: nil)
        }
        let cancelled = await task.value
        XCTAssertEqual(cancelled.status, .notAttempted)
        XCTAssertFalse(cancelled.inputWasSubmitted)
    }
}
