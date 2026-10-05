import Foundation

/// Completion can be released by Original/cancellation without waiting for a
/// misbehaving formatter. No actor or dictated text is retained by this latch.
private final class FormattingCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if completed { lock.unlock(); continuation.resume() }
            else { self.continuation = continuation; lock.unlock() }
        }
    }
    func release() {
        lock.lock(); completed = true; let current = continuation; continuation = nil; lock.unlock()
        current?.resume()
    }
}

/// A later recognition failure preserves committed text for explicit recovery, never insertion.
public struct PartialDictationError: LocalizedError, Sendable {
    public let result: DictationResult
    public let reason: String
    public init(result: DictationResult, reason: String) { self.result = result; self.reason = reason }
    public var errorDescription: String? { "Das Diktat ist unvollständig: \(reason)" }
}

/// Streaming ASR and formatting have separate serial workers. PCM is never dropped to catch up.
public actor ProcessingPipeline {
    public typealias Progress = @Sendable (Double) -> Void
    private struct Job: Sendable { let index: Int; let audio: Range<Int>; let commit: Range<Int>; let overlap: Bool }
    private struct FormatJob: Sendable { let text: String; let skip: Bool; let sampleEnd: Int }
    private struct CachedFormat: Sendable { let value: FormattingRevision.Cache; let sampleEnd: Int }
    private struct Checkpoint: Sendable { let sampleEnd: Int; let transcript: TranscriptSegment; let cache: FormattingRevision.Cache }
    struct SeamWord: Sendable { let word: TranscriptWord; let committed: Bool; let ownershipTime: Double }
    struct SeamSelection: Sendable { let text: String; let words: [TranscriptWord]; let window: [SeamWord] }
    private let speech: SpeechTranscribing
    private let formatter: TextFormatting
    private let activity: (any SpeechActivityDetecting)?
    private let observeSegment: (@Sendable (Range<Int>, TranscriptSegment) -> Void)?
    private let coreSamples: Int
    private let overlapSamples: Int
    private let checkpointMinimumSamples: Int
    private let checkpointIntervalSamples: Int
    private let observeCheckpoint: (@Sendable (Int, Bool) -> Void)?
    private var sessionID: UUID?
    private var generation = UUID()
    private var formatterGeneration = UUID()
    private var originalRequested = false
    private var samples: [Float] = []
    private var jobs: [Job] = []
    private var formats: [FormatJob] = []
    private var asrTask: Task<Void, Never>?
    private var formatTask: Task<Void, Never>?
    private var formattingCompletion: FormattingCompletion?
    private var segmentTask: Task<Void, Never>?
    private var reconciliationTask: Task<TranscriptSegment, Error>?
    private var activityState = SpeechActivityState()
    private var style: TextStyle = .original
    private var matcher = StreamingDictionaryMatcher([])
    private var dictionary = DictionaryMatcher([])
    private var raw: [String] = []
    private var rendered: [String] = []
    private var formattingCache: [CachedFormat] = []
    private var revisionTask: Task<(String, Bool), Error>?
    private var checkpointTask: Task<Void, Never>?
    private var checkpointGeneration = UUID()
    private var checkpoint: Checkpoint?
    private var checkpointStartedAtSample = 0
    private var checkpointFailures = 0
    private var fallback = false
    private var formatterReady = false
    private var failure: Error?
    private var nextIndex = 0
    private var committedSamples = 0
    private var processedSamples = 0
    private var previousWindow: [SeamWord] = []
    private var scannedSamples = 0
    private var quietSamples = 0
    private var heardSpeech = false
    private var naturalPauseCount = 0
    private var forcedWindowUsed = false
    private var accepting = false
    private var progress: Progress?
    private let maxFormattingBacklog = 4
    public init(speech: SpeechTranscribing, formatter: TextFormatting, coreSamples: Int = 224_000, overlapSamples: Int = 8000, observeSegment: (@Sendable (Range<Int>, TranscriptSegment) -> Void)? = nil, checkpointMinimumSamples: Int = 720_000, checkpointIntervalSamples: Int = 240_000, observeCheckpoint: (@Sendable (Int, Bool) -> Void)? = nil) {
        precondition(coreSamples >= 16_000 && overlapSamples >= 0 && coreSamples + 2 * overlapSamples <= 240_000, "ASR window including overlap must be at most fifteen seconds")
        self.speech = speech; self.formatter = formatter; self.activity = speech as? any SpeechActivityDetecting
        self.observeSegment = observeSegment
        self.coreSamples = coreSamples
        self.overlapSamples = overlapSamples
        precondition(checkpointMinimumSamples > 240_000 && checkpointIntervalSamples > 0)
        self.checkpointMinimumSamples = checkpointMinimumSamples; self.checkpointIntervalSamples = checkpointIntervalSamples
        self.observeCheckpoint = observeCheckpoint
    }

    public func start(sessionID: UUID = UUID(), style: TextStyle, dictionary entries: [DictionaryEntry] = []) async throws {
        cancel()
        let token = UUID(); generation = token; self.sessionID = sessionID; self.style = style
        samples = []; jobs = []; formats = []; raw = []; rendered = []; fallback = false; failure = nil
        formattingCache = []
        nextIndex = 0; committedSamples = 0; processedSamples = 0; scannedSamples = 0; quietSamples = 0; heardSpeech = false
        activityState = SpeechActivityState()
        naturalPauseCount = 0; forcedWindowUsed = false
        previousWindow = []
        originalRequested = false
        matcher = StreamingDictionaryMatcher(entries); dictionary = DictionaryMatcher(entries)
        try await speech.prepare(); try ensure(token)
        formatterReady = style == .original
        if style != .original {
            do { try await formatter.prepare(); try ensure(token); formatterReady = true }
            catch is CancellationError { throw CancellationError() }
            catch { try ensure(token); formatterReady = false; fallback = true }
        }
        accepting = true
    }
    public func append(samples incoming: [Float]) throws {
        guard accepting, sessionID != nil else { throw VoiceError.message("Kein aktives Diktat") }
        guard samples.count + incoming.count <= AudioCaptureBuffer.maximumSamples else { throw VoiceError.message("Das Diktat überschreitet 20 Minuten") }
        guard incoming.allSatisfy(\.isFinite) else { throw VoiceError.message("Audio enthält ungültige Samples") }
        samples.append(contentsOf: incoming)
        if activity != nil { launchSegmenter() }
        else { segmentAvailable(final: false); launchASR() }
        launchCheckpoint()
    }
    public func finish() async throws -> DictationResult {
        guard let id = sessionID, accepting else { throw VoiceError.message("Kein aktives Diktat") }
        let token = generation; accepting = false
        stopCheckpoint()
        let reconciliation = samples.count > 240_000 ? speech as? any SpeechSessionReconciling : nil
        if activity != nil {
            launchSegmenter()
            if let segmentTask { await segmentTask.value }; try ensure(token)
            if let failure, reconciliation == nil { try throwFailure(failure, id: id, token: token) }
            while samples.count - committedSamples > coreSamples + overlapSamples {
                forcedWindowUsed = true
                enqueueAudio(commitEnd: committedSamples + coreSamples, decodeEnd: committedSamples + coreSamples + overlapSamples, overlap: true)
            }
            if committedSamples < samples.count {
                enqueueAudio(commitEnd: samples.count, decodeEnd: samples.count, overlap: committedSamples > 0)
            }
        } else { segmentAvailable(final: true) }
        launchASR()
        if let asrTask { await asrTask.value }; try ensure(token)
        if let failure, reconciliation == nil { try throwFailure(failure, id: id, token: token) }
        if let reconciliation {
            do {
                let pcm = samples
                let known = checkpoint.flatMap { $0.sampleEnd == pcm.count ? $0.transcript : nil }
                let verification = Task { if let known { return known }; return try await reconciliation.reconcile(samples: pcm, sessionID: id) }
                reconciliationTask = verification
                var verified = try await withTaskCancellationHandler {
                    try await verification.value
                } onCancel: { verification.cancel() }
                try ensure(token)
                reconciliationTask = nil
                guard verified.sessionID == id else { throw VoiceError.message("Spracherkennung lieferte ein fremdes Diktat") }
                let streamed = raw.joined(separator: " ")
                if activity != nil, failure == nil, naturalPauseCount > 0, !forcedWindowUsed, pcm.count <= 480_000,
                   Self.wholeDecodeLostShortPausePrefix(segments: raw, verified: verified.text) {
                    // The SDK's whole-clip decoder can omit an entire language on
                    // short switches. Successful <=15-second VAD decodes cover
                    // all PCM; only a large, exact ordered omission qualifies.
                    verified = .init(sessionID: id, index: 0, text: streamed)
                }
                guard streamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !verified.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw VoiceError.message("Der abschließende Abgleich hat bereits erkannte Wörter ausgelassen")
                }
                if let checkpoint, known != nil, !originalRequested, style != .original {
                    discardFormatting()
                    raw = [verified.text]; rendered = [checkpoint.cache.output]; fallback = false
                    matcher = StreamingDictionaryMatcher(dictionary.entries)
                } else if failure != nil || Self.lexicalSequence(streamed) != Self.lexicalSequence(verified.text) {
                    // A fast final ASR call must not discard a nearly completed
                    // first formatting job just because its cache is not ready yet.
                    let provisional = dictionary.replace(in: streamed)
                    let finalTarget = dictionary.replace(in: verified.text)
                    let canReusePending = FormattingRevision.plan(target: finalTarget, cache: [.init(input: provisional, output: provisional, formatted: true)]) != nil
                    if !originalRequested, style != .original, known == nil, canReusePending { try await waitForFormatting(token: token) }
                    let cache = cachedFormatting(through: pcm.count)
                    discardFormatting()
                    let target = dictionary.replace(in: verified.text)
                    raw = [verified.text]; failure = nil
                    if !originalRequested, style != .original, formatterReady,
                       let plan = FormattingRevision.plan(target: target, cache: cache) {
                        let formatter = self.formatter, style = self.style, dictionary = self.dictionary
                        let revision = Task { () throws -> (String, Bool) in
                            try await FormattingRevision.render(plan: plan, target: target, formatter: formatter, style: style, dictionary: dictionary)
                        }
                        revisionTask = revision
                        do {
                            let value = try await withTaskCancellationHandler { try await revision.value } onCancel: { revision.cancel() }
                            try ensure(token)
                            if !originalRequested { rendered = [value.0]; fallback = value.1 }
                        } catch is CancellationError {
                            try ensure(token)
                            guard originalRequested else { throw CancellationError() }
                        }
                        revisionTask = nil
                    } else { originalRequested = true }
                    // Old streaming dictionary suffixes must never follow the verified text.
                    matcher = StreamingDictionaryMatcher(dictionary.entries)
                }
                raw = [verified.text]; failure = nil
            } catch is CancellationError { throw CancellationError() }
            catch { try throwFailure(failure ?? error, id: id, token: token) }
        }
        let tail = matcher.process("", final: true)
        if !tail.isEmpty { enqueueFormat(tail) }
        launchFormatter()
        try await waitForFormatting(token: token); try ensure(token)
        if let failure { try throwFailure(failure, id: id, token: token) }
        let original = raw.filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = originalRequested ? dictionary.replace(in: original) : ParagraphLayout.joinSections(rendered)
        let result = DictationResult(id: id, text: originalRequested ? text : ParagraphLayout.apply(text, style: style), original: original, usedFallback: style != .original && (fallback || originalRequested), duration: Double(samples.count) / 16_000)
        sessionID = nil; samples = []; jobs = []; formats = []; previousWindow = []
        return result
    }
    public func cancel() {
        generation = UUID(); accepting = false; sessionID = nil
        formatterGeneration = UUID(); originalRequested = false
        asrTask?.cancel(); formatTask?.cancel(); segmentTask?.cancel(); reconciliationTask?.cancel()
        revisionTask?.cancel(); revisionTask = nil
        formattingCompletion?.release(); formattingCompletion = nil
        asrTask = nil; formatTask = nil; segmentTask = nil; reconciliationTask = nil
        samples = []; jobs = []; formats = []; raw = []; rendered = []; previousWindow = []; progress = nil
        formattingCache = []
        stopCheckpoint(); checkpoint = nil; checkpointStartedAtSample = 0; checkpointFailures = 0
    }
    /// Switch an in-flight finish to recognized text, retaining dictionary replacements.
    /// Recognition still completes once; this never creates a second delivery result.
    public func requestOriginal() {
        guard sessionID != nil, style != .original, !originalRequested else { return }
        originalRequested = true
        stopCheckpoint(); checkpoint = nil
        discardFormatting()
    }
    private func discardFormatting() {
        formatterGeneration = UUID()
        formatTask?.cancel(); formatTask = nil
        formattingCompletion?.release(); formattingCompletion = nil
        revisionTask?.cancel(); revisionTask = nil
        formats = []; rendered = []
    }
    private func waitForFormatting(token: UUID) async throws {
        guard !originalRequested, let pending = formatTask else { return }
        let completion = FormattingCompletion(); formattingCompletion = completion
        Task { await pending.value; completion.release() }
        await withTaskCancellationHandler { await completion.wait() } onCancel: { completion.release() }
        try ensure(token)
        if formattingCompletion === completion { formattingCompletion = nil }
    }
    private func stopCheckpoint() {
        checkpointGeneration = UUID(); checkpointTask?.cancel(); checkpointTask = nil
    }
    private func cachedFormatting(through sampleEnd: Int) -> [FormattingRevision.Cache] {
        let prefix = checkpoint.flatMap { $0.sampleEnd <= sampleEnd ? $0 : nil }
        return (prefix.map { [$0.cache] } ?? []) + formattingCache.filter {
            $0.sampleEnd <= sampleEnd && $0.sampleEnd > (prefix?.sampleEnd ?? 0)
        }.map(\.value)
    }
    private func launchCheckpoint() {
        guard accepting, !originalRequested, style != .original, formatterReady,
              checkpointTask == nil, checkpointFailures < 3, samples.count >= checkpointMinimumSamples,
              let speech = speech as? any SpeechSessionReconciling, let id = sessionID else { return }
        // Above ten minutes, keep the heavier bounded ASR pass off the 15-second cadence.
        let cadence = (samples.count > 9_600_000 ? max(960_000, checkpointIntervalSamples) : checkpointIntervalSamples) * (1 << checkpointFailures)
        guard checkpointStartedAtSample == 0 || samples.count - checkpointStartedAtSample >= cadence else { return }
        let end = samples.count, token = generation, checkpointToken = UUID()
        checkpointGeneration = checkpointToken; checkpointStartedAtSample = end
        let pcm = Array(samples[..<end])
        checkpointTask = Task { await self.prepareCheckpoint(speech: speech, pcm: pcm, end: end, id: id, token: token, checkpointToken: checkpointToken) }
    }
    private func ensureCheckpoint(_ token: UUID, _ checkpointToken: UUID) throws {
        try ensure(token)
        guard accepting, !originalRequested, checkpointToken == checkpointGeneration else { throw CancellationError() }
    }
    private func prepareCheckpoint(speech: any SpeechSessionReconciling, pcm: [Float], end: Int, id: UUID, token: UUID, checkpointToken: UUID) async {
        do {
            let verified = try await speech.reconcile(samples: pcm, sessionID: id)
            try ensureCheckpoint(token, checkpointToken)
            guard verified.sessionID == id, !verified.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VoiceError.message("Ungültiger Aufnahme-Abgleich") }
            let target = dictionary.replace(in: verified.text)
            let plan = FormattingRevision.plan(target: target, cache: cachedFormatting(through: end)) ?? FormattingRevision.coldPlan(target: target)
            let output = try await FormattingRevision.render(plan: plan, target: target, formatter: formatter, style: style, dictionary: dictionary)
            try ensureCheckpoint(token, checkpointToken)
            if !output.1 { checkpoint = Checkpoint(sampleEnd: end, transcript: verified, cache: .init(input: target, output: output.0, formatted: true)); checkpointFailures = 0 }
            else { checkpointFailures += 1 }
            observeCheckpoint?(end, !output.1)
        } catch {
            if token == generation, checkpointToken == checkpointGeneration, accepting { checkpointFailures += 1; observeCheckpoint?(end, false) }
        }
        if token == generation, checkpointToken == checkpointGeneration {
            checkpointTask = nil
            launchCheckpoint()
        }
    }
    public func backlogSeconds() -> Double { Double(max(0, samples.count - processedSamples)) / 16_000 }
    public func process(samples: [Float], sessionID: UUID, style: TextStyle, vocabulary: [String] = [], progress: Progress? = nil) async throws -> DictationResult {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await start(sessionID: sessionID, style: style, dictionary: vocabulary.map { DictionaryEntry(phrase: $0) })
            self.progress = progress
            try Task.checkCancellation(); try append(samples: samples)
            return try await finish()
        } onCancel: { Task { await self.cancel(sessionID: sessionID) } }
    }
    private func cancel(sessionID requested: UUID) {
        guard sessionID == requested else { return }
        cancel()
    }
    private func ensure(_ token: UUID) throws { try Task.checkCancellation(); guard token == generation, sessionID != nil else { throw CancellationError() } }
    private func throwFailure(_ error: Error, id: UUID, token: UUID) throws -> Never {
        try ensure(token)
        if error is CancellationError { throw CancellationError() }
        let original = raw.filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { cancel(); throw error }
        let result = DictationResult(id: id, text: original, original: original, usedFallback: false,
            duration: Double(samples.count) / 16_000, isComplete: false)
        cancel()
        throw PartialDictationError(result: result, reason: error.localizedDescription)
    }
    private func launchSegmenter() {
        guard segmentTask == nil, activity != nil, scannedSamples + 4096 <= samples.count else { return }
        let token = generation
        segmentTask = Task { await self.drainSegmenter(token: token) }
    }
    private func drainSegmenter(token: UUID) async {
        guard let activity else { return }
        do {
            while token == generation, scannedSamples + 4096 <= samples.count {
                try ensure(token)
                let end = scannedSamples + 4096
                let result = try await activity.detectActivity(samples: Array(samples[scannedSamples..<end]), state: activityState)
                // append and cancellation may enter the actor during Core ML inference.
                try ensure(token)
                activityState = result.state; scannedSamples = end
                // Exact sample bounds cap the decoded window at 15 seconds including both overlaps.
                if end - committedSamples >= coreSamples + overlapSamples {
                    forcedWindowUsed = true
                    enqueueAudio(commitEnd: committedSamples + coreSamples, decodeEnd: committedSamples + coreSamples + overlapSamples, overlap: true)
                }
                if result.speechEnded, end > committedSamples {
                    naturalPauseCount += 1
                    enqueueAudio(commitEnd: end, decodeEnd: end, overlap: committedSamples > 0)
                }
                launchASR()
            }
        } catch { if token == generation { failure = error } }
        if token == generation { segmentTask = nil }
    }
    private func segmentAvailable(final: Bool) {
        // Lightweight fallback for transcriber test doubles without SpeechActivityDetecting.
        let frame = 160, silence = 8000, core = coreSamples, overlap = overlapSamples
        while scannedSamples + frame <= samples.count {
            let end = scannedSamples + frame
            let rms = sqrt(samples[scannedSamples..<end].reduce(Float(0)) { $0 + $1 * $1 } / Float(frame))
            if rms < 0.012 { quietSamples += frame } else { quietSamples = 0; heardSpeech = true }
            scannedSamples = end
            if heardSpeech && quietSamples >= silence {
                enqueueAudio(commitEnd: end, decodeEnd: end, overlap: committedSamples > 0)
                quietSamples = 0; heardSpeech = false
            } else if end - committedSamples >= core + overlap {
                enqueueAudio(commitEnd: committedSamples + core, decodeEnd: committedSamples + core + overlap, overlap: true)
                quietSamples = 0; heardSpeech = false
            }
        }
        if final {
            while samples.count - committedSamples > coreSamples + overlap {
                enqueueAudio(commitEnd: committedSamples + coreSamples, decodeEnd: committedSamples + coreSamples + overlap, overlap: true)
            }
            if committedSamples < samples.count { enqueueAudio(commitEnd: samples.count, decodeEnd: samples.count, overlap: committedSamples > 0) }
        }
    }
    private func enqueueAudio(commitEnd: Int, decodeEnd: Int, overlap: Bool) {
        guard commitEnd > committedSamples else { return }
        let lower = overlap ? max(0, committedSamples - overlapSamples) : committedSamples
        jobs.append(.init(index: nextIndex, audio: lower..<decodeEnd, commit: committedSamples..<commitEnd, overlap: overlap))
        nextIndex += 1; committedSamples = commitEnd
    }
    private func launchASR() {
        guard failure == nil, asrTask == nil, !jobs.isEmpty, let id = sessionID else { return }
        let token = generation
        asrTask = Task { await self.drainASR(token: token, id: id) }
    }
    private func drainASR(token: UUID, id: UUID) async {
        do {
            while token == generation, !jobs.isEmpty {
                try ensure(token)
                let job = jobs.removeFirst()
                let pcm = Array(samples[job.audio])
                let segment = try await speech.transcribe(samples: pcm, sessionID: id, index: job.index, offset: Double(job.audio.lowerBound) / 16_000)
                try ensure(token)
                guard segment.sessionID == id, segment.index == job.index else { throw VoiceError.message("Spracherkennung lieferte einen fremden Abschnitt") }
                observeSegment?(job.commit, segment)
                let selection = try Self.selectSeamWords(segment: segment, bounds: job.commit, requiresTimings: job.overlap, previous: previousWindow)
                let text = selection.text
                previousWindow = selection.window
                raw.append(text)
                processedSamples = job.commit.upperBound
                let stable = matcher.process(text + " ")
                if !stable.isEmpty { enqueueFormat(stable) }
                progress?(Double(job.commit.upperBound) / Double(max(1, samples.count)))
            }
        } catch { if token == generation { failure = error } }
        if token == generation { asrTask = nil }
    }
    static func committedText(segment: TranscriptSegment, bounds: Range<Int>, requiresTimings: Bool) throws -> String {
        try selectSeamWords(segment: segment, bounds: bounds, requiresTimings: requiresTimings).text
    }
    static func lexicalSequence(_ text: String) -> [String] {
        let letters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'"))
        return text.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: letters.inverted).filter { !$0.isEmpty }
    }
    static func wholeDecodeLostShortPausePrefix(segments: [String], verified: String) -> Bool {
        let chunks = segments.map(lexicalSequence).filter { !$0.isEmpty }
        let full = chunks.flatMap { $0 }, partial = lexicalSequence(verified)
        guard !partial.isEmpty, full.count - partial.count >= max(5, (full.count + 2) / 3) else { return false }
        var missing: [String] = []
        for boundary in chunks.indices.dropLast() {
            missing += chunks[boundary]
            let distinct = Set(missing).count
            if chunks[(boundary + 1)...].flatMap({ $0 }) == partial,
               distinct >= min(6, missing.count), distinct * 2 > missing.count { return true }
        }
        return false
    }
    static func selectSeamWords(segment: TranscriptSegment, bounds: Range<Int>, requiresTimings: Bool, previous: [SeamWord] = []) throws -> SeamSelection {
        guard !segment.words.isEmpty else {
            if requiresTimings && !segment.text.isEmpty { throw VoiceError.message("Überlappender Abschnitt hat keine Wortzeitstempel") }
            return SeamSelection(text: segment.text, words: [], window: [])
        }
        let lower = Double(bounds.lowerBound) / 16_000, upper = Double(bounds.upperBound) / 16_000
        let matches = seamMatches(previous: previous, current: segment.words, boundary: lower)
        var selected: [String] = []
        var selectedWords: [TranscriptWord] = []
        var window: [SeamWord] = []
        for (index, word) in segment.words.enumerated() {
            let midpoint = (word.start + word.end) / 2
            var ownershipTime = midpoint
            var include = midpoint >= lower && midpoint < upper
            var committed = midpoint < lower
            if let priorIndex = matches[index] {
                let prior = previous[priorIndex]
                // Two independent decodes can shift the same acoustic word across the cut.
                // The earlier full window owns matched words; its uncommitted right context
                // also rescues a word whose second timestamp drifts left of the cut.
                ownershipTime = prior.ownershipTime
                include = !prior.committed && ownershipTime >= lower && ownershipTime < upper
                committed = prior.committed
            }
            if include { selected.append(word.text); selectedWords.append(word); committed = true }
            window.append(SeamWord(word: word, committed: committed, ownershipTime: ownershipTime))
        }
        return SeamSelection(text: selected.joined(separator: " "), words: selectedWords, window: window)
    }
    private static func seamMatches(previous: [SeamWord], current: [TranscriptWord], boundary: Double) -> [Int: Int] {
        func midpoint(_ word: TranscriptWord) -> Double { (word.start + word.end) / 2 }
        func normalized(_ text: String) -> String {
            text.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols))
        }
        // Only compare the shared acoustic context, never repeated words elsewhere in a dictation.
        let priorIndices = previous.indices.filter { abs(midpoint(previous[$0].word) - boundary) <= 1 }
        let currentIndices = current.indices.filter { abs(midpoint(current[$0]) - boundary) <= 1 }
        guard !priorIndices.isEmpty, !currentIndices.isEmpty else { return [:] }
        let rows = priorIndices.count, columns = currentIndices.count
        var scores = Array(repeating: Array(repeating: Double(0), count: columns + 1), count: rows + 1)
        var decisions = Array(repeating: Array(repeating: UInt8(0), count: columns + 1), count: rows + 1)
        for row in 1...rows {
            for column in 1...columns {
                scores[row][column] = scores[row - 1][column]; decisions[row][column] = 1
                if scores[row][column - 1] > scores[row][column] {
                    scores[row][column] = scores[row][column - 1]; decisions[row][column] = 2
                }
                let prior = previous[priorIndices[row - 1]].word, next = current[currentIndices[column - 1]]
                let token = normalized(prior.text), drift = abs(midpoint(prior) - midpoint(next))
                // Observed real window jitter reaches 320 ms. The 500 ms overlap bounds matching.
                if !token.isEmpty, token == normalized(next.text), drift <= 0.5 {
                    let matched = scores[row - 1][column - 1] + 2 - drift / 0.5
                    if matched > scores[row][column] {
                        scores[row][column] = matched; decisions[row][column] = 3
                    }
                }
            }
        }
        var matches: [Int: Int] = [:]
        var row = rows, column = columns
        while row > 0 && column > 0 {
            switch decisions[row][column] {
            case 3:
                matches[currentIndices[column - 1]] = priorIndices[row - 1]; row -= 1; column -= 1
            case 2: column -= 1
            default: row -= 1
            }
        }
        if matches.count == 1, let match = matches.first {
            let prior = previous[match.value], next = current[match.key]
            // Without another lexical anchor, two disjoint instances may be intentional
            // repetition. Retain acoustic ownership rather than suppressing that second word.
            if prior.committed, min(prior.word.end, next.end) <= max(prior.word.start, next.start) {
                matches.removeAll()
            }
        }
        return matches
    }
    private func enqueueFormat(_ text: String) {
        guard !originalRequested, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let skip = formats.count >= maxFormattingBacklog || !formatterReady
        if skip && style != .original { fallback = true }
        formats.append(.init(text: text, skip: skip, sampleEnd: max(processedSamples, accepting ? 0 : samples.count)))
        launchFormatter()
    }
    private func launchFormatter() {
        guard !originalRequested, formatTask == nil, !formats.isEmpty else { return }
        let token = generation, formatterToken = formatterGeneration
        formatTask = Task { await self.drainFormatter(token: token, formatterToken: formatterToken) }
    }
    private func drainFormatter(token: UUID, formatterToken: UUID) async {
        do {
            while token == generation, formatterToken == formatterGeneration, !originalRequested, !formats.isEmpty {
                try ensure(token)
                let job = formats.removeFirst()
                var text = job.text
                var formatted = style != .original && !job.skip
                var continuation: FormattingWindow.Window?
                if style != .original && !job.skip {
                    do {
                        if rendered.count == formattingCache.count,
                           let previous = formattingCache.last, rendered.last == previous.value.output {
                            continuation = FormattingWindow.continuation(previous: previous.value, next: job.text)
                        }
                        let input = continuation?.input ?? job.text
                        let context = continuation.map { rendered.dropLast().joined(separator: " ") + " " + $0.prefixOutput }
                            ?? rendered.joined(separator: " ")
                        text = try await formatter.format(input, style: style, context: LocalFormatter.lastTwoSentences(context), vocabulary: dictionary.topVocabulary(in: input))
                        // The larger window is still the same ordered words. A
                        // failed readback must leave the previous section intact.
                        text = try LocalFormatter.validate(text, original: input, vocabulary: dictionary.topVocabulary(in: input))
                        if let window = continuation, let previous = formattingCache.last {
                            let combinedInput = previous.value.input + " " + job.text
                            _ = try LocalFormatter.validate(ParagraphLayout.joinSections([window.prefixOutput, text]), original: combinedInput, vocabulary: dictionary.topVocabulary(in: combinedInput))
                        }
                    }
                    catch is CancellationError { throw CancellationError() }
                    catch { try ensure(token); fallback = true; text = job.text; formatted = false; continuation = nil }
                }
                try ensure(token)
                guard formatterToken == formatterGeneration, !originalRequested else { throw CancellationError() }
                if let window = continuation, let previous = formattingCache.popLast() {
                    rendered.removeLast()
                    if !window.prefixInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        rendered.append(window.prefixOutput)
                        formattingCache.append(.init(value: .init(input: window.prefixInput, output: window.prefixOutput, formatted: true), sampleEnd: previous.sampleEnd))
                    }
                }
                rendered.append(text)
                formattingCache.append(.init(value: .init(input: continuation?.input ?? job.text, output: text, formatted: formatted), sampleEnd: job.sampleEnd))
            }
        } catch { if token == generation && formatterToken == formatterGeneration { failure = error } }
        if token == generation && formatterToken == formatterGeneration { formatTask = nil }
    }
}
