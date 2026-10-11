import AppKit
import ApplicationServices
@testable import VoiceWisprCore

// Synthetic callback input only: never posts keys, records audio, reads a
// profile, changes the clipboard or installs an accessibility event tap.
final class CallbackFixture {
    let hotkey: GlobalHotkey
    let copy: CGEvent
    let paste: CGEvent
    let down: CGEvent
    let up: CGEvent
    let release: CGEvent
    var actions: [DictationGesture] = []
    var events = 0
    var pulses = 0
    var waitingSince: TimeInterval?
    var done = false
    @MainActor init() {
        hotkey = GlobalHotkey(); hotkey.enabled = true
        hotkey.shortcut = Shortcut(keyCode: 49, modifiers: 1 << 20)
        hotkey.bindings.copyLast = [Shortcut(keyCode: 8, modifiers: (1 << 20) | (1 << 18))]
        hotkey.bindings.pasteLast = [Shortcut(keyCode: 9, modifiers: (1 << 20) | (1 << 18))]
        copy = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true)!
        paste = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)!
        copy.flags = [.maskCommand, .maskControl]; paste.flags = copy.flags
        down = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
        up = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false)!
        down.flags = .maskCommand; up.flags = .maskCommand
        release = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false)!; release.flags = []
        hotkey.onGesture = { [weak self] action in
            Self.require(Thread.isMainThread, "gesture delivered off the main thread")
            self?.actions.append(action)
        }
        hotkey.startExpiryTimer()
    }
    static func require(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL " + message); exit(1) }
    }
    func send(_ type: CGEventType, _ event: CGEvent) {
        let result = GlobalHotkey.eventCallback(type, event: event,
            pointer: Unmanaged.passUnretained(hotkey).toOpaque())
        Self.require(result == nil, "matched key was not consumed synchronously")
        events += 1
    }
    func pulse() {
        Self.require(Thread.isMainThread, "CF source did not run on main thread")
        pulses += 1
        if events < 20_000 {
            for _ in 0..<100 {
                let before = actions.count
                send(.keyDown, copy); send(.keyDown, paste)
                Self.require(actions.count == before + 2 && actions.suffix(2) == [.copyLast, .pasteLast], "gesture order or synchronous delivery changed")
            }
        } else if waitingSince == nil {
            actions.removeAll(); send(.keyDown, down); send(.keyUp, up)
            Self.require(actions == [.start], "character release stopped modifier hold")
            let result = GlobalHotkey.eventCallback(.flagsChanged, event: release,
                pointer: Unmanaged.passUnretained(hotkey).toOpaque())
            Self.require(result?.takeUnretainedValue() === release, "modifier release was consumed")
            Self.require(actions == [.start], "short tap stopped immediately")
            waitingSince = ProcessInfo.processInfo.systemUptime
        } else if ProcessInfo.processInfo.systemUptime - waitingSince! > 0.7 {
            Self.require(actions == [.start, .stop], "production timer did not expire the short tap exactly once")
            done = true
        }
    }
}

@main struct HotkeyCallbackChecks {
    static func main() {
        let fixture = MainActor.assumeIsolated { CallbackFixture() }
        var context = CFRunLoopSourceContext(version: 0, info: Unmanaged.passUnretained(fixture).toOpaque(),
            retain: nil, release: nil, copyDescription: nil, equal: nil, hash: nil,
            schedule: nil, cancel: nil, perform: { pointer in
                guard let pointer else { return }
                Unmanaged<CallbackFixture>.fromOpaque(pointer).takeUnretainedValue().pulse()
            })
        let source = CFRunLoopSourceCreate(nil, 0, &context)!
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        let timer = Timer(timeInterval: 0.005, repeats: true) { _ in
            CFRunLoopSourceSignal(source); CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        RunLoop.main.add(timer, forMode: .common)
        // An unrelated actor continuously hops to the main executor while C
        // callbacks are serviced, without enclosing the run loop in an actor.
        let background = Task.detached {
            for _ in 0..<10_000 { await MainActor.run {} }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while !fixture.done && ProcessInfo.processInfo.systemUptime < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        timer.invalidate(); CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        background.cancel()
        MainActor.assumeIsolated { fixture.hotkey.uninstall() }
        CallbackFixture.require(fixture.done, "native callback probe timed out")
        print("PASS native CFRunLoop callbacks: \(fixture.events) events, \(fixture.pulses) source calls; synchronous consume/order, main-thread confinement and production expiry timer")
    }
}
