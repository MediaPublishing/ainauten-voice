import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// Observe only the exact installed app. No activation, input, content or
/// permission requests: UI preparation belongs to the Computer Use operator.
@main struct WindowVisibilityChecks {
    @MainActor static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3, let seconds = Double(arguments[2]),
              seconds >= 3, seconds <= 10 else {
            throw NSError(domain: "WindowObservation", code: 1)
        }
        let expectedURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        guard expectedURL.path == "/Applications/AInauten Voice.app",
              let bundle = Bundle(url: expectedURL),
              bundle.bundleIdentifier == "com.mediapublishing.VoiceWispr" else {
            throw NSError(domain: "WindowObservation", code: 2)
        }
        let matches = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundle.bundleIdentifier &&
            $0.bundleURL?.standardizedFileURL == expectedURL && !$0.isTerminated
        }
        guard matches.count == 1, let application = matches.first else {
            throw NSError(domain: "WindowObservation", code: 3)
        }
        let pid = application.processIdentifier
        // NSRunningApplication caches changing properties until a main-runloop
        // turn. A sleeping polling loop can therefore report stale activation
        // or termination. Observe after servicing AppKit's common-mode sources.
        _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        let started = ProcessInfo.processInfo.systemUptime
        var samples: [[String: Any]] = []
        while true {
            guard !application.isTerminated,
                  let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
                    as? [[String: Any]], !all.isEmpty else {
                throw NSError(domain: "WindowObservation", code: 4)
            }
            let windows = all.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }
            var observations: [[String: Any]] = []
            for window in windows {
                guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: bounds) else {
                    throw NSError(domain: "WindowObservation", code: 5)
                }
                let name = window[kCGWindowName as String] as? String
                // macOS may redact names without Screen Recording permission.
                // Hosting-view sizing produces 68 x 40 points in idle and
                // larger frames during recording/processing. Keep a
                // conservative small-panel check when the name is redacted.
                let pillFrame = (64...160).contains(frame.width) && (35...50).contains(frame.height)
                let visible = window[kCGWindowIsOnscreen as String] as? Bool ?? false
                let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
                observations.append([
                    "windowID": window[kCGWindowNumber as String] as? NSNumber ?? 0,
                    "onScreen": visible, "alpha": alpha,
                    "layer": window[kCGWindowLayer as String] as? NSNumber ?? 0,
                    "width": frame.width, "height": frame.height,
                    "nameAvailable": name != nil,
                    "pillNamed": name == "AInauten Voice Pill",
                    "pillFrame": pillFrame,
                    "mainSized": frame.width >= 600 && frame.height >= 400
                ])
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let frontmost = NSWorkspace.shared.frontmostApplication
            samples.append(["elapsed": elapsed, "processActive": application.isActive,
                            "frontmostMatches": frontmost?.isEqual(application) == true,
                            "windows": observations])
            if elapsed >= seconds { break }
            if !RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1)) {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        let output: [String: Any] = [
            "observedAtUTC": ISO8601DateFormatter().string(from: Date()),
            "bundlePath": expectedURL.path, "bundleID": bundle.bundleIdentifier!,
            "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            "pid": pid, "processRemainedLive": !application.isTerminated,
            "sampleDuration": samples.last?["elapsed"] as? Double ?? 0,
            "displayCount": NSScreen.screens.count,
            "existingAccessibilityTrusted": AXIsProcessTrusted(),
            "windowQuery": "CGWindowListCopyWindowInfo optionAll; exact PID filter",
            "samples": samples,
            "scope": "All returned WindowServer windows of the exact installed process during this observation only. On-screen means current display/Space exposure, not all future states or other Spaces. Names may be redacted; Pill geometry is separately reported. No UI action or content read."
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}
