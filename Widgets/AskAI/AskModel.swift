import AppKit
import Foundation
import FoundationModels
import Observation

/// Shared state for the dock slot and the hover panel.
///
/// Every Foundation Models call sits behind `#available(macOS 26.0, *)`.
/// The framework is weak-linked when the bundle is built with a 14.0 deployment
/// target, so the widget still loads on older systems and just reports why it
/// can't answer there.
@MainActor
@Observable
final class AskModel {
    enum Phase: Equatable {
        case idle
        case thinking
        case streaming
        case done
        case failed(String)
    }

    /// The model source for answering questions. Currently only local.
    enum Source: String {
        case local
    }

    /// Text currently in the field.
    var question = ""
    /// The answer being streamed, or the last finished answer.
    var answer = ""
    /// The question that produced `answer`.
    var lastQuestion = ""
    var phase: Phase = .idle
    /// Briefly true after a tap copies the answer, to flash a checkmark.
    var justCopied = false
    /// The selected model source; persisted per the house rule for runtime
    /// state: `UserDefaults` under `<pluginId>.<key>`.
    var source: Source = .local

    var isBusy: Bool {
        if case .thinking = phase { return true }
        if case .streaming = phase { return true }
        return false
    }

    init() {}

    @ObservationIgnored private var turns: [(question: String, answer: String)] = []
    @ObservationIgnored private var generation: Task<Void, Never>?
    @ObservationIgnored private var copiedResetTask: Task<Void, Never>?
    @ObservationIgnored private var generationToken = 0
    /// True once the user has started typing in the current clear cycle,
    /// so the first keystroke warms the on-device model but typing more
    /// characters or clearing and retyping does not re-warm.
    @ObservationIgnored private var hasStartedTypingFlag = false

    /// Whether the user has already triggered the one-shot first-keystroke
    /// warm in the current clear cycle. Exposed read/write so the panel can
    /// mark the warm as having happened without reaching into a private flag.
    var hasStartedTyping: Bool {
        get { hasStartedTypingFlag }
        set { hasStartedTypingFlag = newValue }
    }

    private static let instructions = """
    You are a quick assistant shown in a small panel in the macOS Dock. \
    Answer the user's question directly and concisely in plain text: \
    a few sentences at most, no markdown, with line breaks only where they help.
    """

    // MARK: - Availability

    /// `nil` when questions can be answered, otherwise a short human-readable reason.
    func availabilityMessage() -> String? {
        switch source {
        case .local:
            if #available(macOS 26.0, *) {
                switch SystemLanguageModel.default.availability {
                case .available:
                    return nil
                case .unavailable(let reason):
                    switch reason {
                    case .appleIntelligenceNotEnabled:
                        return "Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri."
                    case .deviceNotEligible:
                        return "This Mac doesn't support Apple Intelligence."
                    case .modelNotReady:
                        return "The on-device model is still downloading. Try again in a minute."
                    @unknown default:
                        return "Apple's on-device model isn't available right now."
                    }
                }
            }
            return "Requires macOS 26 or later."
        default:
            return ""
        }
    }

    // MARK: - Actions

    func send() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy, availabilityMessage() == nil else { return }

        generationToken &+= 1
        let token = generationToken
        generation?.cancel()

        question = ""
        answer = ""
        lastQuestion = trimmed
        phase = .thinking

        let history = Array(turns.suffix(3))
        generation = Task { @MainActor [weak self] in
            await self?.generate(token: token, question: trimmed, history: history)
        }
    }

    func clear() {
        generationToken &+= 1
        generation?.cancel()
        generation = nil
        question = ""
        answer = ""
        lastQuestion = ""
        phase = .idle
        justCopied = false
        copiedResetTask?.cancel()
        turns.removeAll()
        hasStartedTypingFlag = false
    }


    /// Copies the current answer to the pasteboard (dock tap action).
    func copyAnswerToClipboard() {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        justCopied = true
        copiedResetTask?.cancel()
        copiedResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.justCopied = false
        }
    }


    // MARK: - Generation

    private func generate(
        token: Int,
        question: String,
        history: [(question: String, answer: String)]
    ) async {
        guard token == generationToken, #available(macOS 26.0, *) else { return }

        // Prior turns are folded into the prompt, so follow-up questions keep
        // their context without holding on to a session object.
        var prompt = ""
        for turn in history {
            prompt += "User: \(turn.question)\nAssistant: \(turn.answer)\n"
        }
        prompt += "User: \(question)\nAssistant:"

        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            var isFirstSnapshot = true
            for try await snapshot in session.streamResponse(to: prompt) {
                guard token == generationToken else { return }
                if isFirstSnapshot {
                    isFirstSnapshot = false
                    phase = .streaming
                }
                answer = snapshot.content
            }
            guard token == generationToken else { return }
            phase = .done

            let summary = String(answer.prefix(1_200))
            turns.append((question: question, answer: summary))
            if turns.count > 6 {
                turns.removeFirst(turns.count - 6)
            }
        } catch {
            guard token == generationToken, !Task.isCancelled else { return }
            if let modelError = error as? LanguageModelSession.GenerationError {
                phase = .failed(Self.message(for: modelError))
            } else {
                phase = .failed("Something went wrong — try again.")
            }
        }
    }

    @available(macOS 26.0, *)
    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .rateLimited:
            return "Too many questions right now — wait a moment and try again."
        case .refusal, .guardrailViolation:
            return "The model declined to answer that."
        case .exceededContextWindowSize:
            return "This conversation got too long — press clear to start over."
        case .concurrentRequests:
            return "The model is busy — try again in a moment."
        case .assetsUnavailable:
            return "The on-device model isn't ready yet. If this Mac has never used Apple's models before, agree to the Foundation Models terms in Terminal first: sudo fm license (it applies machine-wide). Otherwise it may just need a minute to download — try again."
        case .unsupportedLanguageOrLocale:
            return "The model doesn't support this language yet."
        case .decodingFailure:
            return "The model returned an unreadable answer — try again."
        case .unsupportedGuide:
            return "Couldn't format the answer — try again."
        @unknown default:
            return "Something went wrong — try again."
        }
    }
}
