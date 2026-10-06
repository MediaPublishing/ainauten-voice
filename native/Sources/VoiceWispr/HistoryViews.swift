import SwiftUI
import AppKit
import VoiceWisprCore

private func v(_ key: String, _ args: String... ) -> String { L10n.format(key, arguments: args) }

private var metricHelp: String { v("history.metric.words.help") }
private var tempoHelp: String { v("history.metric.tempo.help") }

private func number(_ value: Int) -> String { value.formatted(.number.locale(Locale.current)) }
private func time(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    return minutes >= 60 ? v("history.duration.hours", "\(minutes / 60)", "\(minutes % 60)") : v("history.duration.minutes", "\(minutes)")
}
private func dayTitle(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) { return v("history.day.today") }
    if Calendar.current.isDateInYesterday(date) { return v("history.day.yesterday") }
    return date.formatted(.dateTime.day().month(.wide).locale(L10n.wordsLocale))
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
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
    let availableWidth: CGFloat
    @State private var selection: HistoryEntry?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: model.state == .ready ? "checkmark.circle" : "waveform")
                    .foregroundStyle(model.state == .ready ? Color.green : Color.secondary)
                Text(model.state == .ready ? v("history.ready") : L10n.diagnostic(model.status)).fontWeight(.medium)
                Spacer()
                Button { model.navigate(to: .dictation) } label: { Text(model.document.settings.shortcut.spokenLabel).font(.system(size: 11)).lineLimit(1) }
                    .help(v("history.shortcut.help"))
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
            Text(model.isUIPreview ? v("history.preview") : v("history.localNotice"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.sheet(item: $selection) { entry in HistoryDetail(model: model, entry: entry) }
    }
    private var recent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(v("history.recent")).font(.system(size: 18, weight: .semibold)); Spacer(); Button(v("history.showAll")) { model.navigate(to: .history) }.buttonStyle(.plain).foregroundStyle(Color.accentColor) }
            if model.latestHistory.isEmpty {
                EmptyHistory(model: model, filtered: false)
            } else {
                HistoryRows(model: model, entries: model.latestHistory, selection: $selection)
            }
        }
    }
    private var usage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(v("history.usage.title")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Metric(value: number(model.allHistoryStatistics.words), title: v("history.words"), help: metricHelp)
            Metric(value: model.allHistoryStatistics.wordsPerMinute.map { number(Int($0.rounded())) } ?? "–", title: v("history.wordsPerMinute"), help: tempoHelp)
            Divider()
            Metric(value: time(model.allHistoryStatistics.duration), title: v("history.recordingTime"), help: v("history.recordingTime.help"))
            Text(L10n.plural("history.count", count: model.allHistoryStatistics.dictations) + " · " + L10n.plural("history.activeDayCount", count: model.allHistoryStatistics.activeDays)).font(.system(size: 12)).foregroundStyle(.secondary)
            Button(v("history.showStats")) { model.navigate(to: .statistics) }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
    private var compactUsage: some View {
        HStack(alignment: .top, spacing: 24) {
            Metric(value: number(model.allHistoryStatistics.words), title: v("history.words.short"), help: metricHelp)
            Spacer(minLength: 0)
            Metric(value: model.allHistoryStatistics.wordsPerMinute.map { number(Int($0.rounded())) } ?? "–", title: v("history.wordsPerMinute.short"), help: tempoHelp)
            Spacer(minLength: 0)
            Metric(value: number(model.allHistoryStatistics.dictations), title: v("history.dictations"), help: metricHelp)
        }.padding(.vertical, 6)
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
    @State private var selection: HistoryEntry?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HistoryMessage(model: model)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(v("history.search"), text: $model.historyQuery).textFieldStyle(.plain).accessibilityLabel(v("history.search"))
                if !model.historyQuery.isEmpty { WindowCloseButton(label: L10n.text("history.clearSearch")) { model.historyQuery = "" } }
            }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            ViewThatFits(in: .horizontal) {
                HStack { filters; Spacer(minLength: 20); historyPeriod }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 12) { filters; historyPeriod }
            }
            HStack {
                Text(L10n.plural("history.count", count: model.historyTotal)).foregroundStyle(.secondary)
                if model.historyLoading { ProgressView().controlSize(.small).accessibilityLabel(L10n.text("history.loading")) }
                Spacer()
                Button { model.exportHistory() } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.plain).help(v("history.export.help")).accessibilityLabel(v("history.export"))
            }
            if model.historyEntries.isEmpty && !model.historyLoading {
                EmptyHistory(model: model, filtered: model.historyCollection != .all || !model.historyQuery.isEmpty || model.historyPeriod != .all)
            } else {
                HistoryRows(model: model, entries: model.historyEntries, selection: $selection)
            }
            if model.historyEntries.count < model.historyTotal {
                Button(v("history.more")) { model.refreshHistory(loadMore: true) }.disabled(model.historyLoading)
            }
        }
        .onChange(of: model.historyQuery) { _, _ in model.refreshHistory(debounce: true) }
        .onChange(of: model.historyCollection) { _, _ in model.refreshHistory() }
        .onChange(of: model.historyPeriod) { _, _ in model.refreshHistory() }
        .sheet(item: $selection) { entry in HistoryDetail(model: model, entry: entry) }
    }
    private var filters: some View {
        Picker(v("history.filter"), selection: $model.historyCollection) { ForEach(HistoryCollection.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(v("history.filter" )).frame(width: 280)
    }
    private var historyPeriod: some View {
        Picker(v("history.period"), selection: $model.historyPeriod) { ForEach(HistoryPeriod.allCases) { Text($0.title).tag($0) } }.frame(width: 160)
    }
}

private struct HistoryMessage: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let error = model.historySaveError ?? model.historyError {
            HStack(alignment: .top) {
                Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
                if model.historySaveError != nil { WindowCloseButton(label: L10n.text("history.dismissSave")) { model.historySaveError = nil } }
            }
        } else if !model.historyEnabled {
            HStack { Label(v("history.disabled"), systemImage: "lock"); Spacer(); Button(v("common.change")) { model.navigate(to: .privacy) } }.font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
private struct EmptyHistory: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
    let filtered: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: filtered ? "magnifyingglass" : "waveform").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(filtered ? v("history.noMatches") : v("history.empty.title")).font(.system(size: 17, weight: .semibold))
            Text(filtered ? v("history.noMatches.help") : v("history.empty.help"))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !filtered { Button(v("history.shortcut.language")) { model.navigate(to: .dictation) } }
        }.padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct HistoryRows: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
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
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
    let entry: HistoryEntry
    let open: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.text).lineLimit(3).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 7) {
                        Text(entry.createdAt.formatted(.dateTime.hour().minute().locale(Locale.current))).monospacedDigit()
                        Text("·")
                        Text(entry.appName ?? L10n.text("history.otherApps")).lineLimit(1)
                        if !entry.isComplete { Label(v("history.partial"), systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                        else if entry.usedFallback { Text(v("history.originalUsed")).help(v("history.originalUsed.help")) }
                        Image(systemName: entry.delivery == .confirmed ? "checkmark" : "questionmark.circle").help(deliveryTitle(entry.delivery))
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).pointerAwareFocus().accessibilityLabel(L10n.text("history.rowAX", dayTitle(entry.createdAt), entry.createdAt.formatted(.dateTime.hour().minute().locale(Locale.current)), entry.text))
            VStack(spacing: 10) {
                if entry.deletedAt != nil {
                    Button { model.trashHistory(entry) } label: { Image(systemName: "arrow.uturn.backward") }.help(L10n.text("history.restore")).accessibilityLabel(L10n.text("history.restore"))
                } else {
                    Button { model.favoriteHistory(entry) } label: { Image(systemName: entry.favorite ? "star.fill" : "star") }.foregroundStyle(entry.favorite ? Color.accentColor : Color.secondary).help(entry.favorite ? L10n.text("history.unfavorite") : L10n.text("history.favorite")).accessibilityLabel(entry.favorite ? L10n.text("history.unfavorite") : L10n.text("history.favorite"))
                    Button { model.copyHistory(entry) } label: { Image(systemName: model.historyCopyID == entry.id ? "checkmark" : "doc.on.doc") }.help(model.historyCopyID == entry.id ? L10n.text("history.copied") : L10n.text("history.copyText")).accessibilityLabel(L10n.text("history.copyText"))
                }
            }.buttonStyle(.plain).pointerAwareFocus().padding(.top, 10)
        }.padding(.horizontal, 10).background(hovering ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 7)).onHover { hovering = $0 }
        .contextMenu {
            Button(L10n.text("history.openText"), action: open)
            Button(L10n.text("common.copy")) { model.copyHistory(entry) }
            if !entry.original.isEmpty && entry.original != entry.text { Button(L10n.text("history.copyOriginal")) { model.copyHistory(entry, original: true) } }
            Button(entry.favorite ? L10n.text("history.unfavorite") : L10n.text("history.favorite")) { model.favoriteHistory(entry) }
            Button(entry.deletedAt == nil ? L10n.text("history.trash") : L10n.text("history.restoreBrief")) { model.trashHistory(entry) }
        }
    }
}
private func deliveryTitle(_ status: DeliveryStatus) -> String {
    switch status {
    case .confirmed: v("history.delivery.confirmed")
    case .uncertain: v("history.delivery.uncertain")
    case .failed: v("history.delivery.failed")
    case .notAttempted: v("history.delivery.notAttempted")
    }
}

private struct HistoryDetail: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
    let entry: HistoryEntry
    @Environment(\.dismiss) private var dismiss
    @State private var original = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(dayTitle(entry.createdAt)).font(.system(size: 20, weight: .semibold))
                    Text("\(entry.createdAt.formatted(.dateTime.hour().minute().locale(Locale.current))) · \(entry.appName ?? L10n.text("history.otherApps")) · \(entry.style.interfaceTitle)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(); WindowCloseButton(label: L10n.text("history.closeDetail")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if !entry.original.isEmpty && entry.original != entry.text {
                Picker(L10n.text("history.variant"), selection: $original) { Text(L10n.text("history.processed")).tag(false); Text(L10n.text("history.original")).tag(true) }.pickerStyle(.segmented).frame(maxWidth: 280)
            }
            if !entry.isComplete { Label(L10n.text("history.incomplete"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            ScrollView { Text(original ? entry.original : entry.text).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(deliveryTitle(entry.delivery)).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button(entry.deletedAt == nil ? L10n.text("history.trash") : L10n.text("history.restoreBrief")) { model.trashHistory(entry); dismiss() }
                Spacer()
                Button { model.copyHistory(entry, original: original) } label: { Label(model.historyCopyID == entry.id ? L10n.text("history.copied") : L10n.text("common.copy"), systemImage: model.historyCopyID == entry.id ? "checkmark" : "doc.on.doc") }.keyboardShortcut("c", modifiers: .command)
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
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Text(L10n.text("history.stats.usage")).font(.system(size: 17, weight: .semibold)); Spacer()
                Picker(L10n.text("history.stats.period"), selection: $model.historyPeriod) { ForEach(HistoryPeriod.allCases) { Text($0.title).tag($0) } }.frame(width: 165)
            }
            HistoryMessage(model: model)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), alignment: .leading)], alignment: .leading, spacing: 20) {
                Metric(value: number(model.historyStatistics.words), title: L10n.text("history.metric.words"), help: metricHelp)
                Metric(value: model.historyStatistics.wordsPerMinute.map { number(Int($0.rounded())) } ?? "–", title: L10n.text("history.metric.speed"), help: tempoHelp)
                Metric(value: time(model.historyStatistics.duration), title: L10n.text("history.metric.time"), help: L10n.text("history.metric.pauseHelp"))
                Metric(value: number(model.historyStatistics.dictations), title: L10n.text("history.metric.dictations"), help: metricHelp)
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text(L10n.text("history.stats.fortnight")).font(.system(size: 17, weight: .semibold)); Spacer(); Text(L10n.text("history.metric.wordsBrief")).font(.system(size: 11)).foregroundStyle(.secondary) }
                ActivityBars(days: model.allHistoryStatistics.days)
                Text(L10n.text("history.stats.streak", number(model.historyStatistics.activeDays), number(model.allHistoryStatistics.currentStreak))).font(.system(size: 12)).foregroundStyle(.secondary).help(L10n.text("history.stats.streakHelp"))
            }
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("history.stats.apps")).font(.system(size: 17, weight: .semibold))
                if model.historyStatistics.apps.isEmpty { Text(L10n.text("history.stats.noApps")).foregroundStyle(.secondary) }
                ForEach(model.historyStatistics.apps.prefix(8)) { app in
                    HStack(spacing: 14) {
                        Text(app.name).frame(width: 100, alignment: .leading).lineLimit(1)
                        GeometryReader { geometry in
                            Capsule().fill(Color.accentColor.opacity(0.16)).overlay(alignment: .leading) {
                                Capsule().fill(Color.accentColor).frame(width: max(2, geometry.size.width * Double(app.words) / Double(max(1, model.historyStatistics.apps.first?.words ?? 1))))
                            }
                        }.frame(height: 8).accessibilityHidden(true)
                        Text(number(app.words)).monospacedDigit().frame(width: 65, alignment: .trailing)
                    }.help(L10n.text("history.stats.appHelp", app.name, number(app.words), number(app.dictations))).accessibilityElement(children: .combine)
                }
            }
            Text(L10n.text("history.stats.scope")).font(.system(size: 11)).foregroundStyle(.secondary)
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
                }.frame(maxWidth: .infinity).help(L10n.text("history.stats.dayHelp", day.date.formatted(.dateTime.day().month(.wide).year().locale(L10n.wordsLocale)), number(day.words), number(day.dictations)))
                    .accessibilityElement(children: .ignore).accessibilityLabel(L10n.text("history.stats.dayAX", day.date.formatted(.dateTime.day().month(.wide).year().locale(L10n.wordsLocale)), number(day.words)))
            }
        }.frame(height: 112)
    }
}
