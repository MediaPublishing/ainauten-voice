import Foundation
import AppKit
import ApplicationServices
import Carbon
import VoiceWisprCore

/// Explicit UI test: only generated fixture documents, never user documents.
@main struct TextEditDeliveryChecks {
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
        down.flags = flags; up.flags = flags; down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    @MainActor static func main() async throws {
        guard AXIsProcessTrusted() else { print("{\"passed\":false,\"reason\":\"existingAXUnavailable\"}"); return }
        guard !IsSecureEventInputEnabled() else { print("{\"passed\":false,\"reason\":\"secureInputActive\"}"); return }
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        guard file.lastPathComponent.hasPrefix("AInauten-Voice-Delivery-"), file.pathExtension == "txt" else { print("{\"passed\":false,\"reason\":\"ownedFixtureRequired\"}"); return }
        let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "selection"
        guard ["selection", "caret", "long", "focus"].contains(mode) else { return }
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
        try await Task.sleep(for: .seconds(1))
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
        let selected = mode == "caret" ? NSRange(location: (initial as NSString).length, length: 0) : (initial as NSString).range(of: "ERSETZEN")
        var range = CFRange(location: selected.location, length: selected.length)
        let setRange = AXUIElementSetAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, AXValueCreate(.cfRange, &range)!)
        var selectedReady: FocusSnapshot?
        for _ in 0..<30 {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { break }
            if let candidate = FocusSnapshot.capture(), ownDocument(candidate.window, file), candidate.baseline == initial, candidate.selectedRange == selected { selectedReady = candidate; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard setRange == .success, let ready = selectedReady else {
            let details: [String: Any] = ["passed": false, "reason": "selectionUnavailable", "selectionSetAccepted": setRange == .success, "foregroundMatches": NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier]
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
        }
        var beforeDeliveryRange = CFRange(location: -1, length: -1)
        if let rawRange = attribute(ready.element, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() { _ = AXValueGetValue(rawRange as! AXValue, .cfRange, &beforeDeliveryRange) }
        let started = ContinuousClock.now
        let outcome = await DeliveryCoordinator().deliver(text: insertion, to: ready)
        let duration = started.duration(to: .now).components
        let expected = mode == "focus" ? initial : (initial as NSString).replacingCharacters(in: selected, with: insertion)
        let textMatches = ownDocument(ready.window, file) && (attribute(ready.element, kAXValueAttribute) as? String) == expected
        var currentRange = CFRange(location: -1, length: -1)
        if let rawRange = attribute(ready.element, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() { _ = AXValueGetValue(rawRange as! AXValue, .cfRange, &currentRange) }
        let expectedRange = mode == "focus" ? NSRange(location: beforeDeliveryRange.location, length: beforeDeliveryRange.length) : NSRange(location: selected.location + (insertion as NSString).length, length: 0)
        let caretMatches = currentRange.location == expectedRange.location && currentRange.length == expectedRange.length
        let after = clipboard()
        let equal = before != nil && before == after
        let currentApp = AXUIElementCreateApplication(app.processIdentifier)
        let currentWindow = attribute(currentApp, kAXFocusedWindowAttribute)
        let stillOwned = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier && currentWindow.map { CFEqual($0, ready.window) } == true && ownDocument(ready.window, file)
        var saved = false, closed = false, foregroundRestored = false
        if stillOwned && textMatches {
            key(1, .maskCommand)
            for _ in 0..<100 {
                if (try? String(contentsOf: file, encoding: .utf8)) == expected { saved = true; break }
                try await Task.sleep(for: .milliseconds(50))
            }
            if saved, ownDocument(ready.window, file), let rawClose = attribute(ready.window, kAXCloseButtonAttribute), CFGetTypeID(rawClose) == AXUIElementGetTypeID() {
                let close = rawClose as! AXUIElement
                let requested = AXUIElementPerformAction(close, kAXPressAction as CFString) == .success
                for _ in 0..<30 {
                    let application = AXUIElementCreateApplication(app.processIdentifier)
                    if let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement], !windows.contains(where: { ownDocument($0, file) }) { closed = requested; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { previous?.activate(options: []) }
                for _ in 0..<30 {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == previous?.processIdentifier { foregroundRestored = true; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        let report: [String: Any] = ["passed": (mode == "focus" ? outcome.status == .notAttempted && sameWindowFocusChanged : outcome.status == .confirmed) && textMatches && caretMatches && equal && saved && closed && foregroundRestored,
            "mode": mode, "sameWindowFocusChanged": sameWindowFocusChanged, "insertionUTF16Length": (insertion as NSString).length,
            "status": outcome.status.rawValue, "textMatches": textMatches, "caretMatches": caretMatches,
            "clipboardMaterialized": before != nil, "clipboardByteEqual": equal, "clipboardContentsLogged": false,
            "savedOwnFixture": saved, "closedOwnWindow": closed, "foregroundAppRestored": foregroundRestored,
            "deliverySeconds": Double(duration.seconds) + Double(duration.attoseconds)/1e18,
            "scope": "One real guarded TextEdit delivery case, no microphone/hotkey/ASR/full OS matrix"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
    }
}
