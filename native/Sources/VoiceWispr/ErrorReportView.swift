import SwiftUI
import VoiceWisprCore

struct CrashReportNotice: View {
    @ObservedObject var reports: ErrorReportController
    let open: () -> Void
    var body: some View {
        if reports.crashAvailable {
            HStack {
                Label("Die App wurde unerwartet beendet.", systemImage: "exclamationmark.triangle")
                Spacer()
                Button("Bericht prüfen", action: open)
            }.font(.system(size: 12))
        }
    }
}

struct ErrorReportView: View {
    @ObservedObject var reports: ErrorReportController
    @State private var editing = false
    @State private var details = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if reports.crashAvailable {
                Label("Die App wurde unerwartet beendet. Du kannst den Bericht prüfen.", systemImage: "exclamationmark.triangle")
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ein Problem melden").font(.system(size: 18, weight: .semibold))
                    Text("Erst prüfen, dann senden.").foregroundStyle(.secondary)
                }
                Spacer()
                if !editing { Button("Fehler melden") { reports.beginReport(); editing = true }.buttonStyle(.borderedProminent) }
            }
            if !reports.deliveryAvailable {
                Text("Berichte kannst du bereits lokal speichern. Der direkte Versand wird noch eingerichtet.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if editing {
                Text("Technisch: App-Version, macOS, Fehlercode und bereinigte Absturzstellen. Keine Aufnahmen, Diktate, Zwischenablage oder Wörterbucheinträge.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Was ist passiert? (freiwillig)").fontWeight(.medium)
                    TextEditor(text: Binding(get: { reports.draft.userInput.description }, set: { reports.editDescription($0) })).frame(height: 76).border(Color.secondary.opacity(0.25)).accessibilityLabel("Freiwillige Fehlerbeschreibung")
                    TextField("E-Mail für Rückfragen (freiwillig)", text: Binding(get: { reports.draft.userInput.contact }, set: { reports.editContact($0) })).textFieldStyle(.roundedBorder)
                    Text("Diese Angaben werden mitgesendet. Bitte keine vertraulichen Inhalte eingeben.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Privat an das AInauten-Team.").font(.system(size: 12)).foregroundStyle(.secondary)
                        .help("Technische Daten werden über Cloudflare einer privaten GitHub-Inbox zugeordnet. Freiwilliger Text und Kontakt bleiben im privaten Eingang: 30 Tage, Sicherungskopien höchstens weitere 30 Tage. Sie kommen nicht in GitHub-Issues oder automatische AI-Analysen. Keine automatischen E-Mails.")
                }
                DisclosureGroup("Berichtsvorschau", isExpanded: $details) {
                    if let data = try? reports.draft.validatedData(), let json = String(data: data, encoding: .utf8) {
                        Text(json).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    } else { Text("Bitte Beschreibung oder Kontaktadresse prüfen.").foregroundStyle(.orange) }
                }
                HStack {
                    Button(reports.sending ? "Wird gesendet …" : "Senden") { reports.send() }.buttonStyle(.borderedProminent).disabled(!reports.deliveryAvailable || reports.sending || (try? reports.draft.validatedData()) == nil)
                    Button("Lokal speichern") { reports.export() }.disabled(reports.sending || (try? reports.draft.validatedData()) == nil)
                    Button("Abbrechen") { reports.cancel(); editing = false }
                }
            }
            if !reports.message.isEmpty { Text(reports.message).textSelection(.enabled).font(.system(size: 12)).accessibilityAddTraits(.updatesFrequently) }
            Divider()
            Toggle("Technische Fehler automatisch melden", isOn: Binding(get: { reports.automatic && reports.deliveryAvailable }, set: { reports.setAutomatic($0) })).disabled(!reports.deliveryAvailable)
            Text("Standardmäßig aus. Nur bereinigte technische Daten; freiwillige Texte werden nie automatisch ergänzt. Du siehst jede Meldung hier und kannst die Automatik jederzeit ausschalten.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !reports.entries.isEmpty {
                Text("Meldeverlauf · 7 Tage").fontWeight(.semibold)
                ForEach(reports.entries, id: \.report.reportID) { entry in
                    Button { reports.use(entry); editing = true } label: {
                        HStack {
                            Image(systemName: entry.sent ? "checkmark.circle" : "doc.text")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.codeTitle(entry.report.code)).font(.system(size: 12))
                                Text("\(entry.report.reportID.prefix(8)) · \(entry.sent ? "Empfangen" : "Lokal, noch nicht gesendet")").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.date, style: .date).font(.system(size: 12)).foregroundStyle(.secondary)
                        }.contentShape(Rectangle()).padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
            }
            Link("Die App startet nicht? Hilfe auf der Website", destination: URL(string: "https://voice.ainauten.com/help.html")!).font(.system(size: 12))
            Link(destination: URL(string: "https://buymeacoffee.com/mediapublishing")!) {
                Label("Kaffee spendieren", systemImage: "cup.and.saucer")
                    .font(.system(size: 12))
            }.buttonStyle(.plain).foregroundStyle(.secondary).pointerAwareFocus()
                .help("AInauten Voice freiwillig unterstützen · öffnet Buy Me a Coffee im Browser")
                .accessibilityLabel("Kaffee spendieren, öffnet Buy Me a Coffee im Browser")
        }.frame(maxWidth: 620, alignment: .leading)
    }
    static func codeTitle(_ code: ErrorReport.Code) -> String {
        switch code {
        case .userReported: "Eigene Meldung"
        case .processingFailed: "Verarbeitung fehlgeschlagen"
        case .modelLoadFailed: "Modell konnte nicht geladen werden"
        case .settingsLoadFailed: "Einstellungen konnten nicht geladen werden"
        case .importFailed: "Import fehlgeschlagen"
        case .updateFailed: "Update fehlgeschlagen"
        case .crashSignal, .crashException: "Absturz"
        case .launchLibraryMissing: "Programmbibliothek fehlt beim Start"
        }
    }
}
