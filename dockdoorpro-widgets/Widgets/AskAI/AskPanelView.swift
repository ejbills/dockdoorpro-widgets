import SwiftUI

/// The panel the host shows on hover-activate, long-press or right-click:
/// the streamed answer on top, with a growing text field and send button
/// anchored at the bottom.
struct AskPanelView: View {
    let model: AskModel
    let dismiss: () -> Void

    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .title3) private var fieldHeight: CGFloat = 26

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 10) {
            // Response area — sits above the input and grows as the answer streams.
            if model.phase != .idle {
                answerSection
            }

            if let message = model.availabilityMessage() {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Input row — stays anchored at the bottom of the panel. The field
            // grows vertically (up to a few lines) so the whole prompt is visible.
            HStack(alignment: .bottom, spacing: 8) {
                Image(systemName: "siri.gen2")
                    .font(.title3)
                    .foregroundStyle(AskBrand.iconGradient)
                    .accessibilityHidden(true)

                TextField("Ask anything…", text: $model.question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .onSubmit(model.send)
                    .onChange(of: model.question) { _, newValue in
                        // Warm the on-device model on the user's first keystroke
                        // rather than on panel open, so idle panels never load a
                        // model they may not use while still cutting the
                        // first-answer startup cost once they start typing.
                        if !newValue.isEmpty {
                            model.prewarm()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: model.send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(sendEnabled ? Color.accentColor : Color.secondary.opacity(0.35))
                    .disabled(!sendEnabled)
                    .accessibilityLabel("Send")
                }
            }
            .frame(minHeight: fieldHeight)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 340, alignment: .leading)
        .background {
            Button("Cancel", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onAppear {
            // Don't pull the on-device model into memory until the user
            // actually starts a question — the first real generation still
            // pays the same startup cost, but idle panels no longer warm
            // a model most users never use.
            focusField()
        }
        .onChange(of: model.isBusy) { _, busy in
            // Re-grab key focus after a generation finishes so a follow-up
            // question can be typed right away (e.g. after the user clicked
            // elsewhere while waiting).
            if !busy {
                focusField()
            }
        }
    }

    // MARK: - Answer

    private var answerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.lastQuestion.isEmpty {
                Text(model.lastQuestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                Text(answerBody)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)

            HStack(spacing: 8) {
                statusLine
                Spacer(minLength: 0)
                Button(action: model.clear) {
                    Image(systemName: "arrow.counterclockwise.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear conversation")
                .help("Clear conversation")
            }
        }
    }

    private var answerBody: String {
        if model.answer.isEmpty {
            return model.phase == .thinking ? "…" : ""
        }
        return model.answer
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model.phase {
        case .thinking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Thinking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .streaming:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Writing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .idle, .done:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var sendEnabled: Bool {
        !model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isBusy
            && model.availabilityMessage() == nil
    }

    /// Mirrors SimpleSearch's proven panel autofocus: make the host panel key
    /// first (a `@FocusState` toggle alone never takes in a non-key panel),
    /// force the field focus through a few retries while the panel settles,
    /// then install the system caret with a replayed click.
    private func focusField() {
        Task { @MainActor in
            var keyedPanels: [NSWindow] = []
            for delay in [0, 50, 150, 300] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                keyedPanels = NSApp.windows
                    .filter { $0 is NSPanel && $0.isVisible }
                keyedPanels.forEach { $0.makeKey() }
                isFocused = false
                await Task.yield()
                isFocused = true
            }

            try? await Task.sleep(for: .milliseconds(50))
            Self.clickToShowCursor(onlyIn: keyedPanels)
        }
    }

    // AppKit only installs the caret after a real click in the field editor,
    // so replay one through the event queue (postEvent, never sendEvent —
    // sendEvent blocks the panel's mouse-tracking loop).
    private static func clickToShowCursor(onlyIn panels: [NSWindow]) {
        // Re-verify synchronously that key focus is still on a panel this
        // widget focused: if the user clicked elsewhere during the sleep, the
        // fabricated click must not land in an unrelated window.
        guard let window = NSApp.keyWindow,
              panels.contains(where: { $0 === window }),
              let editor = window.firstResponder as? NSTextView else { return }
        guard editor.string.isEmpty else { return }

        let rect = editor.convert(editor.bounds, to: nil)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        let now = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: now, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: now + 0.001, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
        else { return }
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
    }
}
