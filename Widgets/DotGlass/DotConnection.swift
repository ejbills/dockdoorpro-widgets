import AppKit
import Observation
import OSLog
import WebKit

/// One owned web session per plugin. Messages are held in memory, never logged.
@MainActor
@Observable
final class DotConnection: NSObject {
    @ObservationIgnored let callLog = Logger(subsystem: "dot-glass", category: "Call")
    var messages: [DotMessage] = []
    private var unreadState = DotUnread()
    var unreadCount = 0
    var transcriptAtBottom = false
    @ObservationIgnored private lazy var notifications = DotNotifications(defaults: defaults)
    var notificationsEnabled = false

    func enableNotifications() {
        Task { @MainActor in
            notificationsEnabled = await notifications.enable()
            if !notificationsEnabled {
                notice = "Allow notifications for DockDoor Pro in System Settings → Notifications, then try again."
            }
        }
    }
    func disableNotifications() { notifications.disable(); notificationsEnabled = false }
    func markMessagesRead() {
        unreadState.markRead(); unreadCount = 0; notifications.clear()
    }
    func transcriptPositionChanged(atBottom: Bool) {
        transcriptAtBottom = atBottom
        if atBottom && !visiblePanels.isEmpty { markMessagesRead() }
    }
    var name = "Your dot"
    var ready = false
    var loading = false
    var typing = false
    private var textActivityUntil = Date.distantPast
    private var textActivityPhase = DotPhase.thinking
    var mediaPlaying = false
    var pendingToken: String?
    var draft = ""
    var notice: String?
    var showConnection = false
    var needsSetup = false
    var showTour = false
    private var openedDotAfterLogin = false
    private var completingSetup = false
    private var requestedSignIn = false
    var voiceStarting = false
    private var voiceEnding = false
    private var voiceTimeout: Task<Void, Never>?
    private var visiblePanels = Set<UUID>()
    var voiceConnected = false
    var voiceLevel = 0.0
    private var speechActivity = DotSpeechActivity()
    var voiceSpeaking: Bool { speechActivity.isSpeaking }
    var voiceMeterAvailable = false
    var microphoneMuted = false
    var microphoneChangePending = false
    private(set) var webView: WKWebView!
    private(set) var conversation = ""
    private var timeout: Task<Void, Never>?
    private var hydrated = false
    private var seen = Set<String>()
    private var submittedDraft: String?
    private var handler: DotScriptHandler!
    private let defaults: UserDefaults
    var directory = DotDirectory()
    private var drafts: [String: String] = [:]
    var targetConversation: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        notificationsEnabled = defaults.bool(forKey: "dot-glass.notifications")
        if let data = defaults.data(forKey: "dot-glass.directory"),
           let saved = try? JSONDecoder().decode(DotDirectory.self, from: data) {
            for profile in saved.profiles { directory.remember(url: profile.url, name: profile.name) }
        }
        let config = WKWebViewConfiguration()
        // Dedicated persistent session: no dependency on Tracker or the prototype's cookies.
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "1D9FD40A-8C44-4936-BFAD-08608F59DA71")!)
        config.mediaTypesRequiringUserActionForPlayback = []
        handler = DotScriptHandler(owner: self)
        config.userContentController.add(handler, name: "dotGlass")
        config.userContentController.addUserScript(WKUserScript(source: DotVoiceAdapter.source,
                                                               injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(WKUserScript(source: DotPageAdapter.source,
                                                               injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = .clear
    }

    @ObservationIgnored private var lastCaptureState: WKMediaCaptureState?
    @ObservationIgnored private var observedInboundAudio = false
    @ObservationIgnored private var lastTick = Date.distantPast
    @ObservationIgnored private var tickInFlight = false
    @ObservationIgnored private var lastTranscriptTick = Date.distantPast

    /// Driven by visible panel/dock timelines. A hidden panel keeps voice sampling
    /// while connected. Hidden-panel transcript sampling is bounded to three seconds
    /// and only runs when the host renders the dock timeline.
    func tick() {
        guard !conversation.isEmpty || !visiblePanels.isEmpty || voiceStarting || voiceConnected else { return }
        guard !tickInFlight, Date().timeIntervalSince(lastTick) >= 0.24,
              webView.url?.host == "chatgpt.com" else { return }
        if voiceStarting || voiceConnected {
            let capture = webView.microphoneCaptureState
            if capture != lastCaptureState {
                lastCaptureState = capture
                callLog.notice("Microphone state: active=\(capture == .active) muted=\(capture == .muted)")
            }
        }
        let now = Date()
        let refreshTranscript = now.timeIntervalSince(lastTranscriptTick) >= (!visiblePanels.isEmpty ? 1.5 : 3)
        guard refreshTranscript || voiceStarting || voiceConnected else { return }
        if textActivityUntil != .distantPast && now >= textActivityUntil { textActivityUntil = .distantPast }
        lastTick = now; tickInFlight = true
        if refreshTranscript { lastTranscriptTick = now }
        webView.callAsyncJavaScript("if (refreshTranscript) window.__dotGlass?.refresh(); await window.__dotGlassVoice?.sample();", arguments: ["refreshTranscript": refreshTranscript], in: nil, in: .page) { [weak self] _ in
            Task { @MainActor in self?.tickInFlight = false }
        }
    }

    var phase: DotPhase {
        if voiceConnected && voiceSpeaking { return .speaking }
        if voiceConnected { return .inCall }
        if voiceStarting { return .connecting }
        if pendingToken != nil { return .sending }
        if typing { return .thinking }
        if textActivityUntil > Date() { return textActivityPhase }
        if ready { return .ready }
        return loading ? .connecting : .offline
    }

    var lastReply: DotMessage? { messages.last(where: { !$0.isMine && !$0.text.isEmpty }) }
    var canSend: Bool { ready && pendingToken == nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.utf16.count <= 12000 }

    func connect() {
        guard webView.url == nil else { return }
        loadSaved()
    }

    func loadSaved() {
        guard defaults.bool(forKey: "dot-glass.onboardingComplete"),
              let url = DotURLPolicy.conversation(defaults.string(forKey: "dot-glass.conversationURL")) else {
            needsSetup = true; loading = false
            return
        }
        ready = false; loading = true; notice = nil
        completingSetup = true
        showConnection = false
        webView.load(URLRequest(url: url))
    }

    func beginSetup() {
        openedDotAfterLogin = false
        needsSetup = false; completingSetup = true; requestedSignIn = true
        showConnection = true; loading = true; notice = nil
        webView.load(URLRequest(url: DotURLPolicy.home))
    }

    func finishTour() {
        defaults.set(true, forKey: "dot-glass.tourComplete")
        showTour = false
        if !ready { showConnection = true; notice = "Open Your Dot to finish connecting your conversation." }
    }

    func cancelSetup() {
        stopAudio()
        requestedSignIn = false; completingSetup = false
        webView.stopLoading(); loading = false; showConnection = false; needsSetup = true
    }

    func openSignInIfNeeded() {
        guard requestedSignIn, !needsSetup, webView.url?.host == "chatgpt.com" else { return }
        webView.callAsyncJavaScript("return window.__dotGlass?.openSignIn() ?? false;", arguments: [:], in: nil, in: .page) { [weak self] result in
            Task { @MainActor in
                if case .success(let clicked) = result, clicked as? Bool == true { self?.requestedSignIn = false }
            }
        }
    }

    func reload() {
        guard !voiceStarting && !voiceConnected else {
            notice = "End your call before reconnecting."
            return
        }
        if webView.url == nil { beginSetup(); return }
        guard pendingToken == nil else {
            notice = "Check the conversation before reconnecting; your last message may have been sent."
            showConnection = true
            return
        }
        hydrated = false; unreadState.reset(); unreadCount = 0; ready = false; loading = true; notice = nil
        webView.reload()
    }

    var canSwitchDot: Bool { pendingToken == nil && !voiceConnected && !voiceStarting && !loading }

    func selectDot(_ profile: DotProfile) {
        guard canSwitchDot, let url = DotURLPolicy.conversation(profile.url) else { return }
        guard url.absoluteString != conversation else { showConnection = false; return }
        drafts[conversation] = draft
        targetConversation = url.absoluteString
        ready = false; loading = true; typing = false; messages = []; notice = nil
        name = profile.name; draft = drafts[url.absoluteString] ?? ""
        showConnection = false
        webView.load(URLRequest(url: url))
    }

    func addDot(url: String, name: String) {
        guard canSwitchDot, let valid = DotURLPolicy.conversation(url) else { return }
        directory.remember(url: valid.absoluteString, name: name)
        saveDirectory()
        if let profile = directory.profiles.first(where: { $0.url == valid.absoluteString }) { selectDot(profile) }
    }

    private func saveDirectory() {
        if let data = try? JSONEncoder().encode(directory) { defaults.set(data, forKey: "dot-glass.directory") }
    }

    func receive(_ snapshot: DotSnapshot) {
        guard snapshot.messages.count <= 100 else { return }
        if completingSetup && snapshot.signedIn == true && !openedDotAfterLogin && DotURLPolicy.conversation(snapshot.conversation) == nil {
            openedDotAfterLogin = true; requestedSignIn = false
            showConnection = false; showTour = !defaults.bool(forKey: "dot-glass.tourComplete")
            loading = true
            webView.load(URLRequest(url: DotURLPolicy.dotHome))
            return
        }
        let incoming = DotURLPolicy.conversation(snapshot.conversation)?.absoluteString ?? ""
        if let targetConversation, incoming != targetConversation { return }
        if incoming != conversation {
            if targetConversation == nil { drafts[conversation] = draft; draft = drafts[incoming] ?? "" }
            targetConversation = nil
            hydrated = false; seen.removeAll(); unreadState.reset(); unreadCount = 0
            if pendingToken != nil { notice = "The conversation changed. Check delivery before sending again." }
            pendingToken = nil; timeout?.cancel()
            conversation = incoming
        }
        guard !incoming.isEmpty else {
            ready = false; messages = []; typing = false; mediaPlaying = false
            if !needsSetup && !showTour { showConnection = true; openSignInIfNeeded() }
            return
        }
        if defaults.string(forKey: "dot-glass.conversationURL") != incoming {
            defaults.set(incoming, forKey: "dot-glass.conversationURL")
        }
        let previousProfiles = directory.profiles
        directory.remember(url: incoming, name: snapshot.name)
        if directory.profiles != previousProfiles { saveDirectory() }
        name = directory.profiles.first(where: { $0.url == incoming })?.name ?? String(snapshot.name.prefix(80))
        ready = snapshot.ready; loading = false
        if ready && completingSetup {
            showTour = !defaults.bool(forKey: "dot-glass.tourComplete")
            defaults.set(true, forKey: "dot-glass.onboardingComplete")
            requestedSignIn = false; completingSetup = false; needsSetup = false; showConnection = false
        }
        typing = snapshot.typing; mediaPlaying = snapshot.mediaPlaying
        if hydrated, let latest = snapshot.messages.last,
           messages.first(where: { $0.id == latest.id })?.text != latest.text {
            textActivityPhase = latest.isMine ? .sending : .thinking
            textActivityUntil = Date().addingTimeInterval(2)
        }
        let previousReceipts = messages.reduce(into: [String: String]()) { receipts, message in
            if let receipt = message.readReceipt { receipts[message.id] = receipt }
        }
        messages = snapshot.messages.map { message in
            guard message.readReceipt == nil, let receipt = previousReceipts[message.id] else { return message }
            var updated = message
            updated.readReceipt = receipt
            return updated
        }
        let reading = !visiblePanels.isEmpty && transcriptAtBottom && !showConnection && !showTour
        let newReplies = unreadState.update(room: incoming, messages: snapshot.messages,
                                            typing: snapshot.typing, reading: reading)
        unreadCount = unreadState.count
        if reading { notifications.clear() }
        else if newReplies > 0 { notifications.notify() }
        if let token = pendingToken, snapshot.acknowledgement == token {
            pendingToken = nil; timeout?.cancel()
            if draft == submittedDraft { draft = "" }
            submittedDraft = nil; notice = nil
        }
        seen.formUnion(snapshot.messages.map(\.id))
        if seen.count > 500 { seen = Set(snapshot.messages.map(\.id)) }
        hydrated = true
    }

    func send() {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines), token = UUID().uuidString
        pendingToken = token; submittedDraft = draft; notice = nil
        let expected = conversation
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.pendingToken == token else { return }
            self.notice = "Delivery isn’t confirmed yet. Open the conversation to check before retrying."
            self.showConnection = true
            // Keep send disabled to prevent duplicate messages after an ambiguous outcome.
        }
        webView.callAsyncJavaScript("return await window.__dotGlass?.send(text, token, room) ?? 'not-ready';",
                                    arguments: ["text":text,"token":token,"room":expected], in: nil, in: .page) { [weak self] result in
            Task { @MainActor in
                guard let self, self.pendingToken == token else { return }
                if case .success(let value) = result, value as? String == "submitted" { return }
                self.timeout?.cancel()
                // Unknown execution errors could occur after Send was clicked: never auto-retry.
                if case .success(let value) = result, let status = value as? String,
                   ["not-ready", "existing-draft", "invalid", "room-changed", "send-unavailable", "editor-unavailable"].contains(status) {
                    self.pendingToken = nil
                }
                self.notice = "The message needs attention in the connection view. Your draft is preserved."
                self.showConnection = true
            }
        }
    }

    func confirmDeliveryChecked() {
        pendingToken = nil; timeout?.cancel(); submittedDraft = nil; notice = nil
        // Reload also resets the browser adapter's pending token; user reviewed delivery first.
        reload()
    }

    func openBrowser() { NSWorkspace.shared.open(DotURLPolicy.conversation(conversation) ?? DotURLPolicy.home) }
    func startCall() {
        guard ready, !loading, pendingToken == nil else {
            notice = "Finish connecting your Dot and any pending message before calling."
            return
        }
        guard !voiceStarting, !voiceConnected else { return }
        observedInboundAudio = false; lastCaptureState = nil
        callLog.notice("Call requested")
        voiceEnding = false; voiceStarting = true; showConnection = false; notice = nil
        webView.callAsyncJavaScript("return window.__dotGlass?.startCall(room) ?? 'not-ready';",
            arguments: ["room": conversation], in: nil, in: .page) { [weak self] result in
            Task { @MainActor in
                guard let self, self.voiceStarting else { return }
                guard case .success(let value) = result, value as? String == "started" else {
                    self.voiceStarting = false
                    if case .success(let value) = result, let status = value as? String,
                       ["not-ready", "pending", "call-unavailable"].contains(status) {
                        self.callLog.notice("Call control status: \(status, privacy: .public)")
                    } else if case .failure(let error) = result {
                        self.callLog.notice("Call script error code: \((error as NSError).code)")
                    } else { self.callLog.notice("Unexpected call control result") }
                    self.notice = "The call couldn’t start. Reconnect your Dot, then try again."
                    return
                }
                self.voiceTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled, let self, self.voiceStarting else { return }
                    self.callLog.notice("Call connection timed out")
                    self.stopAudio()
                    self.notice = "The call didn’t connect. Check microphone access and try again."
                }
            }
        }
    }

    func toggleMicrophone() {
        guard voiceConnected, !microphoneChangePending else { return }
        microphoneChangePending = true
        webView.callAsyncJavaScript("return window.__dotGlass?.setMuted(muted, room) ?? 'unavailable';",
            arguments: ["muted": !microphoneMuted, "room": conversation], in: nil, in: .page) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.microphoneChangePending = false
                if case .success(let value) = result, let status = value as? String,
                   ["changed", "unchanged"].contains(status) {
                    self.notice = nil
                    self.webView.callAsyncJavaScript("await window.__dotGlassVoice?.sample();", arguments: [:], in: nil, in: .page, completionHandler: nil)
                } else {
                    self.notice = "Open the connection view to change ChatGPT’s microphone control."
                }
            }
        }
    }

    func panelAppeared(_ identity: UUID) {
        visiblePanels.insert(identity)
        if transcriptAtBottom { markMessagesRead() }
        callLog.notice("Conversation panel appeared")
    }

    func panelDisappeared(_ identity: UUID) {
        visiblePanels.remove(identity)
        if visiblePanels.isEmpty { transcriptAtBottom = false }
        // The plugin owns the call. DockDoor may dismiss its panel on focus
        // changes; hiding presentation must never revoke active microphone use.
        callLog.notice("Conversation panel hidden; active call retained")
    }

    func stopAudio() {
        callLog.notice("Stopping call: starting=\(self.voiceStarting) connected=\(self.voiceConnected)")
        voiceEnding = true
        let wasStarting = voiceStarting
        voiceTimeout?.cancel(); voiceStarting = false
        let hadCapture = webView.microphoneCaptureState != .none
        webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        webView.pauseAllMediaPlayback(completionHandler: nil)
        if voiceConnected || hadCapture || wasStarting { webView.load(URLRequest(url: DotURLPolicy.conversation(conversation) ?? DotURLPolicy.home)) }
        voiceConnected = false; voiceLevel = 0; _ = speechActivity.update(connected: false, level: 0)
        microphoneMuted = false; microphoneChangePending = false
    }
    func receiveVoice(_ value: DotVoiceSnapshot) {
        if value.connected != voiceConnected { callLog.notice("WebRTC connection changed: \(value.connected)") }
        if voiceEnding {
            if !value.connected { voiceEnding = false }
            return
        }
        if value.connected && voiceStarting {
            voiceTimeout?.cancel(); voiceStarting = false
            showConnection = false; notice = nil
        }
        if value.connected && !voiceConnected {
            webView.evaluateJavaScript("window.__dotGlass?.resetCall()", completionHandler: nil)
        }
        if value.connected && value.level > 0.025 && !observedInboundAudio {
            observedInboundAudio = true
            callLog.notice("Inbound audio received")
        }
        voiceConnected = value.connected
        voiceLevel = min(1, max(0, value.level.isFinite ? value.level : 0))
        _ = speechActivity.update(connected: value.connected, level: voiceLevel)
        voiceMeterAvailable = value.meterAvailable
        microphoneMuted = value.connected && ((value.muted ?? false) || webView.microphoneCaptureState == .muted)
    }
}

final class DotScriptHandler: NSObject, WKScriptMessageHandler {
    weak var owner: DotConnection?
    init(owner: DotConnection) { self.owner = owner }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "chatgpt.com",
              [0, 443].contains(message.frameInfo.securityOrigin.port),
              JSONSerialization.isValidJSONObject(message.body),
              let data = try? JSONSerialization.data(withJSONObject: message.body), data.count <= 4_000_000 else { return }
        if let voice = try? JSONDecoder().decode(DotVoiceSnapshot.self, from: data) {
            Task { @MainActor [weak self] in self?.owner?.receiveVoice(voice) }
        } else if let snapshot = try? JSONDecoder().decode(DotSnapshot.self, from: data) {
            Task { @MainActor [weak self] in self?.owner?.receive(snapshot) }
        }
    }
}
