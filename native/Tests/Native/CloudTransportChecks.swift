import Foundation
import VoiceWisprCore

/// Real URLSession transport against a synthetic loopback HTTP server.
@main struct CloudTransportChecks {
    static let text = "Der Bericht wird nicht heute versendet."
    static func seconds(_ start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
    static func formatter(_ base: URL, _ name: String) -> CloudFormatter {
        CloudFormatter(endpoint: base.appendingPathComponent(name), model: "synthetic-model", key: "synthetic-test")
    }
    static func main() async throws {
        let base = URL(string: CommandLine.arguments[1])!
        var cases: [[String: Any]] = []
        let start = ContinuousClock.now
        do {
            let value = try await formatter(base, "success").format(text, style: .cleaned, context: "", vocabulary: ["AInauten"])
            cases.append(["name": "success", "passed": value == text, "seconds": seconds(start)])
        } catch { cases.append(["name": "success", "passed": false, "error": error.localizedDescription]) }
        for name in ["status401", "status429", "redirect", "timeout"] {
            let started = ContinuousClock.now
            do {
                _ = try await formatter(base, name).format(text, style: .cleaned, context: "", vocabulary: [])
                cases.append(["name": name, "passed": false, "error": "Unexpected successful response"])
            } catch {
                let elapsed = seconds(started)
                let expected = name == "timeout"
                    ? (error as? URLError)?.code == .timedOut && elapsed >= 9.5 && elapsed <= 10.5
                    : error.localizedDescription.contains("Cloud-Optimierung ist fehlgeschlagen")
                cases.append(["name": name, "passed": expected, "seconds": elapsed,
                              "errorType": String(describing: type(of: error)), "error": error.localizedDescription])
            }
        }
        let cancelled = Task { try await formatter(base, "cancel").format(text, style: .cleaned, context: "", vocabulary: []) }
        try await Task.sleep(for: .milliseconds(250))
        let cancelledAt = ContinuousClock.now
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            cases.append(["name": "cancel", "passed": false])
        } catch {
            cases.append(["name": "cancel", "passed": error is CancellationError || (error as? URLError)?.code == .cancelled,
                          "secondsAfterCancellation": seconds(cancelledAt), "errorType": String(describing: type(of: error))])
        }
        let original = try await formatter(base, "original").format(text, style: .original, context: "", vocabulary: [])
        cases.append(["name": "original", "passed": original == text])
        let data = try JSONSerialization.data(withJSONObject: ["cases": cases], options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
