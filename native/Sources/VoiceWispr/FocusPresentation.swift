import AppKit
import SwiftUI

/// Pointer selection and keyboard focus are different visual states.
final class FocusPresentation: ObservableObject {
    static let shared = FocusPresentation()
    @Published private(set) var keyboardNavigation = false
    private var monitor: Any?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if event.type != .keyDown { self?.keyboardNavigation = false }
            else if [48, 123, 124, 125, 126].contains(event.keyCode) { self?.keyboardNavigation = true }
            return event
        }
    }
}

struct PointerAwareFocus: ViewModifier {
    @ObservedObject private var presentation = FocusPresentation.shared
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused).focusEffectDisabled()
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(focused && presentation.keyboardNavigation ? Color(nsColor: .keyboardFocusIndicatorColor) : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func pointerAwareFocus() -> some View { modifier(PointerAwareFocus()) }
}
