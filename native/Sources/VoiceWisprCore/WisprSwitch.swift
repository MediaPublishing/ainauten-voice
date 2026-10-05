import Foundation
import AppKit
import ApplicationServices

public enum WisprSwitchStatus: Sendable { case completed, pending, unsupported, failed }
public struct WisprSwitchOutcome: Sendable {
    public let status: WisprSwitchStatus
    public let reason: String
    public init(_ status: WisprSwitchStatus, _ reason: String) { self.status = status; self.reason = reason }
}

@MainActor public struct WisprSwitch {
    public static let bundleID = "com.electron.wispr-flow"
    public let applicationURL: URL
    public let configURL: URL
    public init(applicationURL: URL? = nil, configURL: URL = URL(fileURLWithPath: ("~/Library/Application Support/Wispr Flow/config.json" as NSString).expandingTildeInPath)) {
        self.applicationURL = applicationURL ?? Self.installedURL ?? URL(fileURLWithPath: "/Applications/Wispr Flow.app"); self.configURL = configURL
    }
    /// Wispr Flow may live in ~/Applications or elsewhere; Launch Services knows the bundle.
    public static var installedURL: URL? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
    public func switchFromWispr() async -> WisprSwitchOutcome {
        guard let bundle = Bundle(url: applicationURL), bundle.bundleIdentifier == Self.bundleID else {
            return WisprSwitchOutcome(.pending, "Wispr Flow wurde nicht am erwarteten Installationsort gefunden. Autostart und laufenden Prozess manuell prüfen.")
        }
        // Rechecking a finished switch must not reopen Wispr to request AX access.
        if loginPreference() == false, NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty {
            return WisprSwitchOutcome(.completed, "Wispr-Flow-Autostart ist ausgeschaltet und Wispr Flow läuft nicht.")
        }
        // A user may reopen Flow after completing the switch. Its already-disabled
        // login preference needs no new AX action; a regular quit needs no AX right.
        if loginPreference() == false, let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first {
            guard app.terminate() else { return pending("Autostart ist aus; Wispr Flow konnte noch nicht regulär beendet werden.") }
            for _ in 0..<60 {
                if NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty {
                    guard loginPreference() == false else { return pending("Wispr Flow ist beendet; Autostart muss erneut geprüft werden.") }
                    return WisprSwitchOutcome(.completed, "Wispr-Flow-Autostart war bereits ausgeschaltet. Wispr Flow wurde regulär beendet.")
                }
                do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
            }
            return pending("Autostart ist aus; Wispr Flow läuft weiterhin.")
        }
        guard bundle.infoDictionary?["CFBundleShortVersionString"] as? String == "1.6.1034", AXIsProcessTrusted() else {
            await openGuidedSettings()
            return WisprSwitchOutcome(.pending, "Wispr Flow öffnen: Settings → System → Launch app at login ausschalten, dann Wispr Flow beenden. Version oder Bedienungshilfen sind nicht verifiziert.")
        }
        let app: NSRunningApplication
        do {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first { app = running; app.activate(options: [.activateAllWindows]) }
            else { app = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: NSWorkspace.OpenConfiguration()) }
        } catch { return WisprSwitchOutcome(.pending, "Wispr Flow konnte nicht geöffnet werden; Wechsel manuell abschließen.") }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, Self.messagingTimeout)
        // The adapter is restricted to the UI observed on installed Wispr 1.6.1034.
        if find(root, role: kAXCheckBoxRole, labels: ["Launch app at login"]) == nil {
            guard await pressAndFind(root, labels: ["Settings", "Settings…", "Settings...", "Preferences…"], nextRole: nil, nextLabels: ["System"]) else {
                await openGuidedSettings(); return pending("Wispr-Flow-Settings konnten nicht sicher gefunden werden.")
            }
            guard await pressAndFind(root, labels: ["System"], nextRole: kAXCheckBoxRole, nextLabels: ["Launch app at login"]) else {
                await openGuidedSettings(); return pending("Der geprüfte System-Bereich wurde nicht gefunden.")
            }
        }
        guard let checkbox = find(root, role: kAXCheckBoxRole, labels: ["Launch app at login"]),
              let before = checkboxValue(checkbox), before == 0 || before == 1 else { return pending("Wispr-Flow-Autostart ist nicht lesbar.") }
        if before == 1 {
            guard AXUIElementPerformAction(checkbox, kAXPressAction as CFString) == .success else { return pending("Autostart konnte nicht umgeschaltet werden.") }
        }
        var verified = false
        for _ in 0..<40 {
            if let current = find(root, role: kAXCheckBoxRole, labels: ["Launch app at login"]), checkboxValue(current) == 0, loginPreference() == false { verified = true; break }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return pending("Wechsel unterbrochen.") }
        }
        guard verified else { return pending("Autostart wurde weder im Wispr-Feld noch in den Wispr-Flow-Einstellungen gemeinsam bestätigt.") }
        guard app.terminate() else { return pending("Autostart ist aus; Wispr Flow konnte noch nicht regulär beendet werden.") }
        for _ in 0..<60 {
            if NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty {
                guard loginPreference() == false else { return pending("Wispr Flow ist beendet; Autostart muss erneut geprüft werden.") }
                return WisprSwitchOutcome(.completed, "Wispr-Flow-Autostart per UI und Einstellungen bestätigt ausgeschaltet; Wispr Flow regulär beendet. Separate macOS-Anmeldeobjekte bei Bedarf manuell prüfen.")
            }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
        }
        return pending("Autostart ist ausgeschaltet; Wispr Flow läuft weiterhin. Bitte regulär beenden.")
    }
    public func openGuidedSettings() async {
        if FileManager.default.fileExists(atPath: applicationURL.path) { _ = try? await NSWorkspace.shared.openApplication(at: applicationURL, configuration: NSWorkspace.OpenConfiguration()) }
        if AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first,
           Bundle(url: applicationURL)?.infoDictionary?["CFBundleShortVersionString"] as? String == "1.6.1034" {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, Self.messagingTimeout)
            if let settings = find(root, role: nil, labels: ["Settings", "Settings…", "Settings..."]), isPressable(settings) { _ = AXUIElementPerformAction(settings, kAXPressAction as CFString) }
        }
    }
    public func openLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    private func pending(_ reason: String) -> WisprSwitchOutcome { WisprSwitchOutcome(.pending, reason + " Settings → System → Launch app at login prüfen; anschließend Wispr Flow regulär beenden.") }
    private func loginPreference() -> Bool? {
        guard let data = try? Data(contentsOf: configURL), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prefs = root["prefs"] as? [String: Any], let user = prefs["user"] as? [String: Any] else { return nil }
        return user["openAtLogin"] as? Bool
    }
    private func checkboxValue(_ element: AXUIElement) -> Int? { (AXAccess.value(element, kAXValueAttribute) as? NSNumber)?.intValue }
    private func isPressable(_ element: AXUIElement) -> Bool {
        guard let role = AXAccess.string(element, kAXRoleAttribute) else { return false }
        return [kAXButtonRole, kAXMenuItemRole, kAXRadioButtonRole, kAXCheckBoxRole].contains(role)
    }
    private func pressAndFind(_ root: AXUIElement, labels: Set<String>, nextRole: String?, nextLabels: Set<String>) async -> Bool {
        guard let control = find(root, role: nil, labels: labels), isPressable(control), AXUIElementPerformAction(control, kAXPressAction as CFString) == .success else { return false }
        for _ in 0..<20 {
            if find(root, role: nextRole, labels: nextLabels) != nil { return true }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        return false
    }
    /// Electron answers AX on its busy UI thread; the default wait is 6 s per query
    /// on our main actor. Setting the timeout is local, so every scanned node gets it.
    static let messagingTimeout: Float = 0.25
    func find(_ root: AXUIElement, role: String?, labels: Set<String>) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)], cursor = 0
        while cursor < queue.count && cursor < 1500 {
            let (element, depth) = queue[cursor]; cursor += 1
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
            var title: CFTypeRef?; let started = ProcessInfo.processInfo.systemUptime
            // A real timeout means the app is busy: end this scan (callers retry or
            // report pending) instead of paying the timeout again for every node.
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .cannotComplete,
               ProcessInfo.processInfo.systemUptime - started >= Double(Self.messagingTimeout) * 0.8 { return nil }
            let strings = [title as? String, AXAccess.string(element, kAXDescriptionAttribute), AXAccess.string(element, kAXIdentifierAttribute)].compactMap { $0 }
            if strings.contains(where: labels.contains), role == nil || AXAccess.string(element, kAXRoleAttribute) == role {
                if role != nil || isPressable(element) { return element }
            }
            guard depth < 20 else { continue }
            if let children = AXAccess.value(element, kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf: children.map { ($0, depth + 1) }) }
            if depth == 0, let menu = AXAccess.element(element, kAXMenuBarAttribute) { queue.append((menu, 1)) }
        }
        return nil
    }
}
