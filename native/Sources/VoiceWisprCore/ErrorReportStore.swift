import Foundation

public actor ErrorReportStore {
    public struct Entry: Codable, Equatable, Sendable {
        public var report: ErrorReport
        public var date: Date
        public var sent: Bool
        public var automatic: Bool
        public var receipt: ReportReceipt?
    }
    private struct Document: Codable { var automatic = false; var entries: [Entry] = [] }
    private let url: URL
    private var document = Document()
    private var loaded = false
    private var inFlight: Set<String> = []
    public init(url: URL) { self.url = url }
    private func load(now: Date) throws {
        if !loaded {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try SettingsStore.boundedData(from: url, maximumBytes: 400_000)
                guard data.count < 400_000 else { throw ErrorReport.ReportError.invalid }
                document = try JSONDecoder().decode(Document.self, from: data)
                for entry in document.entries { _ = try entry.report.validatedData() }
            }
            loaded = true
        }
        document.entries.removeAll { now.timeIntervalSince($0.date) > 7 * 86_400 }
        document.entries = Array(document.entries.suffix(20))
    }
    private func save() throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func automatic(now: Date = Date()) throws -> Bool { try load(now: now); return document.automatic }
    public func setAutomatic(_ value: Bool, now: Date = Date()) throws { try load(now: now); document.automatic = value; try save() }
    public func entries(now: Date = Date()) throws -> [Entry] { try load(now: now); try save(); return document.entries.reversed() }
    public func enqueue(_ report: ErrorReport, automatic: Bool, now: Date = Date()) throws {
        try load(now: now); _ = try report.validatedData()
        guard !automatic || (document.automatic && report.userInput == .init()) else { return }
        if let entry = document.entries.first(where: { $0.report.reportID == report.reportID }) {
            guard entry.report == report else { throw ErrorReport.ReportError.invalid }; return
        }
        if automatic, document.entries.contains(where: { $0.automatic && $0.report.code == report.code && $0.report.component == report.component && now.timeIntervalSince($0.date) < 3_600 }) { return }
        if document.entries.count == 20 {
            if let sent = document.entries.firstIndex(where: { $0.sent }) { document.entries.remove(at: sent) }
            else { throw ErrorReport.ReportError.full }
        }
        document.entries.append(Entry(report: report, date: now, sent: false, automatic: automatic)); try save()
    }
    public func remove(_ id: String, now: Date = Date()) throws { try load(now: now); document.entries.removeAll { $0.report.reportID == id }; try save() }
    /// Transport invocation itself sits behind consent. A manual send is a per-report authorization.
    public func sendPending(manualID: String? = nil, now: Date = Date(), transport: @Sendable (Data) async throws -> ReportReceipt) async throws {
        try load(now: now)
        let ids = document.entries.filter { !$0.sent && ($0.report.reportID == manualID || (manualID == nil && document.automatic && $0.automatic)) }.map { $0.report.reportID }
        for id in ids {
            guard let index = document.entries.firstIndex(where: { $0.report.reportID == id && !$0.sent }),
                  !inFlight.contains(id), manualID == id || document.automatic else { continue }
            inFlight.insert(id); defer { inFlight.remove(id) }
            try Task.checkCancellation()
            let receipt = try await transport(document.entries[index].report.validatedData())
            guard receipt.accepted, receipt.reportID == id, ["received", "linked", "needs_review", "fixed"].contains(receipt.state) else { throw ErrorReport.ReportError.acknowledgment }
            // Reentrancy: a cancellation/removal while awaiting must not resurrect the report.
            if let current = document.entries.firstIndex(where: { $0.report.reportID == id }) {
                document.entries[current].sent = true; document.entries[current].receipt = receipt; try save()
            }
        }
    }
}
