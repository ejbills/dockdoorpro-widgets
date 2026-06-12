import SwiftUI

struct VerticalTextWithCursor: View {
    let text: String
    let showCursor: Bool

    @State private var cursorOn = true
    @ScaledMetric(relativeTo: .body) private var characterLineHeight: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var cursorWidth: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var cursorHeight: CGFloat = 1.5

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = max(geometry.size.height, characterLineHeight)
            let maxCharacters = max(1, Int(availableHeight / characterLineHeight))
            let visibleText = String(text.suffix(maxCharacters))

            VStack(spacing: 0) {
                if showCursor && visibleText.isEmpty {
                    cursor
                }

                if !visibleText.isEmpty {
                    ForEach(Array(visibleText.enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .font(.body.weight(.regular))
                            .fontDesign(.rounded)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(height: characterLineHeight)
                    }

                    if showCursor {
                        cursor
                    }
                } else if !showCursor {
                    ForEach(Array("Type".enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .font(.body.weight(.regular))
                            .fontDesign(.rounded)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .frame(height: characterLineHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
