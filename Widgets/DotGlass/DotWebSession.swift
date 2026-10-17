import AppKit
import SwiftUI
import WebKit

extension DotConnection: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if DotURLPolicy.allowsNavigation(url) { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated && ["https", "http"].contains(url.scheme) {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        loading = true
        ready = false
        recovery.begin()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        loading = false
        if let targetConversation, webView.url?.absoluteString != targetConversation {
            self.targetConversation = nil
            notice = "ChatGPT opened a different page. Check access to the selected Dot."
            showConnection = false
        }
        // Navigation is transport; only explicit sign-in or Advanced actions expose it.
        webView.evaluateJavaScript(DotPageAdapter.source, completionHandler: nil)
        webView.evaluateJavaScript("window.__dotGlass?.setActive(\(isPanelVisible));", completionHandler: nil)
        openSignInIfNeeded()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        fail(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        fail(error)
    }
    private func fail(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false; ready = false; typing = false; mediaPlaying = false
        notice = "ChatGPT couldn’t load. Check your connection, then reconnect."
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        loading = false; ready = false; typing = false; mediaPlaying = false
        notice = "The connection paused. Reconnect to continue; your draft is still here."
        stopAudio()
        recovery.begin()
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url, DotURLPolicy.allowsNavigation(url) else { return nil }
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        authPopup = popup
        return popup
    }
    func webViewDidClose(_ webView: WKWebView) {
        if authPopup === webView { authPopup = nil }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard webView === self.webView else { decisionHandler(.deny); return }
        callLog.notice("WebKit requested capture: starting=\(self.voiceStarting) mainFrame=\(frame.isMainFrame) microphone=\(type == .microphone)")
        guard voiceStarting, frame.isMainFrame, origin.protocol == "https", origin.host == "chatgpt.com", [0, 443].contains(origin.port), type == .microphone,
              Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            notice = "This host cannot start a voice call. Open the conversation in your browser for calls."
            decisionHandler(.deny); return
        }
        decisionHandler(.prompt)
    }
}

enum DotWebViewport {
    // Keep CSS pixels and virtualized message measurements at their normal size.
    // Scale the rendered view, rather than WebKit page zoom, into the host panel.
    static func scale(width: CGFloat, isConversation: Bool) -> CGFloat {
        guard isConversation, width > 0 else { return 1 }
        return min(1, max(0.25, width / 1100))
    }
}

@MainActor
struct DotWebSession: View {
    @Bindable var connection: DotConnection
    var body: some View {
        GeometryReader { geometry in
            let scale = DotWebViewport.scale(width: geometry.size.width,
                                             isConversation: !connection.conversation.isEmpty)
            Group {
                if let popup = connection.authPopup {
                    DotWebContent(webView: popup)
                } else {
                    DotWebContent(webView: connection.webView)
                }
            }
                .frame(width: geometry.size.width / scale, height: geometry.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .clipped()
        }
    }
}

@MainActor
private struct DotWebContent: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {
        if view.pageZoom != 1 { view.pageZoom = 1 }
    }
}
