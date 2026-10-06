import AppKit

#if DEBUG
if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--reporting-controller-probe-root=") }) {
    let root = URL(fileURLWithPath: String(argument.dropFirst("--reporting-controller-probe-root=".count)))
    Task { @MainActor in
        do { try await ErrorReportProbe.controller(root); exit(0) }
        catch { print("REPORTING_CONTROLLER_PROBE failed"); exit(1) }
    }
    RunLoop.main.run()
}
if let root = CommandLine.arguments.first(where: { $0.hasPrefix("--reporting-probe-root=") }) {
    do { try ErrorReportProbe.run(URL(fileURLWithPath: String(root.dropFirst("--reporting-probe-root=".count)))) }
    catch { print("REPORTING_PROBE failed"); exit(1) }
    exit(0)
}
#endif
import VoiceWisprCore

// Read-only packaging check: no AppModel, settings migration, hotkeys or model
// loading. Exercise the same lazy diagnostics that run during normal startup.
if CommandLine.arguments.contains("--check-bundled-resources") {
    do {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let resources = Bundle.main.resourceURL,
              let core = Bundle.main.url(forResource: "VoiceWispr_VoiceWisprCore", withExtension: "bundle"),
              core.deletingLastPathComponent().standardizedFileURL == resources.standardizedFileURL,
              L10n.template("settings.interfaceLanguage", language: .en) == "Interface language",
              L10n.template("settings.interfaceLanguage", language: .de) == "Oberflächensprache",
              L10n.plural("history.count", count: 1, language: .en) == "1 dictation",
              L10n.plural("history.count", count: 2, language: .de) == "2 Diktate",
              L10n.message("No speech detected") == .key("status.noSpeech", []) else {
            throw VoiceError.message("Packaged interface resources are missing or unavailable.")
        }
        let manifest = try ModelManifest.bundled()
        guard !manifest.files.isEmpty else { throw VoiceError.message("Packaged model manifest is empty.") }
        print("BUNDLED_RESOURCES_PASS english=true german=true plurals=true diagnostics=true modelManifest=true")
        exit(0)
    } catch {
        print("BUNDLED_RESOURCES_FAIL")
        exit(1)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let model = MainActor.assumeIsolated {
let model = AppModel()
application.delegate = model
#if DEBUG
let preview = CommandLine.arguments.first { $0.hasPrefix("--preview-ui=") }.map { String($0.dropFirst("--preview-ui=".count)) }
if preview != nil, CommandLine.arguments.contains("--preview-dark") { application.appearance = NSAppearance(named: .darkAqua) }
if preview != nil, CommandLine.arguments.contains("--preview-light") { application.appearance = NSAppearance(named: .aqua) }
#else
let preview: String? = nil
#endif
model.launch(preview: preview)
return model
}
// AppKit owns this run loop. Do not keep a Swift actor-isolation scope open
// across arbitrary native callbacks for the entire lifetime of the app.
application.run()
