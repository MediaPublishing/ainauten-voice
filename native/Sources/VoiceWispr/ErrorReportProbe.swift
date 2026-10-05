#if DEBUG
import Foundation
import VoiceWisprCore

private actor ProbeTransport {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    var calls = 0
    var payload: Data?
    func send(_ data: Data) async throws -> ReportReceipt {
        calls += 1; payload = data; entered = true; enteredWaiter?.resume(); enteredWaiter = nil
        // Deliberately return a receipt after cancellation, like an already accepted POST.
        await withCheckedContinuation { releaseWaiter = $0 }
        let report = try ErrorReport.decode(data)
        return .init(reportID: report.reportID, accepted: true, state: "received")
    }
    func waitUntilEntered() async { if !entered { await withCheckedContinuation { enteredWaiter = $0 } } }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

enum ErrorReportProbe {
    @MainActor static func controller(_ root: URL) async throws {
        guard root.standardizedFileURL.path.contains("/native/artifacts/reporting-probe/") else { throw ErrorReport.ReportError.invalid }
        let url = root.appendingPathComponent("controller-\(UUID())/queue.json")
        let gate = ProbeTransport(), local = ErrorReportStore(url: url), controller = ErrorReportController()
        await controller.startProbe(store: local) { try await gate.send($0) }
        guard !controller.automatic, await gate.calls == 0 else { throw ErrorReport.ReportError.invalid }
        controller.beginReport(); controller.editDescription("Synthetic preview for cancellation test")
        let preview = try controller.draft.validatedData()
        controller.send(); await gate.waitUntilEntered()
        guard await gate.payload == preview else { throw ErrorReport.ReportError.invalid }
        controller.cancel(); await controller.waitForProbeCleanup()
        controller.beginReport(); controller.editDescription("New synthetic draft")
        let newID = controller.draft.reportID
        await gate.release(); await controller.waitForProbe()
        guard controller.draft.reportID == newID, controller.message.isEmpty, !controller.sending,
              try await local.entries().isEmpty else { throw ErrorReport.ReportError.invalid }
        let restarted = ErrorReportController()
        await restarted.startProbe(store: ErrorReportStore(url: url)) { try await gate.send($0) }
        guard !restarted.automatic, restarted.entries.isEmpty, await gate.calls == 1 else { throw ErrorReport.ReportError.invalid }
        controller.beginReport(); controller.send(); controller.cancel(); await controller.waitForProbe()
        let beforeSendCalls = await gate.calls
        guard beforeSendCalls == 1, try await local.entries().isEmpty else { throw ErrorReport.ReportError.invalid }
        let autoGate = ProbeTransport(), autoURL = root.appendingPathComponent("automatic-\(UUID())/queue.json")
        let automaticController = ErrorReportController()
        await automaticController.startProbe(store: ErrorReportStore(url: autoURL)) { try await autoGate.send($0) }
        automaticController.setAutomatic(true); automaticController.setAutomatic(false)
        await automaticController.waitForProbe()
        automaticController.record(component: .recognition, code: .processingFailed)
        guard !automaticController.automatic, await autoGate.calls == 0 else { throw ErrorReport.ReportError.invalid }
        automaticController.setAutomatic(true); await automaticController.waitForProbe()
        automaticController.record(component: .recognition, code: .processingFailed)
        await autoGate.waitUntilEntered()
        automaticController.setAutomatic(false); await autoGate.release(); await automaticController.waitForProbe()
        automaticController.record(component: .models, code: .modelLoadFailed)
        let autoRestart = ErrorReportController()
        await autoRestart.startProbe(store: ErrorReportStore(url: autoURL)) { try await autoGate.send($0) }
        guard !automaticController.automatic, !autoRestart.automatic, await autoGate.calls == 1 else { throw ErrorReport.ReportError.invalid }
        let receipt: [String: Any] = ["previewEqualsTransport": true, "lateReceiptDidNotOverwriteNewDraft": true,
            "cancelBeforeSendTransportCalls": 0, "inFlightTransportCalls": 1, "queueAfterCancelAndRestart": 0, "automaticAfterRestart": false,
            "automaticRapidOptOutCalls": 0, "automaticOptInCalls": 1, "automaticOptOutAndRestartCalls": 0,
            "usesProductionController": true, "externalNetwork": false, "normalProfileAccess": false]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("controller-proof.json"))
        print("REPORTING_CONTROLLER_PROBE pass")
    }
    static func run(_ root: URL) throws {
        // Explicit synthetic diagnostic harness. Never reads the normal profile.
        guard root.standardizedFileURL.path.contains("/native/artifacts/reporting-probe/") else { throw ErrorReport.ReportError.invalid }
        guard let store = try CrashRecording.install(at: root) else { throw ErrorReport.ReportError.invalid }
        if CommandLine.arguments.contains("--reporting-crash") { abort() }
        var receipts: [String] = []
        for id in store.reportIDs {
            guard let object = store.report(for: id.int64Value)?.value else { continue }
            let report = try CrashDiagnosticProjection.report(object)
            let data = try report.validatedData()
            try data.write(to: root.appendingPathComponent("projected.json"))
            receipts.append(report.reportID)
            store.deleteReport(with: id.int64Value)
        }
        print("REPORTING_PROBE crashes=\(receipts.count) sink=none")
    }
}
#endif
