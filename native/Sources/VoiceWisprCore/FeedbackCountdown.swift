import Foundation

/// Monotonic time keeps feedback expiry independent of wall-clock changes.
public struct FeedbackCountdown: Sendable {
    public let duration: TimeInterval
    public private(set) var isPaused = false
    private var deadline: TimeInterval
    private var pausedRemaining: TimeInterval

    public init(now: TimeInterval, duration: TimeInterval = 5) {
        self.duration = max(0, duration)
        deadline = now + self.duration
        pausedRemaining = self.duration
    }
    public func remaining(at now: TimeInterval) -> TimeInterval {
        isPaused ? pausedRemaining : min(duration, max(0, deadline - now))
    }
    public func expired(at now: TimeInterval) -> Bool { !isPaused && remaining(at: now) == 0 }
    public mutating func setPaused(_ paused: Bool, at now: TimeInterval) {
        guard paused != isPaused else { return }
        if paused {
            pausedRemaining = remaining(at: now)
            guard pausedRemaining > 0 else { return }
        }
        else { deadline = now + pausedRemaining }
        isPaused = paused
    }
}
