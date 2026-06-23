import DockDoorWidgetSDK
import SwiftUI

struct ToggleDoNotDisturbView: View {
    let size: CGSize
    let isVertical: Bool

    private var dim: CGFloat { min(size.width, size.height) }

    private var isExtended: Bool {
        isVertical
            ? size.height > size.width * 1.5
            : size.width > size.height * 1.5
    }

    private var iconSize: CGFloat {
        dim * WidgetMetrics.sfSymbolScale * (isExtended ? 1.4 : 1.05)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: dim * 0.20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.80),
                            Color.black.opacity(0.36),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: dim * 0.20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )

            Image(systemName: "moon.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 1)
        }
        .compositingGroup()
    }
}
