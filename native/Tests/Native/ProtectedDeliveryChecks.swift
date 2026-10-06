import Foundation
import AppKit
import ApplicationServices
import Carbon
import VoiceWisprCore

/// Owned public test controls only. No actual passwords, microphone or models.
@main struct ProtectedDeliveryChecks {
    @MainActor static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.05)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    @MainActor static func window(_ app: NSRunningApplication, _ file: URL) -> AXUIElement? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let raw = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let window = raw as! AXUIElement
        guard (attribute(window, kAXTitleAttribute) as? String)?.contains(file.lastPathComponent) == true else { return nil }
        return window
    }
    @MainActor static func clipboard() -> [[String: Data]]? {
        let board = NSPasteboard.general, before = board.changeCount
        guard board.pasteboardItems != nil || (board.types ?? []).isEmpty else { return nil }
        var total = 0, result: [[String: Data]] = []
        for item in board.pasteboardItems ?? [] {
            var values: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                total += data.count
                guard total <= 64 * 1024 * 1024 else { return nil }
                values[type.rawValue] = data
            }
            result.append(values)
        }
        return board.changeCount == before ? result : nil
    }
    @MainActor static func state(_ file: URL) async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(from: file.appendingPathComponent("status"))
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    static func untouched(_ state: [String: Any]) -> Bool {
        state["initialMatches"] as? Bool == true && state["expectedMatches"] as? Bool == true
            && state["inputEvents"] as? Int == 0 && state["pasteEvents"] as? Int == 0
            && state["submitEvents"] as? Int == 0 && state["otherEmpty"] as? Bool == true
    }
    @MainActor static func settable(_ field: AXUIElement?, _ name: String) -> Bool? {
        guard let field else { return nil }
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(field, name as CFString, &result) == .success ? result.boolValue : nil
    }
    @MainActor static func main() async throws {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              CGEventSource.flagsState(.hidSystemState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else {
            print("{\"passed\":false,\"reason\":\"existingAXOrInputPreconditionUnavailable\"}"); return
        }
        guard CommandLine.arguments.count >= 3,
              let file = URL(string: CommandLine.arguments[1]), file.scheme == "http", file.host == "127.0.0.1",
              file.lastPathComponent.hasPrefix("AInauten-Voice-Delivery-") else { return }
        let mode = CommandLine.arguments[2]
        guard ["editable-control", "secure", "secure-input", "readonly", "disabled"].contains(mode),
              let comet = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "ai.perplexity.comet") else { return }
        let previous = NSWorkspace.shared.frontmostApplication
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true; configuration.addsToRecentItems = false
        let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.open([file], withApplicationAt: comet, configuration: configuration) { app, error in
                if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: error ?? NSError(domain: "OwnedProtectedControl", code: 1)) }
            }
        }
        WebAccessibility.enable(for: app)
        var ownedWindow: AXUIElement?
        for _ in 0..<60 {
            if let owned = window(app, file), untouched(try await state(file)) { ownedWindow = owned; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let ownedWindow else { print("{\"passed\":false,\"reason\":\"ownedControlUnavailable\"}"); return }
        try await Task.sleep(for: .milliseconds(200))
        let rendererBefore = try await state(file)
        guard untouched(rendererBefore), rendererBefore[mode == "disabled" ? "activeOther" : "activeTarget"] as? Bool == true,
              window(app, file).map({ CFEqual($0, ownedWindow) }) == true else {
            print("{\"passed\":false,\"reason\":\"ownedControlFocusUnavailable\"}"); return
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let rawField = attribute(application, kAXFocusedUIElementAttribute)
        let field = rawField.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        let role = field.flatMap { attribute($0, kAXRoleAttribute) as? String }
        let subrole = field.flatMap { attribute($0, kAXSubroleAttribute) as? String }
        let valueSettable = settable(field, kAXValueAttribute), selectionSettable = settable(field, kAXSelectedTextAttribute)
        let secureBefore = IsSecureEventInputEnabled()
        let target = FocusSnapshot.capture()
        let boardCount = NSPasteboard.general.changeCount, saved = clipboard()
        guard saved != nil else { print("{\"passed\":false,\"reason\":\"clipboardNotMaterializable\"}"); return }
        var enabledByUs = false, enableStatus: OSStatus = 0, disableStatus: OSStatus = 0
        defer { if enabledByUs { _ = DisableSecureEventInput() } }
        if mode == "secure-input" {
            guard !secureBefore, target != nil else { print("{\"passed\":false,\"reason\":\"secureInputControlNotPrepared\"}"); return }
            enableStatus = EnableSecureEventInput(); enabledByUs = enableStatus == noErr
        }
        let secureDuring = IsSecureEventInputEnabled()
        let capturedDuringSecure = mode == "secure-input" ? FocusSnapshot.capture() != nil : target != nil
        let outcome = mode == "editable-control" ? nil : await DeliveryCoordinator().deliver(text: "Öffentlicher Testtext", to: target)
        let postDeliveryModifiers = CGEventSource.flagsState(.hidSystemState).rawValue
        if enabledByUs { disableStatus = DisableSecureEventInput(); enabledByUs = false }
        let secureRestored = IsSecureEventInputEnabled() == secureBefore
        let sameClipboardCount = NSPasteboard.general.changeCount == boardCount
        let byteEqual = saved == clipboard()
        let after = try await state(file)
        let noMutation = untouched(after)
        let sameWindow = window(app, file).map { CFEqual($0, ownedWindow) } == true
        var closed = false, restored = false
        // Close only this exact owned tab when its public contents stayed intact.
        if sameWindow && after["initialMatches"] as? Bool == true && after["otherEmpty"] as? Bool == true && after["submitEvents"] as? Int == 0 {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: true)!
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: false)!
            down.flags = .maskCommand; up.flags = []
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            for _ in 0..<30 {
                if let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement], !windows.contains(where: { (attribute($0, kAXTitleAttribute) as? String)?.contains(file.lastPathComponent) == true }) { closed = true; break }
                try await Task.sleep(for: .milliseconds(50))
            }
            if closed {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { previous?.activate(options: []) }
                for _ in 0..<30 {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == previous?.processIdentifier { restored = true; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        let rejected = mode == "editable-control" ? target != nil : outcome?.status == .notAttempted && outcome?.inputWasSubmitted == false
        let secureProof = mode != "secure-input" || enableStatus == noErr && disableStatus == noErr && secureDuring && !capturedDuringSecure && secureRestored
        let report: [String: Any] = ["passed": rejected && noMutation && sameClipboardCount && byteEqual && sameWindow && closed && restored && secureProof,
            "mode": mode, "role": role ?? "unavailable", "subrole": subrole ?? "unavailable", "valueSettable": valueSettable.map { $0 as Any } ?? NSNull(), "selectedTextSettable": selectionSettable.map { $0 as Any } ?? NSNull(),
            "snapshotAvailable": target != nil, "status": outcome?.status.rawValue ?? "controlOnly", "inputWasSubmitted": outcome?.inputWasSubmitted ?? false,
            "clipboardChangeCountUnchanged": sameClipboardCount, "clipboardByteEqual": byteEqual, "clipboardContentsLogged": false,
            "secureBefore": secureBefore, "secureDuring": secureDuring, "secureRestored": secureRestored, "enableStatus": enableStatus, "disableStatus": disableStatus,
            "snapshotAvailableDuringSecure": capturedDuringSecure, "postDeliveryModifiers": postDeliveryModifiers,
            "rendererUntouched": noMutation, "sameOwnedWindow": sameWindow, "closedOwnTab": closed, "foregroundAppRestored": restored,
            "microphoneUsed": false, "modelsLoaded": false]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
