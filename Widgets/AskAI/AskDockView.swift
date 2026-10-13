import DockDoorWidgetSDK
import SwiftUI

struct AskDockView: View {
    let model: AskModel
    let size: CGSize
    let isVertical: Bool

    private var dim: CGFloat { min(size.width, size.height) }

    private var span: WidgetSlotSpan {
        WidgetSlotSpan.detect(size: size, isVertical: isVertical)
    }

    var body: some View {
        Group {
            switch span {
            case .compact:
                compactLayout
            case .extended, .triple:
                // Triple slots aren't opted into, but if one ever arrives the
                // extended layout just stretches into it.
                if isVertical {
                    verticalLayout
                } else {
                    horizontalLayout
                }
            }
        }
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        askIcon(size: dim * WidgetMetrics.sfSymbolScale)
            .opacity(dimmed ? 0.45 : 1)
            // The glyph is decorative (hidden inside `askIcon`), so expose one
            // labelled element for VoiceOver instead of a hidden child.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ask Apple Intelligence")
    }

    private var horizontalLayout: some View {
        HStack(spacing: max(dim * WidgetMetrics.spacingScale, 3)) {
            askIcon(size: dim * 0.4)

            VStack(alignment: .leading, spacing: 1) {
                Text("Ask")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                questionLine
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !model.answer.isEmpty {
                    Text(model.answer)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 0)

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, max(dim * 0.1, 3))
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(dimmed ? 0.45 : 1)
    }

    private var verticalLayout: some View {
        VStack(spacing: max(dim * WidgetMetrics.spacingScale, 2)) {
            askIcon(size: dim * 0.4)
            Text("Ask")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            questionLine
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
            if !model.answer.isEmpty {
                Text(model.answer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, max(dim * 0.08, 3))
        .frame(maxHeight: .infinity)
        .opacity(dimmed ? 0.45 : 1)
    }

    // MARK: - Pieces

    private func askIcon(size: CGFloat) -> some View {
        Group {
            if model.justCopied {
                // Tap copied the answer — flash a confirmation.
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "siri.gen2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(AskBrand.iconGradient)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var questionLine: some View {
        if !model.question.isEmpty {
            Text(model.question)
                .foregroundStyle(.primary)
        } else if !model.lastQuestion.isEmpty {
            Text(model.lastQuestion)
                .foregroundStyle(.primary)
        } else {
            Text("Ask anything…")
                .foregroundStyle(.tertiary)
        }
    }

    private var dimmed: Bool {
        model.availabilityMessage() != nil
    }
}
