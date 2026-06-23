import DockDoorWidgetSDK
import SwiftUI

struct FocusControlsPanelView: View {
    let widgetId: String
    let dismiss: () -> Void

    private let slotDefaults: [FocusShortcut] = [
        .init(id: "shortcut-1", title: "Reduce Interruptions", symbol: "atom", shortcutName: "reduce interruptions", isFocus: true),
        .init(id: "shortcut-2", title: "Driving", symbol: "car.fill", shortcutName: "driving", isFocus: true),
        .init(id: "shortcut-3", title: "Sleep", symbol: "bed.double.fill", shortcutName: "sleep", isFocus: true),
        .init(id: "shortcut-4", title: "School", symbol: "graduationcap.fill", shortcutName: "school", isFocus: true),
        .init(id: "shortcut-5", title: "", symbol: "", shortcutName: "", isFocus: false),
        .init(id: "shortcut-6", title: "", symbol: "", shortcutName: "", isFocus: false),
        .init(id: "shortcut-7", title: "", symbol: "", shortcutName: "", isFocus: false),
        .init(id: "shortcut-8", title: "", symbol: "", shortcutName: "", isFocus: false)
    ]

    private var shortcuts: [FocusShortcut] {
        (1...8).compactMap { index in
            let defaults = slotDefaults[index - 1]
            let enabled = WidgetDefaults.bool(key: "shortcut\(index)Enabled", widgetId: widgetId, default: defaults.title.isEmpty ? false : true)
            guard enabled else { return nil }

            let title = WidgetDefaults.string(key: "shortcut\(index)Title", widgetId: widgetId, default: defaults.title).trimmingCharacters(in: .whitespacesAndNewlines)
            let symbol = WidgetDefaults.string(key: "shortcut\(index)Symbol", widgetId: widgetId, default: defaults.symbol).trimmingCharacters(in: .whitespacesAndNewlines)
            let shortcutName = WidgetDefaults.string(key: "shortcut\(index)Shortcut", widgetId: widgetId, default: defaults.shortcutName).trimmingCharacters(in: .whitespacesAndNewlines)
            let isFocus = WidgetDefaults.bool(key: "shortcut\(index)IsFocus", widgetId: widgetId, default: defaults.isFocus)

            guard !title.isEmpty, !symbol.isEmpty, !shortcutName.isEmpty else { return nil }
            return FocusShortcut(
                id: "shortcut-\(index)-\(shortcutName)",
                title: title,
                symbol: symbol,
                shortcutName: shortcutName,
                isFocus: isFocus
            )
        }
    }

    private var focusShortcuts: [FocusShortcut] {
        shortcuts.filter { $0.isFocus }
    }

    private var otherShortcuts: [FocusShortcut] {
        shortcuts.filter { !$0.isFocus }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !focusShortcuts.isEmpty {
                sectionHeader("Focus")
                shortcutList(focusShortcuts)
            }

            if !otherShortcuts.isEmpty {
                sectionHeader("Other")
                shortcutList(otherShortcuts)
            }
        }
        .padding(10)
        .frame(width: 250)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 2)
    }

    private func shortcutList(_ shortcuts: [FocusShortcut]) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                Button {
                    ShortcutLauncher.run(name: shortcut.shortcutName)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.12))
                                .frame(width: 30, height: 30)

                            Image(systemName: shortcut.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                        }

                        Text(shortcut.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.05))
                }
                .overlay(alignment: .bottom) {
                    if index != shortcuts.count - 1 {
                        Rectangle()
                            .fill(.white.opacity(0.06))
                            .frame(height: 1)
                            .padding(.leading, 54)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

struct FocusShortcut: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let shortcutName: String
    let isFocus: Bool
}
