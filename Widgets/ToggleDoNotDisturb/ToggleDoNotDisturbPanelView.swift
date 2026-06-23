import SwiftUI

struct ToggleDoNotDisturbPanelView: View {
    let dismiss: () -> Void

    private let shortcuts: [(title: String, icon: String, shortcutName: String)] = [
        ("Reduce Interruptions", "atom", "reduce interruptions"),
        ("Driving", "car.fill", "driving"),
        ("Sleep", "bed.double.fill", "sleep"),
        ("School", "graduationcap.fill", "school")
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(shortcuts.enumerated()), id: \.element.shortcutName) { index, shortcut in
                Button {
                    ShortcutLauncher.run(name: shortcut.shortcutName)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.12))
                                .frame(width: 30, height: 30)

                            Image(systemName: shortcut.icon)
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
        .padding(10)
        .frame(width: 250)
    }
}
