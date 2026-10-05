import XCTest
import Foundation
@testable import VoiceWisprCore

final class LipReadingTests: XCTestCase {
    func testGermanResearchResultsRequireReview() {
        XCTAssertTrue(LipReadingLanguage.german.requiresReview)
        XCTAssertFalse(LipReadingLanguage.english.requiresReview)
    }
    func testOlderSettingsKeepCameraBetaDisabled() throws {
        let old = ExportDocument()
        let encoded = try JSONEncoder().encode(old)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        settings.removeValue(forKey: "lipReadingEnabled"); settings.removeValue(forKey: "lipReadingLanguage"); settings.removeValue(forKey: "lipReadingShortcut")
        json["settings"] = settings
        let loaded = try JSONDecoder().decode(ExportDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(loaded.settings.lipReadingEnabled ?? false)
        XCTAssertEqual(loaded.settings.shortcut, old.settings.shortcut)
        XCTAssertEqual(loaded.settings.defaultStyle, old.settings.defaultStyle)
    }
    func testExportCannotAuthorizeCameraBeta() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-lip-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var document = ExportDocument(); document.settings.lipReadingEnabled = true; document.settings.lipReadingLanguage = "de"
        document.dictionary = [DictionaryEntry(id: "brand", phrase: "A in Auten", replacement: "AInauten")]
        let source = dir.appendingPathComponent("export.json")
        try JSONEncoder().encode(document).write(to: source)
        let imported = try await SettingsStore(url: dir.appendingPathComponent("settings.json")).importDocument(from: source)
        XCTAssertEqual(imported.settings.lipReadingEnabled, false)
        XCTAssertEqual(imported.settings.lipReadingLanguage, "de")
        XCTAssertEqual(imported.dictionary, document.dictionary)
    }
    func testLanguageAndShortcutValidation() throws {
        var document = ExportDocument(); document.settings.lipReadingLanguage = "de"; document.settings.lipReadingShortcut = LipReadingLanguage.defaultShortcut
        try SettingsStore.validate(document)
        XCTAssertFalse(([document.settings.shortcut] + (document.settings.shortcutBindings?.all ?? [])).contains(LipReadingLanguage.defaultShortcut))
        document.settings.lipReadingLanguage = "unknown"
        XCTAssertThrowsError(try SettingsStore.validate(document))
        document.settings.lipReadingLanguage = "en"; document.settings.lipReadingShortcut = Shortcut(keyCode: 300, modifiers: 0)
        XCTAssertThrowsError(try SettingsStore.validate(document))
    }
    func testRuntimeRequiresRealReadyBeforeAnyInput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voice-lip-absent-" + UUID().uuidString)
        let runtime = LipReadingRuntime(root: root, resources: root)
        let installed = await runtime.installed(.german)
        XCTAssertFalse(installed)
        do { try await runtime.prepare(.german); XCTFail("Missing runtime reported ready") } catch {}
        do { _ = try await runtime.transcribe([], session: UUID()); XCTFail("Unprepared inference was accepted") } catch {}
        await runtime.cancel()
    }
    func testCameraCancelDoesNotStartAnyCapture() async {
        let camera = CameraCapture()
        camera.cancel(); XCTAssertFalse(camera.isRunning)
        let frames = await camera.stop(sessionID: UUID())
        XCTAssertTrue(frames.isEmpty); XCTAssertFalse(camera.isRunning)
    }
    private func protocolFixture(delay: Bool = false) throws -> LipReadingRuntime {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-lip-ipc-" + UUID().uuidString)
        let bin = dir.appendingPathComponent("en/.venv/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        // The Apple /usr/bin/python3 launcher inspects argv[0]; symlinking it
        // as 'python' requests missing developer tools on CLT-only machines.
        let python = ProcessInfo.processInfo.environment["VOICE_TEST_PYTHON"] ?? "/opt/homebrew/bin/python3"
        let quoted = "'" + python.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let launcher = bin.appendingPathComponent("python")
        try ("#!/bin/sh\nexec " + quoted + " \"$@\"\n").write(to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)
        let script = """
        import sys,json,time
        print(json.dumps({'type':'ready','language':'en'}),flush=True)
        for line in sys.stdin:
            msg=json.loads(line)
            if msg.get('op')=='finish':
                time.sleep(\(delay ? "0.5" : "0"))
                print(json.dumps({'type':'result','session':msg['session'],'text':'Lautloser Protokolltest.'}),flush=True)
        """
        try script.write(to: dir.appendingPathComponent("worker.py"), atomically: true, encoding: .utf8)
        return LipReadingRuntime(root: dir, resources: dir)
    }
    private var fixtureFrames: [LipReadingFrame] { (0..<8).map { LipReadingFrame(milliseconds: $0 * 40, jpeg: Data([1, 2, 3])) } }
    func testNativeProtocolReadsIndependentSessionsAndRejectsBounds() async throws {
        // Deliberately synthetic transport peer. This tests IPC/session fencing,
        // not a face, a model, recognition quality or camera permission.
        let runtime = try protocolFixture()
        try await runtime.prepare(.english)
        let first = try await runtime.transcribe(fixtureFrames, session: UUID())
        let second = try await runtime.transcribe(fixtureFrames, session: UUID())
        XCTAssertEqual(first, "Lautloser Protokolltest."); XCTAssertEqual(second, first)
        var invalid = fixtureFrames; invalid[7] = LipReadingFrame(milliseconds: 30_001, jpeg: Data([1]))
        do { _ = try await runtime.transcribe(invalid, session: UUID()); XCTFail("Out-of-range timestamp accepted") } catch {}
        invalid[7] = invalid[6]
        do { _ = try await runtime.transcribe(invalid, session: UUID()); XCTFail("Repeated timestamp accepted") } catch {}
        invalid = fixtureFrames; invalid[0] = LipReadingFrame(milliseconds: 0, jpeg: Data(repeating: 1, count: 150_001))
        do { _ = try await runtime.transcribe(invalid, session: UUID()); XCTFail("Oversized JPEG accepted") } catch {}
        await runtime.cancel()
    }
    func testCancelledInferenceCannotReturnLateText() async throws {
        let runtime = try protocolFixture(delay: true)
        try await runtime.prepare(.english)
        let frames = fixtureFrames
        let task = Task { try await runtime.transcribe(frames, session: UUID()) }
        try await Task.sleep(for: .milliseconds(50)); task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled peer returned late text") } catch {}
        await runtime.cancel()
        try await runtime.prepare(.english)
        let fresh = try await runtime.transcribe(frames, session: UUID())
        XCTAssertEqual(fresh, "Lautloser Protokolltest.")
        await runtime.cancel()
    }
}
