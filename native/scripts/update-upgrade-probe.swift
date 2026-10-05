import AppKit
import Sparkle

/// Isolated installation probe. Unique bundle identity; never loads app data or devices.
@main struct UpgradeProbe {
    @MainActor static var updater: SPUStandardUpdaterController?
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let info = Bundle.main.infoDictionary!
        let version = info["CFBundleVersion"] as! String
        let receipt = URL(fileURLWithPath: info["AInautenUpdateProbeReceipt"] as! String)
        try! Data("LAUNCHED build \(version)\n".utf8).write(to: receipt)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AInauten Voice · Updateprüfung \(version)"
        let text = NSTextField(labelWithString: "Isolierte Updateprüfung · Build \(version)")
        text.frame = NSRect(x: 24, y: 110, width: 440, height: 25)
        window.contentView?.addSubview(text)
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        let button = NSButton(title: "Update prüfen", target: updater, action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
        button.frame = NSRect(x: 24, y: 50, width: 160, height: 32)
        window.contentView?.addSubview(button)
        let menu = NSMenu(), item = NSMenuItem(), submenu = NSMenu()
        submenu.addItem(withTitle: "Updateprüfung beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item); app.mainMenu = menu
        window.center(); window.makeKeyAndOrderFront(nil)
        app.run()
    }
}
