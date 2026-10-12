import XCTest
import Carbon
@testable import VoiceWisprCore

final class TypingProbeTests: XCTestCase {
    let marker = TypingProbeVerification.marker

    @MainActor func testUndoKeyProducesZInTheActiveCommandLayout() throws {
        let key = try XCTUnwrap(DeliveryKeyboard.undoKeyCode())
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        let raw = try XCTUnwrap(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData))
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
        var dead: UInt32 = 0, length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), UInt32(cmdKey >> 8),
            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead,
            characters.count, &length, &characters)
        XCTAssertEqual(status, noErr)
        XCTAssertEqual(String(utf16CodeUnits: characters, count: length), "z")
    }

    func testProbeRequiresExactSingleMarkerAtCaret() {
        XCTAssertTrue(TypingProbeVerification.containsProbe(marker, value: "Hello " + marker, selection: NSRange(location: 7, length: 0)))
        for selection in [NSRange(location: 0, length: 0), NSRange(location: 6, length: 0), NSRange(location: 7, length: 1), NSRange(location: NSNotFound, length: 0)] {
            XCTAssertFalse(TypingProbeVerification.containsProbe(marker, value: "Hello " + marker, selection: selection))
        }
        XCTAssertFalse(TypingProbeVerification.containsProbe(marker, value: marker + marker, selection: NSRange(location: 2, length: 0)))
        XCTAssertFalse(TypingProbeVerification.containsProbe(marker, value: "Hello", selection: NSRange(location: 5, length: 0)))
    }
    func testUndoMustRestoreTextAndCaretBeforeInsertion() {
        XCTAssertTrue(TypingProbeVerification.restored(marker, probed: "Hello " + marker + "world", value: "Hello world", selection: NSRange(location: 6, length: 0)))
        XCTAssertTrue(TypingProbeVerification.restored(marker, probed: marker, value: "", selection: NSRange(location: 0, length: 0)))
        XCTAssertFalse(TypingProbeVerification.restored(marker, probed: "Hello " + marker, value: "Hell", selection: NSRange(location: 4, length: 0)))
        XCTAssertFalse(TypingProbeVerification.restored(marker, probed: "Hello " + marker, value: "Hello ", selection: NSRange(location: 0, length: 0)))
        XCTAssertFalse(TypingProbeVerification.restored(marker, probed: marker, value: marker, selection: NSRange(location: 1, length: 0)))
    }
    func testUndoRestoresAReplacedSelectionWithoutLosingItsText() {
        XCTAssertTrue(TypingProbeVerification.restored(marker, probed: "A " + marker + " Z", value: "A selected text Z", selection: NSRange(location: 2, length: 13)))
        XCTAssertFalse(TypingProbeVerification.restored(marker, probed: "A " + marker + " Z", value: "A selected text changed", selection: NSRange(location: 2, length: 13)))
    }
    func testUndoAcceptsAnEmptyEditorsAccessibilityParagraphSeparator() {
        for separator in ["\n", "\r", "\u{2028}", "\u{2029}"] {
            XCTAssertTrue(TypingProbeVerification.restored(marker, probed: marker,
                value: separator, selection: NSRange(location: 0, length: 0)))
        }
        XCTAssertFalse(TypingProbeVerification.restored(marker, probed: marker,
            value: "text\n", selection: NSRange(location: 0, length: 0)))
        XCTAssertFalse(TypingProbeVerification.restored(marker, probed: marker,
            value: "\n", selection: NSRange(location: 2, length: 0)))
    }
    func testProbeAndUndoUseUTF16CaretOffsets() {
        XCTAssertTrue(TypingProbeVerification.containsProbe(marker, value: "🙂" + marker, selection: NSRange(location: 3, length: 0)))
        XCTAssertTrue(TypingProbeVerification.restored(marker, probed: "🙂" + marker, value: "🙂", selection: NSRange(location: 2, length: 0)))
    }
    @MainActor func testEmptyOrCancelledDeliveryDoesNotProbe() async {
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
