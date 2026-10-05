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
    @MainActor func testExpiryTimerRunsOnlyWhileFirstTapIsPending() async throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true
        hotkey.shortcut = Shortcut(keyCode: 49, modifiers: 1 << 20)
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)); down.flags = .maskCommand
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false)); up.flags = .maskCommand
        _ = hotkey.handle(.keyDown, event: down); XCTAssertFalse(hotkey.expiryTimerRunning)
        _ = hotkey.handle(.keyUp, event: up); XCTAssertTrue(hotkey.expiryTimerRunning)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(actions, [.start, .stop]); XCTAssertFalse(hotkey.expiryTimerRunning)
        // A second tap resolves the pending tap; the poll then stops by itself.
        _ = hotkey.handle(.keyDown, event: down); _ = hotkey.handle(.keyUp, event: up); _ = hotkey.handle(.keyDown, event: down)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(actions, [.start, .stop, .start, .handsFree]); XCTAssertFalse(hotkey.expiryTimerRunning)
        _ = hotkey.handle(.keyUp, event: up); XCTAssertFalse(hotkey.expiryTimerRunning)
        hotkey.uninstall(); XCTAssertFalse(hotkey.expiryTimerRunning)
    }
    @MainActor func testKeyedHoldSwallowsItsAutorepeat() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true // default ⌃⌥Space
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)); down.flags = [.maskControl, .maskAlternate]
        let again = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)); again.flags = down.flags
        again.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        let other = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)); other.flags = down.flags
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false))
        XCTAssertNil(hotkey.handle(.keyDown, event: down)); XCTAssertEqual(actions, [.start])
        XCTAssertNil(hotkey.handle(.keyDown, event: again))
        again.flags = .maskControl // ⌥ released first; Space still repeats for the hold.
        XCTAssertNil(hotkey.handle(.keyDown, event: again))
        XCTAssertTrue(hotkey.handle(.keyDown, event: other)?.takeUnretainedValue() === other)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertNil(hotkey.handle(.keyUp, event: up)); XCTAssertEqual(actions, [.start, .stop])
        XCTAssertTrue(hotkey.handle(.keyDown, event: again)?.takeUnretainedValue() === again) // No hold: untouched.
    }
    @MainActor func testModifierOnlyHoldChordDiscardsEarlySessionAndPassesKey() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true
        let chordFlags: CGEventFlags = [.maskShift, .maskControl]
        hotkey.shortcut = Shortcut(keyCode: nil, modifiers: (1 << 17) | (1 << 18))
        hotkey.bindings.holdExtras = [Shortcut(keyCode: nil, modifiers: 1 << 23)]
        hotkey.bindings.handsFree = [Shortcut(keyCode: 49, modifiers: (1 << 17) | (1 << 18))]
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        func event(_ code: CGKeyCode, _ flags: CGEventFlags, down: Bool = true) throws -> CGEvent {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)); event.flags = flags; return event
        }
        let hold = try event(56, chordFlags), release = try event(56, [], down: false), tab = try event(48, chordFlags)
        XCTAssertTrue(hotkey.handle(.flagsChanged, event: hold)?.takeUnretainedValue() === hold); XCTAssertEqual(actions, [.start])
        XCTAssertTrue(hotkey.handle(.keyDown, event: tab)?.takeUnretainedValue() === tab); XCTAssertEqual(actions, [.start, .cancel])
        XCTAssertTrue(hotkey.handle(.keyDown, event: tab) != nil); _ = hotkey.handle(.flagsChanged, event: release)
        XCTAssertEqual(actions, [.start, .cancel]) // The rest of the chord starts nothing.
        let fn = try event(63, .maskSecondaryFn), delete = try event(51, .maskSecondaryFn)
        _ = hotkey.handle(.flagsChanged, event: fn)
        XCTAssertTrue(hotkey.handle(.keyDown, event: delete)?.takeUnretainedValue() === delete)
        _ = hotkey.handle(.flagsChanged, event: release)
        XCTAssertEqual(actions, [.start, .cancel, .start, .cancel])
        // A configured binding is no chord: Ctrl+Shift+Space switches to hands-free.
        actions.removeAll(); _ = hotkey.handle(.flagsChanged, event: hold)
        XCTAssertNil(hotkey.handle(.keyDown, event: try event(49, chordFlags))); XCTAssertEqual(actions, [.start, .handsFree])
        // Pressing the hold to stop hands-free arms nothing; a chord then keeps the result.
        _ = hotkey.handle(.flagsChanged, event: release); _ = hotkey.handle(.flagsChanged, event: hold)
        _ = hotkey.handle(.keyDown, event: tab); XCTAssertEqual(actions, [.start, .handsFree, .stop])
        _ = hotkey.handle(.flagsChanged, event: release); hotkey.reset(); actions.removeAll()
        // After 0.5 s a stray key never discards a running dictation.
        _ = hotkey.handle(.flagsChanged, event: hold); Thread.sleep(forTimeInterval: 0.55)
        XCTAssertTrue(hotkey.handle(.keyDown, event: tab)?.takeUnretainedValue() === tab)
        _ = hotkey.handle(.flagsChanged, event: release); XCTAssertEqual(actions, [.start, .stop])
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

    @MainActor func testControlZKeepsRecordingAfterZReleaseAndStopsOnControlRelease() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true
        hotkey.shortcut = Shortcut(keyCode: 6, modifiers: 1 << 18)
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let pointer = Unmanaged.passUnretained(hotkey).toOpaque()
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: true)); down.flags = .maskControl
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: false)); up.flags = .maskControl
        XCTAssertNil(GlobalHotkey.eventCallback(.keyDown, event: down, pointer: pointer))
        XCTAssertNil(GlobalHotkey.eventCallback(.keyUp, event: up, pointer: pointer))
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(actions, [.start]); XCTAssertFalse(hotkey.expiryTimerRunning)
        let modifiers = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true))
        modifiers.flags = [.maskControl, .maskShift]
        XCTAssertTrue(GlobalHotkey.eventCallback(.flagsChanged, event: modifiers, pointer: pointer)?.takeUnretainedValue() === modifiers)
        modifiers.flags = .maskControl
        _ = GlobalHotkey.eventCallback(.flagsChanged, event: modifiers, pointer: pointer)
        XCTAssertEqual(actions, [.start])
        modifiers.flags = []
        XCTAssertTrue(GlobalHotkey.eventCallback(.flagsChanged, event: modifiers, pointer: pointer)?.takeUnretainedValue() === modifiers)
        XCTAssertEqual(actions, [.start, .stop])
    }
    @MainActor func testControlZReleaseBeforeZConsumesLateRepeatAndKeyUpWhileDisabled() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true
        hotkey.shortcut = Shortcut(keyCode: 6, modifiers: 1 << 18)
        var actions: [DictationGesture] = []
        hotkey.onGesture = { actions.append($0); if $0 == .stop { hotkey.enabled = false } }
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: true)); down.flags = .maskControl
        _ = hotkey.handle(.keyDown, event: down)
        Thread.sleep(forTimeInterval: 0.2)
        let controlUp = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 59, keyDown: false))
        XCTAssertTrue(hotkey.handle(.flagsChanged, event: controlUp)?.takeUnretainedValue() === controlUp)
        XCTAssertEqual(actions, [.start, .stop])
        down.flags = []; down.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertNil(hotkey.handle(.keyDown, event: down))
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: false))
        XCTAssertNil(hotkey.handle(.keyUp, event: up))
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        XCTAssertTrue(hotkey.handle(.keyDown, event: down)?.takeUnretainedValue() === down)
        XCTAssertEqual(actions, [.start, .stop])
    }
    @MainActor func testControlZFullChordDoubleTapStillEntersHandsFree() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true
        hotkey.shortcut = Shortcut(keyCode: 6, modifiers: 1 << 18)
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: true)); down.flags = .maskControl
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: false)); up.flags = .maskControl
        let controlUp = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 59, keyDown: false))
        for _ in 0..<2 {
            XCTAssertNil(hotkey.handle(.keyDown, event: down))
            XCTAssertNil(hotkey.handle(.keyUp, event: up))
            _ = hotkey.handle(.flagsChanged, event: controlUp)
        }
        XCTAssertEqual(actions, [.start, .handsFree])
        XCTAssertNil(hotkey.handle(.keyDown, event: down))
        XCTAssertNil(hotkey.handle(.keyUp, event: up))
        _ = hotkey.handle(.flagsChanged, event: controlUp)
        XCTAssertEqual(actions, [.start, .handsFree, .stop])
        hotkey.uninstall()
    }
    @MainActor func testControlZCancelFencesTheRemainingReleaseEvents() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true; hotkey.cancellationEnabled = true
        hotkey.shortcut = Shortcut(keyCode: 6, modifiers: 1 << 18)
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: true)); down.flags = .maskControl
        _ = hotkey.handle(.keyDown, event: down)
        let escape = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true))
        XCTAssertNil(hotkey.handle(.keyDown, event: escape))
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: false)); up.flags = .maskControl
        XCTAssertNil(hotkey.handle(.keyUp, event: up))
        let controlUp = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 59, keyDown: false))
        _ = hotkey.handle(.flagsChanged, event: controlUp)
        XCTAssertEqual(actions, [.start, .cancel])
        _ = hotkey.handle(.keyDown, event: down)
        XCTAssertEqual(actions, [.start, .cancel, .start])
    }
    @MainActor func testControlZRequiresTheConfiguredChordAndRepeatedZDoesNotStop() throws {
        let hotkey = GlobalHotkey(); hotkey.enabled = true
        hotkey.shortcut = Shortcut(keyCode: 6, modifiers: 1 << 18)
        var actions: [DictationGesture] = []; hotkey.onGesture = { actions.append($0) }
        let control = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 59, keyDown: true)); control.flags = .maskControl
        XCTAssertTrue(hotkey.handle(.flagsChanged, event: control)?.takeUnretainedValue() === control)
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: true)); down.flags = [.maskControl, .maskShift]
        XCTAssertTrue(hotkey.handle(.keyDown, event: down)?.takeUnretainedValue() === down)
        XCTAssertEqual(actions, [])
        down.flags = .maskControl
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 6, keyDown: false)); up.flags = .maskControl
        for _ in 0..<2 {
            XCTAssertNil(hotkey.handle(.keyDown, event: down))
            XCTAssertNil(hotkey.handle(.keyUp, event: up))
        }
        XCTAssertEqual(actions, [.start])
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
