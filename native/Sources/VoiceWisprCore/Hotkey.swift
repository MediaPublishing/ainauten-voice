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
    private var previousFlags: UInt64 = 0
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var expiry: Timer?
    public init() {}
    public func install() -> Bool {
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<GlobalHotkey>.fromOpaque(pointer).takeUnretainedValue()
            return MainActor.assumeIsolated { owner.handle(type, event: event) }
        }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { onFailure?("Globales Tastenkürzel benötigt Bedienungshilfen. Bitte die Freigabe prüfen."); return false }
        tap = newTap; source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        expiry = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { guard let self, self.enabled else { return }; if let action = self.machine.expire(at: ProcessInfo.processInfo.systemUptime) { self.onGesture?(action) } }
        }
        return true
    }
    func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return Unmanaged.passUnretained(event) }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flagMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 23)
        let flags = event.flags.rawValue & flagMask
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
            if released { matched = nil; if let a = machine.up(at: time) { onGesture?(a) }; return held.keyCode == nil ? Unmanaged.passUnretained(event) : nil }
        }
        if let held = ([shortcut] + bindings.holdExtras).first(where: activated) {
            matched = held; if let a = machine.down(at: time) { onGesture?(a) }
            return held.keyCode == nil ? Unmanaged.passUnretained(event) : nil
        }
        return Unmanaged.passUnretained(event)
    }
    public func reset() { machine.reset(); matched = nil; previousFlags = 0 }
    public func beginHandsFree() { matched = nil; machine.beginHandsFree() }
}
