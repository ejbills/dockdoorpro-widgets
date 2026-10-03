import SwiftUI

@MainActor
struct DotTranscript: View {
    @Bindable var connection: DotConnection
    @State private var atBottom = true
    @State private var unread = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(connection.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if connection.typing {
                            HStack(spacing: 7) {
                                ProgressView().controlSize(.mini)
                                Text("Dot is thinking…").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                            }.padding(.horizontal, 4)
                        }
                        Color.clear.frame(height: 1).id("latest")
                            .background(GeometryReader { bottom in
                                Color.clear.preference(key: DotBottomKey.self,
                                                       value: bottom.frame(in: .named("dot-transcript")).maxY)
                            })
                    }.padding(.horizontal, 20).padding(.vertical, 16)
                }
                .coordinateSpace(name: "dot-transcript")
                .defaultScrollAnchor(.bottom)
                .onPreferenceChange(DotBottomKey.self) { bottom in
                    atBottom = bottom <= geometry.size.height + 35
                    if atBottom { unread = false }
                    connection.transcriptPositionChanged(atBottom: atBottom)
                }
                .onChange(of: connection.messages) { _, _ in
                    if atBottom { scroll(proxy) } else { unread = true }
                }
                .onChange(of: connection.typing) { _, _ in if atBottom { scroll(proxy) } }
                .overlay(alignment: .bottom) {
                    if unread {
                        Button { scroll(proxy); unread = false } label: {
                            Label("New messages", systemImage: "arrow.down").font(.caption.weight(.medium))
                        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).padding(.bottom, 8)
                    }
                }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { proxy.scrollTo("latest", anchor: .bottom) }
    }

    private func bubble(_ message: DotMessage) -> some View {
        VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
        HStack(alignment: .bottom, spacing: 0) {
            if message.isMine { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 8) {
                if !message.text.isEmpty {
                    Text(message.text).font(.callout).lineSpacing(4)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if message.hasAttachment {
                    Button { connection.showConnection = true } label: {
                        Label("View attachment", systemImage: "paperclip").font(.caption)
                    }.buttonStyle(.plain).underline()
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
            .modifier(DotBubbleSurface(isMine: message.isMine))
            .contextMenu {
                Button("Copy text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) }
                Button("Open original") { connection.showConnection = true }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(message.isMine ? "You" : connection.name): \(message.text)")
            if !message.isMine { Spacer(minLength: 30) }
        }
        if message.isMine, let receipt = message.readReceipt {
            Text(receipt).font(.caption2).foregroundStyle(.secondary)
                .padding(.trailing, 4).accessibilityLabel(receipt)
        }
        }
    }
}

private struct DotBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
