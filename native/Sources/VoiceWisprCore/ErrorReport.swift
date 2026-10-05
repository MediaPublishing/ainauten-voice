import Foundation

/// Wire format v1: never append runtime descriptions, logs or dictionary values.
public struct ErrorReport: Codable, Equatable, Sendable {
    public enum Code: String, Codable, CaseIterable, Sendable {
        case userReported = "user_reported", processingFailed = "processing_failed"
        case modelLoadFailed = "model_load_failed", settingsLoadFailed = "settings_load_failed"
        case importFailed = "import_failed", updateFailed = "update_failed"
        case crashSignal = "crash_signal", crashException = "crash_exception", launchLibraryMissing = "launch_library_missing"
    }
    public enum Component: String, Codable, CaseIterable, Sendable { case app, recognition, models, settings, migration, updates, launch }
    public enum Event: String, Codable, Sendable { case launch, recordingStarted = "recording_started", processingStarted = "processing_started", processingFailed = "processing_failed", modelLoadStarted = "model_load_started" }
    public struct Frame: Codable, Equatable, Sendable {
        public var binaryUUID: String
        public var offset: Int
        public init(binaryUUID: String, offset: Int) { self.binaryUUID = binaryUUID.lowercased(); self.offset = offset }
    }
    public struct UserInput: Codable, Equatable, Sendable {
        public var description: String
        public var contact: String
        public init(description: String = "", contact: String = "") { self.description = description; self.contact = contact }
    }
    public var schema = 1
    public var reportID: String
    public var version: String
    public var build: String
    public var osVersion: String
    public var architecture: String
    public var component: Component
    public var code: Code
    public var frames: [Frame]
    public var events: [Event]
    public var userInput: UserInput

    public init(id: UUID = UUID(), version: String, build: String, osVersion: String,
                architecture: String = "arm64", component: Component = .app, code: Code = .userReported,
                frames: [Frame] = [], events: [Event] = [], userInput: UserInput = .init()) {
        reportID = id.uuidString.lowercased(); self.version = version; self.build = build
        self.osVersion = osVersion; self.architecture = architecture; self.component = component; self.code = code
        self.frames = frames; self.events = events; self.userInput = userInput
    }
    public func validatedData() throws -> Data {
        func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
        guard schema == 1, UUID(uuidString: reportID) != nil, reportID == reportID.lowercased(),
              matches(version, "^[0-9]{1,3}(\\.[0-9]{1,3}){1,3}$"), matches(build, "^[0-9]{1,9}$"),
              matches(osVersion, "^[0-9]{1,3}(\\.[0-9]{1,3}){1,2}$"), ["arm64", "x86_64"].contains(architecture),
              frames.count <= 32, events.count <= 12,
              frames.allSatisfy({ UUID(uuidString: $0.binaryUUID) != nil && $0.binaryUUID == $0.binaryUUID.lowercased() && (0...2_147_483_647).contains($0.offset) }),
              userInput.description.utf8.count <= 2_000, userInput.contact.utf8.count <= 254,
              !userInput.contact.contains("\n"), !userInput.contact.contains("\r"),
              userInput.contact.isEmpty || matches(userInput.contact, "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$") else { throw ReportError.invalid }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(self)
        guard data.count <= 16_384 else { throw ReportError.invalid }
        return data
    }
    /// Reject unknown keys at every level instead of silently ignoring private fields.
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 16_384, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["schema", "reportID", "version", "build", "osVersion", "architecture", "component", "code", "frames", "events", "userInput"]),
              let frames = object["frames"] as? [[String: Any]], frames.allSatisfy({ Set($0.keys) == ["binaryUUID", "offset"] }),
              let user = object["userInput"] as? [String: Any], Set(user.keys) == ["description", "contact"] else { throw ReportError.invalid }
        let report = try JSONDecoder().decode(Self.self, from: data); _ = try report.validatedData(); return report
    }
    public enum ReportError: Error { case invalid, full, unavailable, acknowledgment }
}

public struct ReportReceipt: Codable, Equatable, Sendable {
    public var reportID: String
    public var accepted: Bool
    public var state: String
    public init(reportID: String, accepted: Bool, state: String) { self.reportID = reportID; self.accepted = accepted; self.state = state }
}

/// Apple IPS JSON is parsed locally. Only the application image's UUID/offsets survive.
public enum AppleDiagnosticProjection {
    public static func report(from data: Data) throws -> ErrorReport {
        guard data.count <= 2_097_152, let text = String(data: data, encoding: .utf8) else { throw ErrorReport.ReportError.invalid }
        // Apple's first JSON line is metadata; the remaining JSON is the payload.
        let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
        let object: [String: Any]
        if let whole = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { object = whole }
        else if parts.count == 2, let body = parts[1].data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { object = parsed }
        else { throw ErrorReport.ReportError.invalid }
        guard let bundle = object["bundleInfo"] as? [String: Any], bundle["CFBundleIdentifier"] as? String == "com.mediapublishing.VoiceWispr",
              let version = bundle["CFBundleShortVersionString"] as? String,
              let build = bundle["CFBundleVersion"] as? String else { throw ErrorReport.ReportError.invalid }
        let osRaw = (object["osVersion"] as? [String: Any])?["train"] as? String ?? ""
        let os = osRaw.range(of: "[0-9]+\\.[0-9]+(?:\\.[0-9]+)?", options: .regularExpression).map { String(osRaw[$0]) } ?? ""
        let exception = object["exception"] as? [String: Any] ?? [:]
        let namespace = (object["termination"] as? [String: Any])?["namespace"] as? String
        let code: ErrorReport.Code = namespace == "DYLD" ? .launchLibraryMissing : (exception["signal"] != nil ? .crashSignal : .crashException)
        var report = ErrorReport(version: version, build: build, osVersion: os, architecture: (object["cpuType"] as? String) == "X86-64" ? "x86_64" : "arm64", component: .launch, code: code)
        let images = object["usedImages"] as? [[String: Any]] ?? []
        let appIndexes = images.indices.filter { ["VoiceWispr", "AInauten Voice"].contains(images[$0]["name"] as? String ?? "") }
        let threads = object["threads"] as? [[String: Any]] ?? []
        for frame in (threads.first(where: { $0["triggered"] as? Bool == true })?["frames"] as? [[String: Any]] ?? []) {
            guard report.frames.count < 32, let index = frame["imageIndex"] as? Int, appIndexes.contains(index),
                  let uuid = images[index]["uuid"] as? String, UUID(uuidString: uuid) != nil,
                  let offset = frame["imageOffset"] as? Int, (0...2_147_483_647).contains(offset) else { continue }
            report.frames.append(.init(binaryUUID: uuid, offset: offset))
        }
        _ = try report.validatedData(); return report
    }
}
