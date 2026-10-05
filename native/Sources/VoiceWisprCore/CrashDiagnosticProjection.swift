import Foundation

/// SDK dumps are strictly projected before they enter the queue or a preview.
public enum CrashDiagnosticProjection {
    public static func report(_ object: [String: Any]) throws -> ErrorReport {
        guard let crash = object["crash"] as? [String: Any], let error = crash["error"] as? [String: Any],
              ["signal", "mach", "nsexception", "cpp_exception"].contains(error["type"] as? String ?? ""),
              let system = object["system"] as? [String: Any],
              let version = system["CFBundleShortVersionString"] as? String,
              let build = system["CFBundleVersion"] as? String,
              let os = system["system_version"] as? String else { throw ErrorReport.ReportError.invalid }
        var report = ErrorReport(version: version, build: build, osVersion: os,
            architecture: system["cpu_arch"] as? String == "x86_64" ? "x86_64" : "arm64",
            component: .app, code: error["type"] as? String == "nsexception" ? .crashException : .crashSignal)
        let images = object["binary_images"] as? [[String: Any]] ?? []
        let threads = crash["threads"] as? [[String: Any]] ?? []
        for f in ((threads.first(where: { $0["crashed"] as? Bool == true })?["backtrace"] as? [String: Any])?["contents"] as? [[String: Any]] ?? []) {
            guard report.frames.count < 32, let addr = f["instruction_addr"] as? UInt64,
                  let image = images.first(where: { i in
                      guard let base = i["image_addr"] as? UInt64, let size = i["image_size"] as? UInt64 else { return false }
                      return addr >= base && addr - base < size && ["VoiceWispr", "AInauten Voice"].contains(URL(fileURLWithPath: i["name"] as? String ?? "").lastPathComponent)
                  }), let base = image["image_addr"] as? UInt64, let uuid = image["uuid"] as? String,
                  UUID(uuidString: uuid) != nil, addr - base <= 2_147_483_647 else { continue }
            report.frames.append(.init(binaryUUID: uuid, offset: Int(addr - base)))
        }
        _ = try report.validatedData(); return report
    }
}
