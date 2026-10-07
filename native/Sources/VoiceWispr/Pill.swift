import SwiftUI
import AppKit
import VoiceWisprCore

private func p(_ key: String, _ args: String... ) -> String { L10n.format(key, arguments: args) }

enum PillState: String { case ready, recording, processing, success, error, paused, loading, needsSetup, conflict }

/// SwiftUI's plain button can demand activation inside a non-key NSPanel.
/// The actual hit view must accept the first click, not only its hosting parent.
private final class PillMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}

private struct PillButton: NSViewRepresentable {
    let symbol: String
    let label: String
    var pointSize: CGFloat = 11
    let action: () -> Void
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func performClick(_ sender: NSButton) { action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = PillMouseButton()
        button.setButtonType(.momentaryChange)
        button.isBordered = false; button.title = ""; button.imagePosition = .imageOnly
        button.focusRingType = .none
        button.target = context.coordinator; button.action = #selector(Coordinator.performClick(_:))
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium))
        button.contentTintColor = NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1)
        button.toolTip = label; button.setAccessibilityLabel(label)
    }
}

struct PillView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if showsControls {
                activeContent
            } else {
                Color.clear.frame(width: 68, height: 40).accessibilityHidden(true)
            }
        }
    }
    private var showsControls: Bool {
        if model.state == .recording || model.state == .processing || model.state == .success || model.state == .error { return true }
        #if DEBUG
        // The public insertion diagnostic needs a button after its recovery
        // timer expires. Production keeps its idle pill hidden as requested.
        return model.isUIPreview && CommandLine.arguments.contains("--test-delivery")
        #else
        return false
        #endif
    }
    private var activeContent: some View {
        HStack(spacing: 6) {
            if model.state == .recording {
                if model.lipSession {
                    Image(systemName: "camera.fill").frame(width: 40, height: 20)
                        .accessibilityLabel(p("pill.lipRecording", model.durationLabel))
                } else {
                HStack(spacing: 2) {
                    ForEach(0..<9, id: \.self) { i in
                        Capsule().fill(Color(red: 0.91, green: 0.94, blue: 0.93))
                            .frame(width: 2, height: barHeight(i))
                    }
                }.frame(width: 40, height: 20)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(p("pill.recording", model.durationLabel))
                }
                PillButton(symbol: "stop.fill", label: p("pill.stop"), pointSize: 9) { model.stop() }.frame(width: 22, height: 24)
                PillButton(symbol: "xmark", label: p("pill.discard"), pointSize: 10) { model.cancel() }.frame(width: 22, height: 24)
            } else if model.state == .processing {
                ProgressView().controlSize(.mini).tint(.white).frame(width: 20)
                    .accessibilityLabel(L10n.diagnostic(model.status))
                PillButton(symbol: "text.alignleft", label: p("pill.useOriginal")) { model.useOriginal() }.frame(width: 22, height: 24)
                PillButton(symbol: "xmark", label: p("pill.cancelProcessing"), pointSize: 10) { model.cancel() }.frame(width: 22, height: 24)
            } else {
                PillButton(symbol: icon, label: model.pillActionLabel) { model.openFromPill() }
                    .frame(width: 52, height: 24)
            }
        }
        .foregroundStyle(Color(red: 0.93, green: 0.94, blue: 0.95))
        .buttonStyle(.plain)
        .frame(width: model.state == .recording ? 118 : model.state == .processing ? 96 : 52,
               height: model.state == .recording || model.state == .processing ? 28 : 24)
        .background(Color(red: 0.105, green: 0.115, blue: 0.13), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .help(recordingWarning ? model.status : model.pillActionLabel)
        .padding(8)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.095), value: model.spectrumLevels)
    }
    private func barHeight(_ index: Int) -> CGFloat {
        return CGFloat(4.0 + 16.0 * Double(model.spectrumLevels[index]))
    }
    private var recordingWarning: Bool { model.state == .recording && (model.elapsed >= 1140 || model.recordingDelayed) }
    private var icon: String { if recordingWarning { return "exclamationmark.triangle.fill" }; switch model.state { case .success: return "checkmark"; case .error, .conflict: return "exclamationmark.circle"; case .needsSetup: return "gearshape"; case .loading: return "hourglass"; case .paused: return "mic.slash"; default: return "mic.fill" } }
}

final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PillHostingView: NSHostingView<PillView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override var isOpaque: Bool { false }
}

@MainActor final class PillWindow {
    let panel: PillPanel
    init(model: AppModel) {
        panel = PillPanel(contentRect: NSRect(x: 0, y: 0, width: 144, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.title = "AInauten Voice Pill"
        panel.becomesKeyOnlyIfNeeded = true; panel.worksWhenModal = true
        panel.ignoresMouseEvents = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = PillHostingView(rootView: PillView(model: model))
        position()
    }
    func setVisible(_ visible: Bool) {
        guard panel.isVisible != visible else { return }
        if visible { position(); panel.orderFrontRegardless() }
        else { panel.orderOut(nil) }
    }
    func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let bounds = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: bounds.midX - panel.frame.width / 2, y: bounds.minY + 14))
    }
}

final class RecoveryPanel: NSPanel {
    override var canBecomeMain: Bool { false }
    override var canBecomeKey: Bool { true }
}

struct RecoveryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var interfaceLanguage = InterfaceLanguageStore.shared
    private var selectedResult: DictationResult? { model.recoveryResult }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                if model.recoveryFailureTitle != nil {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 24, height: 26)
                        .accessibilityHidden(true)
                } else {
                Button {
                    if let id = selectedResult?.id, let index = model.results.firstIndex(where: { $0.id == id }) { model.copyResult(at: index) }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 15)).frame(width: 24, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(selectedResult == nil)
                .accessibilityLabel(L10n.text("recovery.copyAX"))
                .help(model.recoveryHasCopy ? L10n.text("recovery.copiedHelp") : L10n.text("recovery.copyAX"))
                .keyboardShortcut("c", modifiers: .command).pointerAwareFocus()
                }
                Text(model.recoveryTitle).font(.system(size: 13, weight: .semibold))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .help(model.recoveryDetails).accessibilityHint(model.recoveryDetails)
                Spacer(minLength: 4)
                if model.recoveryFailureTitle == nil && !model.recoveryTransient && model.results.count > 1 {
                    Menu {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                            Button(L10n.text("recovery.result", String(index + 1))) { model.showRecovery(activate: false, resultID: result.id) }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 13)).frame(width: 26, height: 26)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .accessibilityLabel(L10n.text("recovery.recent")).help(L10n.text("recovery.recentHelp"))
                }
                if model.recoveryCanUndo {
                    Button { model.undoRecoveryCopy() } label: {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 13)).frame(width: 26, height: 26).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.text("recovery.undoAX"))
                        .help(L10n.text("recovery.undoHelp"))
                        .keyboardShortcut("z", modifiers: .command).pointerAwareFocus()
                }
                FeedbackCloseButton(remaining: model.recoveryCountdownRemaining, paused: model.recoveryCountdownPaused) { model.closeRecovery() }
            }
            if model.recoveryFailureTitle != nil {
                ScrollView {
                    Text(model.recoveryReason).font(.system(size: 12)).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: model.recoveryTextHeight)
            } else if let result = selectedResult {
                ScrollView {
                    Text(result.text).font(.system(size: 13)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                }
                .frame(height: model.recoveryTextHeight)
            }
        }.padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .onHover { model.hoverRecovery($0) }
            .onExitCommand { model.closeRecovery() }
    }
}

private struct FeedbackCloseButton: View {
    let remaining: TimeInterval
    let paused: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var seconds: Int { max(0, Int(ceil(remaining))) }
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1.5)
                Circle().trim(from: 0, to: min(1, max(0, remaining / 5)))
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion || paused ? nil : .linear(duration: 0.1), value: remaining)
                if hovered { Image(systemName: "xmark").font(.system(size: 9, weight: .medium)) }
                else if seconds > 0 { Text("\(seconds)").font(.system(size: 12, weight: .medium)).monospacedDigit() }
            }.frame(width: 20, height: 20).frame(width: 26, height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.secondary)
            .onHover { hovered = $0 }
            .accessibilityLabel(L10n.text("recovery.closeAX"))
            .accessibilityValue(paused ? L10n.text("recovery.timerPaused") : L10n.plural("recovery.secondsAX", count: seconds))
            .help(paused ? L10n.text("recovery.closePausedHelp") : L10n.plural("recovery.secondsHelp", count: seconds))
            .keyboardShortcut("w", modifiers: .command).pointerAwareFocus()
    }
}
