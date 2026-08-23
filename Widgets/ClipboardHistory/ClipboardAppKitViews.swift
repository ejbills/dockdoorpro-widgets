import AppKit
import SwiftUI
import PDFKit
import AVKit
import DockDoorWidgetSDK

// MARK: - Native macOS Cursor Rect View

struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeCursorNSView {
        ResizeCursorNSView()
    }

    func updateNSView(_ nsView: ResizeCursorNSView, context: Context) {}
}

final class ResizeCursorNSView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}

// MARK: - Global Key Handling for Panel Navigation

struct KeyHandlingView: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void
    let isEditing: Bool

    func makeNSView(context: Context) -> KeyHandlingNSView {
        let v = KeyHandlingNSView()
        v.onUp = onUp
        v.onDown = onDown
        v.onReturn = onReturn
        v.onEscape = onEscape
        v.isEditing = isEditing
        return v
    }

    func updateNSView(_ nsView: KeyHandlingNSView, context: Context) {
        nsView.onUp = onUp
        nsView.onDown = onDown
        nsView.onReturn = onReturn
        nsView.onEscape = onEscape
        nsView.isEditing = isEditing
    }
}

final class KeyHandlingNSView: NSView {
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var isEditing: Bool = false
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let win = window, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak win] event in
                guard let self = self, let panelWindow = win else { return event }
                guard event.window == panelWindow else { return event }
                if self.isEditing { return event }

                switch event.keyCode {
                case 126: // Up arrow
                    self.onUp?()
                    return nil
                case 125: // Down arrow
                    self.onDown?()
                    return nil
                case 36:  // Return key
                    self.onReturn?()
                    return nil
                case 53:  // Escape
                    self.onEscape?()
                    return nil
                default:
                    return event
                }
            }
        } else if window == nil, let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    deinit {
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
    }
}

// MARK: - NSPanel Sentinel

struct NSPanelSentinel: NSViewRepresentable {
    let context: PanelWindowContext

    func makeNSView(context ctx: Context) -> SentinelView {
        let view = SentinelView(context: context)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ view: SentinelView, context ctx: Context) {}

    final class SentinelView: NSView {
        let context: PanelWindowContext
        init(context: PanelWindowContext) {
            self.context = context
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            context.window = window
        }
    }
}

// MARK: - PDF Preview

struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}
}

// MARK: - Text File Preview

struct TextFilePreview: View {
    let url: URL
    @State private var content: String?

    var body: some View {
        Group {
            if let content {
                ScrollView {
                    Text(content)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
               data.count < 200_000,
               let text = String(data: data, encoding: .utf8) {
                content = text
            } else {
                content = ""
            }
        }
    }
}
