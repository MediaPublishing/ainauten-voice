import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updates: AppUpdateController
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 24)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AInauten Voice").font(.system(size: 18, weight: .semibold))
                    Text("Version \(updates.version)").foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle("Automatische Updates", isOn: Binding(get: { updates.automaticUpdates }, set: { updates.setAutomaticUpdates($0) }))
                .disabled(!updates.available)
                .help("Sucht täglich nach neuen Versionen, lädt sie und installiert sie beim nächsten App-Neustart. Ausschalten verhindert künftige automatische Suchen; ein bereits geladenes Update kann beim Beenden noch installiert werden.")
            Text(updates.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Nach Updates suchen") { updates.check() }
                .disabled(!updates.available || !updates.canCheck)
            if let date = updates.lastCheck {
                Text("Zuletzt geprüft: \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text("Dein Wörterbuch, Verlauf und deine Einstellungen bleiben erhalten.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .help("Nur freigegebene App-Versionen. Lippenlesen-Betas und Webseitenänderungen allein lösen kein Update aus. Die Übertragung enthält keine Diktate; keine Nutzungsstatistik.")
        }.frame(maxWidth: 580, alignment: .leading)
    }
}
