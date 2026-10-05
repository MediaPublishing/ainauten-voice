import Foundation

/// The current probe is separate from the persisted setup flag. Its text lives
/// only in memory, remains visible after completion, and cannot be replaced by
/// a late result from an aborted or earlier probe.
public struct PracticeFeedback: Sendable {
    public enum Phase: Sendable { case idle, recording, processing, recognized, partial, failed, cancelled }
    public private(set) var phase: Phase = .idle
    public private(set) var result: DictationResult?
    public private(set) var message = ""
    private var sessionID: UUID?
    public init() {}
    public var isActive: Bool { phase == .recording || phase == .processing }
    public var succeeded: Bool { phase == .recognized }
    public mutating func begin(_ id: UUID) {
        sessionID = id; phase = .recording; result = nil; message = ""
    }
    public mutating func processing(_ id: UUID) {
        guard sessionID == id, phase == .recording else { return }
        phase = .processing
    }
    @discardableResult public mutating func finish(_ id: UUID, result: DictationResult) -> Bool {
        guard sessionID == id, isActive else { return false }
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fail(id, message: "Keine Sprache erkannt. Bitte sprich einen ganzen Satz und versuche es erneut.")
            return false
        }
        self.result = result; sessionID = nil
        phase = result.isComplete ? .recognized : .partial
        message = result.isComplete ? "Dieser Text wurde erkannt. Er wurde nicht in eine andere App eingefügt." : "Nur ein Teil wurde erkannt. Bitte wiederhole das Probediktat."
        return result.isComplete
    }
    public mutating func fail(_ id: UUID, message: String, partial: DictationResult? = nil) {
        guard sessionID == id, isActive else { return }
        sessionID = nil; result = partial; phase = partial == nil ? .failed : .partial; self.message = message
    }
    public mutating func cancel(_ id: UUID) {
        guard sessionID == id, isActive else { return }
        sessionID = nil; result = nil; phase = .cancelled; message = "Probediktat abgebrochen. Es wurde kein Text eingefügt."
    }
}

/// Only the setup probe stops on a pause. Normal dictation retains explicit stop.
public struct PracticeSession: Sendable {
    private var lastVoice: TimeInterval?
    public init() {}
    public mutating func shouldStop(level: Float, elapsed: TimeInterval) -> Bool {
        if level >= 0.07 { lastVoice = elapsed }
        if elapsed >= 15 { return true }
        guard elapsed >= 3, let lastVoice else { return false }
        return elapsed - lastVoice >= 2
    }
    /// Without Accessibility the global hotkey and insertion cannot work, so setup is not complete.
    public static func canFinish(modelsReady: Bool, microphoneGranted: Bool, accessibilityGranted: Bool, practiceComplete: Bool) -> Bool {
        modelsReady && microphoneGranted && accessibilityGranted && practiceComplete
    }
}
