import AppKit
import SwiftUI
import PDFKit
import AVKit

private extension Color {
    static let accentMuted: Color = {
        Color(NSColor.controlAccentColor.blended(withFraction: 0.22, of: .black) ?? .controlAccentColor)
    }()
}

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
        }
    }


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
    }

    private func selectPrevious() {
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
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            showCopyToast = true
        }
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
                        selected = manager.clipboardItems.first
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
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                showCopyToast = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                withAnimation { showCopyToast = false }
                            }
                        }
                    }
                    .help("Restore text to original state")
                }

                if currentSelectedText(for: item) != nil {
                    Menu {
                        if item.isModified {
                            Section("History") {
                                Button("Restore Original Text") {
                                    if let restored = manager.restoreItemToOriginal(item) {
                                        selected = restored
                                        manager.copyItemToClipboard(restored)
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            showCopyToast = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                            withAnimation { showCopyToast = false }
                                        }
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
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                showCopyToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { showCopyToast = false }
            }
        }
    }
}

// MARK: - Segmented filter control

private struct SegmentedFilterControl: View {
    @Binding var activeFilter: ClipboardFilter

    private let filters = ClipboardFilter.allCases

    var body: some View {
        GeometryReader { geo in
            let count = CGFloat(filters.count)
            let index = CGFloat(filters.firstIndex(of: activeFilter) ?? 0)
            let segmentWidth = geo.size.width / count
            let segmentHeight = geo.size.height

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.primary.opacity(0.08))

                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .frame(width: segmentWidth, height: segmentHeight)
                    .offset(x: index * segmentWidth)
                    .animation(.spring(response: 0.3, dampingFraction: 0.78), value: activeFilter)

                HStack(spacing: 0) {
                    ForEach(filters, id: \.self) { filter in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                activeFilter = filter
                            }
                        } label: {
                            Image(systemName: filter.icon)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(activeFilter == filter ? .primary : .secondary)
                                .frame(width: segmentWidth, height: segmentHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(height: 32)
    }
}

// MARK: - Search controls

private struct SearchButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovered)
    }
}

private struct SearchField: View {
    @Binding var text: String
    @Binding var isActive: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)

            Button {
                if text.isEmpty {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        isActive = false
                    }
                } else {
                    text = ""
                }
            } label: {
                Image(systemName: text.isEmpty ? "xmark" : "xmark.circle.fill")
                    .font(.system(size: text.isEmpty ? 10 : 12, weight: text.isEmpty ? .semibold : .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.08)))
        .frame(maxWidth: .infinity)
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                if text.isEmpty {
                    isActive = false
                } else {
                    text = ""
                }
            }
        }
    }
}

// MARK: - Item row

private struct ItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                thumbnail
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    if !item.displayText.isEmpty {
                        Text(item.displayText)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(item.typeLabel)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                }

                Spacer(minLength: 0)

                if item.isModified {
                    Image(systemName: "pencil.line")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.accentColor)
                        .help("Modified (Click 'Restore' to revert)")
                }

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        isSelected
                            ? Color.accentMuted
                            : isHovered
                                ? Color.primary.opacity(0.07)
                                : Color.clear
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.data {
        case let .image(data):
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                iconBadge(item.typeIcon, color: .secondary)
            }
        case .text:
            if let color = item.cachedColor {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
            } else {
                iconBadge(item.typeIcon, color: .blue)
            }
        case .url:
            iconBadge("link", color: .blue)
        case .fileURL:
            iconBadge("doc.fill", color: .orange)
        }
    }

    private func iconBadge(_ symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(isSelected ? 0.4 : 0.15))
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(isSelected ? .white : color)
        }
    }
}

// MARK: - Action button

private struct ActionButton: View {
    let icon: String
    let style: Style
    let action: () -> Void

    enum Style { case normal, accent, destructive }

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 36, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var foregroundColor: Color {
        switch style {
        case .accent:      isHovered ? .white : .accentMuted
        case .destructive: isHovered ? .red : .secondary
        case .normal:      isHovered ? .accentColor : .secondary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .accent:      isHovered ? .accentMuted : Color.accentMuted.opacity(0.15)
        case .destructive: isHovered ? Color.red.opacity(0.15) : Color.primary.opacity(0.06)
        case .normal:      isHovered ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)
        }
    }
}

// MARK: - PDF Preview

private struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}
}

// MARK: - Text file preview

private struct TextFilePreview: View {
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

// MARK: - NSPanel Sentinel

struct NSPanelSentinel: NSViewRepresentable {
    let context: PanelWindowContext

    func makeNSView(context ctx: Context) -> SentinelView {
        let view = SentinelView(context: context)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ view: SentinelView, context ctx: Context) {}

    class SentinelView: NSView {
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

// MARK: - Resizable Split Divider

private struct ResizableSplitDivider: View {
    @Binding var sidebarWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragInitialWidth: CGFloat = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1)

            Rectangle()
                .fill(isHovered || isDragging ? Color.accentColor.opacity(0.35) : Color.clear)
                .frame(width: 8)

            ResizeCursorView()
                .frame(width: 8)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragInitialWidth = sidebarWidth
                    }
                    let newWidth = dragInitialWidth + value.translation.width
                    sidebarWidth = min(max(newWidth, minWidth), maxWidth)
                }
                .onEnded { _ in
                    isDragging = false
                    UserDefaults.standard.set(Double(sidebarWidth), forKey: "ClipboardHistory_sidebarWidth")
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                sidebarWidth = 280
                UserDefaults.standard.set(280.0, forKey: "ClipboardHistory_sidebarWidth")
            }
        }
        .help("Drag to resize sidebar (Double-click to reset)")
    }
}

// MARK: - Native macOS Cursor Rect View

private struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeCursorNSView {
        ResizeCursorNSView()
    }

    func updateNSView(_ nsView: ResizeCursorNSView, context: Context) {}
}

private class ResizeCursorNSView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}

// MARK: - Global Key Handling for Panel Navigation

private struct KeyHandlingView: NSViewRepresentable {
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

private class KeyHandlingNSView: NSView {
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
                case 36: // Return key
                    self.onReturn?()
                    return nil
                case 53: // Escape
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



