import XCTest
import JavaScriptCore
@testable import VoiceWisprCore

final class MediaPlaybackPauseTests: XCTestCase {
    @MainActor func testConfirmedPauseResumesOnceAndIgnoresStaleSession() async {
        var calls: [[String]] = []
        let media = MediaPlaybackPause { calls.append($0); return $0 == ["pause"] ? "player" : nil }
        let id = UUID()
        await media.pause(for: id)
        media.resume(for: UUID())
        XCTAssertEqual(calls, [["pause"]])
        media.resume(for: id); media.resume(for: id)
        await media.finishPendingCommands()
        XCTAssertEqual(calls, [["pause"], ["resume", "player"]])
    }
    @MainActor func testUnconfirmedPauseNeverResumes() async {
        var calls: [[String]] = []
        let media = MediaPlaybackPause { calls.append($0); return nil }
        await media.pause(for: UUID()); media.resume()
        await media.finishPendingCommands()
        XCTAssertEqual(calls, [["pause"]])
    }
    @MainActor func testImmediateStopAndNewRecordingSerializeRestoreBeforePause() async {
        var calls: [[String]] = []
        var reply: CheckedContinuation<String?, Never>?
        let media = MediaPlaybackPause { args in
            calls.append(args)
            if calls.count == 1 { return await withCheckedContinuation { reply = $0 } }
            return args == ["pause"] ? "second" : nil
        }
        let first = Task { await media.pause(for: UUID()) }
        while reply == nil { await Task.yield() }
        media.resume()
        let secondID = UUID()
        let second = Task { await media.pause(for: secondID) }
        await Task.yield()
        XCTAssertEqual(calls, [["pause"]])
        reply?.resume(returning: "first")
        await first.value; await second.value
        XCTAssertEqual(calls, [["pause"], ["resume", "first"], ["pause"]])
        media.resume(for: secondID); await media.finishPendingCommands()
        XCTAssertEqual(calls.last, ["resume", "second"])
    }
    @MainActor func testSleepCancelsPendingResume() async {
        var calls: [[String]] = []
        var reply: CheckedContinuation<String?, Never>?
        let media = MediaPlaybackPause { args in
            calls.append(args)
            return await withCheckedContinuation { reply = $0 }
        }
        let start = Task { await media.pause(for: UUID()) }
        while reply == nil { await Task.yield() }
        media.resume(); media.discard()
        reply?.resume(returning: "player")
        await start.value; await media.finishPendingCommands()
        XCTAssertEqual(calls, [["pause"]])
    }
    @MainActor func testCancelledStartDoesNotTouchPlayback() async {
        var calls: [[String]] = []
        let media = MediaPlaybackPause { calls.append($0); return "player" }
        let start = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await media.pause(for: UUID())
        }
        await start.value; media.resume(); await media.finishPendingCommands()
        XCTAssertEqual(calls, [])
    }
    // Exercise the shipped script. Only the native macOS bridge is replaced;
    // playback decisions, confirmation and identity checks use the real code.
    private func script(playing: Bool = true, acceptsPause: Bool = true) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var current = {bundle: 'test.player', pid: 42, player: 'session', playing: \(playing)};
        var alive = true;
        var commands = [], acceptsPause = \(acceptsPause), switchesPlayer = false;
        var request = {
          get localNowPlayingPlayerPath() { return {client: {bundleIdentifier: current.bundle, processIdentifier: current.pid}, player: {identifier: current.player}}; },
          get localIsPlaying() { return current.playing; }
        };
        var ObjC = {import: function(){}, unwrap: function(x){return x;}, bindFunction: function(){}};
        var $ = {kill: function(){return alive ? 0 : -1;},
          NSBundle: {bundleWithPath: function(){return {load: true};}}, NSClassFromString: function(){return request;},
          NSDictionary: {dictionary: {}}, NSDate: {dateWithTimeIntervalSinceNow: function(){return 0;}},
          NSRunLoop: {currentRunLoop: {runUntilDate: function(){}}},
          MRMediaRemoteSendCommand: function(cmd) {
            commands.push(cmd);
            if (cmd === 1 && acceptsPause) current.playing = false;
            if (cmd === 0) current.playing = true;
            if (switchesPlayer) current.player = 'other';
            return true;
          }
        };
        """)
        let url = try XCTUnwrap(MediaPlaybackPause.scriptURL)
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        XCTAssertNil(context.exception)
        return context
    }
    func testScriptPausesPlayingMediaConfirmsAndResumesSamePlayer() throws {
        let context = try script()
        context.evaluateScript("var paused = JSON.parse(run(['pause']));")
        XCTAssertTrue(context.evaluateScript("typeof paused.pausedPlayer === 'string'")!.toBool())
        context.evaluateScript("run(['resume', 'different']);")
        XCTAssertEqual(context.evaluateScript("JSON.stringify(commands)")!.toString(), "[1]")
        context.evaluateScript("run(['resume', paused.pausedPlayer]);")
        XCTAssertEqual(context.evaluateScript("JSON.stringify(commands)")!.toString(), "[1,0]")
    }
    func testScriptLeavesPausedUnknownAndUnconfirmedPlaybackAlone() throws {
        let paused = try script(playing: false)
        XCTAssertEqual(paused.evaluateScript("run(['pause'])")!.toString(), "{}")
        XCTAssertEqual(paused.evaluateScript("JSON.stringify(commands)")!.toString(), "[]")
        let unknown = try script()
        unknown.evaluateScript("current.bundle = undefined;")
        XCTAssertEqual(unknown.evaluateScript("run(['pause'])")!.toString(), "{}")
        XCTAssertEqual(unknown.evaluateScript("JSON.stringify(commands)")!.toString(), "[]")
        let ignored = try script(acceptsPause: false)
        XCTAssertEqual(ignored.evaluateScript("run(['pause'])")!.toString(), "{}")
    }
    func testScriptRefusesResumeAfterPlayerChangeRestartOrManualPlay() throws {
        for change in ["current.player = 'different'", "current.pid = 99", "current.bundle = 'different'", "current.playing = true", "alive = false"] {
            let context = try script()
            context.evaluateScript("var paused = JSON.parse(run(['pause'])); \(change); run(['resume', paused.pausedPlayer]);")
            XCTAssertEqual(context.evaluateScript("JSON.stringify(commands)")!.toString(), "[1]")
        }
        let context = try script()
        context.evaluateScript("switchesPlayer = true;")
        XCTAssertEqual(context.evaluateScript("run(['pause'])")!.toString(), "{}")
    }
}
