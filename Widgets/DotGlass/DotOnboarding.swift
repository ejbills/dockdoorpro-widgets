import SwiftUI

@MainActor
struct DotOnboarding: View {
    @Bindable var connection: DotConnection

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            DotRing(phase: .ready, diameter: 108)
            Text("Bring your Dot closer.").font(.title2.bold())
            Text("Your ChatGPT Dot, in a little glass space on your dock.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 16) {
                Label("Sign in with your ChatGPT account", systemImage: "person.crop.circle")
                Label("Open Your Dot in ChatGPT", systemImage: "circle.circle")
                Label("Start chatting right here", systemImage: "bubble.left.and.bubble.right")
            }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
            Button("Connect ChatGPT", action: connection.beginSetup)
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
            Text("Requires access to ChatGPT Dots. Sign-in stays in ChatGPT’s secure page. Microphone permission is requested only when you start a call.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer(minLength: 12)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RadialGradient(colors: [.cyan.opacity(0.12), .clear], center: .top, startRadius: 0, endRadius: 380))
            .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}
