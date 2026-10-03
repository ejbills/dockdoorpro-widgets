import AppKit
import WebKit

@main
struct ViewportChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 600))
        let fixture = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>@media(max-width: 1000px){#call{display:none}}</style></head>
        <body><button id="call" aria-label="Start call">Call</button></body></html>
        """
        view.loadHTMLString(fixture, baseURL: nil)
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(100))
            if !view.isLoading, (try? await view.evaluateJavaScript("document.readyState")) as? String == "complete" { break }
        }
        let probe = "({width:innerWidth,callVisible:document.getElementById('call').getClientRects().length>0})"
        let narrow = try await view.evaluateJavaScript(probe) as! [String: Any]
        precondition(narrow["callVisible"] as? Bool == false, "Fixture must reproduce the narrow-layout failure")
        let scale = DotWebViewport.scale(width: 440, isConversation: true)
        view.frame.size = NSSize(width: 440 / scale, height: 600 / scale)
        var wide: [String: Any] = [:]
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            wide = try await view.evaluateJavaScript(probe) as! [String: Any]
            if wide["callVisible"] as? Bool == true { break }
        }
        precondition(wide["callVisible"] as? Bool == true, "Desktop viewport must expose the real responsive call control")
        precondition((wide["width"] as? Double ?? 0) >= 1000)
        view.frame.size = NSSize(width: 440, height: 600)
        precondition(DotWebViewport.scale(width: 440, isConversation: false) == 1)
        precondition(view.pageZoom == 1, "WebKit must retain normal CSS and message metrics")
        print("WebKit viewport checks passed: narrow control hidden, desktop control visible, sign-in scale restored")
    }
}
