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
    private var automaticHandoff = true
    @ObservationIgnored lazy var recovery = DotRecovery(connection: self)
    var deliveryUncertain = false
    var connectionState: DotConnectionState {
        if needsSetup { return .setup }
        if showConnection { return ready ? .ready : .authentication }
        if deliveryUncertain { return .deliveryAttention }
        if ready { return .ready }
        if loading { return recovery.attempts > 0 ? .reconnecting : .connecting }
        return .paused
    }

    func inspectConnection() { automaticHandoff = false; showConnection = true }
    func showGlassConversation() { automaticHandoff = true; showConnection = false }
    private var requestedSignIn = false
    var voiceStarting = false
    private var voiceEnding = false
    @ObservationIgnored private var callGeneration = UUID()
    private var voiceTimeout: Task<Void, Never>?
    private var voiceHeartbeat: Task<Void, Never>?
    private var visiblePanels = Set<UUID>()
    var isPanelVisible: Bool { !visiblePanels.isEmpty }
    private var idleUnload: Task<Void, Never>?
    var voiceConnected = false
    var voiceLevel = 0.0
    private var speechActivity = DotSpeechActivity()
    var voiceSpeaking: Bool { speechActivity.isSpeaking }
    var voiceMeterAvailable = false
    var microphoneMuted = false
    var microphoneChangePending = false
    private(set) var webView: WKWebView!
    var authPopup: WKWebView?
    private(set) var conversation = ""
    private var timeout: Task<Void, Never>?
    private var hydrated = false
    private var submittedDraft: String?
    private var handler: DotScriptHandler!
    private let defaults: UserDefaults
    private let websiteDataStore: WKWebsiteDataStore
    var directory = DotDirectory()
    private var drafts: [String: String] = [:]
    var targetConversation: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "1D9FD40A-8C44-4936-BFAD-08608F59DA71")!)
        super.init()
        if let data = defaults.data(forKey: "dot-glass.directory"),
           let saved = try? JSONDecoder().decode(DotDirectory.self, from: data) {
            for profile in saved.profiles { directory.remember(url: profile.url, name: profile.name) }
        }
        let config = WKWebViewConfiguration()
        // Dedicated persistent session: no dependency on Tracker or the prototype's cookies.
        config.websiteDataStore = websiteDataStore
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
    @ObservationIgnored private var tickGeneration = UUID()
    @ObservationIgnored private var lastTranscriptTick = Date.distantPast

    /// A slow visible-panel fallback refreshes the transcript; active calls own
    /// a cancellable audio sampling task. Hidden panels do not read messages.
    func tick() {
        guard !visiblePanels.isEmpty || voiceStarting || voiceConnected else { return }
        recovery.tick()
        if tickInFlight && Date().timeIntervalSince(lastTick) > 5 { tickInFlight = false; tickGeneration = UUID() }
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
        let refreshTranscript = !visiblePanels.isEmpty && now.timeIntervalSince(lastTranscriptTick) >= 30
        guard refreshTranscript || voiceStarting || voiceConnected else { return }
        if textActivityUntil != .distantPast && now >= textActivityUntil { textActivityUntil = .distantPast }
        lastTick = now; tickInFlight = true
        tickGeneration = UUID(); let generation = tickGeneration
        if refreshTranscript { lastTranscriptTick = now }
        webView.callAsyncJavaScript("if (refreshTranscript) window.__dotGlass?.refresh(); if (sampleVoice) await window.__dotGlassVoice?.sample();", arguments: ["refreshTranscript": refreshTranscript, "sampleVoice": voiceStarting || voiceConnected], in: nil, in: .page) { [weak self] _ in
            Task { @MainActor in if self?.tickGeneration == generation { self?.tickInFlight = false } }
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
    var canSend: Bool { ready && !deliveryUncertain && pendingToken == nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.utf16.count <= 12000 }

    func connect() {
        // An auth provider may own this view while an emailed code is fetched.
        // Only an empty or deliberately unloaded page needs its saved Dot loaded.
        guard !webView.isLoading, !signInInProgress,
              webView.url == nil || webView.url?.absoluteString == "about:blank" else { return }
        _ = recovery
        loadSaved()
    }

    func loadSaved() {
        guard defaults.bool(forKey: "dot-glass.onboardingComplete"),
              let url = DotURLPolicy.conversation(defaults.string(forKey: "dot-glass.conversationURL")) else {
            needsSetup = true; loading = false
            return
        }
        ready = false; loading = true; notice = nil
        completingSetup = true; automaticHandoff = true
        showConnection = false
        recovery.begin()
        webView.load(URLRequest(url: url))
    }

    func beginSetup() {
        guard !voiceConnected && !voiceStarting && pendingToken == nil else { notice = "End your call or check message delivery before signing in again."; return }
        ready = false
        openedDotAfterLogin = false
        needsSetup = false; completingSetup = true; automaticHandoff = true; requestedSignIn = true
        showConnection = true; loading = true; notice = nil
        recovery.begin()
        webView.load(URLRequest(url: DotURLPolicy.home))
    }

    func finishTour() {
        defaults.set(true, forKey: "dot-glass.tourComplete")
        showTour = false
        if !ready && !needsSetup { notice = "Your Dot is still connecting. You can stay here while we reconnect."; recovery.begin() }
    }

    func cancelSetup() {
        stopAudio()
        requestedSignIn = false; completingSetup = false
        recovery.cancel()
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
        guard pendingToken == nil else {
            notice = "Check the conversation before reconnecting; your last message may have been sent."
            deliveryUncertain = true; showConnection = false
            return
        }
        if webView.url == nil && conversation.isEmpty { beginSetup(); return }
        automaticHandoff = true
        hydrated = false; ready = false; loading = true; notice = nil
        recovery.begin()
        showConnection = false
        webView.load(URLRequest(url: DotURLPolicy.conversation(conversation) ?? DotURLPolicy.dotHome))
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
        recovery.begin()
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

    @ObservationIgnored private var lastConnectionDiagnostic = ""
    func receive(_ snapshot: DotSnapshot) {
        guard !needsSetup else { return }
        let reason = snapshot.diagnostic ?? "adapter-snapshot"
        if !showConnection && !snapshot.ready {
            if reason == "sign-in-required" { notice = "Your ChatGPT session expired. Sign in again to reconnect; your draft is safe." }
            else if reason == "offline" { notice = "You’re offline. Your conversation and draft are safe; we’ll retry the connection." }
            else if reason == "composer-not-found" { notice = "Your Dot’s controls are still loading. We’ll retry without leaving the glass panel." }
        } else if snapshot.ready && pendingToken == nil && !voiceStarting, let notice,
                  ["Your ChatGPT session", "You’re offline", "Your Dot’s controls", "We couldn’t reconnect", "ChatGPT couldn’t load", "The connection paused"].contains(where: notice.hasPrefix) { self.notice = nil }
        if ["dot-route-unrecognized", "composer-not-found", "offline", "ready", "adapter-snapshot"].contains(reason), reason != lastConnectionDiagnostic {
            lastConnectionDiagnostic = reason
            callLog.notice("Connection route: canonical=\(DotURLPolicy.conversation(snapshot.conversation) != nil) home=\(URL(string: snapshot.conversation)?.path == "/dots/home") setup=\(self.completingSetup) automatic=\(self.automaticHandoff)")
            callLog.notice("Connection adapter: \(reason, privacy: .public); rows=\(snapshot.messages.count) ready=\(snapshot.ready)")
        }
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
        if !incoming.isEmpty && incoming != conversation {
            if targetConversation == nil { drafts[conversation] = draft; draft = drafts[incoming] ?? "" }
            targetConversation = nil
            hydrated = false
            if pendingToken != nil { notice = "The conversation changed. Check delivery before sending again." }
            pendingToken = nil; timeout?.cancel(); deliveryUncertain = false
            conversation = incoming
        }
        guard !incoming.isEmpty else {
            ready = false; typing = false; mediaPlaying = false
            recovery.beginIfNeeded()
            if requestedSignIn { openSignInIfNeeded() }
            return
        }
        if defaults.string(forKey: "dot-glass.conversationURL") != incoming {
            defaults.set(incoming, forKey: "dot-glass.conversationURL")
        }
        let previousProfiles = directory.profiles
        directory.remember(url: incoming, name: snapshot.name)
        if directory.profiles != previousProfiles { saveDirectory() }
        name = directory.profiles.first(where: { $0.url == incoming })?.name ?? String(snapshot.name.prefix(80))
        ready = snapshot.ready; loading = !snapshot.ready
        if ready { recovery.succeeded() } else { recovery.beginIfNeeded() }
        if ready && (completingSetup || automaticHandoff) && pendingToken == nil {
            if completingSetup { showTour = !defaults.bool(forKey: "dot-glass.tourComplete") }
            defaults.set(true, forKey: "dot-glass.onboardingComplete")
            requestedSignIn = false; completingSetup = false; needsSetup = false; showConnection = false
        }
        typing = snapshot.typing; mediaPlaying = snapshot.mediaPlaying
        if hydrated, let latest = snapshot.messages.last,
           messages.first(where: { $0.id == latest.id })?.text != latest.text {
            textActivityPhase = latest.isMine ? .sending : .thinking
            textActivityUntil = Date().addingTimeInterval(2)
        }
        messages = snapshot.messages
        if let token = pendingToken, snapshot.acknowledgement == token {
            pendingToken = nil; timeout?.cancel(); deliveryUncertain = false
            if draft == submittedDraft { draft = "" }
            submittedDraft = nil; notice = nil
        }
        hydrated = true
    }

    func send() {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines), token = UUID().uuidString
        pendingToken = token; submittedDraft = draft; notice = nil; deliveryUncertain = false
        let expected = conversation
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.pendingToken == token else { return }
            self.notice = "Delivery is not confirmed yet. We will not send it again automatically."
            self.deliveryUncertain = true; self.showConnection = false
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
                self.notice = "Your message could not be confirmed. Your draft is preserved; reconnect or check delivery in your browser."
                self.deliveryUncertain = true; self.showConnection = false
            }
        }
    }

    func confirmDeliveryChecked() {
        pendingToken = nil; timeout?.cancel(); submittedDraft = nil; notice = nil; deliveryUncertain = false
        // Reload also resets the browser adapter's pending token; user reviewed delivery first.
        reload()
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
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
        callGeneration = UUID(); let generation = callGeneration
        voiceHeartbeat?.cancel()
        voiceHeartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
                guard self?.voiceStarting == true || self?.voiceConnected == true else { break }
                self?.tick()
            }
        }
        voiceTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled, let self, self.voiceStarting, self.callGeneration == generation else { return }
                    self.callLog.notice("Call connection timed out")
                    self.stopAudio()
                    self.notice = "The call didn’t connect. Check microphone access and try again."
                }
        webView.callAsyncJavaScript("return window.__dotGlass?.startCall(room) ?? 'not-ready';",
            arguments: ["room": conversation], in: nil, in: .page) { [weak self] result in
            Task { @MainActor in
                guard let self, self.voiceStarting, self.callGeneration == generation else { return }
                guard case .success(let value) = result, value as? String == "started" else {
                    self.voiceTimeout?.cancel(); self.voiceStarting = false
                    if case .success(let value) = result, let status = value as? String,
                       ["not-ready", "pending", "call-unavailable"].contains(status) {
                        self.callLog.notice("Call control status: \(status, privacy: .public)")
                    } else if case .failure(let error) = result {
                        self.callLog.notice("Call script error code: \((error as NSError).code)")
                    } else { self.callLog.notice("Unexpected call control result") }
                    self.notice = "The call couldn’t start. Reconnect your Dot, then try again."
                    return
                }

            }
        }
    }

    func toggleMicrophone() {
        guard voiceConnected, !microphoneChangePending else { return }
        microphoneChangePending = true
        let generation = callGeneration
        webView.callAsyncJavaScript("return window.__dotGlass?.setMuted(muted, room) ?? 'unavailable';",
            arguments: ["muted": !microphoneMuted, "room": conversation], in: nil, in: .page) { [weak self] result in
            Task { @MainActor in
                guard let self, self.callGeneration == generation, self.voiceConnected else { return }
                self.microphoneChangePending = false
                if case .success(let value) = result, let status = value as? String,
                   ["changed", "unchanged"].contains(status) {
                    self.notice = nil
                    self.webView.callAsyncJavaScript("await window.__dotGlassVoice?.sample();", arguments: [:], in: nil, in: .page, completionHandler: nil)
                } else {
                    self.notice = "The microphone control did not respond. Try again, or end the call and check microphone access."
                }
            }
        }
    }

    func panelAppeared(_ identity: UUID) {
        idleUnload?.cancel(); idleUnload = nil
        visiblePanels.insert(identity)
        connect()
        webView.evaluateJavaScript("window.__dotGlass?.setActive(true)", completionHandler: nil)
        callLog.notice("Conversation panel appeared")
    }

    func panelDisappeared(_ identity: UUID) {
        visiblePanels.remove(identity)
        if visiblePanels.isEmpty {
            webView.evaluateJavaScript("window.__dotGlass?.setActive(false)", completionHandler: nil)
            scheduleIdleUnload()
        }
        // The plugin owns the call. DockDoor may dismiss its panel on focus
        // changes; hiding presentation must never revoke active microphone use.
        callLog.notice("Conversation panel hidden; active call retained")
    }

    private func scheduleIdleUnload() {
        idleUnload?.cancel()
        idleUnload = Task { [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard !Task.isCancelled, let self, self.visiblePanels.isEmpty,
                  !self.voiceStarting, !self.voiceConnected, self.pendingToken == nil,
                  !self.webView.isLoading, !self.signInInProgress else { return }
            self.webView.stopLoading()
            self.webView.loadHTMLString("", baseURL: nil)
            self.ready = false; self.loading = false; self.typing = false
        }
    }

    private var signInInProgress: Bool {
        if authPopup != nil || requestedSignIn || (completingSetup && showConnection) { return true }
        guard let url = webView.url else { return false }
        return url.absoluteString != "about:blank" && url.host != "chatgpt.com"
    }

    func signOut() {
        guard !voiceStarting, !voiceConnected, pendingToken == nil else {
            notice = "End your call or check message delivery before signing out."
            return
        }
        idleUnload?.cancel(); recovery.cancel()
        authPopup = nil
        webView.stopLoading(); webView.loadHTMLString("", baseURL: nil)
        websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.defaults.removeObject(forKey: "dot-glass.onboardingComplete")
                self.defaults.removeObject(forKey: "dot-glass.conversationURL")
                self.defaults.removeObject(forKey: "dot-glass.directory")
                self.directory = DotDirectory(); self.conversation = ""; self.messages = []
                self.ready = false; self.loading = false; self.needsSetup = true
                self.showConnection = false; self.showTour = false; self.notice = nil
            }
        }
    }

    func stopAudio() {
        callLog.notice("Stopping call: starting=\(self.voiceStarting) connected=\(self.voiceConnected)")
        callGeneration = UUID()
        let endingGeneration = callGeneration
        voiceEnding = true
        let wasStarting = voiceStarting
        voiceTimeout?.cancel(); voiceHeartbeat?.cancel(); voiceStarting = false
        let hadCapture = webView.microphoneCaptureState != .none
        webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        webView.pauseAllMediaPlayback(completionHandler: nil)
        if voiceConnected || hadCapture || wasStarting {
            webView.callAsyncJavaScript("return window.__dotGlass?.endCall(room) ?? false;", arguments: ["room": conversation], in: nil, in: .page) { [weak self] result in
                Task { @MainActor in
                    guard let self, self.callGeneration == endingGeneration else { return }
                    if case .success(let ended) = result, ended as? Bool == true { return }
                    self.notice = "The page’s End call control did not respond. Reloading ChatGPT to end the call."
                    self.ready = false; self.loading = true
                    self.webView.reload()
                }
            }
        }
        voiceConnected = false; voiceLevel = 0; _ = speechActivity.update(connected: false, level: 0)
        microphoneMuted = false; microphoneChangePending = false
        if visiblePanels.isEmpty { scheduleIdleUnload() }
    }
    func receiveVoice(_ value: DotVoiceSnapshot) {
        if voiceConnected && !value.connected && !voiceEnding { notice = "The call ended or the connection dropped. Your conversation is still here; start a new call when ready." }
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
