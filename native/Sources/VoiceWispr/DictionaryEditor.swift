import SwiftUI
import VoiceWisprCore

private func d(_ key: String, _ args: String... ) -> String { L10n.format(key, arguments: args) }

private enum DictionaryKind: String, CaseIterable, Identifiable {
    case all, words, replacements
    var id: String { rawValue }
    var title: String { d("dictionary.kind.\(rawValue)") }
}
struct DictionaryEditor: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
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
                Text(d("dictionary.title")).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button { edit(nil) } label: { Image(systemName: "plus").frame(width: 24, height: 24).contentShape(Rectangle()) }.buttonStyle(.plain).help(d("dictionary.add")).accessibilityLabel(d("dictionary.add"))
            }
            Text(d("dictionary.subtitle")).font(.system(size: 12)).foregroundStyle(.secondary)
            if editorOpen {
                VStack(alignment: .leading, spacing: 12) {
                    Text(editingID == nil ? d("dictionary.new") : d("dictionary.edit")).fontWeight(.semibold)
                    TextField(d("dictionary.phrase.placeholder"), text: $phrase).focused($phraseFocused).textFieldStyle(.roundedBorder)
                    TextField(d("dictionary.replacement.placeholder"), text: $replacement).textFieldStyle(.roundedBorder)
                    if !validation.isEmpty { Text(L10n.diagnostic(validation)).font(.system(size: 12)).foregroundStyle(.orange) }
                    HStack { Text(d("dictionary.caseHint")).font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Button(d("common.cancel")) { editorOpen = false; validation = "" }; Button(d("common.save"), action: save).buttonStyle(.borderedProminent).disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(d("dictionary.search"), text: $query).textFieldStyle(.plain)
                if !query.isEmpty { WindowCloseButton(label: d("dictionary.clearSearch")) { query = "" } }
            }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            ViewThatFits(in: .horizontal) {
                HStack { filters; Spacer(minLength: 20); Text(L10n.plural("dictionary.entryCount", count: matches.count)).foregroundStyle(.secondary) }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 10) { filters; Text(L10n.plural("dictionary.entryCount", count: matches.count)).foregroundStyle(.secondary) }
            }
            if let removed {
                HStack { Text(d("dictionary.removed", removed.entry.phrase)).lineLimit(1); Spacer(); Button(d("common.undo")) {
                    if !model.document.dictionary.contains(where: { $0.id == removed.entry.id }) { model.document.dictionary.insert(removed.entry, at: min(removed.index, model.document.dictionary.count)) }
                    self.removed = nil
                } }.font(.system(size: 12)).padding(.vertical, 4)
            }
            Divider()
            if matches.isEmpty { Text(d("dictionary.empty")).foregroundStyle(.secondary).padding(.vertical, 12) }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(matches.prefix(limit)) { entry in
                    HStack(spacing: 12) {
                        Button { edit(entry) } label: {
                            VStack(alignment: .leading, spacing: 4) { Text(entry.phrase); if let replacement = entry.replacement { Text("→ \(replacement)").font(.system(size: 12)).foregroundStyle(.secondary) } }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain).pointerAwareFocus().help(d("dictionary.edit"))
                        if entry.manuallyModified { Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(.tertiary).help(d("dictionary.manualHint")) }
                        Button { remove(entry) } label: { Image(systemName: "minus.circle").frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).pointerAwareFocus().foregroundStyle(.secondary).help(d("dictionary.remove")).accessibilityLabel(d("dictionary.removeNamed", entry.phrase))
                    }
                    Divider()
                }
            }
            if limit < matches.count { Button(d("dictionary.more")) { limit += 100 } }
            HStack { Button(d("common.export")) { model.exportSettings() }; Button(d("common.import")) { model.importSettings() }; Spacer(); Text(d("dictionary.total", "\(model.document.dictionary.count)")).font(.system(size: 11)).foregroundStyle(.secondary) }
                .padding(.top, 6).disabled(model.isUIPreview)
        }.onAppear(perform: filter)
            .onChange(of: query) { _, _ in filter() }
            .onChange(of: kind) { _, _ in filter() }
            .onChange(of: model.document.dictionary) { _, _ in filter() }
    }
    private var filters: some View { Picker(d("dictionary.kind.label"), selection: $kind) { ForEach(DictionaryKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(d("dictionary.kind.filter")).frame(width: 265) }
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
        guard !name.isEmpty, name.count <= 255 else { validation = d("dictionary.validation.length"); return }
        guard target.utf8.count <= DictionaryEntry.maximumReplacementBytes else { validation = L10n.text("dictionary.validation.replacement"); return }
        guard !model.document.dictionary.contains(where: { $0.id != editingID && $0.phrase == name && ($0.replacement ?? "") == target }) else { validation = d("dictionary.validation.duplicate"); return }
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
