import XCTest
import VoiceWisprCore

final class InterfaceLanguageTests: XCTestCase {
    func testPreferredLanguageOrderAndRegionalVariants() {
        XCTAssertEqual(InterfaceLanguage.resolve(.system, preferred: ["de-CH", "en-GB"]), .de)
        XCTAssertEqual(InterfaceLanguage.resolve(.system, preferred: ["en_GB", "de-DE"]), .en)
        XCTAssertEqual(InterfaceLanguage.resolve(.system, preferred: ["fr-FR", "de-AT"]), .de)
        XCTAssertEqual(InterfaceLanguage.resolve(.system, preferred: ["fr-FR", "es-ES"]), .en)
        XCTAssertEqual(InterfaceLanguage.resolve(.system, preferred: []), .en)
        XCTAssertEqual(InterfaceLanguage.resolve(.de, preferred: ["en-US"]), .de)
        XCTAssertEqual(InterfaceLanguage.resolve(.en, preferred: ["de-DE"]), .en)
    }

    @MainActor func testIndependentPreferenceSurvivesRestartAndReturnsToSystem() throws {
        let name = "InterfaceLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let original = ExportDocument()
        let store = InterfaceLanguageStore(defaults: defaults, preferred: { ["de-CH"] })
        XCTAssertEqual(store.choice, .system)
        XCTAssertEqual(store.resolved, .de)
        try store.setChoice(.en)
        XCTAssertEqual(InterfaceLanguageStore(defaults: defaults).choice, .en)
        XCTAssertEqual(original.settings.languages, ["de", "en"])
        try store.setChoice(.system)
        XCTAssertEqual(store.resolved, .de)
    }

    @MainActor func testUnknownPreferenceAndFailedSaveKeepAppUsable() throws {
        let name = "InterfaceLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("broken", forKey: InterfaceLanguageStore.preferenceKey)
        let store = InterfaceLanguageStore(defaults: defaults, preferred: { ["fr", "en-GB"] }, persist: { _ in false })
        XCTAssertEqual(store.choice, .system)
        XCTAssertEqual(store.resolved, .en)
        XCTAssertThrowsError(try store.setChoice(.de))
        XCTAssertEqual(store.choice, .system)
        XCTAssertEqual(defaults.string(forKey: InterfaceLanguageStore.preferenceKey), "system")
    }

    func testPackagedEnglishGermanMessagesAndArguments() {
        XCTAssertEqual(L10n.format("settings.interfaceLanguage", arguments: [], language: .en), "Interface language")
        XCTAssertEqual(L10n.format("settings.interfaceLanguage", arguments: [], language: .de), "Oberflächensprache")
        XCTAssertEqual(L10n.format("sidebar.version", arguments: ["1.2.3"], language: .en), "Version 1.2.3 · Local")
        XCTAssertEqual(L10n.template("settings.interfaceLanguage", language: .system), "Interface language")
        XCTAssertEqual(L10n.template("test.missing.key", language: .en), "Text unavailable")
    }

    func testPromptsAndStoredStyleCodesStayStable() {
        XCTAssertEqual(TextStyle.cleaned.rawValue, "cleaned")
        XCTAssertEqual(TextStyle.cleaned.title, "Optimiert")
        XCTAssertEqual(TextStyle.email.title, "E-Mail")
        XCTAssertEqual(Shortcut(keyCode: 49, modifiers: 0).keyCode, 49)
        XCTAssertEqual(LocalizedMessage.literal("AInauten ist MIT dabei.").text, "AInauten ist MIT dabei.")
    }

    func testMissingGermanTranslationUsesEnglishResource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalizationFallback-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        for language in ["de", "en"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("\(language).lproj"), withIntermediateDirectories: true)
        }
        try "\"fallback.example\" = \"English fallback\";".write(to: root.appendingPathComponent("en.lproj/Localizable.strings"), atomically: true, encoding: .utf8)
        try "\"other.example\" = \"Anderer Text\";".write(to: root.appendingPathComponent("de.lproj/Localizable.strings"), atomically: true, encoding: .utf8)
        let resources = try XCTUnwrap(Bundle(path: root.path))
        XCTAssertEqual(L10n.template("fallback.example", language: .de, resources: resources), "English fallback")
        XCTAssertEqual(L10n.template("unknown.example", language: .de, resources: resources), "Text nicht verfügbar")
    }

    func testPluralsAndDiagnosticIdentityPreserveValues() {
        XCTAssertEqual(L10n.plural("history.count", count: 0, language: .en), "0 dictations")
        XCTAssertEqual(L10n.plural("history.count", count: 1, language: .en), "1 dictation")
        XCTAssertEqual(L10n.plural("history.count", count: 2, language: .de), "2 Diktate")
        XCTAssertEqual(L10n.plural("recovery.secondsAX", count: 1, language: .en), "Closes in 1 second")
        XCTAssertEqual(L10n.message("Einstellungen konnten nicht geladen werden: OSStatus -50"), .key("settings.loadFailed", ["OSStatus -50"]))
        XCTAssertEqual(L10n.message("Unknown framework error 42"), .literal("Unknown framework error 42"))
        let message = L10n.message("No speech detected")
        XCTAssertEqual(message, .key("status.noSpeech", []))
    }
}
