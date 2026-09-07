import AppKit
import DockDoorWidgetSDK
import SwiftUI

struct AppVolumeMixerPanel: View {
    let dismiss: () -> Void
    let widgetId: String
    var model: AppVolumeMixerModel

    private let panelWidth: CGFloat = 316
    private let maximumListHeight: CGFloat = 420
    /// The playing dots and the app list stay live while the panel is open.
    private let refreshInterval: TimeInterval = 2

    private var showOnlyPlaying: Bool {
        WidgetDefaults.bool(key: "showOnlyPlaying", widgetId: widgetId, default: false)
    }

    private var rows: [MixerEntry] {
        model.entries.filter { entry in
            guard showOnlyPlaying else { return true }
            return entry.isPlaying || model.isAdjusted(entry)
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            content
                .onChange(of: context.date) { _, _ in
                    model.tick(minimumInterval: refreshInterval * 0.8)
                }
        }
        .onAppear { model.refresh() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().opacity(0.5)

            if !model.isSupported {
                notice(
                    symbol: "exclamationmark.triangle",
                    text: "Per-app volume needs macOS 14.4 or newer."
                )
            } else if model.needsPermission {
                notice(
                    symbol: "lock",
                    text: "Allow DockDoor Pro under Privacy & Security › System Audio Recording to control app volumes."
                )
            }

            if rows.isEmpty {
                Text("No apps are using audio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(rows) { entry in
                            row(for: entry)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: maximumListHeight)
            }

            footer
        }
        .padding(14)
        .frame(width: panelWidth)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.vertical.3")
                .font(.headline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Volume Mixer")
                    .font(.headline)
                if let device = model.outputDeviceName {
                    Text(device)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private func row(for entry: MixerEntry) -> some View {
        let volume = model.volume(for: entry)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                icon(for: entry)
                Text(entry.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if entry.isPlaying {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                        .accessibilityLabel("Playing")
                }
                Spacer(minLength: 4)
                Text(entry.isBypassed ? "--" : MixerGlyph.percentLabel(volume))
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if entry.isBypassed {
                Text("Manages its own audio")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 26)
            } else {
                HStack(spacing: 8) {
                    Button {
                        model.toggleMute(entry)
                    } label: {
                        Image(systemName: MixerGlyph.symbol(for: volume))
                            .font(.caption)
                            .frame(width: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(volume < 0.005 ? Color.accentColor : Color.secondary)
                    .help(volume < 0.005 ? "Unmute" : "Mute")

                    Slider(
                        value: Binding(
                            get: { model.volume(for: entry) },
                            set: { model.setVolume($0, for: entry) }
                        ),
                        in: 0 ... (model.boostEnabled ? 2 : 1)
                    )
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func icon(for entry: MixerEntry) -> some View {
        Group {
            if let image = AudioProcessCatalog.icon(for: entry) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed").resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
    }

    private func notice(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var footer: some View {
        HStack {
            Button("Reset All") { model.resetAll() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(model.adjustedEntries.isEmpty ? Color.secondary : Color.accentColor)
                .disabled(model.adjustedEntries.isEmpty)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
