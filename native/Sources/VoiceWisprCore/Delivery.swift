import Foundation
import AppKit
import ApplicationServices
import Carbon

public struct ClipboardOwnership: Sendable, Equatable {
    public let nonce: UUID
    public let changeCount: Int
    public init(nonce: UUID = UUID(), changeCount: Int) { self.nonce = nonce; self.changeCount = changeCount }
    public func owns(changeCount: Int, nonce: UUID?) -> Bool { self.changeCount == changeCount && self.nonce == nonce }
}

public enum DeliveryVerification {
    public static func expectedValue(baseline: String, selection: NSRange, insertion: String) -> String? {
        let value = baseline as NSString
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
              selection.location <= value.length, selection.length <= value.length - selection.location else { return nil }
        return value.replacingCharacters(in: selection, with: insertion)
    }
    public static func confirmed(baseline: String, selection: NSRange, insertion: String, observed: String?, caret: NSRange?) -> Bool {
        guard let expected = expectedValue(baseline: baseline, selection: selection, insertion: insertion) else { return false }
        let caretTarget = selection.location + (insertion as NSString).length
        if observed == expected && caret == NSRange(location: caretTarget, length: 0) { return true }
        // Web and rich-text editors store the same text with other separators
        // (CRLF, U+2028, NBSP, a trailing paragraph newline). Accept only that
        // representation difference, never a different word sequence.
        guard let observed, normalized(observed) == normalized(expected) else { return false }
        // A changed, complete expected field value proves the insertion even
        // when an editor omits or delays its selection/caret AX update.
        // The coordinator separately requires the original app/window/field.
        if normalized(expected) != normalized(baseline) { return true }
        // An unchanged/no-op replacement needs the cursor evidence as before.
        guard let caret, caret.length == 0 else { return false }
        let drift = abs((observed as NSString).length - (expected as NSString).length)
        return abs(caret.location - caretTarget) <= drift
    }
    static func normalized(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\r\n", with: "\n")
        for separator in ["\r", "\u{2028}", "\u{2029}"] { value = value.replacingOccurrences(of: separator, with: "\n") }
        value = value.replacingOccurrences(of: "\u{00A0}", with: " ")
        while value.hasSuffix("\n") { value.removeLast() }
        return value.precomposedStringWithCanonicalMapping
    }
}

/// Electron and Chromium apps build their accessibility tree only for an
/// assistive client that asks for it. Without it the focused text field has no
/// readable value and every dictation there ends in the recovery window.
@MainActor public enum WebAccessibility {
    private static var enabled = Set<pid_t>()
    public static func enable(for app: NSRunningApplication?) {
        guard let app, AXIsProcessTrusted(), !enabled.contains(app.processIdentifier),
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        enabled.insert(app.processIdentifier)
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.05)
        // Unsupported apps return an error; the attribute has no other effect.
        _ = AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}

@MainActor public struct FocusSnapshot {
    public let pid: pid_t
    public let bundleID: String?
    public let window: AXUIElement
    public let element: AXUIElement
    public let selectedRange: NSRange
    public let baseline: String
    public let secure: Bool
    public static func capture() -> FocusSnapshot? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        WebAccessibility.enable(for: app)
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.05)
        guard let window = AXAccess.element(application, kAXFocusedWindowAttribute),
              let field = AXAccess.element(application, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.05)
        AXUIElementSetMessagingTimeout(field, 0.05)
        let subrole = AXAccess.string(field, kAXSubroleAttribute) ?? ""
        let role = AXAccess.string(field, kAXRoleAttribute) ?? ""
        let secure = subrole == kAXSecureTextFieldSubrole || role == kAXSecureTextFieldSubrole || IsSecureEventInputEnabled()
        guard !secure, let baseline = AXAccess.string(field, kAXValueAttribute) ?? AXAccess.fullRangeText(field), let range = AXAccess.range(field),
              DeliveryVerification.expectedValue(baseline: baseline, selection: range, insertion: "") != nil else { return nil }
        return FocusSnapshot(pid: app.processIdentifier, bundleID: app.bundleIdentifier, window: window, element: field, selectedRange: range, baseline: baseline, secure: secure)
    }
    public func isUnchanged() -> Bool {
        guard !secure, !IsSecureEventInputEnabled(), let current = Self.capture() else { return false }
        return !current.secure && current.pid == pid && current.bundleID == bundleID && CFEqual(current.window, window)
            && CFEqual(current.element, element) && current.selectedRange == selectedRange && current.baseline == baseline
    }
    public var selection: NSRange { selectedRange }
}

@MainActor enum AXAccess {
    static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
    static func string(_ element: AXUIElement, _ name: String) -> String? { value(element, name) as? String }
    /// Some rich-text editors omit or lag AXValue while exposing their complete
    /// text through the standard range attributes. Read only this original field.
    static func fullRangeText(_ element: AXUIElement) -> String? {
        guard let count = value(element, kAXNumberOfCharactersAttribute) as? NSNumber,
              count.intValue >= 0, count.intValue <= 4_000_000 else { return nil }
        var range = CFRange(location: 0, length: count.intValue)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        for attribute in [kAXStringForRangeParameterizedAttribute, kAXAttributedStringForRangeParameterizedAttribute] {
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &result) == .success else { continue }
            if let text = result as? String { return text }
            if let text = result as? NSAttributedString { return text.string }
        }
        return nil
    }
    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let result = value(element, name), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    static func range(_ element: AXUIElement) -> NSRange? {
        guard let result = value(element, kAXSelectedTextRangeAttribute), CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        let axValue = result as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    static func settable(_ element: AXUIElement, _ name: String) -> Bool {
        var flag: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &flag) == .success && flag.boolValue
    }
}

/// nspasteboard.org conventions: clipboard managers (Maccy, Raycast, Paste) skip
/// marked items, so dictated text written only for insertion is never archived.
public enum TransientPasteboard {
    public static let types: [NSPasteboard.PasteboardType] = [.init("org.nspasteboard.TransientType"), .init("org.nspasteboard.AutoGeneratedType")]
    @discardableResult public static func mark(_ item: NSPasteboardItem) -> Bool { types.allSatisfy { item.setData(Data(), forType: $0) } }
}

@MainActor struct ClipboardSnapshot {
    static let nonceType = NSPasteboard.PasteboardType("com.mediapublishing.VoiceWispr.delivery-nonce")
    let items: [[NSPasteboard.PasteboardType: Data]]
    let changeCount: Int
    /// Our own temporary write: text, ownership nonce and the transient markers.
    static func ownedItem(_ text: String, nonce: UUID, transient: Bool = true) -> NSPasteboardItem? {
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string), item.setString(nonce.uuidString, forType: nonceType), !transient || TransientPasteboard.mark(item) else { return nil }
        return item
    }
    static func capture(_ board: NSPasteboard) -> ClipboardSnapshot? {
        let before = board.changeCount
        guard board.pasteboardItems != nil || (board.types ?? []).isEmpty else { return nil }
        var total = 0, items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in board.pasteboardItems ?? [] {
            var saved: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                total += data.count
                guard total <= 64 * 1024 * 1024 else { return nil }
                saved[type] = data
            }
            items.append(saved)
        }
        guard before == board.changeCount else { return nil }
        return ClipboardSnapshot(items: items, changeCount: before)
    }
    @discardableResult func restore(_ board: NSPasteboard, ownership: ClipboardOwnership) -> Bool {
        let nonce = board.string(forType: Self.nonceType).flatMap(UUID.init(uuidString:))
        guard ownership.owns(changeCount: board.changeCount, nonce: nonce) else { return false }
        let restored = items.map { saved in
            let item = NSPasteboardItem()
            for (type, data) in saved { item.setData(data, forType: type) }
            return item
        }
        let current = Self.capture(board)
        guard ownership.owns(changeCount: board.changeCount, nonce: board.string(forType: Self.nonceType).flatMap(UUID.init(uuidString:))) else { return false }
        let clearedAt = board.clearContents()
        guard board.changeCount == clearedAt else { return false }
        if restored.isEmpty || board.writeObjects(restored) { return true }
        current?.restoreAfterFailedWrite(board, clearedAt: clearedAt, nonce: ownership.nonce)
        return false
    }
    func restoreAfterFailedWrite(_ board: NSPasteboard, clearedAt: Int, nonce: UUID) {
        guard board.changeCount == clearedAt else { return }
        if board.string(forType: Self.nonceType) == nonce.uuidString {
            restore(board, ownership: ClipboardOwnership(nonce: nonce, changeCount: clearedAt))
        } else if (board.types ?? []).isEmpty {
            let restored = items.map { saved in
                let item = NSPasteboardItem()
                for (type, data) in saved { item.setData(data, forType: type) }
                return item
            }
            board.clearContents()
            if !restored.isEmpty { board.writeObjects(restored) }
        }
    }
}

public enum ClipboardCopyResult: Equatable, Sendable { case copied, unavailable, failed }
public enum ClipboardUndoResult: Equatable, Sendable { case restored, changed, failed }

/// One reversible clipboard write. The complete previous contents stay in RAM;
/// a newer copy, even of identical text, permanently invalidates this undo.
@MainActor public final class ClipboardRecovery {
    private let board: NSPasteboard
    private var saved: ClipboardSnapshot?
    private var ownership: ClipboardOwnership?
    public init(board: NSPasteboard = .general) { self.board = board }
    public var canUndo: Bool {
        guard saved != nil, let ownership else { return false }
        let nonce = board.string(forType: ClipboardSnapshot.nonceType).flatMap(UUID.init(uuidString:))
        return ownership.owns(changeCount: board.changeCount, nonce: nonce)
    }
    /// `transient: false` for an explicit user copy, which clipboard managers may keep.
    @discardableResult public func copy(_ text: String, transient: Bool = true) -> ClipboardCopyResult {
        // Re-clicking the copy icon must keep the original undo snapshot.
        if canUndo, board.string(forType: .string) == text { return .copied }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let previous = ClipboardSnapshot.capture(board) else { return .unavailable }
        let nonce = UUID()
        guard let item = ClipboardSnapshot.ownedItem(text, nonce: nonce, transient: transient), board.changeCount == previous.changeCount else { return .unavailable }
        let clearedAt = board.clearContents()
        guard board.changeCount == clearedAt else { return .unavailable }
        guard board.writeObjects([item]) else {
            previous.restoreAfterFailedWrite(board, clearedAt: clearedAt, nonce: nonce)
            return .failed
        }
        saved = previous; ownership = ClipboardOwnership(nonce: nonce, changeCount: board.changeCount)
        return .copied
    }
    @discardableResult public func undo() -> ClipboardUndoResult {
        guard canUndo, let saved, let ownership else { discardUndo(); return .changed }
        let restored = saved.restore(board, ownership: ownership)
        discardUndo()
        return restored ? .restored : .failed
    }
    public func discardUndo() { saved = nil; ownership = nil }
}

@MainActor public struct DeliveryCoordinator {
    public init() {}
    /// Browser/Electron fields can advertise writable selected text yet ignore
    /// the AX operation. Use paste for these apps on the first attempt, never
    /// as a retry after an ambiguous write. Native TextEdit retains its path.
    public static func usesDirectSelection(bundleID: String?, role: String?) -> Bool {
        bundleID == "com.apple.TextEdit" && (role == kAXTextFieldRole || role == kAXTextAreaRole)
    }
    public func preflight(targetReadable: Bool, secure: Bool, focusUnchanged: Bool) -> DeliveryOutcome {
        guard targetReadable && !secure && focusUnchanged else { return DeliveryOutcome(.notAttempted, reason: "Ziel nicht sicher verifizierbar; Text steht zur Wiederherstellung bereit.") }
        return DeliveryOutcome(.uncertain, reason: "Ziel geprüft; Zustellung muss noch bestätigt werden.")
    }
    public func deliver(text: String, to target: FocusSnapshot?) async -> DeliveryOutcome {
        guard !Task.isCancelled else { return DeliveryOutcome(.notAttempted, reason: "Diktat verworfen") }
        guard !text.isEmpty, let target, target.isUnchanged() else {
            return DeliveryOutcome(.notAttempted, reason: "Fokus, Auswahl oder Textfeld haben sich verändert. Text aus dem Wiederherstellungsfenster verwenden.")
        }
        let role = AXAccess.string(target.element, kAXRoleAttribute)
        let selected = AXAccess.string(target.element, kAXSelectedTextAttribute)
        let expectedSelected = (target.baseline as NSString).substring(with: target.selectedRange)
        // Use a single selected-text operation only when native AX explicitly exposes the exact selection.
        if Self.usesDirectSelection(bundleID: target.bundleID, role: role), selected == expectedSelected,
           AXAccess.settable(target.element, kAXSelectedTextAttribute) {
            #if DEBUG
            if CommandLine.arguments.contains("--test-delivery") { print("DELIVERY_TEST_METHOD selectedText"); fflush(stdout) }
            #endif
            guard !Task.isCancelled, target.isUnchanged() else { return DeliveryOutcome(.notAttempted, reason: "Ziel verändert oder Diktat verworfen") }
            let result = AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, text as CFString)
            guard result == .success else { return DeliveryOutcome(.uncertain, reason: "Textoperation nicht bestätigt; keine automatische Wiederholung.") }
            return await verify(text: text, target: target)
        }
        #if DEBUG
        if CommandLine.arguments.contains("--test-delivery") { print("DELIVERY_TEST_METHOD paste"); fflush(stdout) }
        #endif
        let board = NSPasteboard.general
        let releaseDeadline = ContinuousClock.now.advanced(by: .milliseconds(1500))
        let physicalModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        while !CGEventSource.flagsState(.hidSystemState).intersection(physicalModifiers).isEmpty {
            guard ContinuousClock.now < releaseDeadline, !Task.isCancelled else { return DeliveryOutcome(.notAttempted, reason: "Tastenkürzel noch gehalten; Text bitte aus dem Ergebnisfenster kopieren.") }
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return DeliveryOutcome(.notAttempted, reason: "Diktat verworfen") }
        }
        guard let saved = ClipboardSnapshot.capture(board), let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return DeliveryOutcome(.notAttempted, reason: "Zwischenablage oder Ziel nicht sicher lesbar. Wiederherstellung verwenden.")
        }
        guard !Task.isCancelled, target.isUnchanged(), board.changeCount == saved.changeCount else { return DeliveryOutcome(.notAttempted, reason: "Ziel oder Zwischenablage verändert") }
        let nonce = UUID()
        guard let item = ClipboardSnapshot.ownedItem(text, nonce: nonce) else { return DeliveryOutcome(.notAttempted, reason: "Zwischenablage oder Ziel nicht sicher lesbar. Wiederherstellung verwenden.") }
        let clearedAt = board.clearContents()
        guard board.writeObjects([item]) else {
            saved.restoreAfterFailedWrite(board, clearedAt: clearedAt, nonce: nonce)
            return DeliveryOutcome(.failed, reason: "Zwischenablage konnte nicht geschrieben werden")
        }
        let ownership = ClipboardOwnership(nonce: nonce, changeCount: board.changeCount)
        guard !Task.isCancelled, target.isUnchanged() else { saved.restore(board, ownership: ownership); return DeliveryOutcome(.notAttempted, reason: "Ziel verändert oder Diktat verworfen") }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        let outcome = await verify(text: text, target: target)
        saved.restore(board, ownership: ownership)
        return outcome
    }
    private func verify(text: String, target: FocusSnapshot) async -> DeliveryOutcome {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(1500))
        var focusChanged = false
        while ContinuousClock.now < deadline {
            if let app = NSWorkspace.shared.frontmostApplication {
                if app.processIdentifier != target.pid { focusChanged = true }
                else {
                    let application = AXUIElementCreateApplication(app.processIdentifier)
                    AXUIElementSetMessagingTimeout(application, 0.05)
                    if let window = AXAccess.element(application, kAXFocusedWindowAttribute),
                       let field = AXAccess.element(application, kAXFocusedUIElementAttribute) {
                        AXUIElementSetMessagingTimeout(field, 0.05)
                        if !CFEqual(window, target.window) || !CFEqual(field, target.element) || IsSecureEventInputEnabled() { focusChanged = true }
                        else if !focusChanged {
                            let caret = AXAccess.range(field)
                            let direct = AXAccess.string(field, kAXValueAttribute)
                            if DeliveryVerification.confirmed(baseline: target.baseline, selection: target.selectedRange, insertion: text, observed: direct, caret: caret) {
                                return DeliveryOutcome(.confirmed, reason: "Vollständiger Text im ursprünglichen Ziel bestätigt. macOS bietet keine atomare Fokus-/Einfügeoperation.", inputWasSubmitted: true)
                            }
                            if ContinuousClock.now < deadline,
                               let ranged = AXAccess.fullRangeText(field),
                               DeliveryVerification.confirmed(baseline: target.baseline, selection: target.selectedRange, insertion: text, observed: ranged, caret: caret) {
                                return DeliveryOutcome(.confirmed, reason: "Vollständiger Text über den ursprünglichen Textbereich bestätigt.", inputWasSubmitted: true)
                            }
                        }
                    }
                }
            }
            // Unknown AX reads are retried as observations, never as a second insertion.
            // Keep our pasteboard payload until the bounded deadline so queued paste can consume it.
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { break }
            let pause = min(Duration.milliseconds(50), remaining)
            // The paste was already posted. Cancellation must not restore unrelated
            // clipboard bytes while the target may still consume the queued event.
            // This observation-only delay is bounded and does not enqueue another paste.
            await Task.detached(priority: .utility) { try? await Task.sleep(for: pause) }.value
        }
        if focusChanged { return DeliveryOutcome(.uncertain, reason: "Fokus während der Zustellung verändert. Keine automatische Wiederholung.", inputWasSubmitted: true) }
        return DeliveryOutcome(.uncertain, reason: "Das Einfügen konnte nicht bestätigt werden. Prüfe das Textfeld, bevor du den Text erneut einfügst.", inputWasSubmitted: true)
    }
}
