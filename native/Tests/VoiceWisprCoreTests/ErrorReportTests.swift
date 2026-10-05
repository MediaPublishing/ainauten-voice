import XCTest
@testable import VoiceWisprCore

private actor ReportSpy {
    var bodies: [Data] = []
    func accept(_ data: Data) throws -> ReportReceipt { bodies.append(data); let r = try ErrorReport.decode(data); return .init(reportID: r.reportID, accepted: true, state: "received") }
    func count() -> Int { bodies.count }
}
private actor ReportGate {
    private var started = false
    private var observer: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    var calls = 0
    func accept(_ data: Data) async throws -> ReportReceipt {
        calls += 1; started = true; observer?.resume(); observer = nil
        await withCheckedContinuation { pending = $0 }
        let report = try ErrorReport.decode(data)
        return .init(reportID: report.reportID, accepted: true, state: "received")
    }
    func waitUntilStarted() async { if !started { await withCheckedContinuation { observer = $0 } } }
    func release() { pending?.resume(); pending = nil }
    func count() -> Int { calls }
}
final class ErrorReportTests: XCTestCase {
    private func report() -> ErrorReport { .init(version: "0.1.1", build: "3", osVersion: "26.0.1", component: .recognition, code: .processingFailed) }
    private func store() -> ErrorReportStore { ErrorReportStore(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("voice-report-test-\(UUID())/queue.json")) }
    func testStrictSchemaRejectsInjectedPrivateFields() throws {
        let r = report(); let data = try r.validatedData(); XCTAssertEqual(try ErrorReport.decode(data), r)
        for field in ["transcript", "clipboard", "dictionary", "path", "deviceID", "apiKey", "audio"] {
            var o = try JSONSerialization.jsonObject(with: data) as! [String: Any]; o[field] = "PRIVATE"
            XCTAssertThrowsError(try ErrorReport.decode(JSONSerialization.data(withJSONObject: o)))
        }
        var bad = report(); bad.version = "/Users/private/name"; XCTAssertThrowsError(try bad.validatedData())
        bad = report(); bad.frames = [.init(binaryUUID: UUID().uuidString, offset: -1)]; XCTAssertThrowsError(try bad.validatedData())
        bad = report(); bad.events = Array(repeating: .launch, count: 13); XCTAssertThrowsError(try bad.validatedData())
        bad = report(); bad.userInput.description = String(repeating: "ü", count: 1001); XCTAssertThrowsError(try bad.validatedData())
    }
    func testAppleFileProjectionDropsNamesPathsAndContents() throws {
        let uuid = UUID().uuidString
        let source: [String: Any] = ["bundleInfo": ["CFBundleIdentifier": "com.mediapublishing.VoiceWispr", "CFBundleShortVersionString": "0.1.1", "CFBundleVersion": "3"], "osVersion": ["train": "macOS 26.0.1 (PRIVATE)"], "cpuType": "ARM-64", "exception": ["signal": "SIGABRT", "reason": "PRIVATE transcript"], "userName": "PRIVATE", "usedImages": [["name": "VoiceWispr", "uuid": uuid, "path": "/Users/PRIVATE", "base": 123]], "threads": [["triggered": true, "registers": "PRIVATE clipboard", "frames": [["imageIndex": 0, "imageOffset": 42, "symbol": "PRIVATE"], ["imageIndex": -1, "imageOffset": 2]]]]]
        let payload = try JSONSerialization.data(withJSONObject: source)
        let apple = Data("{\"private\":\"PRIVATE metadata\"}\n".utf8) + payload
        let r = try AppleDiagnosticProjection.report(from: apple)
        XCTAssertEqual(r.frames, [.init(binaryUUID: uuid, offset: 42)])
        XCTAssertFalse(String(data: try r.validatedData(), encoding: .utf8)!.contains("PRIVATE"))
    }
    func testOptOutAndCancellationSendNothing() async throws {
        let s = store(), spy = ReportSpy(); let r = report()
        let enabled = try await s.automatic(); XCTAssertFalse(enabled)
        try await s.enqueue(r, automatic: true)
        try await s.sendPending { try await spy.accept($0) }
        let callsBefore = await spy.count(); XCTAssertEqual(callsBefore, 0)
        try await s.enqueue(r, automatic: false); try await s.remove(r.reportID)
        try await s.sendPending(manualID: r.reportID) { try await spy.accept($0) }
        let callsAfter = await spy.count(); XCTAssertEqual(callsAfter, 0)
    }
    func testOfflineRetryAndPreviewPayloadEquality() async throws {
        let s = store(), spy = ReportSpy(); let r = report()
        try await s.enqueue(r, automatic: false)
        do { try await s.sendPending(manualID: r.reportID) { _ in throw ErrorReport.ReportError.unavailable }; XCTFail() } catch {}
        let offline = try await s.entries(); XCTAssertFalse(offline[0].sent)
        try await s.sendPending(manualID: r.reportID) { data in XCTAssertEqual(data, try r.validatedData()); return try await spy.accept(data) }
        try await s.sendPending(manualID: r.reportID) { try await spy.accept($0) }
        let calls = await spy.count(), sent = try await s.entries(); XCTAssertEqual(calls, 1); XCTAssertTrue(sent[0].sent)
    }
    func testWrongReceiptNeverMarksSent() async throws {
        let s = store(), r = report(); try await s.enqueue(r, automatic: false)
        do { try await s.sendPending(manualID: r.reportID) { _ in .init(reportID: UUID().uuidString, accepted: true, state: "received") }; XCTFail() } catch {}
        let entries = try await s.entries(); XCTAssertFalse(entries[0].sent)
    }
    func testAutomaticDedupDisableAndRetention() async throws {
        let s = store(), spy = ReportSpy(), now = Date()
        try await s.setAutomatic(true, now: now)
        try await s.enqueue(report(), automatic: true, now: now)
        try await s.enqueue(report(), automatic: true, now: now)
        let grouped = try await s.entries(now: now); XCTAssertEqual(grouped.count, 1)
        try await s.setAutomatic(false, now: now)
        try await s.sendPending(now: now) { try await spy.accept($0) }
        let calls = await spy.count(); XCTAssertEqual(calls, 0)
        let expired = try await s.entries(now: now.addingTimeInterval(8 * 86400)); XCTAssertEqual(expired.count, 0)
    }
    func testQueueBoundAndVoluntaryTextNeverAutoSent() async throws {
        let s = store(); try await s.setAutomatic(true)
        var r = report(); r.userInput.description = "Voluntary text"; try await s.enqueue(r, automatic: true)
        let voluntary = try await s.entries(); XCTAssertEqual(voluntary.count, 0)
        for _ in 0..<20 { try await s.enqueue(report(), automatic: false) }
        do { try await s.enqueue(report(), automatic: false); XCTFail() } catch {}
        let full = try await s.entries(); XCTAssertEqual(full.count, 20)
    }
    func testRestartPreservesConsentAndOfflineQueue() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("voice-report-restart-\(UUID())/queue.json")
        let first = ErrorReportStore(url: url), spy = ReportSpy(), r = report()
        try await first.setAutomatic(true); try await first.enqueue(r, automatic: true)
        let restarted = ErrorReportStore(url: url)
        let enabled = try await restarted.automatic(), queued = try await restarted.entries()
        XCTAssertTrue(enabled); XCTAssertEqual(queued[0].report, r); XCTAssertFalse(queued[0].sent)
        try await restarted.setAutomatic(false)
        let disabledRestart = ErrorReportStore(url: url)
        try await disabledRestart.sendPending { try await spy.accept($0) }
        let offCalls = await spy.count(); XCTAssertEqual(offCalls, 0)
        try await disabledRestart.sendPending(manualID: r.reportID) { try await spy.accept($0) }
        let finalRestart = ErrorReportStore(url: url), saved = try await finalRestart.entries()
        XCTAssertTrue(saved[0].sent); XCTAssertEqual(saved[0].receipt?.reportID, r.reportID)
    }
    func testConcurrentSendAndRemovalDoNotDuplicateOrResurrect() async throws {
        let s = store(), gate = ReportGate(), r = report()
        try await s.enqueue(r, automatic: false)
        let sending = Task { try await s.sendPending(manualID: r.reportID) { try await gate.accept($0) } }
        await gate.waitUntilStarted()
        try await s.sendPending(manualID: r.reportID) { try await gate.accept($0) }
        try await s.remove(r.reportID)
        await gate.release(); try await sending.value
        let calls = await gate.count(), remaining = try await s.entries()
        XCTAssertEqual(calls, 1); XCTAssertEqual(remaining.count, 0)
    }
    func testSDKProjectionDropsRawMemoryAndUsesCrashVersion() throws {
        let uuid = UUID().uuidString
        let raw: [String: Any] = ["system": ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "2", "system_version": "26.0.1", "cpu_arch": "arm64", "user_name": "PRIVATE"],
            "binary_images": [["name": "/Users/PRIVATE/AInauten Voice.app/Contents/MacOS/VoiceWispr", "image_addr": 100, "image_size": 100, "uuid": uuid]],
            "crash": ["error": ["type": "signal", "reason": "PRIVATE dictation"], "threads": [["crashed": true, "registers": "PRIVATE clipboard", "backtrace": ["contents": [["instruction_addr": 142, "symbol_name": "PRIVATE"]]]]]]]
        let sdkJSON = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: raw)) as! [String: Any]
        let r = try CrashDiagnosticProjection.report(sdkJSON)
        XCTAssertEqual(r.version, "0.1.0"); XCTAssertEqual(r.build, "2")
        XCTAssertEqual(r.frames, [.init(binaryUUID: uuid, offset: 42)])
        XCTAssertFalse(String(data: try r.validatedData(), encoding: .utf8)!.contains("PRIVATE"))
        XCTAssertThrowsError(try CrashDiagnosticProjection.report(["crash": ["error": ["type": "normal_exit"]]]))
    }
}
