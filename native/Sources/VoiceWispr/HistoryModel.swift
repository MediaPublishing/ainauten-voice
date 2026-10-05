import Foundation
import AppKit
import UniformTypeIdentifiers
import VoiceWisprCore

enum HistoryCollection: String, CaseIterable, Identifiable {
    case all = "Alle", favorites = "Favoriten", trash = "Papierkorb"
    var id: String { rawValue }
    var title: String {
        switch self { case .all: L10n.text("history.collection.all"); case .favorites: L10n.text("history.collection.favorites"); case .trash: L10n.text("history.collection.trash") }
    }
}
enum HistoryPeriod: String, CaseIterable, Identifiable {
    case all = "Gesamt", week = "7 Tage", month = "30 Tage"
    var id: String { rawValue }
    var title: String {
        switch self { case .all: L10n.text("history.period.all"); case .week: L10n.text("history.period.week"); case .month: L10n.text("history.period.month") }
    }
    var since: Date? {
        guard self != .all else { return nil }
        return Calendar.current.date(byAdding: .day, value: self == .week ? -6 : -29, to: Calendar.current.startOfDay(for: Date()))
    }
}
struct HistoryCaptureContext {
    let date: Date
    let style: TextStyle
    let bundleID: String?
    let appName: String?
    let enabled: Bool
}

extension AppModel {
    var historyEnabled: Bool { document.settings.historyEnabled ?? true }
    var historyFilter: HistoryFilter { .init(search: historyQuery, since: historyPeriod.since, favoritesOnly: historyCollection == .favorites, trash: historyCollection == .trash) }

    func navigate(to section: SettingsSection) {
        settingsNavigation = SettingsNavigation(section: section, setupStep: nil)
        showSettings()
    }
    /// Only the capture completion path calls this, never delivery/recovery/copy actions.
    func recordHistory(_ result: DictationResult, context: HistoryCaptureContext, delivery: DeliveryStatus) {
        guard !isUIPreview, context.enabled, historyEnabled,
              !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let entry = HistoryEntry(result: result, createdAt: context.date, style: context.style,
            appBundleID: context.bundleID, appName: context.appName, delivery: delivery)
        let previous = historyWriteTask
        historyWriteTask = Task {
            await previous?.value
            do { try await historyStore.insert(entry); refreshHistory() }
            catch { historySaveError = L10n.text("history.saveFailed") }
        }
    }
    func refreshHistory(loadMore: Bool = false, debounce: Bool = false) {
        let id = UUID(); historyRequestID = id; historyReadTask?.cancel()
        let filter = historyFilter, limit = loadMore ? historyEntries.count + 50 : 50
        historyLoading = true
        if isUIPreview { refreshPreviewHistory(filter: filter, limit: limit); historyLoading = false; return }
        historyReadTask = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled else { return }
            do {
                // Fetch in bounded batches. "More" only extends the visible page;
                // metadata queries never read all transcript strings into memory.
                var entries: [HistoryEntry] = [], total = 0
                while entries.count < limit {
                    let page = try await historyStore.page(filter: filter, limit: min(500, limit - entries.count), offset: entries.count)
                    entries.append(contentsOf: page.entries); total = page.total
                    if entries.count >= total || page.entries.isEmpty { break }
                    guard !Task.isCancelled else { return }
                }
                let latest = try await historyStore.page(limit: 5)
                let allStats = try await historyStore.statistics()
                let stats = historyPeriod == .all ? allStats : try await historyStore.statistics(since: filter.since)
                guard historyRequestID == id, !Task.isCancelled else { return }
                historyEntries = entries; historyTotal = total; latestHistory = latest.entries
                allHistoryStatistics = allStats; historyStatistics = stats; historyError = nil; historyLoading = false
            } catch {
                guard historyRequestID == id else { return }
                historyError = error.localizedDescription; historyLoading = false
            }
        }
    }
    func favoriteHistory(_ entry: HistoryEntry) {
        if isUIPreview { mutatePreviewHistory(entry.id) { $0.favorite.toggle() }; return }
        Task { do { try await historyStore.setFavorite(entry.id, !entry.favorite); refreshHistory() } catch { historyError = error.localizedDescription } }
    }
    func trashHistory(_ entry: HistoryEntry) {
        let date = entry.deletedAt == nil ? Date() : nil
        if isUIPreview { mutatePreviewHistory(entry.id) { $0.deletedAt = date }; return }
        Task { do { try await historyStore.setDeleted(entry.id, at: date); refreshHistory() } catch { historyError = error.localizedDescription } }
    }
    func copyHistory(_ entry: HistoryEntry, original: Bool = false) {
        if !isUIPreview {
            // Explicit deliberate copy, same as Copy in any native text viewer.
            let text = original && !entry.original.isEmpty ? entry.original : entry.text
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(text, forType: .string) else { historyError = L10n.text("history.copyFailed"); return }
        }
        historyCopyID = entry.id
        Task { try? await Task.sleep(for: .seconds(1.5)); if historyCopyID == entry.id { historyCopyID = nil } }
    }
    func exportHistory() {
        guard !isUIPreview else { return }
        let panel = NSSavePanel(); panel.title = L10n.text("history.export.title"); panel.nameFieldStringValue = "AInauten-Voice-Verlauf.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { do { try await historyStore.export(to: url); historyNotice = L10n.text("history.exported") } catch { historyError = L10n.diagnostic(error.localizedDescription) } }
    }
    func resetHistory() {
        guard !isUIPreview, state != .recording, state != .processing else { return }
        let alert = NSAlert(); alert.messageText = L10n.text("history.reset.title")
        alert.informativeText = L10n.text("history.reset.message")
        alert.addButton(withTitle: L10n.text("common.moveToTrash")); alert.addButton(withTitle: L10n.text("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard state != .recording, state != .processing else { return }
        let pending = historyWriteTask
        historyWriteTask = Task {
            await pending?.value
            do { _ = try await historyStore.moveToTrash(); results = []; closeRecovery(); historySaveError = nil; historyNotice = L10n.text("history.reset.done"); refreshHistory() }
            catch { historyError = error.localizedDescription }
        }
    }

    // All fixture paths stay entirely in RAM; never instantiate a production query.
    func refreshPreviewHistory(filter: HistoryFilter, limit: Int) {
        #if DEBUG
        let items = historyPreviewEntries.filter { filter.includes($0) }.sorted { $0.createdAt > $1.createdAt }
        historyEntries = Array(items.prefix(limit)); historyTotal = items.count
        latestHistory = Array(historyPreviewEntries.filter { $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt }.prefix(5))
        let usage = historyPreviewEntries.filter { $0.isComplete && $0.deletedAt == nil }.map { HistoryUsage(date: $0.createdAt, words: $0.wordCount, duration: $0.duration, appID: $0.appBundleID ?? "", appName: $0.appName ?? "Andere Apps") }
        allHistoryStatistics = HistoryStatistics.calculate(usage)
        historyStatistics = HistoryStatistics.calculate(usage.filter { item in filter.since.map { item.date >= $0 } ?? true })
        #endif
    }
    func mutatePreviewHistory(_ id: UUID, mutation: (inout HistoryEntry) -> Void) {
        #if DEBUG
        if let index = historyPreviewEntries.firstIndex(where: { $0.id == id }) { mutation(&historyPreviewEntries[index]) }
        refreshHistory()
        #endif
    }
    #if DEBUG
    func loadHistoryPreview(empty: Bool = false) {
        guard isUIPreview else { return }
        let sentences = [
            "Vielen Dank für die Rückmeldung.\n\nDer überarbeitete Entwurf ist fertig. Bitte prüfe die Zahlen und gib mir bis morgen Bescheid.",
            "Erstelle eine kurze Übersicht: Was wurde umgesetzt, was ist noch offen und welcher nächste Schritt hilft uns am meisten?",
            "Die wichtigsten Punkte für die nächste Ausgabe:\n• Lokale Spracherkennung ausprobieren\n• Eigene Erfahrungen dokumentieren\n• Den fertigen Text gemeinsam prüfen",
            "Thanks for the update. Please send the final draft tomorrow, including the revised figures.",
            "Bitte verschiebe den Termin auf Donnerstag. Die Uhrzeit bleibt gleich.",
            "Der Text ist im Wörterbuch unter OpenAI gespeichert. Namen und Fachbegriffe sollen ihre richtige Schreibweise behalten."
        ]
        if !empty {
            historyPreviewEntries = (0..<16).map { index in
                let date = Calendar.current.date(byAdding: .day, value: -(index / 3), to: Date().addingTimeInterval(Double(-index * 1800)))!
                let text = sentences[index % sentences.count]
                return HistoryEntry(result: .init(id: UUID(), text: text, original: index == 0 ? "vielen Dank für die Rückmeldung der überarbeitete Entwurf ist fertig bitte prüfe die Zahlen und gib mir bis morgen Bescheid" : text, usedFallback: index == 11, duration: Double(14 + index), isComplete: index != 7), createdAt: date, style: index % 3 == 0 ? .email : .cleaned, appBundleID: index % 2 == 0 ? "com.apple.mail" : "com.apple.TextEdit", appName: index % 2 == 0 ? "Mail" : "TextEdit", delivery: index == 7 ? .notAttempted : index == 8 ? .uncertain : .confirmed, favorite: index == 1 || index == 3, deletedAt: index == 15 ? date : nil)
            }
        }
        document.dictionary = [.init(phrase: "OpenAI"), .init(phrase: "AInauten"), .init(phrase: "Chat GPT", replacement: "ChatGPT"), .init(phrase: "Projektstatus"), .init(phrase: "Mit"), .init(phrase: "Rückmeldung")]
        refreshHistory()
    }
    #endif
}
