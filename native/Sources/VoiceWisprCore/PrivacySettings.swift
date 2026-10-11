import Foundation

public enum PrivacySettings {
    public static var renamedAccessibility: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
    }
    public static func accessibilityKey(_ key: String, modern: Bool = renamedAccessibility) -> String {
        modern ? key + ".macOS27" : key
    }
    public static func destination(_ permission: String) -> URL {
        // The PrivacySecurity extension retains the TCC anchors on macOS 27.
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_" + permission)!
    }
}
