import AppKit
import DockDoorWidgetSDK
import QuartzCore
import SwiftUI

// MARK: - Layout constants

private enum StackLayout {
    static let stackWidth: CGFloat = 320
    static let gridWidth: CGFloat = 380
    static let rowHeight: CGFloat = 54
    static let rowVisualHeight: CGFloat = 48
    /// Space reserved at the top for the open-folder button.
    static let topZone: CGFloat = 50
    /// Gap between the dock/widget and the first item.
    static let bottomInset: CGFloat = 18
    static let gridCellHeight: CGFloat = 92
    static let gridMaxHeight: CGFloat = 430
}

// MARK: - Presentation state

/// Drives the open / close animation. Shared between the window controller
/// (which decides when to open/close) and the SwiftUI stack/grid views.
final class FanPresentation: ObservableObject {
    @Published var expanded = false
}

// MARK: - Floating stack window controller

/// Presents the folder as a borderless, transparent floating panel anchored to
/// the widget. The window is sized to its content so the open-folder button
/// sits just above the items, and it follows the widget when the dock moves.
final class FanWindowController: NSObject {
    private let store: FolderStore
    private let anchor: WidgetAnchor
    private var panel: NSPanel?
    private var hosting: NSHostingView<FloatingStackView>?
    private var presentation = FanPresentation()
    private var globalMonitor: Any?
    private var closeWork: DispatchWorkItem?
    private var displayLink: CADisplayLink?
    private var occlusionObserver: Any?
    private var isOpen = false

    private var panelSize = NSSize(width: StackLayout.stackWidth, height: 200)

    init(store: FolderStore, anchor: WidgetAnchor) {
        self.store = store
        self.anchor = anchor
    }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        isOpen = true
        closeWork?.cancel()
        closeWork = nil

        // Scan the folder off the main thread, then present once the contents are
        // known (the window is sized to the item count).
        store.refresh { [weak self] in
            guard let self, self.isOpen else { return }
            self.present()
        }
    }

    private func present() {
        let anchorFrame = currentAnchorFrame()
        panelSize = desiredSize(for: anchorFrame)

        if panel == nil {
            presentation = FanPresentation()
            let root = FloatingStackView(
                store: store,
                presentation: presentation,
                requestClose: { [weak self] in self?.close() }
            )
            let hostingView = NSHostingView(rootView: root)
            hostingView.frame = NSRect(origin: .zero, size: panelSize)

            let newPanel = NSPanel(
                contentRect: NSRect(origin: .zero, size: panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isFloatingPanel = true
            newPanel.level = .popUpMenu
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = false
            newPanel.hidesOnDeactivate = false
            newPanel.contentView = hostingView

            panel = newPanel
            hosting = hostingView
            presentation.expanded = false

            // Pause the follow loop while the panel is hidden/occluded.
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: newPanel,
                queue: .main
            ) { [weak self] _ in
                self?.updateFollowPausedState()
            }
        }

        guard let panel else { return }
        panel.setContentSize(panelSize)
        hosting?.frame = NSRect(origin: .zero, size: panelSize)
        panel.setFrameOrigin(origin(for: anchorFrame, size: panelSize))
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        // Follow the widget if the dock moves while open.
        anchor.onChange = { [weak self] frame in
            guard let self, let panel = self.panel else { return }
            panel.setFrameOrigin(self.origin(for: frame, size: panel.frame.size))
        }

        installGlobalMonitor()
        startFollowing()

        // Animate open on the next runloop tick (from the collapsed state).
        DispatchQueue.main.async { [weak self] in
            self?.presentation.expanded = true
        }
    }

    func close() {
        isOpen = false
        guard let panel else { return }
        removeGlobalMonitor()
        stopFollowing()
        anchor.onChange = nil
        presentation.expanded = false

        let work = DispatchWorkItem { [weak self] in
            panel.orderOut(nil)
            if let observer = self?.occlusionObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self?.occlusionObserver = nil
            self?.panel = nil
            self?.hosting = nil
            self?.closeWork = nil
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: Sizing

    private func screen(for widgetFrame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(widgetFrame) }
            ?? NSScreen.screens.first { $0.frame.contains(CGPoint(x: widgetFrame.midX, y: widgetFrame.midY)) }
            ?? NSScreen.main
    }

    /// Vertical room available above the widget on its screen.
    private func availableHeight(above widgetFrame: CGRect) -> CGFloat {
        let top = screen(for: widgetFrame)?.visibleFrame.maxY ?? (widgetFrame.maxY + 640)
        return max(180, top - widgetFrame.maxY - 8)
    }

    /// Sizes the window to fit the content so the button hugs the items and the
    /// item-count slider has a visible effect.
    private func desiredSize(for widgetFrame: CGRect) -> NSSize {
        let avail = availableHeight(above: widgetFrame)

        switch store.displayStyle {
        case .stack:
            let usable = avail - StackLayout.topZone - StackLayout.bottomInset
            let maxFit = max(1, Int(usable / StackLayout.rowHeight))
            let count = min(store.stackedEntries.count, maxFit)
            let height = StackLayout.topZone + CGFloat(count) * StackLayout.rowHeight + StackLayout.bottomInset
            return NSSize(width: StackLayout.stackWidth, height: height)

        case .grid:
            let columns = max(1, Int((StackLayout.gridWidth - 28) / StackLayout.gridCellHeight))
            let rows = max(1, Int(ceil(Double(store.entries.count) / Double(columns))))
            let contentHeight = CGFloat(rows) * StackLayout.gridCellHeight + 28
            let cap = min(StackLayout.gridMaxHeight, avail - StackLayout.topZone - StackLayout.bottomInset)
            let gridHeight = min(contentHeight, cap)
            let height = StackLayout.topZone + gridHeight + StackLayout.bottomInset
            return NSSize(width: StackLayout.gridWidth, height: height)
        }
    }

    // MARK: Positioning

    private func currentAnchorFrame() -> CGRect {
        if let frame = anchor.screenFrame { return frame }
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y, width: 0, height: 0)
    }

    /// Places the panel's bottom-center at the widget's top-center, clamped to
    /// the visible screen.
    private func origin(for widgetFrame: CGRect, size: NSSize) -> NSPoint {
        var origin = NSPoint(x: widgetFrame.midX - size.width / 2, y: widgetFrame.maxY)
        if let visible = screen(for: widgetFrame)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        return origin
    }

    // MARK: Monitor (other applications only)

    private func installGlobalMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.close()
        }
    }

    private func removeGlobalMonitor() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
    }

    // MARK: Follow the widget

    /// Re-measures the widget's position once per display refresh so the window
    /// tracks the dock even during animations that don't post window move/resize
    /// events. A `CADisplayLink` is more power-friendly than a free-running timer:
    /// it's coalesced with the compositor and pauses automatically when the
    /// display isn't refreshing (sleep, ProMotion ramp-down). Paired with the
    /// dedupe in ``WidgetAnchor``, idle ticks do almost no work.
    private func startFollowing() {
        stopFollowing()
        guard let panel else { return }
        let link = panel.displayLink(target: self, selector: #selector(followTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func followTick() {
        anchor.refresh?()
    }

    private func stopFollowing() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Pauses the follow loop when the panel is fully occluded (and resumes it
    /// when visible again) so we don't poll for a window nobody can see.
    private func updateFollowPausedState() {
        guard let panel else { return }
        displayLink?.isPaused = !panel.occlusionState.contains(.visible)
    }
}

// MARK: - Anchor tracker

/// Invisible helper placed behind the widget content. Reports the widget's
/// screen frame to ``WidgetAnchor`` and updates it whenever the host window
/// (the dock) moves or resizes.
struct AnchorTracker: NSViewRepresentable {
    let anchor: WidgetAnchor

    func makeNSView(context: Context) -> AnchorTrackingView { AnchorTrackingView(anchor: anchor) }
    func updateNSView(_ nsView: AnchorTrackingView, context: Context) { nsView.report() }
}

final class AnchorTrackingView: NSView {
    private let anchor: WidgetAnchor

    init(anchor: WidgetAnchor) {
        self.anchor = anchor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        anchor.refresh = { [weak self] in self?.report() }
        if let window {
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(report), name: NSWindow.didMoveNotification, object: window)
            nc.addObserver(self, selector: #selector(report), name: NSWindow.didResizeNotification, object: window)
        }
        report()
    }

    @objc func report() {
        guard let window else { return }
        let inWindow = convert(bounds, to: nil)
        anchor.update(window.convertToScreen(inWindow))
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

// MARK: - Floating content

/// Transparent overlay that presents the folder's files. No background box in
/// Stack mode; a material container in Grid mode.
struct FloatingStackView: View {
    var store: FolderStore
    @ObservedObject var presentation: FanPresentation
    let requestClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear

            if store.entries.isEmpty {
                emptyState
            } else {
                switch store.displayStyle {
                case .grid:
                    GridStackView(store: store, expanded: presentation.expanded, onActivate: activate)
                        .padding(.top, StackLayout.topZone)
                        .padding(.bottom, StackLayout.bottomInset)
                        .padding(.horizontal, 10)
                case .stack:
                    VerticalStackView(store: store, expanded: presentation.expanded, onActivate: activate)
                }
            }
        }
        .overlay(alignment: .top) {
            OpenFolderButton(name: store.folderName) {
                store.openFolder()
                requestClose()
            }
            .padding(.top, 12)
            .opacity(presentation.expanded ? 1 : 0)
            .offset(y: presentation.expanded ? 0 : -8)
            .animation(
                presentation.expanded
                    ? .spring(response: 0.45, dampingFraction: 0.82).delay(0.04)
                    : .easeIn(duration: 0.18),
                value: presentation.expanded
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activate(_ entry: FileEntry, _ revealOverride: Bool) {
        store.handleClick(entry, revealOverride: revealOverride)
        requestClose()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("\(store.folderName) is empty")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 30)
        .scaleEffect(presentation.expanded ? 1 : 0.6)
        .opacity(presentation.expanded ? 1 : 0)
        .animation(presentation.expanded ? .spring(response: 0.45, dampingFraction: 0.8) : .easeIn(duration: 0.2),
                   value: presentation.expanded)
    }
}

// MARK: - Vertical stack layout

/// A vertical column of file icons that rises out of the dock, each with its
/// name shown to the right in a dark pill, mirroring the native Downloads stack.
private struct VerticalStackView: View {
    var store: FolderStore
    let expanded: Bool
    let onActivate: (FileEntry, Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            let maxRows = max(1, Int((geo.size.height - StackLayout.bottomInset - StackLayout.topZone) / StackLayout.rowHeight))
            let entries = Array(store.stackedEntries.prefix(maxRows))
            let count = entries.count

            ZStack(alignment: .topLeading) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let y = geo.size.height - StackLayout.bottomInset - CGFloat(index) * StackLayout.rowHeight - StackLayout.rowHeight / 2

                    StackRow(entry: entry, width: geo.size.width) { revealOverride in
                        onActivate(entry, revealOverride)
                    }
                    .position(x: geo.size.width / 2, y: y)
                    .offset(y: expanded ? 0 : CGFloat(index + 1) * 22)
                    .opacity(expanded ? 1 : 0)
                    .animation(
                        expanded
                            ? .spring(response: 0.5, dampingFraction: 0.82).delay(Double(index) * 0.03)
                            : .easeIn(duration: 0.2),
                        value: expanded
                    )
                    .zIndex(Double(count - index))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct StackRow: View {
    let entry: FileEntry
    let width: CGFloat
    let onTap: (Bool) -> Void

    @State private var isHovered = false

    private let iconSize: CGFloat = 44
    private let iconLeading: CGFloat = 40
    private let labelGap: CGFloat = 10

    var body: some View {
        DraggableFileItem(
            url: entry.url,
            icon: entry.icon,
            onTap: onTap,
            onHover: { hovered in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovered } }
        ) {
            HStack(spacing: labelGap) {
                FileThumbnail(url: entry.url, pixelSize: 128)
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)

                MarqueeText(text: entry.name, maxWidth: 180, isActive: isHovered)
                    .frame(height: 16)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.black.opacity(isHovered ? 0.78 : 0.6))
                    )

                Spacer(minLength: 0)
            }
            .padding(.leading, iconLeading)
            .frame(width: width, height: StackLayout.rowVisualHeight, alignment: .leading)
            .scaleEffect(isHovered ? 1.06 : 1, anchor: .leading)
        }
        .frame(width: width, height: StackLayout.rowVisualHeight)
    }
}

// MARK: - Grid layout

/// A scrollable grid of every file in the folder, shown in a material panel
/// above the widget. Mirrors the native Downloads grid view.
private struct GridScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct GridStackView: View {
    var store: FolderStore
    let expanded: Bool
    let onActivate: (FileEntry, Bool) -> Void

    /// Single source of truth for hover so it can be cleared on scroll.
    @State private var hoveredURL: URL?

    private let columns = [GridItem(.adaptive(minimum: 82), spacing: 10)]
    private let coordinateSpace = "folderGrid"

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.entries) { entry in
                    GridCell(
                        entry: entry,
                        isHovered: hoveredURL == entry.url,
                        onHover: { hovering in
                            if hovering {
                                hoveredURL = entry.url
                            } else if hoveredURL == entry.url {
                                hoveredURL = nil
                            }
                        },
                        onTap: { revealOverride in onActivate(entry, revealOverride) }
                    )
                }
            }
            .padding(14)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: GridScrollOffsetKey.self,
                        value: proxy.frame(in: .named(coordinateSpace)).minY
                    )
                }
            )
        }
        .coordinateSpace(name: coordinateSpace)
        .onPreferenceChange(GridScrollOffsetKey.self) { _ in
            // Content moved under the cursor — drop the stale highlight.
            hoveredURL = nil
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .scaleEffect(expanded ? 1 : 0.85, anchor: .bottom)
        .opacity(expanded ? 1 : 0)
        .animation(expanded ? .spring(response: 0.42, dampingFraction: 0.84) : .easeIn(duration: 0.2),
                   value: expanded)
    }
}

private struct GridCell: View {
    let entry: FileEntry
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onTap: (Bool) -> Void

    var body: some View {
        DraggableFileItem(
            url: entry.url,
            icon: entry.icon,
            onTap: onTap,
            onHover: onHover
        ) {
            VStack(spacing: 5) {
                FileThumbnail(url: entry.url, pixelSize: 128)
                    .frame(width: 48, height: 48)

                Text(entry.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .frame(width: 74)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: StackLayout.gridCellHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.12) : .clear)
            )
        }
        .frame(height: StackLayout.gridCellHeight)
    }
}

// MARK: - Open folder button

private struct OpenFolderButton: View {
    let name: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .semibold))
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(isHovered ? 0.85 : 0.65)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 240)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Marquee text

/// Single-line text that scrolls smoothly back and forth while `isActive` (i.e.
/// the row is hovered) when it is wider than `maxWidth`, otherwise renders
/// statically. Scrolling only on hover keeps long names readable without leaving
/// a perpetual animation running for every overflowing row the whole time the
/// stack is open.
private struct MarqueeText: View {
    let text: String
    var maxWidth: CGFloat
    var isActive: Bool

    @State private var fullWidth: CGFloat = 0
    @State private var animate = false

    private var overflow: CGFloat { max(0, fullWidth - maxWidth) }
    private var isClipped: Bool { overflow > 0.5 }
    private var shouldScroll: Bool { isClipped && isActive }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { fullWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newValue in fullWidth = newValue }
                }
            )
            .offset(x: animate ? -overflow : 0)
            .frame(width: isClipped ? maxWidth : nil, alignment: .leading)
            .clipped()
            .onChange(of: shouldScroll) { _, scroll in restart(scroll) }
            .onChange(of: text) { _, _ in restart(shouldScroll) }
            .onDisappear { animate = false }
    }

    private func restart(_ scroll: Bool) {
        // Explicitly override any in-flight repeatForever animation and ease the
        // text back to its starting position. Setting `animate = false` without a
        // transaction leaves the repeating animation in control, which makes the
        // name slide back in from the right when the hover ends.
        withAnimation(.easeOut(duration: 0.2)) { animate = false }

        guard scroll else { return }
        let duration = max(2.0, Double(overflow) / 35.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard shouldScroll else { return }
            withAnimation(.linear(duration: duration).delay(0.3).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Draggable file item (AppKit drag source)

/// Hosts SwiftUI content inside an AppKit view that acts as an `NSDraggingSource`
/// offering both move and copy. Dragging a file to another same-volume Finder
/// folder therefore moves it (like the native Downloads stack), while drags to
/// apps that require a copy still work. Click and right-click are handled here
/// too, since the host view captures mouse events.
private struct DraggableFileItem<Content: View>: NSViewRepresentable {
    let url: URL
    let icon: NSImage
    let onTap: (Bool) -> Void
    let onHover: (Bool) -> Void
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> DraggableItemHostView<Content> {
        let view = DraggableItemHostView<Content>()
        view.url = url
        view.icon = icon
        view.onTap = onTap
        view.onHover = onHover
        view.setContent(content())
        return view
    }

    func updateNSView(_ nsView: DraggableItemHostView<Content>, context: Context) {
        nsView.url = url
        nsView.icon = icon
        nsView.onTap = onTap
        nsView.onHover = onHover
        nsView.setContent(content())
    }
}

private final class DraggableItemHostView<Content: View>: NSView, NSDraggingSource {
    var url: URL?
    var icon = NSImage()
    var onTap: ((Bool) -> Void)?
    var onHover: ((Bool) -> Void)?

    private var hosting: NSHostingView<Content>?
    private var mouseDownPoint: NSPoint = .zero
    private var dragging = false
    private var trackingArea: NSTrackingArea?

    func setContent(_ content: Content) {
        if let hosting {
            hosting.rootView = content
        } else {
            let host = NSHostingView(rootView: content)
            host.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: leadingAnchor),
                host.trailingAnchor.constraint(equalTo: trailingAnchor),
                host.topAnchor.constraint(equalTo: topAnchor),
                host.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            hosting = host
        }
    }

    // Capture all mouse events; the hosted SwiftUI content is display-only.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging else { return }
        let dx = event.locationInWindow.x - mouseDownPoint.x
        let dy = event.locationInWindow.y - mouseDownPoint.y
        if (dx * dx + dy * dy) > 16 {
            dragging = true
            beginDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragging = false }
        guard !dragging else { return }
        let reveal = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option)
        onTap?(reveal)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open", action: #selector(openItem), keyEquivalent: "")
        let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealItem), keyEquivalent: "")
        open.target = self
        reveal.target = self
        menu.addItem(open)
        menu.addItem(reveal)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openItem() { onTap?(false) }
    @objc private func revealItem() { onTap?(true) }

    private func beginDrag(with event: NSEvent) {
        guard let url else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let dragSize = NSSize(width: 48, height: 48)
        let local = convert(event.locationInWindow, from: nil)
        let frame = NSRect(x: local.x - dragSize.width / 2, y: local.y - dragSize.height / 2,
                           width: dragSize.width, height: dragSize.height)
        item.setDraggingFrame(frame, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.move, .copy]
    }
}
