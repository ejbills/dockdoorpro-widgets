import SwiftUI

struct DockInstrumentSurface: ViewModifier {
    let size: CGSize
    let accent: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(size.width, size.height) * 0.26, style: .continuous)
        let base = scheme == .dark ? Color.black : Color.white
        content
            .frame(width: max(1, size.width - 4), height: max(1, size.height - 4))
            .background {
                shape.fill(base.opacity(reduceTransparency ? 1 : 0.64))
                shape.fill(LinearGradient(colors: [accent.opacity(0.42), accent.opacity(0.12), .clear],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                shape.strokeBorder(LinearGradient(colors: [accent.opacity(0.85), .primary.opacity(0.10), accent.opacity(0.35)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .clipShape(shape)
    }
}
