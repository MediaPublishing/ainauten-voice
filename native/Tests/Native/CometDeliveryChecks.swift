import Foundation
import AppKit
import ApplicationServices
import Carbon
import CryptoKit
import VoiceWisprCore

/// Explicit UI test: only an owned synthetic loopback page in Comet.
/// No microphone/models; clipboard formats stay in memory. Uses existing AX.
@main struct CometDeliveryChecks {
    @MainActor static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.05)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    @MainActor static func ownDocument(_ window: AXUIElement, _ file: URL) -> Bool {
        guard let title = attribute(window, kAXTitleAttribute) as? String else { return false }
        return title.contains(file.lastPathComponent)
    }
    @MainActor static func rangedText(_ element: AXUIElement) -> String? {
        guard let count = attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber,
              count.intValue >= 0, count.intValue <= 4_000_000 else { return nil }
        var range = CFRange(location: 0, length: count.intValue)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        for name in [kAXStringForRangeParameterizedAttribute, kAXAttributedStringForRangeParameterizedAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success else { continue }
            if let text = value as? String { return text }
            if let text = value as? NSAttributedString { return text.string }
        }
        return nil
    }
    @MainActor static func chunkReadback(_ element: AXUIElement, expected: String) -> [String: Any] {
        let count = attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber
        var joined = "", errors: [Int32] = []
        let total = (expected as NSString).length
        let started = ContinuousClock.now
        var offset = 0
        while offset < total {
            let safe = (expected as NSString).rangeOfComposedCharacterSequences(for: NSRange(location: offset, length: min(1000, total - offset)))
            var range = CFRange(location: safe.location, length: safe.length)
            var result: CFTypeRef?
            let error = AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, AXValueCreate(.cfRange, &range)!, &result)
            if error != .success { errors.append(error.rawValue); break }
            guard let text = result as? String else { errors.append(-1); break }
            joined += text; offset = safe.location + safe.length
        }
        var tailRange = CFRange(location: total, length: 1), tailValue: CFTypeRef?
        let tailError = AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, AXValueCreate(.cfRange, &tailRange)!, &tailValue)
        let tail = tailValue as? String
        var markerRange: CFTypeRef?, markerText: CFTypeRef?, markerLength: CFTypeRef?
        let markerRangeError = AXUIElementCopyParameterizedAttributeValue(element, "AXTextMarkerRangeForUIElement" as CFString, element, &markerRange)
        var markerTextError: AXError = .noValue, markerLengthError: AXError = .noValue
        if let markerRange {
            markerLengthError = AXUIElementCopyParameterizedAttributeValue(element, "AXLengthForTextMarkerRange" as CFString, markerRange, &markerLength)
            markerTextError = AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, markerRange, &markerText)
        }
        let full = markerText as? String
        let markerMatches = markerRangeError == .success && markerLengthError == .success && markerTextError == .success
            && full == expected && (full.map { ($0 as NSString).length } ?? -1) == (markerLength as? NSNumber)?.intValue
        let endVerified = markerMatches
        let a = Array(joined.utf16), b = Array(expected.utf16)
        let mismatch = zip(a,b).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset ?? -1
        let elapsed = started.duration(to: .now).components
        return ["advertisedUTF16Length": count?.intValue ?? -1, "chunkErrors": errors,
            "chunkJoinedUTF16Length": (joined as NSString).length, "chunkJoinedSHA256": hash(joined),
            "chunkExactMatch": joined == expected, "endVerified": endVerified, "markerRangeStatus": markerRangeError.rawValue, "markerStringStatus": markerTextError.rawValue, "markerLengthStatus": markerLengthError.rawValue, "markerReportedLength": (markerLength as? NSNumber)?.intValue ?? -1, "tailError": tailError.rawValue, "tailUTF16Length": tail.map { ($0 as NSString).length } ?? -1, "firstMismatchUTF16Index": mismatch, "expectedCodeUnit": mismatch >= 0 ? Int(b[mismatch]) : -1, "observedCodeUnit": mismatch >= 0 ? Int(a[mismatch]) : -1, "chunkSeconds": Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18]
    }
    @MainActor static func fieldText(_ element: AXUIElement) -> String? {
        attribute(element, kAXValueAttribute) as? String ?? rangedText(element)
    }
    static func expectedRangeForReadback(_ selected: NSRange, _ insertion: String) -> NSRange { NSRange(location: selected.location + (insertion as NSString).length, length: 0) }
    static func hash(_ value: String?) -> String { value.map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() } ?? "unavailable" }
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
        let file = URL(string: CommandLine.arguments[1])!
        guard file.lastPathComponent.hasPrefix("AInauten-Voice-Delivery-"), file.scheme == "http", file.host == "127.0.0.1" else { print("{\"passed\":false,\"reason\":\"ownedFixtureRequired\"}"); return }
        let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "selection"
        let editor = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "textarea"
        guard ["textarea", "contenteditable"].contains(editor) else { return }
        let physicalModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        guard CGEventSource.flagsState(.hidSystemState).intersection(physicalModifiers).isEmpty else {
            print("{\"passed\":false,\"reason\":\"physicalModifiersHeldBeforeOpening\"}"); return
        }
        guard ["selection", "caret", "long", "focus", "long-extra", "long-mismatch", "long-truncated"].contains(mode) else { return }
        let initial = "Anfang ERSETZEN Ende"
        let negative = mode.hasPrefix("long-")
        let insertion = mode.hasPrefix("long") ? String(repeating: "Öffentlicher Absatz. 12,5 bleibt unverändert, nicht 20. 👋\n", count: 400) : "öffentlicher Testtext 👋"
        let previous = NSWorkspace.shared.frontmostApplication
        let cometURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "ai.perplexity.comet")!
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        configuration.addsToRecentItems = false
        let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.open([file], withApplicationAt: cometURL, configuration: configuration) { app, error in
                if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: error ?? NSError(domain: "OwnedComet", code: 1)) }
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
                    if ownDocument(window, file), let candidate = FocusSnapshot.capture(), candidate.baseline.trimmingCharacters(in: .newlines) == initial {
                        target = candidate; break
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let target else { print("{\"passed\":false,\"reason\":\"ownedTargetUnavailable\"}"); return }
        let selected = mode == "caret" ? NSRange(location: (initial as NSString).length, length: 0) : (initial as NSString).range(of: "ERSETZEN")
                let setRange: AXError = target.selectedRange == selected ? .success : .failure
        var selectedReady: FocusSnapshot?
        for _ in 0..<30 {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { break }
            if let candidate = FocusSnapshot.capture(), ownDocument(candidate.window, file), candidate.baseline.trimmingCharacters(in: .newlines) == initial, candidate.selectedRange == selected { selectedReady = candidate; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard setRange == .success, let ready = selectedReady else {
            let details: [String: Any] = ["passed": false, "reason": "selectionUnavailable", "selectionSetAccepted": setRange == .success, "foregroundMatches": NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier]
            print(String(decoding: try JSONSerialization.data(withJSONObject: details, options: [.sortedKeys]), as: UTF8.self)); return
        }
        let before = clipboard()
        var sameWindowFocusChanged = false
        if mode == "focus" {
            var request = URLRequest(url: file.appendingPathComponent("focus")); request.httpMethod = "POST"
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
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
        let outcome = await DeliveryCoordinator().deliver(text: insertion, to: ready, allowClipboard: true)
        let postPasteModifiers = CGEventSource.flagsState(.hidSystemState).rawValue
        let duration = started.duration(to: .now).components
        let expected = mode == "focus" ? ready.baseline : (ready.baseline as NSString).replacingCharacters(in: selected, with: insertion)
        let direct = attribute(ready.element, kAXValueAttribute) as? String
        let ranged = rangedText(ready.element)
        let chunks = chunkReadback(ready.element, expected: expected)
        let textMatches = ownDocument(ready.window, file) && ((fieldText(ready.element)?.trimmingCharacters(in: .newlines) == expected.trimmingCharacters(in: .newlines)) || (chunks["chunkExactMatch"] as? Bool == true && chunks["endVerified"] as? Bool == true))
        // Public synthetic content only. Hashes/lengths diagnose AX representation
        // without storing the clipboard or reading other browser fields.
        let readback: [String: Any] = ["directUTF16Length": direct.map { ($0 as NSString).length } ?? -1,
            "rangeUTF16Length": ranged.map { ($0 as NSString).length } ?? -1,
            "expectedUTF16Length": (expected as NSString).length,
            "directSHA256": hash(direct), "rangeSHA256": hash(ranged), "expectedSHA256": hash(expected),
            "rangedExactMatch": ranged == expected,
            "directIsExpectedPrefix": direct.map { expected.hasPrefix($0) } == true,
            "directNormalizedMatch": direct.map { DeliveryVerification.confirmed(baseline: ready.baseline, selection: selected, insertion: insertion, observed: $0, caret: expectedRangeForReadback(selected, insertion)) } == true,
            "chunks": chunks,
            "rangeNormalizedMatch": ranged.map { DeliveryVerification.confirmed(baseline: ready.baseline, selection: selected, insertion: insertion, observed: $0, caret: expectedRangeForReadback(selected, insertion)) } == true]
        var currentRange = CFRange(location: -1, length: -1)
        if let rawRange = attribute(ready.element, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() { _ = AXValueGetValue(rawRange as! AXValue, .cfRange, &currentRange) }
        let expectedRange = mode == "focus" ? NSRange(location: beforeDeliveryRange.location, length: beforeDeliveryRange.length) : NSRange(location: selected.location + (insertion as NSString).length, length: 0)
        let caretMatches = currentRange.location == expectedRange.location && currentRange.length == expectedRange.length
        let after = clipboard()
        let equal = before != nil && before == after
        let currentApp = AXUIElementCreateApplication(app.processIdentifier)
        let currentWindow = attribute(currentApp, kAXFocusedWindowAttribute)
        let stillOwned = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier && currentWindow.map { CFEqual($0, ready.window) } == true && ownDocument(ready.window, file)
        var closed = false, foregroundRestored = false
        var rendererMatched = false, rendererEventsMatch = false, rendererFocusMatches = false
        for _ in 0..<20 {
            let (stateBytes, _) = try await URLSession.shared.data(from: file.appendingPathComponent("status"))
            if let state = try JSONSerialization.jsonObject(with: stateBytes) as? [String: Any] {
                rendererMatched = state["expectedMatches"] as? Bool == true
                rendererEventsMatch = state["inputEvents"] as? Int == (mode == "focus" ? 0 : 1)
                    && state["pasteEvents"] as? Int == (mode == "focus" ? 0 : 1)
                    && state["submitEvents"] as? Int == 0 && state["otherEmpty"] as? Bool == true
                rendererFocusMatches = state[mode == "focus" ? "activeOther" : "activeTarget"] as? Bool == true
            }
            if rendererMatched { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        if stillOwned && rendererMatched {
            key(13, .maskCommand)
            for _ in 0..<30 {
                let application = AXUIElementCreateApplication(app.processIdentifier)
                if let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement], !windows.contains(where: { ownDocument($0, file) }) { closed = true; break }
                try await Task.sleep(for: .milliseconds(50))
            }
            if closed {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { previous?.activate(options: []) }
                for _ in 0..<30 {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == previous?.processIdentifier { foregroundRestored = true; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        let report: [String: Any] = ["passed": (negative ? outcome.status == .uncertain && !textMatches : (mode == "focus" ? outcome.status == .notAttempted && sameWindowFocusChanged : outcome.status == .confirmed) && textMatches) && (negative || mode == "focus" || caretMatches) && equal && rendererMatched && rendererEventsMatch && rendererFocusMatches && closed && foregroundRestored && (postPasteModifiers & physicalModifiers.rawValue) == 0,
            "postPasteModifiers": postPasteModifiers, "postCleanupModifiers": CGEventSource.flagsState(.hidSystemState).rawValue, "mode": mode, "editor": editor, "sameWindowFocusChanged": sameWindowFocusChanged, "insertionUTF16Length": (insertion as NSString).length,
            "status": outcome.status.rawValue, "readback": readback, "textMatches": textMatches, "rejectedReceiverChange": negative && outcome.status == .uncertain && !textMatches, "caretChecked": !negative && mode != "focus", "caretMatches": negative || mode == "focus" ? NSNull() : caretMatches as Any,
            "clipboardMaterialized": before != nil, "clipboardByteEqual": equal, "clipboardContentsLogged": false,
            "rendererExpectedValueMatched": rendererMatched, "rendererEventCountsMatched": rendererEventsMatch, "rendererFocusMatched": rendererFocusMatches, "closedOwnTab": closed, "foregroundAppRestored": foregroundRestored,
            "deliverySeconds": Double(duration.seconds) + Double(duration.attoseconds)/1e18,
            "scope": "One real guarded Comet Core delivery case; no microphone, physical hotkey, ASR, installed-app recovery UI or full OS matrix/p95 acceptance"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
    }
}
