import Foundation
import Combine

public enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, de, en
    public var id: String { rawValue }
    public static func resolve(_ choice: Self, preferred: [String]) -> Self {
        guard choice == .system else { return choice }
        for language in preferred {
            switch language.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first {
            case "de": return .de
            case "en": return .en
            default: continue
            }
        }
        return .en
    }
}

@MainActor public final class InterfaceLanguageStore: ObservableObject {
    public static let shared = InterfaceLanguageStore()
    public static let preferenceKey = "interfaceLanguage"
    public static let didChangeNotification = Notification.Name("AInautenInterfaceLanguageDidChange")
    @Published public private(set) var choice: InterfaceLanguage
    public var resolved: InterfaceLanguage { InterfaceLanguage.resolve(choice, preferred: preferred()) }
    private let defaults: UserDefaults
    private let preferred: () -> [String]
    private let persist: (String) -> Bool

    public init(defaults: UserDefaults = L10n.preferenceDefaults, preferred: @escaping () -> [String] = { L10n.preferredLanguages }, persist: ((String) -> Bool)? = nil) {
        self.defaults = defaults
        self.preferred = preferred
        self.choice = InterfaceLanguage(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
        self.persist = persist ?? { value in
            defaults.set(value, forKey: InterfaceLanguageStore.preferenceKey)
            return defaults.string(forKey: InterfaceLanguageStore.preferenceKey) == value
        }
    }

    public func setChoice(_ next: InterfaceLanguage) throws {
        guard next != choice else { return }
        let old = choice
        guard persist(next.rawValue) else {
            defaults.set(old.rawValue, forKey: Self.preferenceKey)
            throw InterfaceLanguageSaveError()
        }
        choice = next
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

public struct InterfaceLanguageSaveError: LocalizedError {
    public var errorDescription: String? { L10n.text("settings.interfaceLanguage.saveFailed") }
}

/// User content, prompts and stored enum codes never pass through this layer.
public indirect enum LocalizedMessage: Equatable {
    case key(String, [String])
    case literal(String)
    case joined([LocalizedMessage], String)
    public var text: String {
        switch self {
        case let .key(key, arguments): return L10n.format(key, arguments: arguments)
        case let .literal(value): return value
        case let .joined(values, separator): return values.map(\.text).joined(separator: separator)
        }
    }
}

public enum L10n {
    public static let preferenceDefaults: UserDefaults = {
        #if DEBUG
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--preview-ui=") }) {
            let defaults = UserDefaults(suiteName: "AInautenVoiceUIPreview.\(ProcessInfo.processInfo.processIdentifier)")!
            if let value = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-language=") })?.split(separator: "=").last,
               let choice = InterfaceLanguage(rawValue: String(value)) { defaults.set(choice.rawValue, forKey: "interfaceLanguage") }
            return defaults
        }
        #endif
        return .standard
    }()
    public static var preferredLanguages: [String] { UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages }
    public static var language: InterfaceLanguage {
        InterfaceLanguage.resolve(InterfaceLanguage(rawValue: preferenceDefaults.string(forKey: "interfaceLanguage") ?? "") ?? .system, preferred: preferredLanguages)
    }
    public static var wordsLocale: Locale {
        let region = Locale.current.region?.identifier ?? "US"
        return Locale(identifier: "\(language.rawValue)_\(region)")
    }
    private static let tables = ["Localizable", "Views", "Runtime", "Core", "Diagnostics"]
    private static func bundle(_ language: InterfaceLanguage, resources: Bundle? = nil) -> Bundle? {
        (resources ?? Bundle.module).path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:))
    }
    public static func text(_ key: String, _ arguments: String...) -> String { format(key, arguments: arguments) }
    public static func format(_ key: String, arguments: [String], language: InterfaceLanguage? = nil) -> String {
        let value = template(key, language: language ?? self.language)
        guard !arguments.isEmpty else { return value }
        return String(format: value, locale: Locale.current, arguments: arguments.map { $0 as CVarArg })
    }
    public static func template(_ key: String, language: InterfaceLanguage, resources: Bundle? = nil) -> String {
        for code in [language, .en] {
            guard let localized = bundle(code, resources: resources) else { continue }
            for table in tables {
                let value = localized.localizedString(forKey: key, value: "\u{1}", table: table)
                if value != "\u{1}" { return value }
            }
        }
        return language == .de ? "Text nicht verfügbar" : "Text unavailable"
    }
    public static func plural(_ key: String, count: Int, language: InterfaceLanguage? = nil) -> String {
        for code in [language ?? self.language, .en] {
            guard let localized = bundle(code) else { continue }
            for table in tables {
                let value = localized.localizedString(forKey: key, value: "\u{1}", table: table)
                if value != "\u{1}" { return String.localizedStringWithFormat(value, count) }
            }
        }
        return text(key, count.formatted())
    }

    private struct DiagnosticTemplate {
        let key: String
        let value: String
        let pattern: NSRegularExpression?
        let argumentOrder: [Int]
    }
    private static let diagnostics: [DiagnosticTemplate] = [InterfaceLanguage.de, .en].flatMap { language in tables.flatMap { table -> [DiagnosticTemplate] in
        guard let url = bundle(language)?.url(forResource: table, withExtension: "strings"),
              let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else { return [] }
        return values.map { key, value in
            let token = try! NSRegularExpression(pattern: "%([1-9][0-9]*\\$)?@")
            let matches = token.matches(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value))
            var pattern = "\\A", previous = value.startIndex, order: [Int] = []
            for (index, match) in matches.enumerated() {
                guard let range = Range(match.range, in: value) else { continue }
                pattern += NSRegularExpression.escapedPattern(for: String(value[previous..<range.lowerBound])) + "([\\s\\S]*?)"
                previous = range.upperBound
                let position = Range(match.range(at: 1), in: value).flatMap { Int(value[$0].dropLast()) }
                order.append((position ?? (index + 1)) - 1)
            }
            pattern += NSRegularExpression.escapedPattern(for: String(value[previous...])) + "\\z"
            let expression = !matches.isEmpty && value.count > matches.count * 4 ? try? NSRegularExpression(pattern: pattern) : nil
            return DiagnosticTemplate(key: key, value: value, pattern: expression, argumentOrder: order)
        }
    }}.sorted { $0.value.count > $1.value.count }

    /// Compatibility at the UI boundary for existing app-generated diagnostics.
    /// Never call with dictated text, a user's description, reports or log files.
    public static func diagnostic(_ source: String) -> String {
        message(source).text
    }

    /// Keep message identity and values so visible feedback can change language live.
    public static func message(_ source: String) -> LocalizedMessage {
        if let exact = diagnostics.first(where: { $0.value == source }) { return .key(exact.key, []) }
        for candidate in diagnostics {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            guard let match = candidate.pattern?.firstMatch(in: source, range: range) else { continue }
            var arguments = Array(repeating: "", count: (candidate.argumentOrder.max() ?? -1) + 1)
            for (index, position) in candidate.argumentOrder.enumerated() {
                if let range = Range(match.range(at: index + 1), in: source) { arguments[position] = String(source[range]) }
            }
            return .key(candidate.key, arguments)
        }
        return .literal(source)
    }

}
