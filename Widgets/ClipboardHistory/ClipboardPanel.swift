import AppKit
import SwiftUI
import DockDoorWidgetSDK

// MARK: - Main Panel Container

struct ClipboardPanelView: View {
    var manager: ClipboardManagerState
    let dismiss: () -> Void
    let guardedDismiss: () -> Void
    let context: PanelWindowContext

    var body: some View {
        ClipboardPanelContent(manager: manager, dismiss: dismiss)
            .background(NSPanelSentinel(context: context))
            .onHover { inside in
                if inside { context.cancelScheduledClose() }
            }
    }
}

// MARK: - Panel Content

private struct ClipboardPanelContent: View {
    var manager: ClipboardManagerState
    let dismiss: () -> Void

    @State private var selected: ClipboardItem?
    @State private var activeFilter: ClipboardFilter = .all
    @State private var searchActive = false
    @State private var searchText = ""
    @State private var isEditing = false
    @State private var editedText = ""
    @State private var showCopyToast = false
    @State private var toastDismissWorkItem: DispatchWorkItem?
    @FocusState private var isEditorFocused: Bool
    @State private var sidebarWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "ClipboardHistory_sidebarWidth")
        return saved >= 180 && saved <= 440 ? CGFloat(saved) : 280
    }()

    private var filtered: [ClipboardItem] {
        let base = manager.filteredItems(activeFilter)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }
        return base.filter { item in
            item.displayText.lowercased().contains(query)
                || item.typeLabel.lowercased().contains(query)
                || item.source.lowercased().contains(query)
        }
    }

    private var filteredPinned: [ClipboardItem] { filtered.filter { $0.isPinned } }
    private var filteredUnpinned: [ClipboardItem] { filtered.filter { !$0.isPinned } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let _ = manager.refresh()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)

                ResizableSplitDivider(
                    sidebarWidth: $sidebarWidth,
                    minWidth: 180,
                    maxWidth: 440
                )

                previewPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 620, height: 420)
            .background(
                KeyHandlingView(
                    onUp: { selectPrevious() },
                    onDown: { selectNext() },
                    onReturn: { copySelected() },
                    onEscape: {
                        if searchActive { searchActive = false }
                        else { dismiss() }
                    },
                    isEditing: isEditing
                )
            )
            .overlay(alignment: .top) {
                if showCopyToast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Copied to Clipboard!")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThickMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                    .padding(.top, 14)
                    .zIndex(100)
                }
            }
            .onAppear {
                if selected == nil {
                    selected = filtered.first ?? manager.clipboardItems.first
                }
            }
            .onChange(of: activeFilter) { _, _ in
                validateAndSyncSelection()
            }
            .onChange(of: searchText) { _, _ in
                validateAndSyncSelection()
            }
        }
    }

    private func validateAndSyncSelection() {
        if isEditing {
            isEditing = false
            editedText = ""
        }
        let items = filtered
        if let sel = selected {
            if !items.contains(where: { $0.id == sel.id }) {
                selected = items.first
            }
        } else {
            selected = items.first
        }
    }

    private func triggerCopyToast() {
        toastDismissWorkItem?.cancel()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            showCopyToast = true
        }
        let work = DispatchWorkItem {
            withAnimation {
                showCopyToast = false
            }
        }
        toastDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if searchActive {
                    SearchField(text: $searchText, isActive: $searchActive)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity),
                            removal: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity)
                        ))
                } else {
                    SegmentedFilterControl(activeFilter: $activeFilter)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85, anchor: .trailing).combined(with: .opacity),
                            removal: .scale(scale: 0.85, anchor: .trailing).combined(with: .opacity)
                        ))
                    SearchButton {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            searchActive = true
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .onChange(of: searchActive) { _, active in
                if !active {
                    searchText = ""
                }
            }

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 4) {
                            if !filteredPinned.isEmpty {
                                sectionHeader(pinned: true)
                                ForEach(filteredPinned) { item in
                                    ItemRow(item: item, isSelected: selected?.id == item.id) {
                                        handleTap(item)
                                    }
                                    .id(item.id)
                                    .transition(.opacity)
                                }
                            }
                            if !filteredUnpinned.isEmpty {
                                if !filteredPinned.isEmpty { sectionHeader(pinned: false) }
                                ForEach(filteredUnpinned) { item in
                                    ItemRow(item: item, isSelected: selected?.id == item.id) {
                                        handleTap(item)
                                    }
                                    .id(item.id)
                                    .transition(.opacity)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .animation(.easeInOut(duration: 0.18), value: activeFilter)
                        .animation(.easeInOut(duration: 0.18), value: searchText)
                    }
                    .onChange(of: selected?.id) { _, newId in
                        if let newId {
                            withAnimation(.easeOut(duration: 0.12)) {
                                scrollProxy.scrollTo(newId, anchor: .center)
                            }
                        }
                    }
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 20).allowsHitTesting(false).blendMode(.destinationOut)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.black, .clear], startPoint: .bottom, endPoint: .top)
                        .frame(height: 20).allowsHitTesting(false).blendMode(.destinationOut)
                }
                .compositingGroup()
            }

            sidebarFooter
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    manager.togglePersistence()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: manager.isPersistenceEnabled ? "internaldrive.fill" : "memorychip")
                        .font(.system(size: 10))
                    Text(manager.isPersistenceEnabled ? "Persist" : "RAM Only")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(manager.isPersistenceEnabled ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                .foregroundStyle(manager.isPersistenceEnabled ? Color.accentColor : Color.secondary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(manager.isPersistenceEnabled ? "Clipboard history survives restarts (Click to switch to RAM only)" : "Clipboard history is memory only (Click to enable disk persistence)")

            Spacer()

            ActionButton(icon: "trash.slash", style: .destructive) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    manager.clearAllItems()
                    selected = manager.pinnedItems.first
                }
            }
            .opacity(manager.unpinnedItems.isEmpty ? 0.3 : 1)
            .disabled(manager.unpinnedItems.isEmpty)
            .help("Remove all non-pinned items (\(manager.unpinnedItems.count))")
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    // MARK: - Navigation & Tap Handlers

    private func selectPrevious() {
        if isEditing {
            isEditing = false
            editedText = ""
        }
        let items = filtered
        guard !items.isEmpty else { return }
        if let sel = selected, let idx = items.firstIndex(where: { $0.id == sel.id }) {
            let prevIdx = max(0, idx - 1)
            selected = items[prevIdx]
        } else {
            selected = items.first
        }
    }

    private func selectNext() {
        if isEditing {
            isEditing = false
            editedText = ""
        }
        let items = filtered
        guard !items.isEmpty else { return }
        if let sel = selected, let idx = items.firstIndex(where: { $0.id == sel.id }) {
            let nextIdx = min(items.count - 1, idx + 1)
            selected = items[nextIdx]
        } else {
            selected = items.first
        }
    }

    private func copySelected() {
        guard let item = selected ?? filtered.first else { return }
        manager.copyItemToClipboard(item)
        triggerCopyToast()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            dismiss()
        }
    }

    private func handleTap(_ item: ClipboardItem) {
        if selected?.id == item.id {
            if !isEditing {
                copySelected()
            }
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selected = item
                isEditing = false
                editedText = ""
            }
        }
    }

    private func sectionHeader(pinned: Bool) -> some View {
        HStack(spacing: 4) {
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
            Text(pinned ? "Pinned" : "Recent")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if searchActive, !searchText.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            } else if activeFilter != .all {
                Image(systemName: activeFilter.icon)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "clipboard")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Preview Pane

    private var previewPane: some View {
        VStack(spacing: 0) {
            Group {
                if let item = selected {
                    previewContent(item)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "clipboard.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selected?.id)

            if let item = selected {
                HStack {
                    if !item.source.isEmpty {
                        Text(item.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider().opacity(0.5)
                actionBar(item)
            }
        }
    }

    @ViewBuilder
    private func previewContent(_ item: ClipboardItem) -> some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("EDITING TEXT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Text("\(editedText.count) chars")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    TextEditor(text: $editedText)
                        .font(.caption.monospaced())
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.textBackgroundColor).opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .focused($isEditorFocused)
                }
            } else {
                switch item.data {
                case let .text(text):
                    if let color = item.cachedColor {
                        VStack(spacing: 16) {
                            Spacer()
                            RoundedRectangle(cornerRadius: 24)
                                .fill(color)
                                .frame(width: 120, height: 120)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                )
                            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            Text(text)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                    }

                case let .image(data):
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(16)
                    }

                case let .url(url):
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "link")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text(url.absoluteString)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)

                case let .fileURL(url):
                    filePreview(url)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.06))
                .padding(8)
        )
    }

    private static let textExtensions: Set<String> = [
        "txt","md","swift","py","js","ts","jsx","tsx","html","css","json","xml",
        "yaml","yml","toml","sh","rb","php","go","rs","kt","java","c","cpp","h","m"
    ]
    private static let imageExtensions: Set<String> = [
        "png","jpg","jpeg","gif","webp","tiff","tif","bmp","heic","heif","svg"
    ]

    @ViewBuilder
    private func filePreview(_ url: URL) -> some View {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            PDFPreview(url: url)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(16)
        } else if Self.imageExtensions.contains(ext) {
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(16)
            } else {
                fileFallback(url)
            }
        } else if Self.textExtensions.contains(ext) {
            TextFilePreview(url: url)
        } else {
            fileFallback(url)
        }
    }

    private func fileFallback(_ url: URL) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.fill")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.body.weight(.medium))
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
            if !url.pathExtension.isEmpty {
                Text(url.pathExtension.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Spacer()
        }
        .padding(16)
    }

    // MARK: - Action Bar

    @ViewBuilder
    private func actionBar(_ item: ClipboardItem) -> some View {
        if isEditing {
            HStack(spacing: 10) {
                ActionButton(icon: "xmark", style: .destructive) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isEditing = false
                        editedText = ""
                    }
                }
                .help("Cancel editing (Esc)")
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                ActionButton(icon: "checkmark", style: .accent) {
                    if let updated = manager.updateItemText(item, newText: editedText) {
                        selected = updated
                    }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isEditing = false
                    }
                }
                .help("Save edits (⌘Return)")
                .keyboardShortcut(.return, modifiers: .command)

                ActionButton(icon: "doc.on.doc.fill", style: .accent) {
                    if let updated = manager.updateItemText(item, newText: editedText) {
                        selected = updated
                        manager.copyItemToClipboard(updated)
                        dismiss()
                    }
                }
                .help("Save & Copy (⇧⌘Return)")
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        } else {
            HStack(spacing: 10) {
                ActionButton(icon: "trash", style: .destructive) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        manager.removeItem(item)
                        selected = filtered.first ?? manager.clipboardItems.first
                    }
                }
                .help("Delete item")

                ActionButton(icon: item.isPinned ? "pin.slash" : "pin", style: .normal) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        manager.togglePin(item)
                    }
                }
                .help(item.isPinned ? "Unpin item" : "Pin item")

                if case .text(let text) = item.data {
                    ActionButton(icon: "pencil", style: .normal) {
                        editedText = text
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isEditing = true
                        }
                        isEditorFocused = true
                    }
                    .help("Edit text")
                } else if case .url(let url) = item.data {
                    ActionButton(icon: "pencil", style: .normal) {
                        editedText = url.absoluteString
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isEditing = true
                        }
                        isEditorFocused = true
                    }
                    .help("Edit URL")
                }

                if item.isModified {
                    ActionButton(icon: "arrow.uturn.backward", style: .normal) {
                        if let restored = manager.restoreItemToOriginal(item) {
                            selected = restored
                            manager.copyItemToClipboard(restored)
                            triggerCopyToast()
                        }
                    }
                    .help("Restore text to original state")
                }

                if currentSelectedText(for: item) != nil {
                    toolsMenu(for: item)
                }

                Spacer()

                if case let .fileURL(url) = item.data {
                    ActionButton(icon: "folder", style: .normal) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .help("Reveal in Finder")
                }

                if case let .url(url) = item.data {
                    ActionButton(icon: "arrow.up.right.square", style: .normal) {
                        NSWorkspace.shared.open(url)
                    }
                    .help("Open Link")
                }

                ActionButton(icon: "doc.on.doc", style: .accent) {
                    copySelected()
                }
                .help("Copy to Clipboard")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
    }

    private func toolsMenu(for item: ClipboardItem) -> some View {
        Menu {
            if item.isModified {
                Section("History") {
                    Button("Restore Original Text") {
                        if let restored = manager.restoreItemToOriginal(item) {
                            selected = restored
                            manager.copyItemToClipboard(restored)
                            triggerCopyToast()
                        }
                    }
                }
            }

            Section("Transform Case") {
                Button("UPPERCASE") { applyTransformation(to: item) { DeveloperTextTools.toUpperCase($0) } }
                Button("lowercase") { applyTransformation(to: item) { DeveloperTextTools.toLowerCase($0) } }
                Button("camelCase") { applyTransformation(to: item) { DeveloperTextTools.toCamelCase($0) } }
                Button("snake_case") { applyTransformation(to: item) { DeveloperTextTools.toSnakeCase($0) } }
                Button("kebab-case") { applyTransformation(to: item) { DeveloperTextTools.toKebabCase($0) } }
            }

            Section("Developer Utilities") {
                Button("Clean Plain Text (Strip Quotes & Trim)") {
                    applyTransformation(to: item) { DeveloperTextTools.cleanPlainText($0) }
                }

                if let txt = currentSelectedText(for: item), DeveloperTextTools.isJSON(txt) {
                    Button("Beautify JSON") {
                        if let formatted = DeveloperTextTools.beautifyJSON(txt) {
                            applyTransformedString(to: item, newText: formatted)
                        }
                    }
                    Button("Minify JSON") {
                        if let formatted = DeveloperTextTools.minifyJSON(txt) {
                            applyTransformedString(to: item, newText: formatted)
                        }
                    }
                }

                Button("Base64 Encode") {
                    if let txt = currentSelectedText(for: item) {
                        applyTransformedString(to: item, newText: DeveloperTextTools.encodeBase64(txt))
                    }
                }

                if let txt = currentSelectedText(for: item), DeveloperTextTools.isBase64(txt) {
                    Button("Base64 Decode") {
                        if let decoded = DeveloperTextTools.decodeBase64(txt) {
                            applyTransformedString(to: item, newText: decoded)
                        }
                    }
                }

                Button("URL Encode") {
                    if let txt = currentSelectedText(for: item), let enc = DeveloperTextTools.encodeURL(txt) {
                        applyTransformedString(to: item, newText: enc)
                    }
                }

                if let txt = currentSelectedText(for: item), DeveloperTextTools.isURLEncoded(txt) {
                    Button("URL Decode") {
                        if let dec = DeveloperTextTools.decodeURL(txt) {
                            applyTransformedString(to: item, newText: dec)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 36, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Developer & Text Tools (Case, JSON, Base64, URL)")
    }

    private func currentSelectedText(for item: ClipboardItem) -> String? {
        switch item.data {
        case .text(let t): return t
        case .url(let u): return u.absoluteString
        default: return nil
        }
    }

    private func applyTransformation(to item: ClipboardItem, transform: (String) -> String) {
        guard let text = currentSelectedText(for: item) else { return }
        applyTransformedString(to: item, newText: transform(text))
    }

    private func applyTransformedString(to item: ClipboardItem, newText: String) {
        if let updated = manager.updateItemText(item, newText: newText) {
            selected = updated
            manager.copyItemToClipboard(updated)
            triggerCopyToast()
        }
    }
}
