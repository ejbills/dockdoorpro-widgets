import SwiftUI

struct TextWithCursor: View {
    let text: String
    let showCursor: Bool

    @State private var cursorOn = true
    @ScaledMetric(relativeTo: .body) private var textLineHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var cursorWidth: CGFloat = 1.5
    @ScaledMetric(relativeTo: .body) private var cursorHeight: CGFloat = 16

    var body: some View {
        HStack(spacing: 0) {
            if showCursor && text.isEmpty {
                cursor
            }

            if !text.isEmpty {
                HStack(spacing: 0) {
                    Text(text)
                        .font(.body.weight(.regular))
                        .fontDesign(.rounded)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    if showCursor {
                        cursor
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: textLineHeight)
            } else if !showCursor {
                Text("Type")
                    .font(.body.weight(.regular))
                    .fontDesign(.rounded)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var cursor: some View {
        Rectangle()
            .fill(.primary)
            .frame(width: cursorWidth, height: cursorHeight)
            .opacity(cursorOn ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    cursorOn.toggle()
                }
            }
    }
}
