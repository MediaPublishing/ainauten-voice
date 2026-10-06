import AppKit
import SwiftUI
import VoiceWisprCore
import KSCrashRecording

private final class NoReportRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class ErrorReportController: ObservableObject {
    @Published var automatic = false
    @Published var entries: [ErrorReportStore.Entry] = []
    @Published var draft: ErrorReport
    @Published private var messageValue: LocalizedMessage = .literal("")
    var message: String { get { messageValue.text } set { messageValue = L10n.message(newValue) } }
    @Published var sending = false
    @Published var crashAvailable = false
    private var store: ErrorReportStore?
    private var preview = false
    private var latestTechnical: ErrorReport?
    private var sendingTask: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var preferenceTask: Task<Void, Never>?
    private var automaticChoice: Bool?
    #if DEBUG
    private var probeTransport: (@Sendable (Data) async throws -> ReportReceipt)?
    func startProbe(store: ErrorReportStore, transport: @escaping @Sendable (Data) async throws -> ReportReceipt) async {
        self.store = store; probeTransport = transport; await refresh()
    }
    func waitForProbe() async { await preferenceTask?.value; await sendingTask?.value; await automaticTask?.value; await cleanupTask?.value; await refresh() }
    func waitForProbeCleanup() async { await cleanupTask?.value }
    #endif
    var deliveryAvailable: Bool {
        #if DEBUG
        if probeTransport != nil || preview { return true }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "AInautenReportDeliveryEnabled") as? Bool == true
    }
    private let endpoint = URL(string: "https://voice.ainauten.com/api/reports")!
    private var sender: @Sendable (Data) async throws -> ReportReceipt {
        #if DEBUG
        if let probeTransport { return probeTransport }
        #endif
        return Self.transport(endpoint)
    }

    init() { draft = Self.makeReport() }
    static func makeReport(component: ErrorReport.Component = .app, code: ErrorReport.Code = .userReported) -> ErrorReport {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return ErrorReport(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1",
                           build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3",
                           osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", component: component, code: code)
    }
    func start(preview: Bool) {
        self.preview = preview
        if preview { draft = Self.makeReport(component: .recognition, code: .processingFailed); latestTechnical = draft; return }
        store = ErrorReportStore(url: ModelPaths.support.appendingPathComponent("Reports/queue.json"))
        Task {
            await refresh()
            capturePreviousCrash()
            scheduleAutomatic()
        }
    }
    func refresh() async {
        guard let store else { return }
        do { let saved = try await store.automatic(); automatic = automaticChoice ?? saved; entries = try await store.entries() }
        catch { message = L10n.text("reports.readFailed") }
    }
    func setAutomatic(_ value: Bool) {
        guard !value || deliveryAvailable else { message = L10n.text("reports.deliveryUnavailable") ; return }
        automaticChoice = value; automatic = value
        if !value { automaticTask?.cancel() }
        guard let store else { return }
        let previous = preferenceTask
        preferenceTask = Task {
            await previous?.value
            do { try await store.setAutomatic(value); await refresh(); if value && automaticChoice == value { scheduleAutomatic() } }
            catch { if automaticChoice == value { automaticChoice = false; automatic = false; message = L10n.text("reports.preferenceSaveFailed") } }
        }
    }
    func beginReport() {
        if !crashAvailable { draft = latestTechnical ?? Self.makeReport(); draft.reportID = UUID().uuidString.lowercased(); draft.userInput = .init() }
        message = ""
    }
    func editDescription(_ value: String) { draft.userInput.description = value; draft.reportID = UUID().uuidString.lowercased() }
    func editContact(_ value: String) { draft.userInput.contact = value; draft.reportID = UUID().uuidString.lowercased() }
    func record(component: ErrorReport.Component, code: ErrorReport.Code) {
        guard !preview else { return }
        let report = Self.makeReport(component: component, code: code)
        // Never overwrite a report the user is editing; beginReport() picks up latestTechnical.
        latestTechnical = report
        guard automatic, let store else { return }
        Task {
            do { try await store.enqueue(report, automatic: true); await refresh(); scheduleAutomatic() }
            catch { message = L10n.text("reports.queueFailed") }
        }
    }
    private func scheduleAutomatic() {
        guard deliveryAvailable, automatic, !preview, automaticTask == nil else { return }
        automaticTask = Task { await sendAutomatic(); let cancelled = Task.isCancelled; automaticTask = nil; if cancelled && automatic { scheduleAutomatic() } }
    }
    private func sendAutomatic() async {
        guard automatic, !preview, !sending, let store else { return }
        sending = true; defer { sending = false }
        do { try await store.sendPending(transport: sender); await refresh() }
        catch is CancellationError { await refresh() }
        catch { message = L10n.text("reports.deliveryUnconfirmed"); await refresh() }
    }
    func send() {
        guard deliveryAvailable else { message = L10n.text("reports.deliveryUnavailable"); return }
        guard !sending, (try? draft.validatedData()) != nil else { return }
        if preview { message = "Vorschau: kein Versand und keine Nutzerdaten."; return }
        guard let store else { return }
        let report = draft
        sending = true
        sendingTask = Task {
            defer { sending = false; sendingTask = nil; scheduleAutomatic() }
            do {
                try Task.checkCancellation()
                try await store.enqueue(report, automatic: false)
                try await store.sendPending(manualID: report.reportID, transport: sender)
                guard !Task.isCancelled, draft.reportID == report.reportID else { return }
                message = L10n.format("reports.received", arguments: [String(report.reportID.prefix(8))]); crashAvailable = false
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, draft.reportID == report.reportID else { return }
                message = L10n.text("reports.notConfirmed")
            }
            await refresh()
        }
    }
    func cancel() {
        let started = sending
        sendingTask?.cancel()
        // A cancelled unsent draft must not later leave the device automatically.
        let id = draft.reportID
        if let store { cleanupTask = Task { if (try? await store.entries().first(where: { $0.report.reportID == id })?.sent) != true { try? await store.remove(id) }; await refresh() } }
        draft = Self.makeReport(); crashAvailable = false
        message = started ? L10n.text("reports.cancelledAfterStart") : L10n.text("reports.cancelled")
    }
    func use(_ entry: ErrorReportStore.Entry) { draft = entry.report; message = entry.sent ? L10n.format("reports.alreadyReceived", arguments: [String(entry.report.reportID.prefix(8))]) : L10n.text("reports.savedLocally") }
    func export() {
        guard let data = try? draft.validatedData() else { message = L10n.text("reports.invalid"); return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "AInauten-Voice-Fehler-\(draft.reportID.prefix(8)).json"
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url, options: .atomic); message = L10n.text("reports.exported") }
            catch { message = L10n.text("reports.exportFailed") }
        }
    }
    static func transport(_ endpoint: URL) -> @Sendable (Data) async throws -> ReportReceipt {
        return { data in
            _ = try ErrorReport.decode(data)
            guard endpoint.scheme == "https", endpoint.host == "voice.ainauten.com", endpoint.path == "/api/reports" else { throw ErrorReport.ReportError.unavailable }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 15
            let session = URLSession(configuration: configuration, delegate: NoReportRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = data
            let (reply, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), reply.count <= 4096 else { throw ErrorReport.ReportError.unavailable }
            return try JSONDecoder().decode(ReportReceipt.self, from: reply)
        }
    }
    private func capturePreviousCrash() {
        let path = ModelPaths.support.appendingPathComponent("Reports/CrashCache")
        do {
            guard let sdkStore = try CrashRecording.install(at: path) else { return }
            for id in sdkStore.reportIDs {
                defer { sdkStore.deleteReport(with: id.int64Value) }
                guard let object = sdkStore.report(for: id.int64Value)?.value,
                      let projected = try? CrashDiagnosticProjection.report(object) else { continue }
                draft = projected; crashAvailable = true
                if let store { Task { try? await store.enqueue(projected, automatic: automatic); await refresh(); scheduleAutomatic() } }
            }
        } catch { /* Reporting must never prevent app startup. No raw failure details are collected. */ }
    }
}
