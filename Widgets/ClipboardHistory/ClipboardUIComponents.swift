import AppKit
import SwiftUI

// MARK: - Accent Color Helper

extension Color {
    static let accentMuted: Color = {
        Color(NSColor.controlAccentColor.blended(withFraction: 0.22, of: .black) ?? .controlAccentColor)
    }()
}

// MARK: - Action Button

struct ActionButton: View {
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
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10)
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

// MARK: - Search Button & Field

struct SearchButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
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

struct SearchField: View {
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
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 15).fill(Color.primary.opacity(0.08)))
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

// MARK: - Segmented Filter Control

struct SegmentedFilterControl: View {
    @Binding var activeFilter: ClipboardFilter

    private let filters = ClipboardFilter.allCases

    var body: some View {
        GeometryReader { geo in
            let count = CGFloat(filters.count)
            let index = CGFloat(filters.firstIndex(of: activeFilter) ?? 0)
            let segmentWidth = geo.size.width / count
            let segmentHeight = geo.size.height

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.primary.opacity(0.08))

                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .frame(width: max(0, segmentWidth), height: segmentHeight)
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
                                .frame(width: max(0, segmentWidth), height: segmentHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(height: 30)
    }
}

// MARK: - Sidebar Item Row

struct ItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    var isCompact: Bool = false
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            if isCompact {
                compactContent
            } else {
                standardContent
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var compactContent: some View {
        HStack {
            Spacer(minLength: 0)
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .frame(width: 32, height: 32)
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(isSelected ? .white : Color.accentColor)
                        .offset(x: 4, y: -4)
                } else if item.isModified {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 8))
                        .foregroundStyle(isSelected ? .white : Color.accentColor)
                        .offset(x: 4, y: -4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    isSelected
                        ? Color.accentMuted
                        : isHovered
                            ? Color.primary.opacity(0.07)
                            : Color.clear
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var standardContent: some View {
        HStack(spacing: 8) {
            thumbnail
                .frame(width: 34, height: 34)

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
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isSelected
                        ? Color.accentMuted
                        : isHovered
                            ? Color.primary.opacity(0.07)
                            : Color.clear
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.data {
        case let .image(data):
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                iconBadge(item.typeIcon, color: .secondary)
            }
        case .text:
            if let color = item.cachedColor {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
            } else {
                iconBadge(item.typeIcon, color: .blue)
            }
        case .url:
            iconBadge(item.typeIcon, color: .purple)
        case let .fileURL(url):
            fileIcon(for: url)
        }
    }

    private func iconBadge(_ symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(isSelected ? 0.35 : 0.12))
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(isSelected ? .white : color)
        }
    }

    @ViewBuilder
    private func fileIcon(for url: URL) -> some View {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            fileBadge("doc.richtext", color: .red)
        case "zip", "tar", "gz", "rar", "7z":
            fileBadge("doc.zipper", color: .yellow)
        case "mp3", "m4a", "wav", "flac", "aac":
            fileBadge("music.note", color: .pink)
        case "mp4", "mov", "m4v", "mkv", "avi":
            fileBadge("film", color: .orange)
        case "swift", "py", "js", "ts", "json", "html", "css", "c", "cpp", "rs", "go":
            fileBadge("chevron.left.forwardslash.chevron.right", color: .cyan)
        default:
            iconBadge(item.typeIcon, color: .secondary)
        }
    }

    private func fileBadge(_ symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(isSelected ? 0.4 : 0.15))
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(isSelected ? .white : color)
        }
    }
}

// MARK: - Resizable Split Divider

struct ResizableSplitDivider: View {
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
                sidebarWidth = 240
                UserDefaults.standard.set(240.0, forKey: "ClipboardHistory_sidebarWidth")
            }
        }
        .help("Drag to resize sidebar (Double-click to reset)")
    }
}
