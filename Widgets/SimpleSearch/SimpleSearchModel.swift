import Observation
import SwiftUI

@Observable
final class SimpleSearchModel {
    var text = ""
    var isActive = false
    var isExtended = false
    var displayText = ""
    var isErasing = false
    var pendingSubmission: String?
    var activatedAt: Date?

    @ObservationIgnored private var eraseTask: Task<Void, Never>?
    @ObservationIgnored private let keyboardCapture = SimpleSearchKeyboardCapture()

    func configure(size: CGSize, isVertical: Bool) {
        isExtended = SimpleSearchLayout.isExtended(size: size, isVertical: isVertical)
    }

    func activate() {
        eraseTask?.cancel()
        isErasing = false
        isActive = true
        text = ""
        displayText = ""
        activatedAt = .now
        keyboardCapture.start(
            initialText: "",
            onChange: { [weak self] query in
                self?.updateQuery(query)
            },
            onSubmit: { [weak self] in
                self?.submit()
            },
            onCancel: { [weak self] in
                self?.reset()
            }
        )
    }

    func updateQuery(_ query: String) {
        text = query
        displayText = query
    }

    func reset() {
        eraseTask?.cancel()
        keyboardCapture.stop()
        isActive = false
        isErasing = false
        text = ""
        displayText = ""
        activatedAt = nil
    }

    func clearPendingSubmission() {
        pendingSubmission = nil
    }

    func startErasing(visibleText: String, completion: @escaping () -> Void) {
        eraseTask?.cancel()

        guard !visibleText.isEmpty else {
            completion()
            return
        }

        isErasing = true
        displayText = visibleText
        let characters = Array(visibleText)

        eraseTask = Task { @MainActor in
            for index in stride(from: characters.count - 1, through: 0, by: -1) {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(5))
                guard !Task.isCancelled else { return }
                displayText = String(characters.prefix(index))
            }

            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }

            isErasing = false
            completion()
        }
    }

    func submit() {
        let submittedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedText.isEmpty else { return }

        pendingSubmission = submittedText
        text = ""
        displayText = ""
        keyboardCapture.stop()

        startErasing(visibleText: submittedText) {
            self.reset()
        }
    }
}
