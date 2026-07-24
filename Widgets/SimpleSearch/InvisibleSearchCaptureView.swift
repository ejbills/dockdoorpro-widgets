import SwiftUI

struct InvisibleSearchCaptureView: View {
    let model: SimpleSearchModel
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $query)
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit(submit)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .background {
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        .onChange(of: query) { _, newQuery in
            model.updateQuery(newQuery)
        }
        .onAppear {
            model.activate()
        }
        .task {
            await focusField()
        }
        .onDisappear {
            // Pendant le scroll, l'hôte démonte/remonte brièvement cette capture
            // alors que le pointeur est toujours sur le widget : ne pas reset dans
            // ce cas (sinon isActive tombe et le chip disparaît en plein scroll).
            // La sortie réelle est gérée par la fermeture auto de la vue inline.
            if !model.isErasing && !model.isHovering {
                model.reset()
            }
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
        let effectiveQuery = model.scrolledPrefix != nil && !query.isEmpty
            ? "\(model.scrolledPrefix!) \(query)"
            : query
        model.recordLastUsedEngine(model.scrolledPrefix)
        if let url = searchURL(for: effectiveQuery, widgetId: "simple-search", skipShortcuts: model.prefixJustRemoved) {
            openURL(url)
        }

        let visibleText = model.displayText
        query = ""
        model.updateQuery("")

        model.startErasing(visibleText: visibleText) {
            model.reset()
            dismiss()
        }
    }

    private func cancel() {
        query = ""
        model.reset()
        dismiss()
    }
}
