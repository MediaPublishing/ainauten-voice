import Foundation

/// A held follow-up dictation is expected, not a paste timeout. The ordinary
/// modifier-release deadline starts only after recording stops. No text or
/// clipboard data is retained here; delivery revalidates its target afterwards.
public struct DictationDeliveryReadiness: Sendable {
    public enum Decision: Equatable, Sendable { case wait, ready, timedOut }
    private let modifierTimeout: TimeInterval
    private var waitingSince: TimeInterval?
    public init(modifierTimeout: TimeInterval = 1.5) {
        precondition(modifierTimeout > 0)
        self.modifierTimeout = modifierTimeout
    }
    public mutating func update(recording: Bool, modifiersHeld: Bool, now: TimeInterval) -> Decision {
        if recording { waitingSince = nil; return .wait }
        guard modifiersHeld else { waitingSince = nil; return .ready }
        if waitingSince == nil { waitingSince = now }
        return now - (waitingSince ?? now) >= modifierTimeout ? .timedOut : .wait
    }
}

/// Main-actor owners reserve the worst-case PCM working set before starting a
/// microphone. Pending audio stays in RAM; only one job may process at a time.
public struct DictationQueue: Sendable {
    public enum Phase: Equatable, Sendable { case capturing, pending, processing }
    public struct Entry: Equatable, Sendable {
        public let id: UUID
        public let sequence: UInt64
        public var phase: Phase
    }
    public static let captureReservationBytes = AudioCaptureBuffer.maximumSamples * MemoryLayout<Float>.stride * 3 + 1_048_576
    public let maximumBytes: Int
    public let reservationBytes: Int
    public private(set) var entries: [Entry] = []
    public private(set) var overlaps = false
    public private(set) var automaticDeliverySuppressed = false
    private var sequence: UInt64 = 0
    public init(maximumBytes: Int = 768 * 1_048_576, reservationBytes: Int = Self.captureReservationBytes) {
        precondition(maximumBytes > 0 && reservationBytes > 0)
        self.maximumBytes = maximumBytes; self.reservationBytes = reservationBytes
    }
    public var reservedBytes: Int { entries.count * reservationBytes }
    public var canCapture: Bool {
        !entries.contains { $0.phase == .capturing } && maximumBytes - reservedBytes >= reservationBytes
    }
    @discardableResult public mutating func reserve(_ id: UUID) -> Bool {
        guard canCapture, !entries.contains(where: { $0.id == id }) else { return false }
        if !entries.isEmpty { overlaps = true }
        sequence &+= 1
        entries.append(.init(id: id, sequence: sequence, phase: .capturing))
        return true
    }
    @discardableResult public mutating func captured(_ id: UUID) -> Bool {
        guard let i = entries.firstIndex(where: { $0.id == id && $0.phase == .capturing }) else { return false }
        entries[i].phase = .pending; return true
    }
    public mutating func beginNext() -> UUID? {
        guard !entries.contains(where: { $0.phase == .processing }), let first = entries.first,
              first.phase == .pending else { return nil }
        entries[0].phase = .processing; return first.id
    }
    public func mayAutomaticallyDeliver(_ id: UUID) -> Bool {
        !automaticDeliverySuppressed && entries.first?.id == id && entries.first?.phase == .processing
    }
    public mutating func suppressAutomaticDelivery() { automaticDeliverySuppressed = true }
    public mutating func finish(_ id: UUID) { entries.removeAll { $0.id == id } }
    public mutating func resetBatchIfIdle() { if entries.isEmpty { overlaps = false; automaticDeliverySuppressed = false } }
    public mutating func cancelAll() { entries.removeAll(); automaticDeliverySuppressed = true }
}
