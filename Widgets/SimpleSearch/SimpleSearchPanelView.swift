import SwiftUI
import AppKit

struct SimpleSearchPanelView: View {
    let widgetId: String
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var isSubmitting = false
    @State private var isHoveringClear = false
    @State private var isHoveringSearch = false
    @FocusState private var isFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Search or URL", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(.white)
                .onSubmit(submit)
                .focused($isFocused)
                .frame(maxWidth: .infinity)
                .frame(height: 26)

            if !query.isEmpty && !isSubmitting {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    query = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(isHoveringClear ? Color.white : Color.white.opacity(0.4))
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .onHover { isHoveringClear = $0 }
                .animation(.easeOut(duration: 0.15), value: isHoveringClear)
            }

            Button("Search", systemImage: isSubmitting ? "magnifyingglass.circle.fill" : "magnifyingglass.circle", action: submit)
                .labelStyle(.iconOnly)
                .foregroundStyle(
                    trimmedQuery.isEmpty
                        ? Color.white.opacity(0.3)
                        : isHoveringSearch ? Color.white : Color.white.opacity(0.6)
                )
                .scaleEffect(isSubmitting ? 1.3 : 1.0)
                .rotationEffect(.degrees(isSubmitting ? 360 : 0))
                .animation(.spring(response: 0.20, dampingFraction: 0.6), value: isSubmitting)
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .disabled(trimmedQuery.isEmpty)
                .onHover { isHoveringSearch = $0 }
                .animation(.easeOut(duration: 0.15), value: isHoveringSearch)
        }
        .background {
            Button("Cancel", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 320)
        .animation(.easeOut(duration: 0.15), value: isSubmitting)
        .task {
            await focusField()
        }
    }

    private func focusField() async {
        for delay in [0, 50, 150, 300] {
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(delay))
            }

            isFocused = false
            await Task.yield()
            isFocused = true
        }
    }

    private func submit() {
        guard !trimmedQuery.isEmpty else { return }

        withAnimation {
            isSubmitting = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if let url = searchURL(for: query, widgetId: widgetId) {
                openURL(url)
            }
            query = ""
            isSubmitting = false
            dismiss()
        }
    }
}
