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
