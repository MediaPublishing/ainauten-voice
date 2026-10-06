import Foundation

public enum TextStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case original, cleaned, email, chat
    public var id: String { rawValue }
    public var title: String { switch self { case .original: "Original"; case .cleaned: "Optimiert"; case .email: "E-Mail"; case .chat: "Chat" } }
    /// Display label for native controls. `title` is retained for formatter
    /// prompts and stored-profile compatibility.
    public var interfaceTitle: String {
        switch self {
        case .original: L10n.text("style.original")
        case .cleaned: L10n.text("style.optimized")
        case .email: L10n.text("style.email")
        case .chat: L10n.text("style.chat")
        }
    }
}

public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16?
    public var modifiers: UInt64
    public init(keyCode: UInt16? = 49, modifiers: UInt64 = (1 << 18) | (1 << 19)) { self.keyCode = keyCode; self.modifiers = modifiers }
    public var spokenLabel: String {
        var parts: [String] = []
        if modifiers & (1 << 23) != 0 { parts.append(L10n.text("shortcut.fn")) }
        if modifiers & (1 << 18) != 0 { parts.append(L10n.text("shortcut.control")) }
        if modifiers & (1 << 19) != 0 { parts.append(L10n.text("shortcut.option")) }
        if modifiers & (1 << 17) != 0 { parts.append(L10n.text("shortcut.shift")) }
        if modifiers & (1 << 20) != 0 { parts.append(L10n.text("shortcut.command")) }
        if let keyCode { parts.append(Self.keyName(keyCode)) }
        return parts.joined(separator: " + ")
    }
    public var label: String {
        var s = ""
        if modifiers & (1 << 23) != 0 { s += "Fn " }
        if modifiers & (1 << 18) != 0 { s += "⌃ " }
        if modifiers & (1 << 19) != 0 { s += "⌥ " }
        if modifiers & (1 << 17) != 0 { s += "⇧ " }
        if modifiers & (1 << 20) != 0 { s += "⌘ " }
        return (s + (keyCode.map(Self.keyName) ?? "")).trimmingCharacters(in: .whitespaces)
    }
    private static func keyName(_ code: UInt16) -> String {
        let key: String
        switch code {
        case 49: key = L10n.text("shortcut.space")
        case 53: key = L10n.text("shortcut.escape")
        case 36: key = L10n.text("shortcut.return")
        case 48: key = L10n.text("shortcut.tab")
        default: key = [0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U", 34:"I", 35:"P", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M" ][code] ?? L10n.format("shortcut.key", arguments: [String(code)])
        }
        return key
    }
}

/// Additional dictation actions. Optional in Settings to read existing version-1 files.
public struct ShortcutBindings: Codable, Equatable, Sendable {
    public var holdExtras: [Shortcut] = []
    public var handsFree: [Shortcut] = []
    public var cancel: [Shortcut] = []
    public var copyLast: [Shortcut] = []
    public var pasteLast: [Shortcut] = []
    public init() {}
    public var all: [Shortcut] { holdExtras + handsFree + cancel + copyLast + pasteLast }
}

public struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    public static let maximumReplacementBytes = 16_384
    public var id: String
    public var phrase: String
    public var replacement: String?
    public var sourceID: String?
    public var sourceFingerprint: String?
    public var manuallyModified: Bool
    public init(id: String = UUID().uuidString, phrase: String, replacement: String? = nil, sourceID: String? = nil, sourceFingerprint: String? = nil, manuallyModified: Bool = false) {
        self.id = id; self.phrase = phrase; self.replacement = replacement; self.sourceID = sourceID; self.sourceFingerprint = sourceFingerprint; self.manuallyModified = manuallyModified
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var languages: [String] = ["de", "en"]
    public var shortcut = Shortcut()
    public var shortcutBindings: ShortcutBindings?
    public var defaultStyle: TextStyle = .cleaned
    public var manualStyle: TextStyle?
    public var appStyles: [String: TextStyle] = [:]
    /// Only an explicit opt-in may expose automatic dictation to the system clipboard.
    public var clipboardCompatibility: Bool?
    public var usesClipboardForInsertion: Bool { clipboardCompatibility == true }
    public var cloudEnabled = false
    public var cloudEndpoint = "https://api.openai.com/v1"
    public var cloudModel = "gpt-4.1-mini"
    public var onboardingComplete = false
    /// Optional for backwards-compatible decoding of existing version-1 files.
    public var practiceCompleted: Bool?
    /// nil decodes older files; the explicitly requested local text history defaults to enabled.
    public var historyEnabled: Bool?
    /// Older profiles decode nil; camera-based research beta is opt-in.
    public var lipReadingEnabled: Bool?
    public var lipReadingLanguage: String?
    public var lipReadingShortcut: Shortcut?
    public var paused = false
    public var importedWisprShortcut = false
    public init() {}
    public func style(for bundleID: String?) -> TextStyle { manualStyle ?? bundleID.flatMap { appStyles[$0] } ?? defaultStyle }
}

public struct ExportDocument: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var settings: Settings
    public var dictionary: [DictionaryEntry]
    public init(settings: Settings = Settings(), dictionary: [DictionaryEntry] = []) { self.settings = settings; self.dictionary = dictionary }
}

public struct TranscriptWord: Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double
    public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}

public struct TranscriptSegment: Sendable {
    public let sessionID: UUID
    public let index: Int
    public let text: String
    public let words: [TranscriptWord]
    public init(sessionID: UUID, index: Int, text: String, words: [TranscriptWord] = []) { self.sessionID = sessionID; self.index = index; self.text = text; self.words = words }
}

public protocol SpeechTranscribing: Sendable {
    func prepare() async throws
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment
}

public protocol TextFormatting: Sendable {
    func prepare() async throws
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String
}

public struct DictationResult: Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let original: String
    public let usedFallback: Bool
    public let duration: Double
    public let isComplete: Bool
    public init(id: UUID, text: String, original: String, usedFallback: Bool, duration: Double, isComplete: Bool = true) { self.id = id; self.text = text; self.original = original; self.usedFallback = usedFallback; self.duration = duration; self.isComplete = isComplete }
}

public enum DeliveryStatus: String, Codable, Sendable { case confirmed, uncertain, failed, notAttempted }
public struct DeliveryOutcome: Sendable {
    public let status: DeliveryStatus
    public let reason: String
    /// Input was submitted once; this is not evidence that the editor accepted it.
    public let inputWasSubmitted: Bool
    public init(_ status: DeliveryStatus, reason: String = "", inputWasSubmitted: Bool = false) {
        self.status = status; self.reason = reason; self.inputWasSubmitted = inputWasSubmitted
    }
    /// An unreadable acknowledgement after a single submission must not open a
    /// text overlay over text that may already be inserted. Keep the result in RAM.
    public var shouldShowRecovery: Bool {
        status != .confirmed && !(status == .uncertain && inputWasSubmitted)
    }
}

public enum VoiceError: Error, LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let s): s } }
}

/// The pinned recognizer needs at least 300 ms of actual 16 kHz audio.
/// A short input remains an error; no invented silence or words are added.
public enum SpeechInputError: Error, LocalizedError, Sendable {
    case tooShort
    public var errorDescription: String? {
        "Der Audioabschnitt war zu kurz. Halte dein Tastenkürzel beim Sprechen etwas länger gedrückt."
    }
}
