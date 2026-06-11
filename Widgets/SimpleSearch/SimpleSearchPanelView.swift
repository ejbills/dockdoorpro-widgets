import SwiftUI

struct SimpleSearchPanelView: View {
    let widgetId: String
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Search...", text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(submit)
            .frame(height: 22)

            if !query.isEmpty && !isSubmitting {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    query = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Button("Search", systemImage: isSubmitting ? "magnifyingglass.circle.fill" : "magnifyingglass", action: submit)
                .labelStyle(.iconOnly)
                .foregroundStyle(trimmedQuery.isEmpty ? .tertiary : .primary)
                .scaleEffect(isSubmitting ? 1.3 : 1.0)
                .rotationEffect(.degrees(isSubmitting ? 360 : 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isSubmitting)
                .buttonStyle(.plain)
                .disabled(trimmedQuery.isEmpty)
        }
        .background {
            Button("Cancel", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .padding(12)
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
            try? await Task.sleep(for: .milliseconds(400))
            if let url = searchURL(for: query, widgetId: widgetId) {
                openURL(url)
            }
            query = ""
            isSubmitting = false
            dismiss()
        }
    }
}
