import SwiftUI
import AppKit
import VoiceWisprCore

private let metricHelp = "Vollständige gespeicherte Diktate außerhalb des Papierkorbs. Wörter im Originaltext, sonst in der Ausgabe."
private let tempoHelp = "Erkannte Wörter pro Aufnahmeminute, einschließlich Pausen. Über alle gültigen Aufnahmezeiten gewichtet."

private func number(_ value: Int) -> String { value.formatted(.number.locale(Locale(identifier: "de_DE"))) }
private func time(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    return minutes >= 60 ? "\(minutes / 60) Std. \(minutes % 60) Min." : "\(minutes) Min."
}
private func dayTitle(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) { return "Heute" }
    if Calendar.current.isDateInYesterday(date) { return "Gestern" }
    return date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "de_DE")))
}
private struct HistoryGroup: Identifiable {
    let date: Date
    let entries: [HistoryEntry]
    var id: Date { date }
}
private func groups(_ entries: [HistoryEntry]) -> [HistoryGroup] {
    Dictionary(grouping: entries, by: { Calendar.current.startOfDay(for: $0.createdAt) })
        .map { HistoryGroup(date: $0.key, entries: $0.value) }.sorted { $0.date > $1.date }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    let availableWidth: CGFloat
    @State private var selection: HistoryEntry?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: model.state == .ready ? "checkmark.circle" : "waveform")
                    .foregroundStyle(model.state == .ready ? Color.green : Color.secondary)
                Text(model.state == .ready ? "Bereit zum Diktieren" : model.status).fontWeight(.medium)
                Spacer()
                Button { model.navigate(to: .dictation) } label: { Text(model.document.settings.shortcut.spokenLabel).font(.system(size: 11)).lineLimit(1) }
                    .help("Kürzel halten, sprechen und zum Einfügen loslassen. Kürzel und Sprache ändern.")
            }
            HistoryMessage(model: model)
            if availableWidth >= 700 {
                HStack(alignment: .top, spacing: 28) {
                    recent.frame(maxWidth: .infinity)
                    Divider()
                    usage.frame(width: 185)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) { compactUsage; recent }
            }
            Text(model.isUIPreview ? "Oberflächenvorschau · Beispieldaten, keine Nutzungswerte" : "Dein Verlauf beginnt mit den Diktaten ab dieser Version. Nur Text, nur auf diesem Mac.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.sheet(item: $selection) { entry in HistoryDetail(model: model, entry: entry) }
    }
    private var recent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Letzte Diktate").font(.system(size: 18, weight: .semibold)); Spacer(); Button("Alle anzeigen") { model.navigate(to: .history) }.buttonStyle(.plain).foregroundStyle(Color.accentColor) }
            if model.latestHistory.isEmpty {
                EmptyHistory(model: model, filtered: false)
            } else {
                HistoryRows(model: model, entries: model.latestHistory, selection: $selection)
            }
        }
    }
    private var usage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("DEINE NUTZUNG").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Metric(value: number(model.allHistoryStatistics.words), title: "erkannte Wörter", help: metricHelp)
            Metric(value: model.allHistoryStatistics.wordsPerMinute.map { number(Int($0.rounded())) } ?? "–", title: "Wörter / Minute", help: tempoHelp)
            Divider()
            Metric(value: time(model.allHistoryStatistics.duration), title: "Aufnahmezeit", help: "Gesamte Dauer vollständiger gespeicherter Aufnahmen.")
            Text("\(number(model.allHistoryStatistics.dictations)) Diktate · \(number(model.allHistoryStatistics.activeDays)) aktive Tage").font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Statistik ansehen") { model.navigate(to: .statistics) }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
    private var compactUsage: some View {
        HStack(alignment: .top, spacing: 24) {
            Metric(value: number(model.allHistoryStatistics.words), title: "Wörter", help: metricHelp)
            Spacer(minLength: 0)
            Metric(value: model.allHistoryStatistics.wordsPerMinute.map { number(Int($0.rounded())) } ?? "–", title: "Wörter / Min.", help: tempoHelp)
            Spacer(minLength: 0)
            Metric(value: number(model.allHistoryStatistics.dictations), title: "Diktate", help: metricHelp)
        }.padding(.vertical, 6)
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var selection: HistoryEntry?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HistoryMessage(model: model)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Diktate durchsuchen", text: $model.historyQuery).textFieldStyle(.plain).accessibilityLabel("Diktate durchsuchen")
                if !model.historyQuery.isEmpty { WindowCloseButton(label: "Suche leeren") { model.historyQuery = "" } }
            }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            ViewThatFits(in: .horizontal) {
                HStack { filters; Spacer(minLength: 20); historyPeriod }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 12) { filters; historyPeriod }
            }
            HStack {
                Text("\(number(model.historyTotal)) \(model.historyTotal == 1 ? "Diktat" : "Diktate")").foregroundStyle(.secondary)
                if model.historyLoading { ProgressView().controlSize(.small).accessibilityLabel("Verlauf wird geladen") }
                Spacer()
                Button { model.exportHistory() } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.plain).help("Verlauf als JSON exportieren, ohne Papierkorb").accessibilityLabel("Verlauf exportieren")
            }
            if model.historyEntries.isEmpty && !model.historyLoading {
                EmptyHistory(model: model, filtered: model.historyCollection != .all || !model.historyQuery.isEmpty || model.historyPeriod != .all)
            } else {
                HistoryRows(model: model, entries: model.historyEntries, selection: $selection)
            }
            if model.historyEntries.count < model.historyTotal {
                Button("Weitere Diktate anzeigen") { model.refreshHistory(loadMore: true) }.disabled(model.historyLoading)
            }
        }
        .onChange(of: model.historyQuery) { _, _ in model.refreshHistory(debounce: true) }
        .onChange(of: model.historyCollection) { _, _ in model.refreshHistory() }
        .onChange(of: model.historyPeriod) { _, _ in model.refreshHistory() }
        .sheet(item: $selection) { entry in HistoryDetail(model: model, entry: entry) }
    }
    private var filters: some View {
        Picker("Verlauf", selection: $model.historyCollection) { ForEach(HistoryCollection.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Verlauf filtern").frame(width: 280)
    }
    private var historyPeriod: some View {
        Picker("Zeitraum", selection: $model.historyPeriod) { ForEach(HistoryPeriod.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 160)
    }
}

private struct HistoryMessage: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let error = model.historySaveError ?? model.historyError {
            HStack(alignment: .top) {
                Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
                if model.historySaveError != nil { WindowCloseButton(label: "Speicherhinweis schließen") { model.historySaveError = nil } }
            }
        } else if !model.historyEnabled {
            HStack { Label("Verlauf für neue Diktate ausgeschaltet", systemImage: "lock"); Spacer(); Button("Ändern") { model.navigate(to: .privacy) } }.font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
private struct EmptyHistory: View {
    @ObservedObject var model: AppModel
    let filtered: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: filtered ? "magnifyingglass" : "waveform").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(filtered ? "Keine passenden Diktate" : "Dein nächstes Diktat bleibt hier erreichbar.").font(.system(size: 17, weight: .semibold))
            Text(filtered ? "Ändere die Suche oder den Filter. Texte im Papierkorb lassen sich wiederherstellen." : "Setze den Cursor in ein Textfeld. Halte dein Kürzel beim Sprechen und lasse es zum Einfügen los. Den Text findest du danach auch hier.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !filtered { Button("Kürzel und Sprache ansehen") { model.navigate(to: .dictation) } }
        }.padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct HistoryRows: View {
    @ObservedObject var model: AppModel
    let entries: [HistoryEntry]
    @Binding var selection: HistoryEntry?
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(groups(entries)) { group in
                VStack(alignment: .leading, spacing: 5) {
                    Text(dayTitle(group.date)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 6)
                    ForEach(group.entries) { entry in
                        HistoryRow(model: model, entry: entry) { selection = entry }
                        if entry.id != group.entries.last?.id { Divider() }
                    }
                }
            }
        }
    }
}
private struct HistoryRow: View {
    @ObservedObject var model: AppModel
    let entry: HistoryEntry
    let open: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.text).lineLimit(3).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 7) {
                        Text(entry.createdAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE")))).monospacedDigit()
                        Text("·")
                        Text(entry.appName ?? "Andere Apps").lineLimit(1)
                        if !entry.isComplete { Label("Teiltext", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                        else if entry.usedFallback { Text("Original verwendet").help("Die Textoptimierung war nicht verfügbar. Der erkannte Text blieb erhalten.") }
                        Image(systemName: entry.delivery == .confirmed ? "checkmark" : "questionmark.circle").help(deliveryTitle(entry.delivery))
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).pointerAwareFocus().accessibilityLabel("Diktat von \(dayTitle(entry.createdAt)), \(entry.createdAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE")))). \(entry.text)")
            VStack(spacing: 10) {
                if entry.deletedAt != nil {
                    Button { model.trashHistory(entry) } label: { Image(systemName: "arrow.uturn.backward") }.help("Diktat wiederherstellen").accessibilityLabel("Diktat wiederherstellen")
                } else {
                    Button { model.favoriteHistory(entry) } label: { Image(systemName: entry.favorite ? "star.fill" : "star") }.foregroundStyle(entry.favorite ? Color.accentColor : Color.secondary).help(entry.favorite ? "Favorit entfernen" : "Als Favorit merken").accessibilityLabel(entry.favorite ? "Favorit entfernen" : "Als Favorit merken")
                    Button { model.copyHistory(entry) } label: { Image(systemName: model.historyCopyID == entry.id ? "checkmark" : "doc.on.doc") }.help(model.historyCopyID == entry.id ? "Kopiert" : "Text kopieren").accessibilityLabel("Text kopieren")
                }
            }.buttonStyle(.plain).pointerAwareFocus().padding(.top, 10)
        }.padding(.horizontal, 10).background(hovering ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 7)).onHover { hovering = $0 }
        .contextMenu {
            Button("Text öffnen", action: open)
            Button("Kopieren") { model.copyHistory(entry) }
            if !entry.original.isEmpty && entry.original != entry.text { Button("Original kopieren") { model.copyHistory(entry, original: true) } }
            Button(entry.favorite ? "Favorit entfernen" : "Als Favorit merken") { model.favoriteHistory(entry) }
            Button(entry.deletedAt == nil ? "In den Papierkorb" : "Wiederherstellen") { model.trashHistory(entry) }
        }
    }
}
private func deliveryTitle(_ status: DeliveryStatus) -> String {
    switch status {
    case .confirmed: "Einfügen bestätigt"
    case .uncertain: "Einfügen nicht bestätigt. Vor erneutem Einfügen das Textfeld prüfen."
    case .failed: "Einfügen fehlgeschlagen"
    case .notAttempted: "Nicht automatisch eingefügt"
    }
}

private struct HistoryDetail: View {
    @ObservedObject var model: AppModel
    let entry: HistoryEntry
    @Environment(\.dismiss) private var dismiss
    @State private var original = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(dayTitle(entry.createdAt)).font(.system(size: 20, weight: .semibold))
                    Text("\(entry.createdAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE")))) · \(entry.appName ?? "Andere Apps") · \(entry.style.title)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(); WindowCloseButton(label: "Diktat schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if !entry.original.isEmpty && entry.original != entry.text {
                Picker("Textfassung", selection: $original) { Text("Aufbereitet").tag(false); Text("Original").tag(true) }.pickerStyle(.segmented).frame(maxWidth: 280)
            }
            if !entry.isComplete { Label("Unvollständiger Teiltext", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            ScrollView { Text(original ? entry.original : entry.text).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(deliveryTitle(entry.delivery)).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button(entry.deletedAt == nil ? "In den Papierkorb" : "Wiederherstellen") { model.trashHistory(entry); dismiss() }
                Spacer()
                Button { model.copyHistory(entry, original: original) } label: { Label(model.historyCopyID == entry.id ? "Kopiert" : "Kopieren", systemImage: model.historyCopyID == entry.id ? "checkmark" : "doc.on.doc") }.keyboardShortcut("c", modifiers: .command)
            }
        }.padding(24).frame(width: 570, height: detailHeight)
    }
    private var detailHeight: CGFloat {
        let text = original ? entry.original : entry.text
        let size = (text as NSString).boundingRect(with: NSSize(width: 522, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let variants: CGFloat = !entry.original.isEmpty && entry.original != entry.text ? 44 : 0
        return min(600, max(300, ceil(size.height) + 220 + variants + (entry.isComplete ? 0 : 28)))
    }
}

private struct Metric: View {
    let value: String
    let title: String
    let help: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 27, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }.help(help).accessibilityElement(children: .combine)
    }
}
struct StatisticsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Text("Deine Nutzung").font(.system(size: 17, weight: .semibold)); Spacer()
                Picker("Zeitraum", selection: $model.historyPeriod) { ForEach(HistoryPeriod.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 165)
            }
            HistoryMessage(model: model)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), alignment: .leading)], alignment: .leading, spacing: 20) {
                Metric(value: number(model.historyStatistics.words), title: "erkannte Wörter", help: metricHelp)
                Metric(value: model.historyStatistics.wordsPerMinute.map { number(Int($0.rounded())) } ?? "–", title: "Wörter / Minute", help: tempoHelp)
                Metric(value: time(model.historyStatistics.duration), title: "Aufnahmezeit", help: "Die Aufnahmezeit enthält Sprechpausen.")
                Metric(value: number(model.historyStatistics.dictations), title: "Diktate", help: metricHelp)
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("Die letzten 14 Tage").font(.system(size: 17, weight: .semibold)); Spacer(); Text("Wörter").font(.system(size: 11)).foregroundStyle(.secondary) }
                ActivityBars(days: model.allHistoryStatistics.days)
                Text("\(number(model.historyStatistics.activeDays)) aktive Tage im Zeitraum · \(number(model.allHistoryStatistics.currentStreak)) Tage in Folge").font(.system(size: 12)).foregroundStyle(.secondary).help("Die aktuelle Folge endet heute oder gestern und berücksichtigt vollständige gespeicherte Diktate.")
            }
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text("Wo du diktierst").font(.system(size: 17, weight: .semibold))
                if model.historyStatistics.apps.isEmpty { Text("Nach deinem ersten Diktat erscheint hier die Ziel-App.").foregroundStyle(.secondary) }
                ForEach(model.historyStatistics.apps.prefix(8)) { app in
                    HStack(spacing: 14) {
                        Text(app.name).frame(width: 100, alignment: .leading).lineLimit(1)
                        GeometryReader { geometry in
                            Capsule().fill(Color.accentColor.opacity(0.16)).overlay(alignment: .leading) {
                                Capsule().fill(Color.accentColor).frame(width: max(2, geometry.size.width * Double(app.words) / Double(max(1, model.historyStatistics.apps.first?.words ?? 1))))
                            }
                        }.frame(height: 8).accessibilityHidden(true)
                        Text(number(app.words)).monospacedDigit().frame(width: 65, alignment: .trailing)
                    }.help("\(app.name): \(number(app.words)) erkannte Wörter in \(number(app.dictations)) Diktaten").accessibilityElement(children: .combine)
                }
            }
            Text("Nur lokal gespeicherte, vollständige Diktate zählen. Probediktate und Texte im Papierkorb sind ausgeschlossen. Keine Statistik aus alten Wispr-Flow-Daten.").font(.system(size: 11)).foregroundStyle(.secondary)
        }.onChange(of: model.historyPeriod) { _, _ in model.refreshHistory() }
    }
}
private struct ActivityBars: View {
    let days: [HistoryDay]
    var body: some View {
        let maximum = max(1, days.map(\.words).max() ?? 0)
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(days) { day in
                VStack(spacing: 7) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3).fill(day.words == 0 ? Color.primary.opacity(0.06) : Color.accentColor.opacity(0.8))
                        .frame(height: max(3, 86 * Double(day.words) / Double(maximum)))
                    Text(day.date.formatted(.dateTime.day())).font(.system(size: 9)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).help("\(day.date.formatted(date: .long, time: .omitted)): \(number(day.words)) Wörter, \(number(day.dictations)) Diktate")
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(day.date.formatted(date: .long, time: .omitted)), \(number(day.words)) Wörter")
            }
        }.frame(height: 112)
    }
}
