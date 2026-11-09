import AppKit
import Foundation

/// A read signal controls retention, never destination identity or delivery success.
final class ClipboardConsumption: NSObject, NSPasteboardItemDataProvider {
    static let maximumHold = 5
    private let text: String
    @MainActor private(set) var lastReadAt: TimeInterval?

    init(text: String) { self.text = text }

    @MainActor func recordRead(at time: TimeInterval) {
        lastReadAt = max(lastReadAt ?? time, time)
    }

    @MainActor func restoreAt(submittedAt: TimeInterval) -> TimeInterval {
        guard let lastReadAt else { return submittedAt + Double(Self.maximumHold) }
        return min(submittedAt + Double(Self.maximumHold), max(submittedAt + 1, lastReadAt + 0.5))
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .string else { return }
        item.setString(text, forType: type)
        let readAt = ProcessInfo.processInfo.systemUptime
        if Thread.isMainThread {
            MainActor.assumeIsolated { recordRead(at: readAt) }
        } else {
            DispatchQueue.main.async { self.recordRead(at: readAt) }
        }
    }
}
