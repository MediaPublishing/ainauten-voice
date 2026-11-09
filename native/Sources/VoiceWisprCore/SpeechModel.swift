import Foundation
import FluidAudio

public enum SpeechModel: String, Codable, CaseIterable, Identifiable, Sendable {
    case parakeetV3 = "parakeet-v3"
    case parakeetUltra = "parakeet-ultra"

    public var id: String { rawValue }
    public var title: String { self == .parakeetV3 ? "Parakeet v3" : "Parakeet Ultra" }
    public var group: String { self == .parakeetV3 ? "parakeet" : "parakeet-ultra" }
    public var directory: URL { ModelPaths.models.appendingPathComponent(group, isDirectory: true) }
    public var downloadGroups: Set<String> { [group, "vad", "qwen"] }
    public var asrVersion: AsrModelVersion { self == .parakeetV3 ? .v3 : .ultra }
}
