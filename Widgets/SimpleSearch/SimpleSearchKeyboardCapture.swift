import SwiftUI

final class SimpleSearchKeyboardCapture: NSObject, NSTextFieldDelegate {
    private var panel: KeyboardCapturePanel?
    private var field: NSTextField?
    private var onChange: ((String) -> Void)?
    private var onSubmit: (() -> Void)?
    private var onCancel: (() -> Void)?
    private var focusTask: Task<Void, Never>?

    func start(
        initialText: String,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        stop()

        self.onChange = onChange
        self.onSubmit = onSubmit
        self.onCancel = onCancel

        focusTask?.cancel()

        let textField = NSTextField()
        textField.stringValue = initialText
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.alphaValue = 0.01
        textField.delegate = self

        let captureOrigin = Self.captureOrigin()
        let capturePanel = KeyboardCapturePanel(
            contentRect: NSRect(x: captureOrigin.x, y: captureOrigin.y, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        capturePanel.isOpaque = false
        capturePanel.backgroundColor = .clear
        capturePanel.hasShadow = false
        capturePanel.level = .floating
        capturePanel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        capturePanel.contentView = textField

        panel = capturePanel
        field = textField

        NSApp.activate(ignoringOtherApps: true)
        capturePanel.makeKeyAndOrderFront(nil)
        focus()

        focusTask = Task { @MainActor in
            for delay in [50, 150, 300] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                focus()
            }
        }
    }

    func stop() {
        focusTask?.cancel()
        focusTask = nil

        field?.delegate = nil
        field?.target = nil
        field?.action = nil

        if let panel {
            panel.makeFirstResponder(nil)
            panel.contentView = nil
            panel.orderOut(nil)
            panel.close()
        }

        panel = nil
        field = nil
        onChange = nil
        onSubmit = nil
        onCancel = nil
    }

    private func focus() {
        guard let panel, let field else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.count, length: 0)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        onChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            onSubmit?()
            return true
        }

        if selector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
            return true
        }

        return false
    }

    deinit {
        stop()
    }

    private static func captureOrigin() -> CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: -10_000, y: -10_000)
        }

        return CGPoint(x: screen.frame.minX - 100, y: screen.frame.minY - 100)
    }
}

private final class KeyboardCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
