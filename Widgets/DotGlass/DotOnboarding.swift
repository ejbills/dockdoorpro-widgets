import SwiftUI

@MainActor
struct DotOnboarding: View {
    @Bindable var connection: DotConnection
    @Environment(\.dotTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 8)
                    DotRing(phase: .ready, diameter: 90)
                    Text("Bring your Dot closer.").font(.title2.bold())
                    Text("Your ChatGPT Dot, in a little glass space on your dock.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Sign in with your ChatGPT account", systemImage: "person.crop.circle")
                        Label("Open Your Dot in ChatGPT", systemImage: "circle.circle")
                        Label("Start chatting right here", systemImage: "bubble.left.and.bubble.right")
                    }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                    Button("Connect ChatGPT", action: connection.beginSetup)
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                    Button("See how it works") { connection.showTour = true }.buttonStyle(.plain)
                    Text("Requires access to ChatGPT Dots. Microsoft sign-in is not offered in this ChatGPT sign-in screen; use a method already linked to your account. If email says it will create an account, go back unless you want a separate account. Signing in through Safari will not connect this widget. Microphone permission is requested only when you start a call.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                }.padding(22).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }.background(RadialGradient(colors: [theme.colors[0].opacity(0.12), .clear], center: .top, startRadius: 0, endRadius: 380))
        }.clipShape(RoundedRectangle(cornerRadius: 28))
    }
}
