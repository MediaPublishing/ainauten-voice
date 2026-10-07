import AppKit
import ApplicationServices

public enum DictationGesture: Equatable, Sendable { case start, stop, handsFree, cancel, copyLast, pasteLast }

/// The FreeFlow hold/toggle controller is retained. This adapter adds Wispr's double-tap gesture.
public final class DictationGestureMachine {
    private let controller = DictationShortcutSessionController()
    private var downAt: TimeInterval?
    private var firstTap: TimeInterval?
    public var recording = false
    public init() {}
    public func down(at time: TimeInterval) -> DictationGesture? {
        guard downAt == nil else { return nil }
        downAt = time
        if controller.activeMode == .toggle {
            if controller.handle(event: .toggleActivated, isTranscribing: false) == .stop { recording = false; return .stop }
            return nil
        }
        if let tap = firstTap, time - tap <= 0.5, recording {
            firstTap = nil; controller.forceToggleMode(); return .handsFree
        }
        firstTap = nil
        if controller.handle(event: .holdActivated, isTranscribing: false) != nil { recording = true; return .start }
        return nil
    }
    public func up(at time: TimeInterval) -> DictationGesture? {
        guard let start = downAt else { return nil }; downAt = nil
        if controller.activeMode == .toggle { _ = controller.handle(event: .toggleDeactivated, isTranscribing: false); return nil }
        if time - start < 0.18 { firstTap = start; return nil }
        if controller.handle(event: .holdDeactivated, isTranscribing: false) == .stop { recording = false; return .stop }
        return nil
    }
    public func expire(at time: TimeInterval) -> DictationGesture? {
        guard let tap = firstTap, time - tap >= 0.5, downAt == nil else { return nil }
        firstTap = nil
        if controller.handle(event: .holdDeactivated, isTranscribing: false) == .stop { recording = false; return .stop }
        return nil
    }
    var awaitingSecondTap: Bool { firstTap != nil }
    var isHoldRecording: Bool { recording && controller.activeMode == .hold }
    public func reset() { controller.reset(); recording = false; downAt = nil; firstTap = nil }
    public func beginHandsFree() { reset(); controller.forceToggleMode(); _ = controller.handle(event: .toggleDeactivated, isTranscribing: false); recording = true }
    public func toggleHandsFree() -> DictationGesture {
        if recording && controller.activeMode == .toggle { reset(); return .stop }
        if recording { downAt = nil; firstTap = nil; controller.forceToggleMode(); _ = controller.handle(event: .toggleDeactivated, isTranscribing: false); return .handsFree }
        beginHandsFree(); return .start
    }
}

@MainActor public final class GlobalHotkey {
    public var onGesture: ((DictationGesture) -> Void)?
    public var onFailure: ((String) -> Void)?
    public var shortcut = Shortcut()
    public var bindings = ShortcutBindings()
    public var cancellationEnabled = false
    public var enabled = false { didSet { if !enabled && oldValue { machine.reset(); matched = nil; previousFlags = 0 } } }
    private let machine = DictationGestureMachine()
    private var matched: Shortcut?
    private var chordDeadline: TimeInterval?
    private var previousFlags: UInt64 = 0
    private static let flagMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 23)
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var expiry: Timer?
    public init() {}
    // CGEventTap needs a synchronous reply (nil consumes the key). Its source
    // runs exclusively on CFRunLoopGetMain(), but a CF callback can inherit an
    // unrelated Swift executor context. Check the actual thread before bridging
    // to our main-actor state; do not inspect that borrowed executor context.
    nonisolated static func eventCallback(_ type: CGEventType, event: CGEvent,
                                         pointer: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
        guard Thread.isMainThread, let pointer else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<GlobalHotkey>.fromOpaque(pointer).takeUnretainedValue()
        let operation: @MainActor () -> Unmanaged<CGEvent>? = { owner.handle(type, event: event) }
        return withoutActuallyEscaping(operation) {
            unsafeBitCast($0, to: (() -> Unmanaged<CGEvent>?).self)()
        }
    }
    public func install() -> Bool {
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, pointer in
            GlobalHotkey.eventCallback(type, event: event, pointer: pointer)
        }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { onFailure?("Globales Tastenkürzel benötigt Bedienungshilfen. Bitte die Freigabe prüfen."); return false }
        tap = newTap; source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }
    /// The 30 ms poll only resolves a pending first tap; it stops itself afterwards
    /// so an idle app does not wake the CPU.
    func startExpiryTimer() {
        guard expiry == nil else { return }
        expiry = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.expireGesture() }
        }
    }
    var expiryTimerRunning: Bool { expiry != nil }
    private func expireGesture() {
        if enabled, let action = machine.expire(at: ProcessInfo.processInfo.systemUptime) { onGesture?(action) }
        if !machine.awaitingSecondTap { expiry?.invalidate(); expiry = nil }
    }
    public func uninstall() {
        expiry?.invalidate(); expiry = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil; reset()
    }
    deinit {
        expiry?.invalidate()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
    func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recoverAfterTapTimeout()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue & Self.flagMask
        let previous = previousFlags
        if type == .flagsChanged { previousFlags = flags }
        func activated(_ shortcut: Shortcut) -> Bool {
            if let key = shortcut.keyCode { return type == .keyDown && code == key && flags == shortcut.modifiers && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 }
            return type == .flagsChanged && flags == shortcut.modifiers && previous != flags
        }
        if cancellationEnabled && (type == .keyDown && code == 53 || bindings.cancel.contains(where: activated)) { reset(); onGesture?(.cancel); return nil }
        guard enabled else { return Unmanaged.passUnretained(event) }
        let time = ProcessInfo.processInfo.systemUptime
        if bindings.copyLast.contains(where: activated) { onGesture?(.copyLast); return nil }
        if bindings.pasteLast.contains(where: activated) { onGesture?(.pasteLast); return nil }
        if bindings.handsFree.contains(where: activated) {
            matched = nil
            onGesture?(machine.toggleHandsFree())
            return nil
        }
        // A keyed hands-free combination can extend an active modifier-only hold.
        // Releasing its Fn/modifier must not turn it back into a hold-to-stop session.
        if let held = matched {
            let released = held.keyCode.map { type == .keyUp && code == $0 } ?? (type == .flagsChanged && flags != held.modifiers)
            if released {
                matched = nil; if let a = machine.up(at: time) { onGesture?(a) }
                if machine.awaitingSecondTap { startExpiryTimer() }
                return held.keyCode == nil ? Unmanaged.passUnretained(event) : nil
            }
            // Autorepeat of the held key belongs to the shortcut, not to the target app.
            if let key = held.keyCode, type == .keyDown, code == key { return nil }
            // Ctrl+Shift+Tab, Fn+Delete: the held modifiers began another app's shortcut.
            // Discard that fresh session and pass the key on unchanged. Later keys never
            // discard, so a stray key cannot cost a long dictation.
            if held.keyCode == nil, type == .keyDown, let deadline = chordDeadline, time <= deadline,
               !([shortcut] + bindings.all).contains(where: activated) {
                machine.reset(); matched = nil; chordDeadline = nil
                onGesture?(.cancel); return Unmanaged.passUnretained(event)
            }
        }
        if let held = ([shortcut] + bindings.holdExtras).first(where: activated) {
            matched = held; let action = machine.down(at: time)
            chordDeadline = held.keyCode == nil && action == .start ? time + 0.5 : nil
            if let action { onGesture?(action) }
            return held.keyCode == nil ? Unmanaged.passUnretained(event) : nil
        }
        return Unmanaged.passUnretained(event)
    }
    /// A disabled tap may miss release events. Finish a released hold without losing its audio.
    func recoverAfterTapTimeout(flags: CGEventFlags = CGEventSource.flagsState(.combinedSessionState),
                               keyIsDown: (UInt16) -> Bool = { CGEventSource.keyState(.combinedSessionState, key: $0) }) {
        guard enabled, machine.isHoldRecording, let held = matched else { return }
        let heldNow = held.keyCode.map(keyIsDown) ?? (flags.rawValue & Self.flagMask == held.modifiers)
        guard !heldNow else { return }
        reset(); onGesture?(.stop)
    }
    public func reset() { machine.reset(); matched = nil; previousFlags = 0 }
    public func beginHandsFree() { matched = nil; machine.beginHandsFree() }
}
