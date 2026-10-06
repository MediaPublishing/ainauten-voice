import Foundation
import AVFoundation
import CryptoKit
import FluidAudio
import VoiceWisprCore

private struct OriginalFormatter: TextFormatting {
    func prepare() async throws {}
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String { text }
}
private final class CheckpointMeasurements: @unchecked Sendable {
    private let lock = NSLock()
    private var successful = 0, failed = 0, latestSample = 0
    func record(_ sample: Int, _ success: Bool) {
        lock.lock(); defer { lock.unlock() }
        if success { successful += 1; latestSample = max(latestSample, sample) } else { failed += 1 }
    }
    func snapshot() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return ["successful": successful, "failed": failed, "latestSample": latestSample]
    }
}

/// Developer-only tracing of public fixtures. The new stream contains timings,
/// counts and content hashes, never transcripts, audio or dictionary contents.
private final class StageTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var fixture = "warmup", style = "", run = 0
    func select(fixture: String, style: String, run: Int) {
        lock.lock(); defer { lock.unlock() }
        self.fixture = fixture; self.style = style; self.run = run
    }
    private func identity() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["fixture": fixture, "style": style, "run": run]
    }
    private func emit(_ fields: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        FileHandle.standardOutput.write(data + Data([10]))
    }
    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func redactedRecord(_ fields: [String: Any]) -> [String: Any] {
        var result = fields
        for key in ["reference", "original", "text"] {
            if let text = result[key] as? String {
                result[key + "UTF8Bytes"] = text.utf8.count
                result[key + "SHA256"] = digest(text)
            }
        }
        for key in ["reference", "original", "text", "referenceNegations", "recognizedNegations", "formattedNegations",
                    "referenceNumbers", "recognizedNumbers", "formattedNumbers", "error"] {
            result.removeValue(forKey: key)
        }
        if fields["contentsLogged"] != nil { result["contentsLogged"] = false }
        if fields["error"] != nil { result["errorKind"] = "failed" }
        return result
    }
    func captureEnd() {
        var event = identity()
        event["event"] = "diagnostic-stage"; event["stage"] = "capture-end"; event["phase"] = "mark"
        event["uptimeSeconds"] = ProcessInfo.processInfo.systemUptime
        emit(event)
    }
    func measure<T>(_ stage: String, details: [String: Any] = [:], operation: () async throws -> T,
                    output: (T) -> [String: Any] = { _ in [:] }) async throws -> T {
        var event = identity()
        let began = ProcessInfo.processInfo.systemUptime
        event["event"] = "diagnostic-stage"; event["stage"] = stage; event["phase"] = "begin"
        event["callID"] = UUID().uuidString; event["uptimeSeconds"] = began
        event.merge(details) { current, _ in current }
        emit(event)
        do {
            let value = try await operation()
            let ended = ProcessInfo.processInfo.systemUptime
            event["phase"] = "end"; event["uptimeSeconds"] = ended; event["durationSeconds"] = ended - began
            event.merge(output(value)) { current, _ in current }
            emit(event)
            return value
        } catch {
            let ended = ProcessInfo.processInfo.systemUptime
            event["phase"] = "error"; event["uptimeSeconds"] = ended; event["durationSeconds"] = ended - began
            event["errorKind"] = error is CancellationError ? "cancelled" : "failed"
            emit(event)
            throw error
        }
    }
}

private struct StageSpeech: SpeechTranscribing, SpeechActivityDetecting, SpeechSessionReconciling {
    let base: SpeechRuntime
    let trace: StageTrace
    func prepare() async throws { try await trace.measure("speech-prepare") { try await base.prepare() } }
    func detectActivity(samples: [Float], state: SpeechActivityState) async throws -> SpeechActivityResult {
        // Do not log per-frame callbacks or alter the VAD's state progression.
        try await base.detectActivity(samples: samples, state: state)
    }
    func transcribe(samples: [Float], sessionID: UUID, index: Int, offset: Double) async throws -> TranscriptSegment {
        try await trace.measure("transcribe", details: ["samples": samples.count, "segmentIndex": index, "offsetSeconds": offset]) {
            try await base.transcribe(samples: samples, sessionID: sessionID, index: index, offset: offset)
        } output: { ["outputUTF8Bytes": $0.text.utf8.count, "outputSHA256": StageTrace.digest($0.text)] }
    }
    func reconcile(samples: [Float], sessionID: UUID) async throws -> TranscriptSegment {
        try await trace.measure("reconcile", details: ["samples": samples.count]) {
            try await base.reconcile(samples: samples, sessionID: sessionID)
        } output: { ["outputUTF8Bytes": $0.text.utf8.count, "outputSHA256": StageTrace.digest($0.text)] }
    }
}

private struct StageFormatter: TextFormatting {
    let base: LocalFormatter
    let trace: StageTrace
    func prepare() async throws { try await trace.measure("formatter-prepare") { try await base.prepare() } }
    func format(_ text: String, style: TextStyle, context: String, vocabulary: [String]) async throws -> String {
        try await trace.measure("format", details: ["inputUTF8Bytes": text.utf8.count, "inputSHA256": StageTrace.digest(text),
                                                   "contextUTF8Bytes": context.utf8.count, "vocabularyCount": vocabulary.count]) {
            try await base.format(text, style: style, context: context, vocabulary: vocabulary)
        } output: { ["outputUTF8Bytes": $0.utf8.count, "outputSHA256": StageTrace.digest($0)] }
    }
}

@main struct Probe {
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            if arguments.dropFirst().first == "camera-check" {
                // Explicit local hardware check. No requestAccess, file/video
                // export, model, transcript, history or target-app insertion.
                guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw VoiceError.message("Camera permission is not already authorized") }
                let camera = CameraCapture(), earlyID = UUID()
                let early = Task { try await camera.start(sessionID: earlyID) { _ in } }
                try await Task.sleep(for: .milliseconds(1))
                let earlyFrames = await camera.stop(sessionID: earlyID)
                var cancelled = false
                do { try await early.value } catch is CancellationError { cancelled = true }
                let id = UUID(), start = ProcessInfo.processInfo.systemUptime
                try await camera.start(sessionID: id) { _ in }
                let ready = ProcessInfo.processInfo.systemUptime
                try await Task.sleep(for: .seconds(2))
                let frames = await camera.stop(sessionID: id)
                guard frames.count >= 8, !camera.isRunning else { throw VoiceError.message("Camera did not return enough frames or did not stop") }
                try emit(["authorized": true, "earlyCancelled": cancelled, "earlyFrames": earlyFrames.count,
                    "frames": frames.count, "startupSeconds": ready - start, "stopped": !camera.isRunning,
                    "audio": false, "savedImages": false, "transcription": false])
                return
            }
            if arguments.dropFirst().first == "lip-video", arguments.count == 5 {
                guard let language = LipReadingLanguage(rawValue: arguments[2]) else { throw VoiceError.message("Use en or de") }
                let data = try Data(contentsOf: URL(fileURLWithPath: arguments[3]))
                guard data.count <= 90_000_000, let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw VoiceError.message("Invalid public fixture") }
                let frames = try items.map { item -> LipReadingFrame in
                    guard let milliseconds = item["ts_ms"] as? Int, let encoded = item["jpeg"] as? String, let jpeg = Data(base64Encoded: encoded) else { throw VoiceError.message("Invalid frame") }
                    return LipReadingFrame(milliseconds: milliseconds, jpeg: jpeg)
                }
                let runtime = LipReadingRuntime(resources: URL(fileURLWithPath: arguments[4]))
                do {
                    let start = ProcessInfo.processInfo.systemUptime
                    try await runtime.prepare(language)
                    let ready = ProcessInfo.processInfo.systemUptime
                    let text = try await runtime.transcribe(frames, session: UUID())
                    try emit(["language": language.rawValue, "text": text, "frames": frames.count, "warmupSeconds": ready - start, "inferenceSeconds": ProcessInfo.processInfo.systemUptime - ready, "requiresReview": language.requiresReview, "audio": false, "scope": "public video fixture through native IPC; no camera or target app"])
                    await runtime.cancel()
                } catch { await runtime.cancel(); throw error }
                return
            }
            if arguments.dropFirst().first == "download" {
                let downloader = ModelDownloader()
                let progress = ProgressPrinter()
                try await downloader.install { current, total, group in progress.report(current, total, group) }
                print("Verified pinned models installed.")
                return
            }
            if arguments.dropFirst().first == "migration-preview" {
                let preview = WisprMigrationService().preview()
                try emit(["words": preview.words, "replacements": preview.replacements, "deleted": preview.deleted, "uniqueEntries": preview.uniqueEntries, "sourceDuplicates": preview.sourceDuplicates, "languages": preview.languages, "shortcut": preview.shortcut?.label ?? "", "errors": preview.errors, "unsupported": preview.unsupported])
                return
            }
            if arguments.dropFirst().first == "migration-check", arguments.count == 3 {
                // Verification writes only a new temporary copy. The live settings
                // and Wispr source remain read-only; emit aggregate metadata only.
                let source = URL(fileURLWithPath: arguments[2])
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("voice-wispr-import-check-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let target = root.appendingPathComponent("settings.json")
                try FileManager.default.copyItem(at: source, to: target)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                let store = SettingsStore(url: target), before = try await store.load()
                let first = try await store.applyWisprImport(WisprMigrationService()), once = try await store.load()
                let second = try await store.applyWisprImport(WisprMigrationService()), twice = try await store.load()
                try emit(["sourceErrors": first.preview.errors + second.preview.errors, "sourceWords": first.preview.words,
                    "sourceReplacements": first.preview.replacements, "deletedSkipped": first.preview.deleted,
                    "sourceDuplicates": first.preview.sourceDuplicates, "uniqueSourceEntries": first.preview.uniqueEntries,
                    "dictionaryBefore": before.dictionary.count, "dictionaryAfter": twice.dictionary.count,
                    "firstAdded": first.imported, "firstUpdated": first.updated, "firstPreserved": first.preserved,
                    "secondAdded": second.imported, "secondUpdated": second.updated, "secondPreserved": second.preserved,
                    "repeatIdentical": once == twice, "settingsPreserved": before.settings == twice.settings,
                    "dictionaryPreserved": before.dictionary == twice.dictionary, "summary": second.summary(savedCount: twice.dictionary.count),
                    "isolatedCopy": root.path])
                return
            }
            if arguments.dropFirst().first == "speech-config-check" {
                let configuration = suiteSpeechConfiguration(arguments)
                try emit(["event": "speech-config-check", "loadsModels": false,
                          "encoderPrecision": configuration.encoderPrecision.rawValue,
                          "dualDecodeArbitration": configuration.dualDecodeArbitration,
                          "sdkWorkers": configuration.sdkWorkers,
                          "vadSilenceSeconds": configuration.activitySilenceDuration,
                          "trimTrailingSilence": configuration.trimTrailingSilence])
                return
            }
            if arguments.dropFirst().first == "suite", arguments.count >= 3 {
                try await suite(arguments)
                return
            }
            if arguments.dropFirst().first == "feed-pacing-check" {
                try await checkFeedPacing()
                return
            }
            if arguments.dropFirst().first == "format-cases", arguments.count == 3 {
                try await formatCases(URL(fileURLWithPath: arguments[2]))
                return
            }
            if arguments.dropFirst().first == "inspect-seams", arguments.count >= 4 {
                try await inspectSeams(manifestURL: URL(fileURLWithPath: arguments[2]), id: arguments[3], encoderV2: arguments.contains("--encoder-v2"), coreSeconds: coreSeconds(arguments), overlapSeconds: overlapSeconds(arguments), vadSilence: vadSilence(arguments), trimTail: arguments.contains("--trim-tail"), sdkWorkers: sdkWorkers(arguments))
                return
            }
            if arguments.dropFirst().first == "inspect-window", arguments.count >= 6,
               let start = Double(arguments[4]), let end = Double(arguments[5]) {
                try await inspectWindow(manifestURL: URL(fileURLWithPath: arguments[2]), id: arguments[3], start: start, end: end, encoderV2: arguments.contains("--encoder-v2"), trimTail: arguments.contains("--trim-tail"), repeats: option("--repeat=", in: arguments).flatMap(Int.init) ?? 1, sdkWorkers: sdkWorkers(arguments), dualDecode: arguments.contains("--dual-decode"), blockSeconds: option("--reconcile-block-seconds=", in: arguments).flatMap(Int.init), blockContext: option("--reconcile-context-seconds=", in: arguments).flatMap(Int.init) ?? 2)
                return
            }
            guard arguments.count >= 3, arguments[1] == "transcribe" else {
                print("Usage: VoiceWisprProbe download | migration-preview | migration-check <settings-file> | speech-config-check [--encoder-v2] [--dual-decode] | transcribe <audio-file> [original|cleaned|email|chat] [stream] | suite <manifest> [repeat=3] [--ids=id,id] [--styles=original,cleaned] [--stream] [--long] [--encoder-v2] [--dual-decode] | inspect-seams <synthetic manifest> <fixture-id> | inspect-window <synthetic manifest> <fixture-id> <start-sec> <end-sec> [--repeat=3] [--sdk-workers=1|2] [--dual-decode] [--reconcile-block-seconds=30...120] [--reconcile-context-seconds=2...10]")
                exit(2)
            }
            let style = arguments.count > 3 ? TextStyle(rawValue: arguments[3]) ?? .original : .original
            let speech = makeSpeech(encoderV2: arguments.contains("--encoder-v2"), silenceDuration: vadSilence(arguments), trimTrailingSilence: arguments.contains("--trim-tail"), sdkWorkers: sdkWorkers(arguments))
            let local = LocalFormatter(modelURL: ModelPaths.formatter)
            do {
            let started = ProcessInfo.processInfo.systemUptime
            try await speech.prepare()
            if style != .original { try await local.prepare() }
            let loadSeconds = ProcessInfo.processInfo.systemUptime - started
            let audio = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: arguments[2]))
            // A separate tiny recognition pass initializes ASR kernels before a warm measurement.
            _ = try await speech.transcribe(samples: Array(audio.prefix(16_000)), sessionID: UUID(), index: 0, offset: 0)
            let pipeline = ProcessingPipeline(speech: speech, formatter: style == .original ? OriginalFormatter() : local, coreSamples: Int(coreSeconds(arguments) * 16000), overlapSamples: Int(overlapSeconds(arguments) * 16000))
            let id = UUID()
            try await pipeline.start(sessionID: id, style: style)
            let processStart = ProcessInfo.processInfo.systemUptime
            var stopAt = processStart
            var feed: StreamFeed?
            if arguments.contains("stream") {
                feed = try await feedAudio(audio, began: processStart) { try await pipeline.append(samples: $0) }
                stopAt = feed!.scheduledStop
            } else { try await pipeline.append(samples: audio) }
            let result = try await pipeline.finish()
            let finished = ProcessInfo.processInfo.systemUptime
            try emit(["text": result.text, "original": result.original, "fallback": result.usedFallback, "audioSeconds": Double(audio.count) / 16_000, "warmStopToResultSeconds": arguments.contains("stream") ? finished - stopAt : NSNull(), "totalProcessingSeconds": finished - processStart, "loadSeconds": loadSeconds, "style": style.rawValue, "streamedAtRealTime": arguments.contains("stream"), "feedPacing": "append-after-capture-deadline", "feedChunkSamples": 1600, "feedCompletionDelaySeconds": feed.map { max(0, $0.completed - $0.scheduledStop) } ?? 0, "maxEarlyFeedSeconds": feed?.maxEarly ?? 0])
            await local.shutdown()
            } catch { await local.shutdown(); throw error }
        } catch { fputs("Probe failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    private struct StreamFeed {
        let scheduledStop: Double
        let completed: Double
        let maxEarly: Double
        let maxLag: Double
    }
    private static func feedAudio(_ audio: [Float], began: Double, append: @Sendable ([Float]) async throws -> Void) async throws -> StreamFeed {
        var early = 0.0, lag = 0.0
        for offset in stride(from: 0, to: audio.count, by: 1600) {
            try Task.checkCancellation()
            let upper = min(audio.count, offset + 1600)
            let available = began + Double(upper) / 16000
            // Capture must have produced the entire block before it is delivered.
            // The fractional last block ends at its exact sample deadline.
            while available > ProcessInfo.processInfo.systemUptime {
                let remaining = available - ProcessInfo.processInfo.systemUptime
                if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
            }
            let delivered = ProcessInfo.processInfo.systemUptime
            early = max(early, available - delivered)
            lag = max(lag, delivered - available)
            try await append(Array(audio[offset..<upper]))
        }
        return StreamFeed(scheduledStop: began + Double(audio.count) / 16000, completed: ProcessInfo.processInfo.systemUptime, maxEarly: early, maxLag: lag)
    }
    private struct FeedArrival: Sendable { let frames: Int; let time: Double }
    private actor FeedRecorder {
        var arrivals: [FeedArrival] = []
        func record(_ frames: Int) { arrivals.append(.init(frames: frames, time: ProcessInfo.processInfo.systemUptime)) }
        func snapshot() -> [FeedArrival] { arrivals }
    }
    private static func checkFeedPacing() async throws {
        let recorder = FeedRecorder(), began = ProcessInfo.processInfo.systemUptime
        let feed = try await feedAudio([Float](repeating: 0, count: 5440), began: began) { samples in
            await recorder.record(samples.count)
        }
        let arrivals = await recorder.snapshot()
        guard arrivals.map(\.frames) == [1600, 1600, 1600, 640] else { throw VoiceError.message("Feed check lost or padded samples") }
        var frames = 0
        for arrival in arrivals {
            frames += arrival.frames
            guard arrival.time >= began + Double(frames) / 16000 else { throw VoiceError.message("Audio arrived before it was captured") }
        }
        let delayedBegan = ProcessInfo.processInfo.systemUptime
        let delayed = try await feedAudio([Float](repeating: 0, count: 1600), began: delayedBegan) { _ in
            try await Task.sleep(for: .milliseconds(120))
        }
        guard delayed.completed - delayed.scheduledStop >= 0.12 else { throw VoiceError.message("Final delivery delay disappeared from the logical stop clock") }
        try emit(["event": "feed-pacing-check", "passed": true, "scope": "synthetic clock/transport test only; no models, microphone or insertion", "frames": frames,
                  "captureSeconds": 0.34, "deliveredBlockFrames": arrivals.map(\.frames), "arrivalSeconds": arrivals.map { $0.time - began },
                  "maxEarlyFeedSeconds": feed.maxEarly, "lastBlockDeadlineSeconds": feed.scheduledStop - began, "delayedFinalAppendSeconds": delayed.completed - delayed.scheduledStop])
    }
    private static func emit(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    private static func jsonLine(_ value: [String: Any], suppressContents: Bool = false) throws {
        let data = try JSONSerialization.data(withJSONObject: suppressContents ? StageTrace.redactedRecord(value) : value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self)); fflush(stdout)
    }
    private struct FormatCases: Decodable {
        struct Case: Decodable { let id: String; let text: String; let style: TextStyle; let context: String; let vocabulary: [String] }
        let source: String
        let humanAcceptance: Bool
        let cases: [Case]
    }
    private static func formatCases(_ url: URL) async throws {
        let fixtures = try JSONDecoder().decode(FormatCases.self, from: Data(contentsOf: url))
        guard fixtures.source == "synthetic-formatting-contract", !fixtures.humanAcceptance else {
            throw VoiceError.message("Formatting diagnostics require an explicitly synthetic fixture manifest")
        }
        let formatter = LocalFormatter(modelURL: ModelPaths.formatter)
        do {
        try await formatter.prepare()
        var failures = 0
        for fixture in fixtures.cases {
            do {
                let text = try await formatter.format(fixture.text, style: fixture.style, context: fixture.context, vocabulary: fixture.vocabulary)
                try jsonLine(["event": "format-contract", "source": fixtures.source, "humanAcceptance": false, "id": fixture.id, "original": fixture.text, "text": text, "validated": true])
            } catch {
                failures += 1
                try jsonLine(["event": "format-contract-failure", "id": fixture.id, "error": error.localizedDescription])
            }
        }
        try jsonLine(["event": "format-contract-summary", "cases": fixtures.cases.count, "failures": failures, "humanAcceptance": false])
        await formatter.shutdown()
        guard failures == 0 else { throw VoiceError.message("Synthetic formatting contracts failed") }
        } catch { await formatter.shutdown(); throw error }
    }
    private static func suite(_ arguments: [String]) async throws {
        let manifest = try JSONDecoder().decode(FixtureManifest.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
        let publicHuman = manifest.source == "public-human-fleurs" && manifest.publicCorpus?.dataset == "google/fleurs" && manifest.publicCorpus?.license == "cc-by-4.0" && manifest.publicCorpus?.revision == "70bb2e84b976b7e960aa89f1c648e09c59f894dd"
        guard (manifest.source == "synthetic-apple-say" || publicHuman), !manifest.humanAcceptance,
              !publicHuman || manifest.cases.allSatisfy({ $0.audioSHA256 != nil }) else { throw VoiceError.message("Suite requires explicitly synthetic or pinned public-human fixtures; private recordings are not accepted") }
        let repeats = max(1, min(10, arguments.dropFirst(3).compactMap(Int.init).first ?? 3))
        let ids = option("--ids=", in: arguments).map { Set($0.split(separator: ",").map(String.init)) }
        let styles = option("--styles=", in: arguments).map { $0.split(separator: ",").compactMap { TextStyle(rawValue: String($0)) } }
        let selected = manifest.cases.filter { fixture in
            if let ids { return ids.contains(fixture.id) }
            return arguments.contains("--long") || fixture.kind == "short"
        }
        guard !selected.isEmpty else { throw VoiceError.message("No matching fixtures") }
        let useSettingsDictionary = arguments.contains("--settings-dictionary")
        guard !arguments.contains("--trace-stages") || (publicHuman && !useSettingsDictionary) else {
            throw VoiceError.message("Stage tracing requires public FLEURS fixtures without the user dictionary")
        }
        var entries: [DictionaryEntry] = []
        if useSettingsDictionary {
            let settingsURL = ModelPaths.support.appendingPathComponent("settings.json")
            guard FileManager.default.fileExists(atPath: settingsURL.path) else { throw VoiceError.message("Local settings not found") }
            entries = try await SettingsStore(url: settingsURL).load().dictionary
        }
        let dictionary = DictionaryMatcher(entries)
        let streaming = arguments.contains("--stream")
        let speechConfiguration = suiteSpeechConfiguration(arguments)
        let baseSpeech = SpeechRuntime(configuration: speechConfiguration)
        let local = LocalFormatter(modelURL: ModelPaths.formatter)
        let trace = arguments.contains("--trace-stages") ? StageTrace() : nil
        let speech: any SpeechTranscribing
        let measuredFormatter: any TextFormatting
        if let trace { speech = StageSpeech(base: baseSpeech, trace: trace); measuredFormatter = StageFormatter(base: local, trace: trace) }
        else { speech = baseSpeech; measuredFormatter = local }
        do {
        let loadStarted = ProcessInfo.processInfo.systemUptime
        try await speech.prepare()
        let needsFormatting = selected.contains { fixture in (styles ?? fixture.styles.compactMap(TextStyle.init(rawValue:))).contains { $0 != .original } }
        if needsFormatting { try await local.prepare() }
        let warmAudio = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: selected[0].audio))
        // Warm the complete first public fixture through the same bounded pipeline.
        // It remains in all three measured repetitions; no reference is a prompt.
        let warmPipeline = ProcessingPipeline(speech: speech, formatter: needsFormatting ? measuredFormatter : OriginalFormatter(), coreSamples: Int(coreSeconds(arguments) * 16000), overlapSamples: Int(overlapSeconds(arguments) * 16000))
        _ = try await warmPipeline.process(samples: warmAudio, sessionID: UUID(), style: needsFormatting ? .cleaned : .original)
        try jsonLine(["event": "suite-start", "source": manifest.source, "coreSeconds": coreSeconds(arguments), "overlapSeconds": overlapSeconds(arguments), "vadSilenceSeconds": vadSilence(arguments), "trimTrailingSilence": arguments.contains("--trim-tail"), "encoderPrecision": arguments.contains("--encoder-v2") ? "int8-v2" : "int8", "sdkWorkers": speechConfiguration.sdkWorkers, "dualDecodeArbitration": speechConfiguration.dualDecodeArbitration, "reconciliationContextSeconds": 8, "boundedReconciliationAboveSeconds": 600, "humanAcceptance": false, "fixtures": selected.count, "repeats": repeats, "streamedAtRealTime": streaming, "loadAndWarmSeconds": ProcessInfo.processInfo.systemUptime - loadStarted,
                      "normalizationNotes": manifest.normalizationNotes, "hardware": "Run host; see machine receipt. Other simultaneous processes may affect latency.", "feedPacing": "append-after-capture-deadline", "feedChunkSamples": 1600, "latencyClock": "logical-capture-end-including-feed-lag", "warmupScope": "complete-first-fixture-pipeline-ungraded-no-case-exclusion"])
        var successful: [SuiteMeasurement] = [], failures = 0
        for fixture in selected {
            if let expected = fixture.audioSHA256 {
                let digest = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: fixture.audio))).map { String(format: "%02x", $0) }.joined()
                guard digest == expected else { throw VoiceError.message("Fixture checksum changed: \(fixture.id)") }
            }
            let audio = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: fixture.audio))
            for style in styles ?? fixture.styles.compactMap(TextStyle.init(rawValue:)) {
                for run in 1...repeats {
                    trace?.select(fixture: fixture.id, style: style.rawValue, run: run)
                    let formatter: any TextFormatting = style == .original ? OriginalFormatter() : measuredFormatter
                    let checkpoints = CheckpointMeasurements()
                    let pipeline = ProcessingPipeline(speech: speech, formatter: formatter, coreSamples: Int(coreSeconds(arguments) * 16000), overlapSamples: Int(overlapSeconds(arguments) * 16000), checkpointMinimumSamples: arguments.contains("--no-checkpoints") ? AudioCaptureBuffer.maximumSamples + 1 : 720_000, observeCheckpoint: { checkpoints.record($0, $1) })
                    do {
                        try await pipeline.start(sessionID: UUID(), style: style, dictionary: entries)
                        let began = ProcessInfo.processInfo.systemUptime
                        var feed: StreamFeed?
                        if streaming { feed = try await feedAudio(audio, began: began) { try await pipeline.append(samples: $0) } }
                        else { try await pipeline.append(samples: audio) }
                        let finalFeed = ProcessInfo.processInfo.systemUptime
                        let stopped = feed?.scheduledStop ?? finalFeed
                        trace?.captureEnd()
                        let result = try await pipeline.finish()
                        let finished = ProcessInfo.processInfo.systemUptime
                        let reference = words(fixture.reference), recognized = words(result.original), formatted = words(result.text)
                        let canonicalReference = words(fixture.reference, aliases: manifest.numberAliases)
                        let canonicalRecognized = words(result.original, aliases: manifest.numberAliases)
                        let canonicalFormatted = words(result.text, aliases: manifest.numberAliases)
                        let expectedFormatted = words(dictionary.replace(in: fixture.reference), aliases: manifest.numberAliases)
                        let strict = wer(reference, recognized), canonical = wer(canonicalReference, canonicalRecognized)
                        let stopLatency = finished - stopped
                        successful.append(.init(style: style.rawValue, kind: fixture.kind, stop: stopLatency, canonicalWER: canonical, fallback: result.usedFallback, complete: result.isComplete))
                        try jsonLine(["event": "case", "id": fixture.id, "language": fixture.language, "kind": fixture.kind, "tags": fixture.tags, "style": style.rawValue, "run": run,
                                      "audioSeconds": Double(audio.count) / 16000, "streamedAtRealTime": streaming, "modelProcessingAfterFinalFeedSeconds": finished - finalFeed,
                                      "feedCompletionDelaySeconds": streaming ? max(0, finalFeed - stopped) : 0, "maxEarlyFeedSeconds": feed?.maxEarly ?? 0, "maxFeedArrivalLagSeconds": feed?.maxLag ?? 0,
                                      "totalElapsedSeconds": finished - began, "stopToResultSeconds": streaming ? stopLatency : NSNull(),
                                      "strictOriginalWER": strict, "canonicalOriginalWER": canonical, "strictFormattedWER": wer(reference, formatted), "canonicalFormattedWER": wer(canonicalReference, canonicalFormatted), "dictionaryExpectedFormattedWER": wer(expectedFormatted, canonicalFormatted), "dictionaryEntries": entries.count,
                                      "strictReferenceWordCount": reference.count, "canonicalReferenceWordCount": canonicalReference.count,
                                      "strictOriginalWordEdits": Int((strict * Double(reference.count)).rounded()), "canonicalOriginalWordEdits": Int((canonical * Double(canonicalReference.count)).rounded()),
                                      "reference": useSettingsDictionary ? NSNull() : fixture.reference as Any, "original": useSettingsDictionary ? NSNull() : result.original as Any, "text": useSettingsDictionary ? NSNull() : result.text as Any, "contentsLogged": !useSettingsDictionary, "usedFallback": result.usedFallback,
                                      "recordingCheckpoints": checkpoints.snapshot(),
                                      "recognitionComplete": result.isComplete, "formatterAttempted": style != .original, "entireResultFormatted": result.isComplete && style != .original && !result.usedFallback,
                                      "resultProcessingStatus": !result.isComplete ? "recognition-partial" : style == .original ? "original-successful" : result.usedFallback ? "formatting-fallback-partial-or-full" : "formatted-successful",
                                      "referenceNegations": useSettingsDictionary ? NSNull() : negations(reference) as Any, "recognizedNegations": useSettingsDictionary ? NSNull() : negations(recognized) as Any, "formattedNegations": useSettingsDictionary ? NSNull() : negations(formatted) as Any,
                                      "referenceNumbers": useSettingsDictionary ? NSNull() : canonicalReference.filter { $0.allSatisfy(\.isNumber) } as Any, "recognizedNumbers": useSettingsDictionary ? NSNull() : canonicalRecognized.filter { $0.allSatisfy(\.isNumber) } as Any, "formattedNumbers": useSettingsDictionary ? NSNull() : canonicalFormatted.filter { $0.allSatisfy(\.isNumber) } as Any,
                                      "numbersPreserved": expectedFormatted.filter { $0.allSatisfy(\.isNumber) } == canonicalFormatted.filter { $0.allSatisfy(\.isNumber) }, "negationsPreserved": negations(expectedFormatted) == negations(canonicalFormatted)], suppressContents: trace != nil)
                    } catch {
                        await pipeline.cancel(); failures += 1
                        try jsonLine(["event": "case-failure", "id": fixture.id, "style": style.rawValue, "run": run, "error": error.localizedDescription], suppressContents: trace != nil)
                    }
                }
            }
        }
        var groups: [[String: Any]] = []
        for key in Set(successful.map { $0.style + ":" + $0.kind }).sorted() {
            let values = successful.filter { $0.style + ":" + $0.kind == key }
            let entirelyFormatted = values.filter { $0.complete && $0.style != "original" && !$0.fallback }
            groups.append(["styleAndKind": key, "runs": values.count, "p95AllProcessedAfterFinalFeedSeconds": percentile95(values.map(\.stop)), "latencyPopulation": "all processed results including visible formatting fallbacks",
                           "p95StopToResultSeconds": streaming ? percentile95(values.map(\.stop)) : NSNull(), "meanCanonicalOriginalWER": values.map(\.canonicalWER).reduce(0, +) / Double(values.count),
                           "fallbackRuns": values.filter(\.fallback).count, "recognitionIncompleteRuns": values.filter { !$0.complete }.count, "originalSuccessfulRuns": values.filter { $0.complete && $0.style == "original" }.count,
                           "entirelyFormattedRuns": entirelyFormatted.count,
                           "p95EntirelyFormattedProcessingAfterFinalFeedSeconds": entirelyFormatted.isEmpty ? NSNull() : percentile95(entirelyFormatted.map(\.stop)),
                           "p95EntirelyFormattedStopToResultSeconds": streaming && !entirelyFormatted.isEmpty ? percentile95(entirelyFormatted.map(\.stop)) : NSNull()])
        }
        try jsonLine(["event": "suite-summary", "source": manifest.source, "humanAcceptance": false, "processedRuns": successful.count, "recognitionCompleteRuns": successful.filter(\.complete).count, "entirelyFormattedRuns": successful.filter { $0.complete && $0.style != "original" && !$0.fallback }.count, "formattingFallbackRuns": successful.filter(\.fallback).count, "formattingAcceptance": successful.contains { $0.style != "original" && ($0.fallback || !$0.complete) } ? "not-passed-visible-fallbacks" : publicHuman ? "public-read-speech-not-personal-dictation-accepted" : "synthetic-only-not-human-accepted", "recognitionIncompleteRuns": successful.filter { !$0.complete }.count, "failedRuns": failures, "streamedAtRealTime": streaming, "groups": groups])
        await local.shutdown()
        if failures > 0 { throw VoiceError.message("Suite failed: \(failures) cases") }
        } catch { await local.shutdown(); throw error }
    }
    private static func option(_ prefix: String, in arguments: [String]) -> String? { arguments.first(where: { $0.hasPrefix(prefix) }).map { String($0.dropFirst(prefix.count)) } }
    private static func inspectSeams(manifestURL: URL, id: String, encoderV2: Bool = false, coreSeconds: Double = 14, overlapSeconds: Double = 0.5, vadSilence: Double = 0.5, trimTail: Bool = false, sdkWorkers: Int = 2) async throws {
        let manifest = try JSONDecoder().decode(FixtureManifest.self, from: Data(contentsOf: manifestURL))
        let publicHuman = manifest.source == "public-human-fleurs" && manifest.publicCorpus?.dataset == "google/fleurs" && manifest.publicCorpus?.license == "cc-by-4.0" && manifest.publicCorpus?.revision == "70bb2e84b976b7e960aa89f1c648e09c59f894dd"
        guard (manifest.source == "synthetic-apple-say" || publicHuman), !manifest.humanAcceptance,
              let fixture = manifest.cases.first(where: { $0.id == id }), let expected = fixture.audioSHA256 else {
            throw VoiceError.message("Seam diagnostics require a synthetic or pinned public-human, checksum-defined fixture")
        }
        let source = try Data(contentsOf: URL(fileURLWithPath: fixture.audio))
        guard SHA256.hash(data: source).map({ String(format: "%02x", $0) }).joined() == expected else { throw VoiceError.message("Fixture checksum changed") }
        let audio = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: fixture.audio))
        let speech = makeSpeech(encoderV2: encoderV2, silenceDuration: vadSilence, trimTrailingSilence: trimTail, sdkWorkers: sdkWorkers)
        let observer: @Sendable (Range<Int>, TranscriptSegment) -> Void = { bounds, segment in
            let lower = Double(bounds.lowerBound) / 16000, upper = Double(bounds.upperBound) / 16000
            let windowWords = segment.words.filter { abs(($0.start + $0.end) / 2 - lower) <= 1 || abs(($0.start + $0.end) / 2 - upper) <= 1 }
            do { try jsonLine(["event": "seam-segment", "source": manifest.source, "id": fixture.id, "segmentIndex": segment.index,
                              "commitStart": lower, "commitEnd": upper, "windowFirstWordStart": segment.words.first?.start ?? NSNull(), "windowLastWordEnd": segment.words.last?.end ?? NSNull(),
                              "segmentText": segment.text, "totalTimedWords": segment.words.count,
                              "firstTimedWord": segment.words.first.map { ["text": $0.text, "start": $0.start, "end": $0.end] as [String: Any] } ?? [:],
                              "lastTimedWord": segment.words.last.map { ["text": $0.text, "start": $0.start, "end": $0.end] as [String: Any] } ?? [:],
                              "boundaryWords": windowWords.map { word in ["text": word.text, "start": word.start, "end": word.end, "midpoint": (word.start + word.end) / 2,
                                                                           "independentMidpointCommitted": (word.start + word.end) / 2 >= lower && (word.start + word.end) / 2 < upper] as [String: Any] }]) }
            catch { fputs("Seam diagnostic output failed\n", stderr) }
        }
        let pipeline = ProcessingPipeline(speech: speech, formatter: OriginalFormatter(), coreSamples: Int(coreSeconds * 16000), overlapSamples: Int(overlapSeconds * 16000), observeSegment: observer)
        try await pipeline.start(sessionID: UUID(), style: .original)
        try await pipeline.append(samples: audio)
        let result = try await pipeline.finish()
        try jsonLine(["event": "seam-result", "source": manifest.source, "coreSeconds": coreSeconds, "overlapSeconds": overlapSeconds, "vadSilenceSeconds": vadSilence, "trimTrailingSilence": trimTail, "encoderPrecision": encoderV2 ? "int8-v2" : "int8", "sdkWorkers": sdkWorkers, "id": fixture.id, "audioSeconds": Double(audio.count) / 16000,
                      "canonicalWER": wer(words(fixture.reference, aliases: manifest.numberAliases), words(result.original, aliases: manifest.numberAliases)), "original": result.original])
    }
    private static func inspectWindow(manifestURL: URL, id: String, start: Double, end: Double, encoderV2: Bool = false, trimTail: Bool = false, repeats: Int = 1, sdkWorkers: Int = 2, dualDecode: Bool = false, blockSeconds: Int? = nil, blockContext: Int = 2) async throws {
        let manifest = try JSONDecoder().decode(FixtureManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.source == "synthetic-apple-say", !manifest.humanAcceptance,
              let fixture = manifest.cases.first(where: { $0.id == id }), let expected = fixture.audioSHA256 else { throw VoiceError.message("Only checksum-defined synthetic windows can be inspected") }
        let source = try Data(contentsOf: URL(fileURLWithPath: fixture.audio))
        guard SHA256.hash(data: source).map({ String(format: "%02x", $0) }).joined() == expected else { throw VoiceError.message("Fixture checksum changed") }
        let audio = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: fixture.audio))
        guard start.isFinite, end.isFinite, start >= 0, end > start, end <= Double(audio.count) / 16000 else { throw VoiceError.message("Invalid audio window") }
        let speech = makeSpeech(encoderV2: encoderV2, trimTrailingSilence: trimTail, sdkWorkers: sdkWorkers, dualDecode: dualDecode, blockSeconds: blockSeconds, blockContext: blockContext)
        let preparing = ProcessInfo.processInfo.systemUptime
        try await speech.prepare()
        let warmSeconds = ProcessInfo.processInfo.systemUptime - preparing
        let lower = Int((start * 16000).rounded()), upper = Int((end * 16000).rounded())
        let samples = Array(audio[lower..<upper])
        for run in 1...max(1, min(10, repeats)) {
            let began = ProcessInfo.processInfo.systemUptime
            let decoded = blockSeconds == nil
                ? try await speech.transcribe(samples: samples, sessionID: UUID(), index: 0, offset: start)
                : try await speech.reconcile(samples: samples, sessionID: UUID())
            let segment = blockSeconds == nil || start == 0 ? decoded : TranscriptSegment(sessionID: decoded.sessionID, index: 0, text: decoded.text, words: decoded.words.map { .init(text: $0.text, start: $0.start + start, end: $0.end + start) })
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            let fullFixture = lower == 0 && upper == audio.count
            try jsonLine(["event": "independent-asr-window", "source": manifest.source, "humanAcceptance": false, "encoderPrecision": encoderV2 ? "int8-v2" : "int8", "sdkWorkers": sdkWorkers, "dualDecodeArbitration": dualDecode, "reconciliationBlockSeconds": blockSeconds ?? NSNull(), "reconciliationContextSeconds": blockSeconds == nil ? NSNull() : blockContext, "id": fixture.id, "audioStart": start, "audioEnd": end,
                          "run": run, "loadAndWarmSeconds": warmSeconds, "recognitionSeconds": elapsed, "fullFixture": fullFixture,
                          "canonicalWER": fullFixture ? wer(words(fixture.reference, aliases: manifest.numberAliases), words(segment.text, aliases: manifest.numberAliases)) : NSNull(),
                          "text": segment.text, "words": segment.words.map { ["text": $0.text, "start": $0.start, "end": $0.end] as [String: Any] }])
        }
    }
    private static func makeSpeech(encoderV2: Bool, silenceDuration: Double = 0.5, trimTrailingSilence: Bool = false, sdkWorkers: Int = 2, dualDecode: Bool = false, blockSeconds: Int? = nil, blockContext: Int = 8) -> SpeechRuntime {
        SpeechRuntime(configuration: makeSpeechConfiguration(encoderV2: encoderV2, silenceDuration: silenceDuration, trimTrailingSilence: trimTrailingSilence, sdkWorkers: sdkWorkers, dualDecode: dualDecode, blockSeconds: blockSeconds, blockContext: blockContext))
    }
    /// Both the real suite and the model-free diagnostic consume this same value.
    private static func suiteSpeechConfiguration(_ arguments: [String]) -> SpeechRuntimeConfiguration {
        makeSpeechConfiguration(encoderV2: arguments.contains("--encoder-v2"), silenceDuration: vadSilence(arguments), trimTrailingSilence: arguments.contains("--trim-tail"), sdkWorkers: sdkWorkers(arguments), dualDecode: arguments.contains("--dual-decode"))
    }
    private static func makeSpeechConfiguration(encoderV2: Bool, silenceDuration: Double = 0.5, trimTrailingSilence: Bool = false, sdkWorkers: Int = 2, dualDecode: Bool = false, blockSeconds: Int? = nil, blockContext: Int = 8) -> SpeechRuntimeConfiguration {
        var configuration = SpeechRuntimeConfiguration(modelDirectory: ModelPaths.speech)
        configuration.encoderPrecision = encoderV2 ? .int8V2 : .int8
        configuration.activitySilenceDuration = silenceDuration
        configuration.trimTrailingSilence = trimTrailingSilence
        configuration.sdkWorkers = sdkWorkers
        configuration.dualDecodeArbitration = dualDecode
        configuration.reconciliationBlockSeconds = blockSeconds
        configuration.reconciliationContextSeconds = blockContext
        return configuration
    }
    private static func coreSeconds(_ arguments: [String]) -> Double {
        let value = option("--core-seconds=", in: arguments).flatMap(Double.init) ?? 14
        guard value.isFinite else { return 14 }
        return min(15 - 2 * overlapSeconds(arguments), max(1, value))
    }
    private static func overlapSeconds(_ arguments: [String]) -> Double {
        guard let value = option("--overlap-seconds=", in: arguments).flatMap(Double.init), value.isFinite else { return 0.5 }
        return min(2, max(0.25, value))
    }
    private static func vadSilence(_ arguments: [String]) -> Double {
        guard let value = option("--vad-silence=", in: arguments).flatMap(Double.init), value.isFinite else { return 0.5 }
        return min(1, max(0, value))
    }
    private static func sdkWorkers(_ arguments: [String]) -> Int {
        min(4, max(1, option("--sdk-workers=", in: arguments).flatMap(Int.init) ?? 2))
    }
    private static func words(_ text: String, aliases: [String: String] = [:]) -> [String] {
        var normalized = text.lowercased().precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
        normalized = normalized.split(separator: " ").joined(separator: " ")
        for alias in aliases.keys.sorted(by: { $0.count > $1.count }) {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: alias) + "(?![\\p{L}\\p{N}])"
            normalized = normalized.replacingOccurrences(of: pattern, with: aliases[alias]!, options: .regularExpression)
        }
        return normalized.split(separator: " ").map(String.init)
    }
    private static func wer(_ reference: [String], _ actual: [String]) -> Double {
        var previous = Array(0...actual.count)
        for (i, expected) in reference.enumerated() {
            var current = [i + 1]
            for (j, word) in actual.enumerated() { current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (expected == word ? 0 : 1))) }
            previous = current
        }
        return Double(previous.last ?? actual.count) / Double(max(1, reference.count))
    }
    private static func negations(_ words: [String]) -> [String] {
        let values: Set<String> = ["nicht", "kein", "keine", "keinen", "keiner", "keines", "keinem", "nie", "niemals", "ohne", "not", "no", "never", "without", "cannot"]
        return words.filter { values.contains($0) }
    }
    private static func percentile95(_ values: [Double]) -> Double { let sorted = values.sorted(); return sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)] }
}

private struct PublicCorpus: Decodable { let dataset: String; let revision: String; let license: String }
private struct FixtureManifest: Decodable { let source: String; let humanAcceptance: Bool; let normalizationNotes: String; let numberAliases: [String: String]; let cases: [Fixture]; let publicCorpus: PublicCorpus? }
private struct Fixture: Decodable { let id: String; let language: String; let audio: String; let audioSHA256: String?; let reference: String; let kind: String; let tags: [String]; let styles: [String] }
private struct SuiteMeasurement { let style: String; let kind: String; let stop: Double; let canonicalWER: Double; let fallback: Bool; let complete: Bool }

private final class ProgressPrinter: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Int64(-1)
    func report(_ current: Int64, _ total: Int64, _ group: String) {
        lock.lock(); defer { lock.unlock() }
        let step = current / (256 * 1024 * 1024)
        if step != last || current == total { last = step; print("\(group): \(current) / \(total) bytes") }
    }
}
