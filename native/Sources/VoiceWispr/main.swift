import AppKit
import VoiceWisprCore

let application = NSApplication.shared
application.setActivationPolicy(.regular)
MainActor.assumeIsolated {
let model = AppModel()
application.delegate = model
#if DEBUG
let preview = CommandLine.arguments.first { $0.hasPrefix("--preview-ui=") }.map { String($0.dropFirst("--preview-ui=".count)) }
if preview != nil, CommandLine.arguments.contains("--preview-dark") { application.appearance = NSAppearance(named: .darkAqua) }
#else
let preview: String? = nil
#endif
model.launch(preview: preview)
application.run()
}
