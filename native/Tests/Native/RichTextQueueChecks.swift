import Foundation
import AppKit
import ApplicationServices
import VoiceWisprCore

/// Own isolated editor, never the protected Codex UI or a user document.
@MainActor final class QueueRichTextView: NSTextView {
    var delayCaret = false
    var pasteOnly = false
    var truncatedValue = false
    var inconsistentCaret = false
    var unavailableText = false
    var unavailableCaret = false
    private(set) var staleCaretReads = 0
    private var readbackAfter: TimeInterval = 0
    func delayReadback() { if delayCaret { readbackAfter = ProcessInfo.processInfo.systemUptime + 0.18 } }
    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        insertText(text, replacementRange: selectedRange())
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let value = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        super.insertText(value.replacingOccurrences(of: " ", with: "\u{00A0}"), replacementRange: replacementRange)
        delayReadback()
    }
    override func accessibilitySelectedTextRange() -> NSRange {
        if unavailableCaret { return NSRange(location: NSNotFound, length: 0) }
        if ProcessInfo.processInfo.systemUptime < readbackAfter { staleCaretReads += 1; return NSRange(location: 0, length: 0) }
        let range = super.accessibilitySelectedTextRange()
        return inconsistentCaret ? NSRange(location: range.location + 1, length: range.length) : range
    }
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if pasteOnly && [NSSelectorFromString("setAccessibilityValue:"), NSSelectorFromString("setAccessibilitySelectedText:")].contains(selector) { return false }
        return super.isAccessibilitySelectorAllowed(selector)
    }
    override func accessibilityValue() -> String? { unavailableText ? nil : truncatedValue ? "" : super.accessibilityValue() }
    override func accessibilityNumberOfCharacters() -> Int { unavailableText ? -1 : super.accessibilityNumberOfCharacters() }
    override func accessibilityIsAttributeSettable(_ attribute: NSAccessibility.Attribute) -> Bool {
        if pasteOnly && [NSAccessibility.Attribute.value, .selectedText].contains(attribute) { return false }
        return super.accessibilityIsAttributeSettable(attribute)
    }
}

@main struct RichTextQueueChecks {
    @MainActor static func clipboard() -> [[String: Data]]? {
        let board = NSPasteboard.general, count = board.changeCount
        guard board.pasteboardItems != nil || (board.types ?? []).isEmpty else { return nil }
        var total = 0, values: [[String: Data]] = []
        for item in board.pasteboardItems ?? [] {
            var value: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                total += data.count; guard total <= 64 * 1024 * 1024 else { return nil }
                value[type.rawValue] = data
            }
            values.append(value)
        }
        return board.changeCount == count ? values : nil
    }
    @MainActor static func main() {
        guard AXIsProcessTrusted() else { print("{\"passed\":false,\"reason\":\"existingAXUnavailable\"}"); return }
        guard CGEventSource.flagsState(.hidSystemState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else {
            print("{\"passed\":false,\"reason\":\"physicalModifiersHeldBeforeOpening\"}"); return
        }
        let app = NSApplication.shared
        _ = app.setActivationPolicy(.regular)
        let mode = CommandLine.arguments.dropFirst().first ?? "normalized"
        let menu = NSMenu(), application = NSMenuItem(), edit = NSMenuItem()
        application.submenu = NSMenu(title: "Queue fixture"); menu.addItem(application)
        edit.submenu = NSMenu(title: "Edit")
        edit.submenu?.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu?.autoenablesItems = false
        edit.submenu?.items.first?.isEnabled = mode != "read-only"
        menu.addItem(edit); app.mainMenu = menu
        let previous = NSWorkspace.shared.frontmostApplication
        let view = QueueRichTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 280))
        view.isRichText = false; view.isEditable = mode != "read-only"; view.isSelectable = true
        view.pasteOnly = mode == "paste-only" || mode == "read-only"
        view.truncatedValue = mode == "range-value"
        if view.truncatedValue { view.string = "Anfang. "; view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0)) }
        view.inconsistentCaret = mode.hasPrefix("unmapped-caret")
        view.unavailableText = mode == "unreadable-text"
        view.unavailableCaret = mode == "unreadable-caret"
        if view.inconsistentCaret || view.unavailableText || view.unavailableCaret {
            view.string = "."; view.setSelectedRange(NSRange(location: 1, length: 0))
        }
        view.delayCaret = CommandLine.arguments.contains("delayed") || CommandLine.arguments.contains("cancelled")
        let window = NSWindow(contentRect: NSRect(x: 300, y: 220, width: 600, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "AInauten Voice – eigener Rich-Text-Test"
        window.contentView = view
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
        app.activate(ignoringOtherApps: true)
        Task { @MainActor in
            let report = await check(view: view, window: window)
            window.close()
            _ = previous?.activate(options: [])
            print(String(data: try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
            fflush(stdout)
            exit(report["passed"] as? Bool == true ? 0 : 1)
        }
        app.run()
    }
    @MainActor static func check(view: QueueRichTextView, window: NSWindow) async -> [String: Any] {
        let mode = CommandLine.arguments.dropFirst().first ?? "normalized"
        for _ in 0..<60 {
            if NSApp.isActive && window.isKeyWindow && window.firstResponder === view { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard NSApp.isActive, window.isKeyWindow, window.firstResponder === view else {
            return ["passed": false, "reason": "ownEditorNotReadyForKeyboard", "appActive": NSApp.isActive,
                    "windowKey": window.isKeyWindow, "responderIsView": window.firstResponder === view]
        }
        // Let AppKit finish activation before posting the fixture's first key.
        try? await Task.sleep(for: .milliseconds(300))
        if mode == "read-only" {
            let count = NSPasteboard.general.changeCount
            let target = FocusSnapshot.capture(expectedPID: getpid())
            let outcome = await DeliveryCoordinator().deliver(text: "Kein Einfügen", to: target, allowClipboard: true)
            return ["passed": target == nil && !outcome.inputWasSubmitted && view.string.isEmpty && NSPasteboard.general.changeCount == count,
                    "scope": "Read-only field must never receive paste", "targetCaptured": target != nil]
        }
        var first: FocusSnapshot?
        for _ in 0..<60 {
            if let snapshot = FocusSnapshot.capture(expectedPID: getpid()),
               view.unavailableText ? snapshot.baseline == nil : snapshot.baseline == view.string { first = snapshot; break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let first else { return ["passed": false, "reason": "ownEditorNotFocused"] }
        guard let before = clipboard() else { return ["passed": false, "reason": "clipboardUnavailable"] }
        if view.inconsistentCaret || view.unavailableText || view.unavailableCaret {
            guard first.baseline == (view.unavailableText ? nil : "."),
                  first.selectedRange == NSRange(location: view.unavailableCaret ? NSNotFound : view.inconsistentCaret ? 2 : 1, length: 0) else {
                return ["passed": false, "reason": "inconsistentCaretNotReproduced"]
            }
            let boardCount = NSPasteboard.general.changeCount
            var other: NSTextView?
            if mode == "unmapped-caret-moved" { view.setSelectedRange(NSRange(location: 0, length: 0)) }
            if mode == "unmapped-caret-field" {
                other = NSTextView(frame: view.frame)
                window.contentView = other; window.makeFirstResponder(other)
            }
            let allowed = ["unmapped-caret", "unreadable-text", "unreadable-caret"].contains(mode)
            let outcome = await DeliveryCoordinator().deliver(text: "Weiter.", to: first,
                allowClipboard: mode != "unmapped-caret-no-clipboard")
            let advanced = await first.afterConfirmedInsertion("Weiter.")
            return ["passed": outcome.status == (allowed ? .uncertain : .notAttempted)
                    && outcome.inputWasSubmitted == allowed && !outcome.shouldShowRecovery == allowed
                    && view.string == (allowed ? ".Weiter." : ".") && advanced == nil
                    && clipboard() == before && (allowed || NSPasteboard.general.changeCount == boardCount)
                    && (other == nil || other?.string.isEmpty == true),
                "mode": mode, "status": outcome.status.rawValue, "inputWasSubmitted": outcome.inputWasSubmitted,
                "clipboardByteEqual": clipboard() == before, "clipboardContentsLogged": false,
                "scope": "Owned editor with inconsistent or unavailable AX text/caret; one paste without added spacing, unchanged-field and clipboard guards"]
        }
        let texts = ["Erster Abschnitt.", "Second part.", "Troisième partie."]
        var targets = [first, first, first]
        var statuses: [String] = []
        var rebases = 0
        var advanceSeconds: TimeInterval = 0
        var expected = view.string
        for i in texts.indices {
            let target = targets[i]
            let text = i == 0 ? texts[i] : DeliveryVerification.queuedContinuationText(texts[i], baseline: target.baseline, selection: target.selectedRange)
            let outcome = await DeliveryCoordinator().deliver(text: text, to: target, allowClipboard: true)
            statuses.append(outcome.status.rawValue)
            guard outcome.status == .confirmed else { return ["passed": false, "reason": "delivery", "statuses": statuses,
                "deliveryReason": outcome.reason, "characters": view.string.utf16.count, "clipboardByteEqual": clipboard() == before] }
            expected += (i == 0 ? "" : " ") + texts[i]
            // Start the stale AX caret after the paste is confirmed, so the
            // continuation check itself must wait, rather than only verify().
            view.delayReadback()
            var alternate: NSTextView?
            if i == 0 && mode == "moved" { view.setSelectedRange(NSRange(location: 0, length: 0)) }
            if i == 0 && mode == "field" {
                let other = NSTextView(frame: view.frame); alternate = other
                window.contentView = other; window.makeFirstResponder(other)
            }
            let advancement = Task { await target.afterConfirmedInsertion(text) }
            let advanceStarted = ProcessInfo.processInfo.systemUptime
            if i == 0 && mode == "cancelled" { try? await Task.sleep(for: .milliseconds(40)); advancement.cancel() }
            let advanced = await advancement.value
            advanceSeconds += ProcessInfo.processInfo.systemUptime - advanceStarted
            if i == 0 && ["moved", "field", "cancelled"].contains(mode) {
                return ["passed": advanced == nil && clipboard() == before && view.string.replacingOccurrences(of: "\u{00A0}", with: " ") == expected && (alternate == nil || alternate?.string.isEmpty == true),
                    "statuses": statuses, "reason": "unsafeContinuationRefused", "clipboardByteEqual": clipboard() == before,
                    "clipboardContentsLogged": false, "mode": mode]
            }
            guard let advanced else {
                return ["passed": false, "reason": "confirmedButCannotAdvance", "statuses": statuses,
                    "editorRewritesSpaces": view.string.contains("\u{00A0}"), "delayedCaret": view.delayCaret,
                    "confirmedTextMatches": view.string.replacingOccurrences(of: "\u{00A0}", with: " ") == expected,
                    "clipboardContentsLogged": false, "clipboardByteEqual": clipboard() == before]
            }
            rebases += 1
            for next in texts.indices where next > i {
                guard targets[next].matches(target) else { return ["passed": false, "reason": "unexpectedSnapshot"] }
                targets[next] = advanced
            }
        }
        return ["passed": statuses == ["confirmed", "confirmed", "confirmed"] && view.string.contains("\u{00A0}") && view.string.replacingOccurrences(of: "\u{00A0}", with: " ") == expected && clipboard() == before && (!view.delayCaret || (view.staleCaretReads > 0 && advanceSeconds >= 0.3)),
            "statuses": statuses, "rebases": rebases, "editorRewritesSpaces": view.string.contains("\u{00A0}"),
            "delayedCaret": view.delayCaret, "clipboardContentsLogged": false,
            "staleCaretReads": view.staleCaretReads, "advanceSeconds": advanceSeconds,
            "clipboardByteEqual": clipboard() == before,
            "scope": "Own native NSTextView with NBSP rewriting and optional delayed AX caret; actual clipboard insertion, no microphone, no Codex automation"]
    }
}
