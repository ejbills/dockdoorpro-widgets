import DockDoorWidgetSDK
import SwiftUI

@objc(DotGlassPlugin)
final class DotGlassPlugin: WidgetPlugin, DockDoorWidgetProvider {
    @MainActor private lazy var connection = DotConnection()
    var id: String { "dot-glass" }
    var name: String { "Dot Glass" }
    var iconSymbol: String { "circle.circle" }
    var widgetDescription: String { "Your Dot in a glass conversation panel, with messages, voice calls and a cloud orb." }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }
    func settingsSchema() -> [WidgetSetting] {
        [
            .picker(key: "theme", label: "Theme", options: DotTheme.allCases.map(\.rawValue), defaultValue: "Arctic"),
            .slider(key: "glassOpacity", label: "Glass opacity", range: 0.2...1, step: 0.05, defaultValue: 0.68)
        ]
    }
    @MainActor func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(TimelineView(.periodic(from: .now, by: connection.voiceStarting || connection.voiceConnected ? 0.25 : 30)) { timeline in
            DotCompact(size: size, vertical: isVertical, connection: self.connection)
                .environment(\.dotTheme, DotTheme.current)
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
    private var extendedVertical: Bool { vertical && size.height > size.width * 1.5 }
    private var status: String {
        if connection.voiceConnected { return connection.microphoneMuted ? "Call · muted" : "Call · mic on" }
        if connection.voiceStarting { return "Calling…" }
        if !connection.ready && !connection.loading && !connection.needsSetup { return "Open to connect" }
        return connection.connectionState.rawValue
    }
    private var ring: some View {
        DotRing(phase: connection.phase,
                diameter: (extendedVertical ? min(size.width, size.height * 0.58) : side) * WidgetMetrics.contentScale,
                audioLevel: connection.voiceLevel)
    }
    var body: some View {
        Group {
            if extendedVertical {
                VStack(spacing: 6) {
                    ring
                    Text(status)
                        .font(.system(size: max(10, size.width * 0.15), weight: .medium))
                        .lineLimit(2).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    ring
                    if !vertical && size.width > side * 1.6 {
                        Text(status)
                            .font(.system(size: max(10, side * 0.2), weight: .medium))
                            .lineLimit(1)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .overlay(alignment: .bottomTrailing) {
            if connection.voiceStarting || connection.voiceConnected {
                Image(systemName: connection.microphoneMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: max(10, side * 0.19), weight: .bold))
                    .foregroundStyle(.white).padding(4)
                    .background(connection.microphoneMuted ? Color.orange : Color.red, in: Circle())
                    .accessibilityLabel(connection.microphoneMuted ? "Call active, microphone muted" : "Call active, microphone on")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dot Glass, \(themeName). \(status). Open conversation panel.")
    }
}
