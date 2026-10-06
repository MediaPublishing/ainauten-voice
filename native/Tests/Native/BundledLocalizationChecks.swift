import Foundation
import Darwin

@main struct BundledLocalizationChecks {
    static func main() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { exit(2) }
        if CommandLine.arguments.contains("--missing") {
            guard L10n.template("settings.interfaceLanguage", language: .en) == "Text unavailable",
                  L10n.template("settings.interfaceLanguage", language: .de) == "Text nicht verfügbar",
                  L10n.message("No speech detected") == .literal("No speech detected") else { exit(1) }
            print("MISSING_RESOURCES_PASS controlledFallback=true")
        } else {
            guard L10n.template("settings.interfaceLanguage", language: .en) == "Interface language",
                  L10n.template("settings.interfaceLanguage", language: .de) == "Oberflächensprache",
                  L10n.plural("history.count", count: 1, language: .en) == "1 dictation",
                  L10n.plural("history.count", count: 2, language: .de) == "2 Diktate",
                  L10n.message("No speech detected") == .key("status.noSpeech", []) else { exit(1) }
            print("PACKAGED_LOCALIZATION_PASS english=true german=true plurals=true diagnostics=true")
        }
    }
}
