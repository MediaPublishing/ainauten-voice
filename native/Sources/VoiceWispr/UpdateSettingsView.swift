import SwiftUI
import VoiceWisprCore

private func u(_ key: String, _ args: String... ) -> String { L10n.format(key, arguments: args) }

struct UpdateSettingsView: View {
    @ObservedObject var updates: AppUpdateController
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 24)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(u("updates.appName")).font(.system(size: 18, weight: .semibold))
                    Text(u("updates.version", updates.version)).foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle(u("updates.automatic"), isOn: Binding(get: { updates.automaticUpdates }, set: { updates.setAutomaticUpdates($0) }))
                .disabled(!updates.available)
                .help(u("updates.automatic.help"))
            Text(updates.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(u("updates.check")) { updates.check() }
                .disabled(!updates.available || !updates.canCheck)
            if let date = updates.lastCheck {
                Text(u("updates.lastCheck", date.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.wordsLocale)) + " · " + date.formatted(.dateTime.hour().minute().locale(Locale.current)))).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text(u("updates.preserve"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .help(u("updates.help"))
        }.frame(maxWidth: 580, alignment: .leading)
    }
}
