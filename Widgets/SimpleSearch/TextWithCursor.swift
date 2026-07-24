import SwiftUI

struct TextWithCursor: View {
    let text: String
    let showCursor: Bool
    var scrolling: Bool = false
    var isTriple: Bool = false
    var cursorColor: Color = .primary
    var suggestion: String? = nil

    @State private var cursorOn = true
    @ScaledMetric(relativeTo: .body) private var textLineHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var cursorWidth: CGFloat = 1.5
    @ScaledMetric(relativeTo: .body) private var cursorHeight: CGFloat = 16

    var body: some View {
        if scrolling && !text.isEmpty {
            ScrollingTextDisplay(
                text: text,
                showCursor: showCursor,
                lineHeight: textLineHeight,
                cursorWidth: cursorWidth,
                cursorHeight: cursorHeight,
                cursorColor: cursorColor
            )
        } else {
            HStack(spacing: 0) {
                if showCursor && text.isEmpty {
                    cursor
                    if let suggestion {
                        (Text(Image(systemName: "clipboard.fill")).baselineOffset(1) + Text(" \(suggestion)"))
                            .font(.body.weight(.regular))
                            .fontDesign(.rounded)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, 2)
                    }
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
                    Text(isTriple ? "Type to search" : "Type")
                        .font(.body.weight(.regular))
                        .fontDesign(.rounded)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var cursor: some View {
        Rectangle()
            .fill(cursorColor)
            .frame(width: cursorWidth, height: cursorHeight)
            .opacity(cursorOn ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    cursorOn.toggle()
                }
            }
    }
}

private struct ScrollingTextDisplay: View {
    let text: String
    let showCursor: Bool
    let lineHeight: CGFloat
    let cursorWidth: CGFloat
    let cursorHeight: CGFloat
    let cursorColor: Color

    @State private var textWidth: CGFloat = 0
    @State private var cursorOn = true

    var body: some View {
        GeometryReader { geo in
            let contentWidth = textWidth + (showCursor ? cursorWidth : 0)
            let offset = min(CGFloat(0), geo.size.width - contentWidth)

            HStack(spacing: 0) {
                Text(text)
                    .font(.body.weight(.regular))
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { tg in
                            Color.clear
                                .onAppear { textWidth = tg.size.width }
                                .onChange(of: tg.size.width) { _, w in textWidth = w }
                        }
                    )

                if showCursor {
                    Rectangle()
                        .fill(cursorColor)
                        .frame(width: cursorWidth, height: cursorHeight)
                        .opacity(cursorOn ? 1 : 0)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                                cursorOn.toggle()
                            }
                        }
                }
            }
            .frame(height: geo.size.height, alignment: .center)
            .offset(x: offset)
        }
        .frame(height: lineHeight)
        .clipped()
    }
}
