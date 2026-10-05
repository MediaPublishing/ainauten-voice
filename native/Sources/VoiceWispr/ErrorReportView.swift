import SwiftUI
import VoiceWisprCore

private func r(_ key: String, _ args: String... ) -> String { L10n.format(key, arguments: args) }

struct CrashReportNotice: View {
    @ObservedObject var reports: ErrorReportController
    let open: () -> Void
    var body: some View {
        if reports.crashAvailable {
            HStack {
                Label(r("report.crash.short"), systemImage: "exclamationmark.triangle")
                Spacer()
                Button(r("report.review"), action: open)
            }.font(.system(size: 12))
        }
    }
}

struct ErrorReportView: View {
    @ObservedObject var reports: ErrorReportController
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
    @State private var editing = false
    @State private var details = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if reports.crashAvailable {
                Label(r("report.crash.review"), systemImage: "exclamationmark.triangle")
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(r("report.title")).font(.system(size: 18, weight: .semibold))
                    Text(r("report.subtitle")).foregroundStyle(.secondary)
                }
                Spacer()
                if !editing { Button(r("report.start")) { reports.beginReport(); editing = true }.buttonStyle(.borderedProminent) }
            }
            if !reports.deliveryAvailable {
                Text(r("report.deliveryUnavailable"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if editing {
                Text(r("report.technicalPrivacy")).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(r("report.description.label")).fontWeight(.medium)
                    TextEditor(text: Binding(get: { reports.draft.userInput.description }, set: { reports.editDescription($0) })).frame(height: 76).border(Color.secondary.opacity(0.25)).accessibilityLabel(r("report.description.accessibility"))
                    TextField(r("report.contact.placeholder"), text: Binding(get: { reports.draft.userInput.contact }, set: { reports.editContact($0) })).textFieldStyle(.roundedBorder)
                    Text(r("report.userDataHint")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(r("report.privateTeam")).font(.system(size: 12)).foregroundStyle(.secondary)
                        .help(r("report.privateHelp"))
                }
                DisclosureGroup(r("report.preview"), isExpanded: $details) {
                    if let data = try? reports.draft.validatedData(), let json = String(data: data, encoding: .utf8) {
                        Text(json).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    } else { Text(r("report.invalid")).foregroundStyle(.orange) }
                }
                HStack {
                    Button(reports.sending ? r("report.sending") : r("report.send")) { reports.send() }.buttonStyle(.borderedProminent).disabled(!reports.deliveryAvailable || reports.sending || (try? reports.draft.validatedData()) == nil)
                    Button(r("report.saveLocal")) { reports.export() }.disabled(reports.sending || (try? reports.draft.validatedData()) == nil)
                    Button(r("common.cancel")) { reports.cancel(); editing = false }
                }
            }
            if !reports.message.isEmpty { Text(reports.message).textSelection(.enabled).font(.system(size: 12)).accessibilityAddTraits(.updatesFrequently) }
            Divider()
            Toggle(r("report.automatic"), isOn: Binding(get: { reports.automatic && reports.deliveryAvailable }, set: { reports.setAutomatic($0) })).disabled(!reports.deliveryAvailable)
            Text(r("report.automaticHint")).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !reports.entries.isEmpty {
                Text(r("report.history")).fontWeight(.semibold)
                ForEach(reports.entries, id: \.report.reportID) { entry in
                    Button { reports.use(entry); editing = true } label: {
                        HStack {
                            Image(systemName: entry.sent ? "checkmark.circle" : "doc.text")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.codeTitle(entry.report.code)).font(.system(size: 12))
                                Text(r("report.entryStatus", String(entry.report.reportID.prefix(8)), entry.sent ? r("report.received") : r("report.localPending"))).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.date.formatted(.dateTime.day().month(.wide).year().locale(L10n.wordsLocale))).font(.system(size: 12)).foregroundStyle(.secondary)
                        }.contentShape(Rectangle()).padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
            }
            Link(r("report.helpLink"), destination: URL(string: "https://voice.ainauten.com/help.html")!).font(.system(size: 12))
            Link(destination: URL(string: "https://buymeacoffee.com/mediapublishing")!) {
                Label(r("report.coffee"), systemImage: "cup.and.saucer")
                    .font(.system(size: 12))
            }.buttonStyle(.plain).foregroundStyle(.secondary).pointerAwareFocus()
                .help(r("report.coffee.help"))
                .accessibilityLabel(r("report.coffee.accessibility"))
        }.frame(maxWidth: 620, alignment: .leading)
    }
    static func codeTitle(_ code: ErrorReport.Code) -> String {
        switch code {
        case .userReported: r("report.code.user")
        case .processingFailed: r("report.code.processing")
        case .modelLoadFailed: r("report.code.model")
        case .settingsLoadFailed: r("report.code.settings")
        case .importFailed: r("report.code.import")
        case .updateFailed: r("report.code.update")
        case .crashSignal, .crashException: r("report.code.crash")
        case .launchLibraryMissing: r("report.code.library")
        }
    }
}
