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
                SearchFieldDisplayView(size: size, isVertical: isVertical, model: model)
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

            if let url = searchURL(for: query, widgetId: widgetId) {
                openURL(url)
            }

            model.clearPendingSubmission()
        }
        .onHover { isHovering in
            self.isHovering = isHovering
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

    private var dim: CGFloat { min(size.width, size.height) }
    private var usesVerticalText: Bool { isVertical && model.isExtended }

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

            TextWithCursor(
                text: model.isErasing ? model.displayText : model.text,
                showCursor: model.isActive && !model.isErasing
            )
            .frame(maxWidth: (model.isActive || model.isErasing) ? .infinity : nil, alignment: .leading)
        }
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

            VerticalTextWithCursor(
                text: model.isErasing ? model.displayText : model.text,
                showCursor: model.isActive && !model.isErasing
            )
        }
        .frame(maxHeight: .infinity)
    }
}
