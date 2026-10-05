import SwiftUI
import VoiceWisprCore

private enum DictionaryKind: String, CaseIterable, Identifiable {
    case all = "Alle", words = "Wörter", replacements = "Ersetzungen"
    var id: String { rawValue }
}
struct DictionaryEditor: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var kind: DictionaryKind = .all
    @State private var matches: [DictionaryEntry] = []
    @State private var limit = 100
    @State private var editingID: String?
    @State private var editorOpen = false
    @State private var phrase = ""
    @State private var replacement = ""
    @State private var validation = ""
    @State private var removed: (entry: DictionaryEntry, index: Int)?
    @FocusState private var phraseFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Namen, Fachwörter und Ersetzungen").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button { edit(nil) } label: { Image(systemName: "plus").frame(width: 24, height: 24).contentShape(Rectangle()) }.buttonStyle(.plain).help("Neuen Eintrag hinzufügen").accessibilityLabel("Neuen Eintrag hinzufügen")
            }
            Text("Wörter geben Schreibweisenhinweise. Ersetzungen ändern den erkannten Text gezielt.").font(.system(size: 12)).foregroundStyle(.secondary)
            if editorOpen {
                VStack(alignment: .leading, spacing: 12) {
                    Text(editingID == nil ? "Neuer Eintrag" : "Eintrag bearbeiten").fontWeight(.semibold)
                    TextField("Wort oder Ausdruck", text: $phrase).focused($phraseFocused).textFieldStyle(.roundedBorder)
                    TextField("Ersetzen durch (optional)", text: $replacement).textFieldStyle(.roundedBorder)
                    if !validation.isEmpty { Text(validation).font(.system(size: 12)).foregroundStyle(.orange) }
                    HStack { Text("Ohne Ersetzung bleibt die erkannte Groß-/Kleinschreibung erhalten.").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Button("Abbrechen") { editorOpen = false; validation = "" }; Button("Speichern", action: save).buttonStyle(.borderedProminent).disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Wörter und Ersetzungen suchen", text: $query).textFieldStyle(.plain)
                if !query.isEmpty { WindowCloseButton(label: "Wörterbuchsuche leeren") { query = "" } }
            }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            ViewThatFits(in: .horizontal) {
                HStack { filters; Spacer(minLength: 20); Text("\(matches.count) \(matches.count == 1 ? "Eintrag" : "Einträge")").foregroundStyle(.secondary) }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 10) { filters; Text("\(matches.count) \(matches.count == 1 ? "Eintrag" : "Einträge")").foregroundStyle(.secondary) }
            }
            if let removed {
                HStack { Text("„\(removed.entry.phrase)“ entfernt").lineLimit(1); Spacer(); Button("Rückgängig") {
                    if !model.document.dictionary.contains(where: { $0.id == removed.entry.id }) { model.document.dictionary.insert(removed.entry, at: min(removed.index, model.document.dictionary.count)) }
                    self.removed = nil
                } }.font(.system(size: 12)).padding(.vertical, 4)
            }
            Divider()
            if matches.isEmpty { Text("Keine passenden Einträge. Füge ein Wort hinzu oder ändere die Suche.").foregroundStyle(.secondary).padding(.vertical, 12) }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(matches.prefix(limit)) { entry in
                    HStack(spacing: 12) {
                        Button { edit(entry) } label: {
                            VStack(alignment: .leading, spacing: 4) { Text(entry.phrase); if let replacement = entry.replacement { Text("→ \(replacement)").font(.system(size: 12)).foregroundStyle(.secondary) } }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain).pointerAwareFocus().help("Eintrag bearbeiten")
                        if entry.manuallyModified { Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(.tertiary).help("Manuell bearbeitet. Diese Fassung hat beim Wispr-Flow-Import Vorrang.") }
                        Button { remove(entry) } label: { Image(systemName: "minus.circle").frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).pointerAwareFocus().foregroundStyle(.secondary).help("Eintrag entfernen").accessibilityLabel("\(entry.phrase) entfernen")
                    }
                    Divider()
                }
            }
            if limit < matches.count { Button("Weitere Einträge anzeigen") { limit += 100 } }
            HStack { Button("Exportieren …") { model.exportSettings() }; Button("Importieren …") { model.importSettings() }; Spacer(); Text("\(model.document.dictionary.count) insgesamt").font(.system(size: 11)).foregroundStyle(.secondary) }
                .padding(.top, 6).disabled(model.isUIPreview)
        }.onAppear(perform: filter)
            .onChange(of: query) { _, _ in filter() }
            .onChange(of: kind) { _, _ in filter() }
            .onChange(of: model.document.dictionary) { _, _ in filter() }
    }
    private var filters: some View { Picker("Eintragsart", selection: $kind) { ForEach(DictionaryKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Eintragsart filtern").frame(width: 265) }
    private func filter() {
        let key = HistoryWords.searchKey(query.trimmingCharacters(in: .whitespacesAndNewlines))
        matches = model.document.dictionary.filter { entry in
            let replacement = entry.replacement?.isEmpty == false
            return (kind == .all || (kind == .replacements ? replacement : !replacement)) && (key.isEmpty || HistoryWords.searchKey(entry.phrase + "\n" + (entry.replacement ?? "")).contains(key))
        }.sorted { $0.phrase.localizedStandardCompare($1.phrase) == .orderedAscending }
        limit = 100
    }
    private func edit(_ entry: DictionaryEntry?) {
        editingID = entry?.id; phrase = entry?.phrase ?? ""; replacement = entry?.replacement ?? ""
        validation = ""; editorOpen = true; phraseFocused = true
    }
    private func save() {
        let name = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 255, target.utf8.count <= 1_000_000 else { validation = "Ein Wort darf höchstens 255 Zeichen enthalten. Bitte kürze den Eintrag."; return }
        guard !model.document.dictionary.contains(where: { $0.id != editingID && $0.phrase == name && ($0.replacement ?? "") == target }) else { validation = "Dieser Eintrag ist bereits vorhanden."; return }
        if let editingID, let index = model.document.dictionary.firstIndex(where: { $0.id == editingID }) {
            model.document.dictionary[index].phrase = name; model.document.dictionary[index].replacement = target.isEmpty ? nil : target; model.document.dictionary[index].manuallyModified = true
        } else { model.document.dictionary.append(.init(phrase: name, replacement: target.isEmpty ? nil : target, manuallyModified: true)) }
        editorOpen = false; editingID = nil; phrase = ""; replacement = ""
    }
    private func remove(_ entry: DictionaryEntry) {
        guard let index = model.document.dictionary.firstIndex(where: { $0.id == entry.id }) else { return }
        removed = (entry, index); model.document.dictionary.remove(at: index)
        if editingID == entry.id { editorOpen = false; editingID = nil }
    }
}
