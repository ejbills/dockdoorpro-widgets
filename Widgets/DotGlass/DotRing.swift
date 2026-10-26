import SwiftUI

/// Compatibility wrapper used by the panel, dock tile and onboarding.
struct DotRing: View {
    @Environment(\.dotTheme) private var theme
    let phase: DotPhase
    var diameter: CGFloat = 104
    var audioLevel: Double = 0

    private var state: VoiceOrbState {
        if phase == .speaking { return .speaking }
        if phase == .inCall { return .listening }
        if phase == .connecting { return .listening }
        return .idle
    }
    var body: some View {
        DotVoiceOrb(state: state, audioLevel: audioLevel, configuration: VoiceOrbConfiguration(colors: theme.colors))
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .ignore).accessibilityLabel("Dot, \(phase.rawValue)")
    }
}
