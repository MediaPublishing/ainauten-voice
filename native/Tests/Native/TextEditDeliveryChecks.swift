import Foundation
import AppKit
import ApplicationServices
import Carbon
import VoiceWisprCore

/// Explicit UI test: only generated fixture documents, never user documents.
@main struct TextEditDeliveryChecks {
    @MainActor static func checkQueue(_ first: FocusSnapshot, initial: String, changeCaret: Bool) async -> (DeliveryOutcome, String, NSRange, Bool) {
        let ids = [UUID(), UUID(), UUID()]
        let texts = ["Erster Teil", "Second sentence.", "Troisième phrase."]
        var queue = DictationQueue(maximumBytes: 30, reservationBytes: 10)
        var snapshots = [first, first, first]
        var expected = initial, expectedCaret = first.selectedRange
        var last = DeliveryOutcome(.notAttempted, reason: "fixture")
        var passed = queue.reserve(ids[0]) && queue.captured(ids[0]) && queue.beginNext() == ids[0]
        // These captures finish while the first result is still processing.
        for id in ids.dropFirst() { passed = queue.reserve(id) && queue.captured(id) && passed }
        for index in ids.indices {
            if index > 0 { passed = queue.beginNext() == ids[index] && passed }
            guard passed, queue.mayAutomaticallyDeliver(ids[index]) else { return (last, expected, expectedCaret, false) }
            let target = snapshots[index]
            let text = index == 0 ? texts[index] : DeliveryVerification.queuedContinuationText(texts[index], baseline: target.baseline, selection: target.selectedRange)
            last = await DeliveryCoordinator().deliver(text: text, to: target)
            guard last.status == .confirmed else { return (last, expected, expectedCaret, false) }
            let insertion = DeliveryVerification.insertionText(text, baseline: expected, selection: expectedCaret)
            expected = DeliveryVerification.expectedValue(baseline: expected, selection: expectedCaret, insertion: insertion)!
            expectedCaret = NSRange(location: expectedCaret.location + (insertion as NSString).length, length: 0)
            if changeCaret && index == 0 {
                var moved = CFRange(location: 0, length: 0)
                if AXUIElementSetAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, AXValueCreate(.cfRange, &moved)!) != .success {
                    guard let current = FocusSnapshot.capture(), current.matches(target.afterConfirmedInsertion(texts[index]) ?? target) else { return (last, expected, expectedCaret, false) }
                    key(126, .maskCommand) // Move only the owned fixture caret to its start.
                }
                try? await Task.sleep(for: .milliseconds(100))
                passed = target.afterConfirmedInsertion(texts[index]) == nil && passed
                // The unadvanced second snapshot must not paste into that caret.
                last = await DeliveryCoordinator().deliver(text: texts[1], to: snapshots[1])
                passed = last.status == .notAttempted && passed
                queue.suppressAutomaticDelivery(); queue.finish(ids[index])
                passed = queue.beginNext() == ids[1] && !queue.mayAutomaticallyDeliver(ids[1]) && passed
                return (last, expected, NSRange(location: 0, length: 0), passed)
            }
            guard let advanced = target.afterConfirmedInsertion(text) else { return (last, expected, expectedCaret, false) }
            for next in ids.indices where next > index {
                passed = snapshots[next].matches(target) && passed
                snapshots[next] = advanced
            }
            queue.finish(ids[index])
        }
        return (last, expected, expectedCaret, passed && queue.entries.isEmpty)
    }
    @MainActor static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.05)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    @MainActor static func ownDocument(_ window: AXUIElement, _ file: URL) -> Bool {
        guard let path = attribute(window, kAXDocumentAttribute) as? String, let url = URL(string: path) else { return false }
        return url.standardizedFileURL.path == file.standardizedFileURL.path
    }
    @MainActor static func clipboard() -> [[String: Data]]? {
        let board = NSPasteboard.general, before = board.changeCount
        guard board.pasteboardItems != nil || (board.types ?? []).isEmpty else { return nil }
        var total = 0, values: [[String: Data]] = []
        for item in board.pasteboardItems ?? [] {
            var saved: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                total += data.count; guard total <= 64 * 1024 * 1024 else { return nil }
                saved[type.rawValue] = data
            }
            values.append(saved)
        }
        return before == board.changeCount ? values : nil
    }
    @MainActor static func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!
        down.flags = flags; up.flags = []; down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    @MainActor static func main() async throws {
        guard AXIsProcessTrusted() else { print("{\"passed\":false,\"reason\":\"existingAXUnavailable\"}"); return }
        guard !IsSecureEventInputEnabled() else { print("{\"passed\":false,\"reason\":\"secureInputActive\"}"); return }
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        guard file.lastPathComponent.hasPrefix("AInauten-Voice-Delivery-"), file.pathExtension == "txt" else { print("{\"passed\":false,\"reason\":\"ownedFixtureRequired\"}"); return }
        let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "selection"
        guard ["selection", "caret", "long", "focus", "fullscreen", "queued", "queued-focus"].contains(mode) else { return }
        let physicalModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        guard CGEventSource.flagsState(.hidSystemState).intersection(physicalModifiers).isEmpty else { print("{\"passed\":false,\"reason\":\"physicalModifiersHeldBeforeOpening\"}");return }
        let initial = "Anfang ERSETZEN Ende\n"
        let insertion = mode == "long" ? String(repeating: "Öffentlicher Absatz. 12,5 bleibt unverändert, nicht 20. 👋\n", count: 400) : "öffentlicher Testtext 👋"
        if FileManager.default.fileExists(atPath: file.path) {
            guard (try? String(contentsOf: file, encoding: .utf8)) == initial else { print("{\"passed\":false,\"reason\":\"existingFixtureChanged\"}"); return }
        } else { try initial.write(to: file, atomically: true, encoding: .utf8) }
        let previous = NSWorkspace.shared.frontmostApplication
        let textEditURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")!
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        configuration.addsToRecentItems = false
        let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.open([file], withApplicationAt: textEditURL, configuration: configuration) { app, error in
                if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: error ?? NSError(domain: "OwnedTextEdit", code: 1)) }
            }
        }
        // Document activation/selection restoration is asynchronous; let the
        // owned fixture settle before setting the explicit test selection.
        _ = app.activate(options: [.activateIgnoringOtherApps])
        try await Task.sleep(for: .seconds(1))
        // TextEdit can retain Find-bar focus across documents. Raise and focus
        // only the synthetic document, never another window or a user document.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            if let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement],
               let window = windows.first(where: { ownDocument($0, file) }) {
                _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                func focusText(_ element: AXUIElement, depth: Int) -> Bool {
                    guard depth < 8 else { return false }
                    if attribute(element, kAXRoleAttribute) as? String == kAXTextAreaRole,
                       attribute(element, kAXValueAttribute) as? String == initial {
                        return AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
                    }
                    for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(100) {
                        if focusText(child, depth: depth + 1) { return true }
                    }
                    return false
                }
                _ = focusText(window, depth: 0)
            }
        }
        var target: FocusSnapshot?
        for _ in 0..<100 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                let application = AXUIElementCreateApplication(app.processIdentifier)
                if let rawWindow = attribute(application, kAXFocusedWindowAttribute), CFGetTypeID(rawWindow) == AXUIElementGetTypeID() {
                    let window = rawWindow as! AXUIElement
                    if ownDocument(window, file), let candidate = FocusSnapshot.capture(), candidate.baseline == initial {
                        target = candidate; break
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let target else { print("{\"passed\":false,\"reason\":\"ownedTargetUnavailable\"}"); return }
        let usesFullscreen = mode == "fullscreen"
        var entered = false
        if usesFullscreen {
            let enterRequest = AXUIElementSetAttributeValue(target.window, "AXFullScreen" as CFString, kCFBooleanTrue)
            for _ in 0..<80 {
                if ownDocument(target.window, file), attribute(target.window, "AXFullScreen") as? Bool == true { entered = true; break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard enterRequest == .success, entered else { print("{\"passed\":false,\"reason\":\"fullscreenNotAvailable\"}"); return }
            try await Task.sleep(for: .seconds(1))
        }
        let selected = mode == "caret" ? NSRange(location: (initial as NSString).length, length: 0) : (initial as NSString).range(of: "ERSETZEN")
        var range = CFRange(location: selected.location, length: selected.length)
        let setRange = AXUIElementSetAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, AXValueCreate(.cfRange, &range)!)
        if setRange != .success, target.isUnchanged(), ownDocument(target.window, file) {
            // Some TextEdit versions expose a readable selection but do not
            // implement its AX setter. Prepare the same owned fixture using
            // ordinary navigation; never type or touch a different document.
            if mode == "caret" { key(125, .maskCommand) }
            else {
                key(126, .maskCommand)
                for _ in 0..<selected.location { key(124, []) }
                for _ in 0..<selected.length { key(124, .maskShift) }
            }
        }
        var selectedReady: FocusSnapshot?
        for _ in 0..<30 {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { break }
            if let candidate = FocusSnapshot.capture(), ownDocument(candidate.window, file), candidate.baseline == initial, candidate.selectedRange == selected { selectedReady = candidate; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let ready = selectedReady else {
            let details: [String: Any] = ["passed": false, "reason": "selectionUnavailable", "selectionSetAccepted": setRange == .success, "selectionSetError": setRange.rawValue, "foregroundMatches": NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier]
            print(String(decoding: try JSONSerialization.data(withJSONObject: details, options: [.sortedKeys]), as: UTF8.self)); return
        }
        let before = clipboard()
        var sameWindowFocusChanged = false
        if mode == "focus" {
            key(3, .maskCommand)
            for _ in 0..<50 {
                let application = AXUIElementCreateApplication(app.processIdentifier)
                if let rawWindow = attribute(application, kAXFocusedWindowAttribute), let rawField = attribute(application, kAXFocusedUIElementAttribute), CFGetTypeID(rawWindow) == AXUIElementGetTypeID(), CFGetTypeID(rawField) == AXUIElementGetTypeID() {
                    sameWindowFocusChanged = CFEqual(rawWindow, ready.window) && !CFEqual(rawField, ready.element)
                    if sameWindowFocusChanged { break }
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard sameWindowFocusChanged else {
                // A missing Find-bar focus change is a test setup failure,
                // never permission to run the negative test on the old target.
                print("{\"passed\":false,\"reason\":\"focusChangeSetupUnavailable\",\"insertionAttempted\":false}")
                return
            }
        }
        var beforeDeliveryRange = CFRange(location: -1, length: -1)
        if let rawRange = attribute(ready.element, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() { _ = AXValueGetValue(rawRange as! AXValue, .cfRange, &beforeDeliveryRange) }
        let started = ContinuousClock.now
        let queued = mode == "queued" || mode == "queued-focus"
        let proof = queued ? await checkQueue(ready, initial: initial, changeCaret: mode == "queued-focus") : nil
        let outcome: DeliveryOutcome
        if let proof { outcome = proof.0 }
        else { outcome = await DeliveryCoordinator().deliver(text: insertion, to: ready) }
        let duration = started.duration(to: .now).components
        let expected = proof?.1 ?? (mode == "focus" ? initial : (initial as NSString).replacingCharacters(in: selected, with: insertion))
        let textMatches = ownDocument(ready.window, file) && (attribute(ready.element, kAXValueAttribute) as? String) == expected
        var currentRange = CFRange(location: -1, length: -1)
        if let rawRange = attribute(ready.element, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() { _ = AXValueGetValue(rawRange as! AXValue, .cfRange, &currentRange) }
        let expectedRange = proof?.2 ?? (mode == "focus" ? NSRange(location: beforeDeliveryRange.location, length: beforeDeliveryRange.length) : NSRange(location: selected.location + (insertion as NSString).length, length: 0))
        let caretMatches = currentRange.location == expectedRange.location && currentRange.length == expectedRange.length
        let after = clipboard()
        let equal = before != nil && before == after
        let currentApp = AXUIElementCreateApplication(app.processIdentifier)
        let currentWindow = attribute(currentApp, kAXFocusedWindowAttribute)
        let stillOwned = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier && currentWindow.map { CFEqual($0, ready.window) } == true && ownDocument(ready.window, file)
        var saved = false, closed = false, foregroundRestored = false, exited = false
        if stillOwned && textMatches {
            if usesFullscreen {
                let exitRequest = AXUIElementSetAttributeValue(ready.window, "AXFullScreen" as CFString, kCFBooleanFalse)
                for _ in 0..<80 {
                    if ownDocument(ready.window, file), attribute(ready.window, "AXFullScreen") as? Bool == false { exited = exitRequest == .success; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                try await Task.sleep(for: .seconds(1))
                guard exited, ownDocument(ready.window, file), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { print("{\"passed\":false,\"reason\":\"fullscreenExitNotVerified\"}");return }
            }
            key(1, .maskCommand)
            for _ in 0..<100 {
                if (try? String(contentsOf: file, encoding: .utf8)) == expected { saved = true; break }
                try await Task.sleep(for: .milliseconds(50))
            }
            if saved, ownDocument(ready.window, file), let rawClose = attribute(ready.window, kAXCloseButtonAttribute), CFGetTypeID(rawClose) == AXUIElementGetTypeID() {
                let close = rawClose as! AXUIElement
                _ = AXUIElementPerformAction(close, kAXPressAction as CFString)
                for _ in 0..<30 {
                    let application = AXUIElementCreateApplication(app.processIdentifier)
                    if let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement], !windows.contains(where: { ownDocument($0, file) }) { closed = true; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                if !closed, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                   let current = FocusSnapshot.capture(), CFEqual(current.window, ready.window), ownDocument(current.window, file) {
                    // A failed AX press must not close a different user window.
                    // Only the freshly verified, saved fixture may receive Cmd-W.
                    key(13, .maskCommand)
                    for _ in 0..<30 {
                        let application = AXUIElementCreateApplication(app.processIdentifier)
                        if let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement], !windows.contains(where: { ownDocument($0, file) }) { closed = true; break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { previous?.activate(options: []) }
                for _ in 0..<30 {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == previous?.processIdentifier { foregroundRestored = true; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        let report: [String: Any] = ["passed": (mode == "queued-focus" ? outcome.status == .notAttempted : mode == "focus" ? outcome.status == .notAttempted && sameWindowFocusChanged : outcome.status == .confirmed) && (proof?.3 ?? true) && textMatches && caretMatches && equal && saved && closed && foregroundRestored && (!usesFullscreen || (entered && exited)),
            "queueChecked": queued, "queueChecksPassed": proof?.3 ?? true,
            "mode": mode, "fullscreenChecked": usesFullscreen, "fullscreenEntered": usesFullscreen ? entered as Any : NSNull(), "fullscreenExited": usesFullscreen ? exited as Any : NSNull(), "modifiersAfterCleanup": CGEventSource.flagsState(.hidSystemState).rawValue, "sameWindowFocusChanged": sameWindowFocusChanged, "insertionUTF16Length": (insertion as NSString).length,
            "status": outcome.status.rawValue, "textMatches": textMatches, "caretMatches": caretMatches,
            "clipboardMaterialized": before != nil, "clipboardByteEqual": equal, "clipboardContentsLogged": false,
            "savedOwnFixture": saved, "closedOwnWindow": closed, "foregroundAppRestored": foregroundRestored,
            "deliverySeconds": Double(duration.seconds) + Double(duration.attoseconds)/1e18,
            "scope": "One real guarded TextEdit Core insertion; optional fullscreen only. No microphone, physical hotkey, ASR, installed Pill/recovery UI, multi-display or full OS/p95 acceptance"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
    }
}
