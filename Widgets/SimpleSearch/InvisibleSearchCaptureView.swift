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
            if !model.isErasing {
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
        if let url = searchURL(for: query, widgetId: "simple-search") {
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
