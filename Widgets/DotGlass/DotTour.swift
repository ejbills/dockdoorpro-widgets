import SwiftUI

@MainActor
struct DotTour: View {
    @Bindable var connection: DotConnection
    @State private var page = 0
    @Environment(\.dotTheme) private var selectedTheme
    private var themeName: String { selectedTheme.rawValue }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var palette: [Color] { (DotTheme(rawValue: themeName) ?? .arctic).colors }
    private let titles = ["Your Dot. A little closer.", "Talk naturally.", "Make it yours."]
    private let details = ["Send a message at the bottom of the panel. Your real Dot replies here, with your conversation kept together.", "Use the phone button to start a real Dot call. The ring responds to Dot’s voice. Calls continue when the panel hides. Reopen it and use End call when you’re finished.", "Choose one of six colors in DockDoor’s widget settings under Orb glow. Your ring and chat bubbles follow your theme."]
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            Text("MEET YOUR DOT").font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(.secondary)
            DotRing(phase: .ready, diameter: 108)
            VStack(spacing: 12) {
                Text(titles[page]).font(.title2.weight(.semibold))
                Text(details[page]).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }.id(page).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
            if page == 0 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hello, Dot.").padding(14).modifier(DotBubbleSurface(isMine: true)).frame(maxWidth: .infinity, alignment: .trailing)
                    Text("A space for your next idea.").padding(14).modifier(DotBubbleSurface(isMine: false)).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Example conversation").font(.caption2).foregroundStyle(.secondary)
                }.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.15), lineWidth: 0.7))
            } else if page == 1 {
                Image(systemName: "phone.fill").font(.largeTitle).padding(20)
                    .background(.thinMaterial, in: Circle()).foregroundStyle(palette[0]).shadow(color: palette[0].opacity(0.2), radius: 16)
                Text("Microphone permission is requested when you call.").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    ForEach(DotTheme.allCases, id: \.rawValue) { theme in
                        Circle().fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(.white, lineWidth: themeName == theme.rawValue ? 2 : 0))
                            .accessibilityLabel(theme.rawValue)

                    }
                }
                Text(themeName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                ForEach(0..<3) { index in Capsule().fill(index == page ? Color.primary : Color.secondary.opacity(0.25)).frame(width: index == page ? 22 : 6, height: 6) }
            }.accessibilityLabel("Step \(page + 1) of 3")
            HStack {
                Button("Skip tour", action: connection.finishTour).buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button(page == 2 ? "Start chatting" : "Continue") {
                    if page == 2 { connection.finishTour() }
                    else { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { page += 1 } }
                }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            }
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    RadialGradient(colors: [palette[0].opacity(0.22), .clear], center: .init(x: 0.25, y: 0.18), startRadius: 0, endRadius: 310)
                    RadialGradient(colors: [palette[1].opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 280)
                }.allowsHitTesting(false)
            }
            .modifier(DotGlassSurface())
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.18), lineWidth: 0.7).allowsHitTesting(false))
            .tint(palette[0])
    }
}
