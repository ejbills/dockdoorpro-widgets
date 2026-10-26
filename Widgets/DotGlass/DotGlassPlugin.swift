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
    private var diameter: CGFloat {
        (extendedVertical ? min(size.width, size.height * 0.58) : side) * WidgetMetrics.contentScale
    }
    /// Short enough to fit a dock slot; the accessibility label keeps the full wording.
    private var status: String {
        if connection.voiceConnected { return connection.microphoneMuted ? "Muted" : "On a call" }
        if connection.voiceStarting { return "Calling" }
        switch connection.connectionState {
        case .setup: return "Set up"
        case .authentication: return "Signing in"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .ready: return "Connected"
        case .paused: return "Offline"
        case .deliveryAttention: return "Check delivery"
        }
    }
    private var spokenStatus: String {
        if connection.voiceConnected { return connection.microphoneMuted ? "On a call, microphone muted" : "On a call, microphone on" }
        if connection.voiceStarting { return "Calling your Dot" }
        return connection.connectionState.rawValue
    }
    private var ring: some View {
        DotRing(phase: connection.phase, diameter: diameter, audioLevel: connection.voiceLevel)
            .overlay(alignment: .bottomTrailing) {
                if connection.voiceStarting || connection.voiceConnected {
                    Image(systemName: connection.microphoneMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: diameter * 0.26, weight: .bold))
                        .foregroundStyle(.white).padding(diameter * 0.08)
                        .background(connection.microphoneMuted ? Color.orange : Color.red, in: Circle())
                }
            }
    }
    var body: some View {
        Group {
            if extendedVertical {
                VStack(spacing: size.width * WidgetMetrics.spacingScale) {
                    ring
                    Text(status)
                        .font(.system(size: size.width * 0.2, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, size.width * 0.06)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: side * WidgetMetrics.spacingScale) {
                    ring
                    if !vertical && size.width > side * 1.6 {
                        Text(status)
                            .font(.system(size: side * 0.22, weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dot Glass, \(themeName). \(spokenStatus). Open conversation panel.")
    }
}
