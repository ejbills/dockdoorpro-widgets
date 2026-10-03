import SwiftUI
import DockDoorWidgetSDK

@MainActor
struct DotPanel: View {
    @Bindable var connection: DotConnection
    var dismiss: () -> Void = {}
    @State private var selectedTheme = DotTheme.current
    @State private var panelIdentity = UUID()
    @State private var showDotPicker = false
    private var glassOpacity: Double { WidgetDefaults.double(key: "glassOpacity", widgetId: "dot-glass", default: 0.68) }
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var panelGlassOpacity: Double { min(1, max(0.2, glassOpacity)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if connection.needsSetup {
                DotOnboarding(connection: connection)
            } else {
            ZStack {
                DotWebSession(connection: connection)
                    .opacity(connection.showConnection && !connection.showTour ? 1 : 0.001)
                    .allowsHitTesting(connection.showConnection && !connection.showTour)
                    .accessibilityHidden(!connection.showConnection || connection.showTour)
                if connection.showTour { DotTour(connection: connection) }
                else if !connection.showConnection { conversation }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if connection.showConnection && !connection.showTour { connectionFooter }
            }
        }
        .environment(\.dotTheme, selectedTheme)
        .environment(\.dotGlassOpacity, panelGlassOpacity)
        .modifier(DotGlassSurface(opacity: panelGlassOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.13), lineWidth: 0.7).allowsHitTesting(false))
        .sheet(isPresented: $showDotPicker) { DotPicker(connection: connection) }
        .background {
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                Color.clear.onChange(of: timeline.date) { _, _ in connection.tick(); selectedTheme = DotTheme.current }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
        .task { connection.connect() }
        .onAppear { connection.panelAppeared(panelIdentity) }
        .onDisappear { connection.panelDisappeared(panelIdentity) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Button { showDotPicker = true } label: {
                    HStack(spacing: 6) {
                        Text(connection.name).font(.headline).lineLimit(1)
                        Image(systemName: "chevron.down").font(.callout.weight(.semibold))
                    }
                }.buttonStyle(.plain).help("Choose Dot").accessibilityLabel("Choose Dot")
                HStack(spacing: 5) {
                    Circle().fill(connection.ready ? Color.cyan : Color.secondary).frame(width: 5, height: 5)
                    Text(connection.ready ? "Connected to ChatGPT" : "Dot Glass").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            DotIconButton(title: connection.voiceConnected || connection.voiceStarting ? "End call" : "Call your Dot",
                          symbol: connection.voiceConnected || connection.voiceStarting ? "phone.down.fill" : "phone.fill",
                          prominent: true, destructive: connection.voiceConnected || connection.voiceStarting) {
                if connection.voiceConnected || connection.voiceStarting { connection.stopAudio() }
                else { connection.startCall() }
            }
            if connection.voiceConnected {
                DotIconButton(title: connection.microphoneMuted ? "Unmute microphone" : "Mute microphone",
                              symbol: connection.microphoneMuted ? "mic.slash.fill" : "mic.fill",
                              destructive: connection.microphoneMuted, action: connection.toggleMicrophone)
                    .disabled(connection.microphoneChangePending)
            }
            DotIconButton(title: connection.showConnection ? "Show glass conversation" : "Show ChatGPT connection",
                          symbol: connection.showConnection ? "bubble.left.and.bubble.right" : "link") {
                connection.showConnection.toggle()
            }
            Menu {
                Section("Conversation") {
                    Button { showDotPicker = true } label: { Label("Choose Dot", systemImage: "circle.circle") }
                    Button { connection.showConnection = true } label: { Label("Manage connection", systemImage: "person.crop.circle") }
                    Button(action: connection.openBrowser) { Label("Open in browser", systemImage: "safari") }
                }
                Section("Notifications") {
                    if connection.notificationsEnabled {
                        Button("Turn off notifications", action: connection.disableNotifications)
                    } else {
                        Button("Enable native notifications", action: connection.enableNotifications)
                    }
                    Text("Delivered by DockDoor Pro · message text stays private")
                }
                Section("Help") {
                    Text("Dot Glass review candidate")
                    Button { connection.showTour = true } label: { Label("Quick tour", systemImage: "sparkles") }
                    Button(action: connection.reload) { Label("Reconnect", systemImage: "arrow.clockwise") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.callout.weight(.semibold))
                    .foregroundStyle(.white).frame(width: 36, height: 36)
                    .background(.black.opacity(0.22), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Dot Glass options").accessibilityLabel("Dot Glass options")
            DotIconButton(title: "Hide panel", symbol: "xmark", action: dismiss)
        }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                DotRing(phase: connection.phase, diameter: 98)
                Text(connection.voiceConnected && connection.microphoneMuted ? "Microphone muted · Dot can’t hear you" : connection.phase.rawValue)
                    .font(.caption).foregroundStyle(connection.voiceConnected && connection.microphoneMuted ? Color.orange : Color.secondary)
            }.padding(.top, 4).padding(.bottom, 12).frame(maxWidth: .infinity)
            Rectangle().fill(.primary.opacity(0.06)).frame(height: 0.5).padding(.horizontal, 22)
            if connection.messages.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { DotTranscript(connection: connection) }
            if let notice = connection.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 18).padding(.bottom, 8)
            }
            composer
        }.background(.clear)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(connection.loading ? "Bringing your Dot closer…" : "A little space for your Dot.")
                .font(.headline)
            Text(connection.loading ? "Your conversation will appear here." : "Sign in to ChatGPT and open Your Dot to begin.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !connection.loading {
                Button("Connect your Dot") { connection.beginSetup() }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            }
        }.padding(28)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message your Dot", text: $connection.draft, axis: .vertical)
                .font(.callout).textFieldStyle(.plain).lineLimit(1...5)
                .focused($focused).onSubmit { if connection.canSend { connection.send() } }
                .disabled(connection.pendingToken != nil)
                .padding(.vertical, 8).padding(.leading, 7)
                .accessibilityLabel("Message your Dot")
            Button(action: connection.send) {
                Image(systemName: connection.pendingToken == nil ? "arrow.up" : "ellipsis")
                    .font(.callout.weight(.semibold)).frame(width: 32, height: 32)
                    .foregroundStyle(connection.canSend ? .white : .secondary)
                    .background(connection.canSend ? Color.blue : Color.primary.opacity(0.06), in: Circle())
            }.buttonStyle(.plain).disabled(!connection.canSend).help("Send message").accessibilityLabel("Send message")
        }.padding(8)
            .background {
                let shape = RoundedRectangle(cornerRadius: 25, style: .continuous)
                if reduceTransparency {
                    shape.fill(.regularMaterial)
                } else {
                    shape.fill(.ultraThinMaterial).opacity(panelGlassOpacity)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(.primary.opacity(focused ? 0.18 : 0.08), lineWidth: 0.7))
            .padding(.horizontal, 16).padding(.top, 5).padding(.bottom, 16)
    }

    private var connectionFooter: some View {
        VStack(spacing: 8) {
            if let notice = connection.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            Text(connection.ready ? "Your Dot is connected. Choose Done to return to the glass conversation." : "Sign in to ChatGPT, then open Your Dot. Your conversation appears here automatically after setup.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Back to setup", action: connection.cancelSetup)
                Spacer()
                if connection.pendingToken != nil {
                    Button("I’ve checked delivery", action: connection.confirmDeliveryChecked)
                } else {
                    Button("Quick tour") { connection.showTour = true }
                Button("Reconnect", action: connection.reload)
                    Button("Done") { connection.showConnection = false }.disabled(!connection.ready)
                }
            }.controlSize(.small)
        }.padding(14)
    }
}
