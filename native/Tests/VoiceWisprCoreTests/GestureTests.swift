import XCTest
import ApplicationServices
@testable import VoiceWisprCore

final class GestureTests: XCTestCase {
    @MainActor func testNativeCallbackConsumesSynchronouslyAndForwardsUnrelatedKeys() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true
        hotkey.bindings.copyLast = [Shortcut(keyCode: 8, modifiers: (1 << 20) | (1 << 18))]
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let pointer = Unmanaged.passUnretained(hotkey).toOpaque()
        let copy = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        copy.flags = [.maskCommand, .maskControl]
        XCTAssertNil(GlobalHotkey.eventCallback(.keyDown, event: copy, pointer: pointer))
        XCTAssertEqual(actions, [.copyLast]) // Must happen before the C callback returns.
        copy.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertTrue(GlobalHotkey.eventCallback(.keyDown, event: copy, pointer: pointer)?.takeUnretainedValue() === copy)
        XCTAssertEqual(actions, [.copyLast])
        XCTAssertTrue(GlobalHotkey.eventCallback(.keyDown, event: copy, pointer: nil)?.takeUnretainedValue() === copy)
    }
    func testNativeCallbackOnWorkerThreadDoesNotDereferenceContextOrConsumeKey() throws {
        let key = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            // Deliberately invalid context: it must never be read off the main thread.
            let result = GlobalHotkey.eventCallback(.keyDown, event: key, pointer: UnsafeMutableRawPointer(bitPattern: 1))
            XCTAssertTrue(result?.takeUnretainedValue() === key)
            finished.signal()
        }
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
    }
    @MainActor func testNativeCallbackHoldDoubleTapHandsFreeAndEscape() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true
        hotkey.shortcut = Shortcut(keyCode: 49, modifiers: 1 << 20)
        hotkey.bindings.handsFree = [Shortcut(keyCode: 49, modifiers: 1 << 23)]
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let pointer = Unmanaged.passUnretained(hotkey).toOpaque()
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)); down.flags = .maskCommand
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false)); up.flags = .maskCommand
        _ = GlobalHotkey.eventCallback(.keyDown, event: down, pointer: pointer)
        Thread.sleep(forTimeInterval: 0.2)
        _ = GlobalHotkey.eventCallback(.keyUp, event: up, pointer: pointer)
        XCTAssertEqual(actions, [.start, .stop])
        hotkey.reset(); actions.removeAll()
        _ = GlobalHotkey.eventCallback(.keyDown, event: down, pointer: pointer)
        _ = GlobalHotkey.eventCallback(.keyUp, event: up, pointer: pointer)
        _ = GlobalHotkey.eventCallback(.keyDown, event: down, pointer: pointer)
        _ = GlobalHotkey.eventCallback(.keyUp, event: up, pointer: pointer)
        _ = GlobalHotkey.eventCallback(.keyDown, event: down, pointer: pointer)
        XCTAssertEqual(actions, [.start, .handsFree, .stop])
        hotkey.reset(); actions.removeAll(); down.flags = .maskSecondaryFn
        _ = GlobalHotkey.eventCallback(.keyDown, event: down, pointer: pointer)
        _ = GlobalHotkey.eventCallback(.keyDown, event: down, pointer: pointer)
        XCTAssertEqual(actions, [.start, .stop])
        hotkey.enabled = false; hotkey.cancellationEnabled = true
        let escape = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true))
        XCTAssertNil(GlobalHotkey.eventCallback(.keyDown, event: escape, pointer: pointer))
        XCTAssertEqual(actions, [.start, .stop, .cancel])
    }
    @MainActor func testNativeTimerExpiresShortTapAndUninstallFencesPendingStop() async throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true
        hotkey.shortcut = Shortcut(keyCode: 49, modifiers: 1 << 20)
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let pointer = Unmanaged.passUnretained(hotkey).toOpaque()
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)); down.flags = .maskCommand
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false)); up.flags = .maskCommand
        hotkey.startExpiryTimer(); hotkey.startExpiryTimer()
        XCTAssertNil(GlobalHotkey.eventCallback(.keyDown, event: down, pointer: pointer))
        XCTAssertNil(GlobalHotkey.eventCallback(.keyUp, event: up, pointer: pointer))
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(actions, [.start, .stop])
        hotkey.reset()
        _ = GlobalHotkey.eventCallback(.keyDown, event: down, pointer: pointer)
        _ = GlobalHotkey.eventCallback(.keyUp, event: up, pointer: pointer)
        hotkey.uninstall()
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(actions, [.start, .stop, .start])
    }
    @MainActor func testImportedHandsFreeAndCopyPasteBindings() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true
        hotkey.bindings.handsFree = [Shortcut(keyCode: 49, modifiers: 1 << 23)]
        hotkey.bindings.copyLast = [Shortcut(keyCode: 8, modifiers: (1 << 20) | (1 << 18))]
        hotkey.bindings.pasteLast = [Shortcut(keyCode: 9, modifiers: (1 << 20) | (1 << 18))]
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        func press(_ code: UInt16, flags: CGEventFlags) throws {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)); event.flags = flags
            XCTAssertNil(hotkey.handle(.keyDown, event: event))
        }
        try press(49, flags: .maskSecondaryFn); XCTAssertEqual(actions, [.start])
        try press(49, flags: .maskSecondaryFn); XCTAssertEqual(actions, [.start, .stop])
        try press(8, flags: [.maskCommand, .maskControl]); try press(9, flags: [.maskCommand, .maskControl])
        XCTAssertEqual(actions, [.start, .stop, .copyLast, .pasteLast])
    }
    @MainActor func testPillHandsFreeStopsOnNextHoldPressAndExtraBindings() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true; hotkey.beginHandsFree()
        hotkey.bindings.holdExtras = [Shortcut(keyCode: 40, modifiers: 1 << 20)]
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 40, keyDown: true)); event.flags = .maskCommand
        XCTAssertNil(hotkey.handle(.keyDown, event: event)); XCTAssertEqual(actions, [.stop])
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 40, keyDown: false)); up.flags = .maskCommand
        XCTAssertNil(hotkey.handle(.keyUp, event: up)); XCTAssertEqual(actions, [.stop])
    }
    @MainActor func testUnchangedPermissionRefreshKeepsActiveHold() throws {
        let hotkey = GlobalHotkey(); hotkey.shortcut = Shortcut(keyCode: 49, modifiers: 1 << 20); hotkey.enabled = true
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)); down.flags = .maskCommand
        _ = hotkey.handle(.keyDown, event: down)
        hotkey.enabled = true
        hotkey.enabled = false; hotkey.enabled = false
        hotkey.enabled = true
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false)); up.flags = .maskCommand
        _ = hotkey.handle(.keyUp, event: up)
        XCTAssertEqual(actions, [.start]) // The disable transition fences the old hold.
    }
    func testHandsFreeConvertsAnActiveHoldWithoutStoppingAudio() {
        let machine = DictationGestureMachine(); XCTAssertEqual(machine.down(at: 1), .start)
        XCTAssertEqual(machine.toggleHandsFree(), .handsFree)
        XCTAssertNil(machine.up(at: 1.3)); XCTAssertTrue(machine.recording)
        XCTAssertEqual(machine.toggleHandsFree(), .stop); XCTAssertFalse(machine.recording)
    }
    @MainActor func testEscapeCancelsProcessingWhileRecordingShortcutDisabled() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = false; hotkey.cancellationEnabled = true
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true))
        XCTAssertNil(hotkey.handle(.keyDown, event: event)); XCTAssertEqual(actions, [.cancel])
        hotkey.cancellationEnabled = false
        XCTAssertTrue(hotkey.handle(.keyDown, event: event) != nil); XCTAssertEqual(actions, [.cancel])
    }

    func testHoldReleaseStops() {
        let m = DictationGestureMachine()
        XCTAssertEqual(m.down(at: 1), .start)
        XCTAssertEqual(m.up(at: 2), .stop)
        XCTAssertNil(m.expire(at: 3))
    }
    func testDoubleTapHandsfreeThenStop() {
        let m = DictationGestureMachine()
        XCTAssertEqual(m.down(at: 1), .start)
        XCTAssertNil(m.up(at: 1.05))
        XCTAssertEqual(m.down(at: 1.3), .handsFree)
        XCTAssertNil(m.up(at: 1.35))
        XCTAssertNil(m.expire(at: 2))
        XCTAssertEqual(m.down(at: 3), .stop)
    }
    func testSingleShortTapExpiresAndCancelFences() {
        let m = DictationGestureMachine()
        _ = m.down(at: 1); _ = m.up(at: 1.05)
        XCTAssertNil(m.expire(at: 1.49))
        XCTAssertEqual(m.expire(at: 1.5), .stop)
        _ = m.down(at: 2); m.reset()
        XCTAssertNil(m.up(at: 3)); XCTAssertFalse(m.recording)
    }
}
