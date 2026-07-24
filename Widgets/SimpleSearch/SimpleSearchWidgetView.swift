import DockDoorWidgetSDK
import SwiftUI

struct SimpleSearchWidgetView: View {
    let size: CGSize
    let isVertical: Bool
    let widgetId: String
    let model: SimpleSearchModel

    @Environment(\.openURL) private var openURL
    @State private var hoverExitTask: Task<Void, Never>?
    @State private var isHovering = false

    private var dim: CGFloat { min(size.width, size.height) }

    var body: some View {
        ZStack {
            Color.white.opacity(0.001)
                .contentShape(.rect)

            if model.isExtended || model.isActive {
                SearchFieldDisplayView(size: size, isVertical: isVertical, model: model, widgetId: widgetId)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .leading)))
            } else {
                SearchIconView(dim: dim)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: model.isActive)
        .onAppear {
            model.configure(size: size, isVertical: isVertical)
        }
        .onChange(of: size) { _, newSize in
            model.configure(size: newSize, isVertical: isVertical)
        }
        .onChange(of: isVertical) { _, newValue in
            model.configure(size: size, isVertical: newValue)
        }
        .onChange(of: model.pendingSubmission) { _, query in
            guard let query else { return }

            if let url = searchURL(for: query, widgetId: widgetId, skipShortcuts: model.prefixJustRemoved) {
                openURL(url)
            }

            model.clearPendingSubmission()
        }
        .onHover { isHovering in
            self.isHovering = isHovering
            model.isHovering = isHovering
            hoverExitTask?.cancel()

            guard !isHovering else { return }

            hoverExitTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))

                let activeFor = model.activatedAt.map { Date.now.timeIntervalSince($0) } ?? 0
                if !self.isHovering && activeFor > 0.6 && model.isActive && !model.isErasing {
                    model.reset()
                }
            }
        }
        .onDisappear {
            hoverExitTask?.cancel()
            model.reset()
        }
    }
}

private struct SearchIconView: View {
    let dim: CGFloat

    var body: some View {
        Image(systemName: "magnifyingglass")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: dim * 0.38, height: dim * 0.38)
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct SearchFieldDisplayView: View {
    let size: CGSize
    let isVertical: Bool
    let model: SimpleSearchModel
    let widgetId: String

    private var dim: CGFloat { min(size.width, size.height) }
    private var usesVerticalText: Bool { isVertical && model.isExtended }

    private var activeChip: (prefix: String, isStatic: Bool)? {
        guard model.isActive, !model.isErasing, !model.prefixJustRemoved else { return nil }
        guard model.scrolledPrefix == nil else { return nil }
        guard shortcutsEnabled(widgetId: widgetId) else { return nil }
        guard let spaceIdx = model.text.firstIndex(of: " ") else { return nil }
        let prefix = String(model.text[..<spaceIdx]).lowercased()
        guard !prefix.isEmpty, !prefix.contains(" "),
              let template = resolvedShortcuts(widgetId: widgetId)[prefix] else { return nil }
        let isStatic = !template.contains("[Input]") && !template.contains("%s") && !template.contains("{searchTerms}")
        return (prefix, isStatic)
    }

    @ScaledMetric(relativeTo: .body) private var dotLineHeight: CGFloat = 22

    private var textAfterChip: String {
        guard activeChip != nil,
              let spaceIdx = model.text.firstIndex(of: " ") else { return model.text }
        return String(model.text[model.text.index(after: spaceIdx)...])
    }

    var body: some View {
        Group {
            if usesVerticalText {
                verticalLayout
            } else {
                horizontalLayout
            }
        }
        .padding(.horizontal, usesVerticalText ? 4 : 8)
        .padding(.vertical, usesVerticalText ? 6 : 0)
        .animation(.easeOut(duration: 0.15), value: model.isActive)
        .animation(.easeOut(duration: 0.15), value: model.isErasing)
    }

    private var horizontalLayout: some View {
        HStack(spacing: 5) {
            if !model.isActive && !model.isErasing {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            if let chip = activeChip {
                let chipText = model.isErasing ? model.displayText : textAfterChip
                let chipColor = engineColor(for: chip.prefix, widgetId: widgetId, isStatic: chip.isStatic)
                if chipText.isEmpty {
                    Text(engineDisplayName(for: chip.prefix, widgetId: widgetId))
                        .font(.system(.footnote, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(chipColor, in: RoundedRectangle(cornerRadius: 6))
                        .fixedSize()
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity),
                            removal: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity)
                        ))
                } else {
                    Circle()
                        .fill(chipColor)
                        .frame(width: 6, height: 6)
                        .frame(height: dotLineHeight)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity),
                            removal: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity)
                        ))
                }
                TextWithCursor(
                    text: chipText,
                    showCursor: model.isActive && !model.isErasing,
                    scrolling: !chipText.isEmpty,
                    cursorColor: chipColor
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let sp = model.scrolledPrefix, model.isActive, !model.isErasing {
                let queryText = model.text
                let spColor = engineColor(for: sp, widgetId: widgetId)
                if queryText.isEmpty {
                    Text(engineDisplayName(for: sp, widgetId: widgetId))
                        .font(.system(.footnote, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(spColor, in: RoundedRectangle(cornerRadius: 6))
                        .fixedSize()
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(spColor)
                        .frame(width: 6, height: 6)
                        .frame(height: dotLineHeight)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity),
                            removal: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity)
                        ))
                }
                TextWithCursor(
                    text: queryText,
                    showCursor: true,
                    scrolling: !queryText.isEmpty,
                    isTriple: model.slotSpan == .triple,
                    cursorColor: spColor,
                    suggestion: model.clipboardSuggestion
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextWithCursor(
                    text: model.isErasing ? model.displayText : textAfterChip,
                    showCursor: model.isActive && !model.isErasing,
                    isTriple: model.slotSpan == .triple,
                    suggestion: model.clipboardSuggestion
                )
                .frame(minWidth: 10, maxWidth: (model.isActive || model.isErasing) ? .infinity : nil, alignment: .leading)
                .clipped()
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: textAfterChip.isEmpty)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.prefixJustRemoved)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.scrolledPrefix)
    }

    private var verticalLayout: some View {
        VStack(spacing: 4) {
            if !model.isActive && !model.isErasing {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            if let chip = activeChip {
                let chipColor = engineColor(for: chip.prefix, widgetId: widgetId, isStatic: chip.isStatic)
                HStack(spacing: 4) {
                    Text(engineDisplayName(for: chip.prefix, widgetId: widgetId))
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(chipColor, in: RoundedRectangle(cornerRadius: 4))
                        .transition(.scale.combined(with: .opacity))
                    TextWithCursor(
                        text: textAfterChip,
                        showCursor: model.isActive && !model.isErasing,
                        cursorColor: chipColor
                    )
                }
            } else {
                VerticalTextWithCursor(
                    text: model.isErasing ? model.displayText : model.text,
                    showCursor: model.isActive && !model.isErasing
                )
            }
        }
        .frame(maxHeight: .infinity)
    }
}

