import DockDoorWidgetSDK
import SwiftUI

@objc(DotGlassPlugin)
final class DotGlassPlugin: WidgetPlugin, DockDoorWidgetProvider {
    @MainActor private lazy var connection = DotConnection()
    var id: String { "dot-glass" }
    var name: String { "Dot Glass" }
    var iconSymbol: String { "circle.circle" }
    var widgetDescription: String { "Your Dot in a glass conversation panel, with real messages and a speaking-animated ring." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }
    func settingsSchema() -> [WidgetSetting] {
        [
            .picker(key: "theme", label: "Orb glow", options: DotTheme.allCases.map(\.rawValue), defaultValue: "Arctic"),
            .slider(key: "glassOpacity", label: "Glass opacity", range: 0.2...1, step: 0.05, defaultValue: 0.68)
        ]
    }
    @MainActor func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(TimelineView(.periodic(from: .now, by: connection.voiceStarting || connection.voiceConnected ? 0.25 : 1)) { timeline in
            DotCompact(size: size, vertical: isVertical, connection: self.connection)
                .environment(\.dotTheme, DotTheme.current)
                .task { self.connection.connect() }
                .onChange(of: timeline.date) { _, _ in self.connection.tick() }
        })
    }
    @MainActor func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? { AnyView(DotPanel(connection: connection, dismiss: dismiss).frame(width: 440, height: 640)) }
}

@MainActor
struct DotCompact: View {
    let size: CGSize
    let vertical: Bool
    let connection: DotConnection
    @Environment(\.dotTheme) private var selectedTheme
    private var themeName: String { selectedTheme.rawValue }
    private var side: CGFloat { max(20, min(size.width, size.height)) }
    var body: some View {
        DotRing(phase: connection.phase, diameter: side * WidgetMetrics.contentScale)
        .overlay(alignment: .topTrailing) {
            if connection.unreadCount > 0 {
                Text(connection.unreadCount > 99 ? "99+" : "\(connection.unreadCount)")
                    .font(.system(size: max(10, side * 0.18), weight: .bold, design: .rounded))
                    .foregroundStyle(.white).padding(4)
                    .background(.red, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                    .accessibilityLabel("\(connection.unreadCount) unread messages")
            }
        }
        .contentShape(Rectangle())
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dot Glass, \(themeName). \(connection.phase.rawValue). \(connection.microphoneMuted ? "Microphone muted." : "") \(connection.unreadCount) unread messages. Open conversation panel.")
    }
}
