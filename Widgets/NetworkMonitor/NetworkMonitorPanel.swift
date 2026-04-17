import DockDoorWidgetSDK
import SwiftUI
import SystemConfiguration


struct NetworkMonitorPanel: View {
    let dismiss: () -> Void
    let pluginId: String

    @ObservedObject private var monitor = NetworkSpeedMonitor.shared
    @State private var selectedIface: String = ""
    @State private var appeared = false

    private var speedUnit: String {
        WidgetDefaults.string(key: "speedUnit", widgetId: pluginId, default: "Auto")
    }

    private var colors: NetworkColors {
        NetworkColors.resolve(pluginId: pluginId)
    }

    private var dlColor: Color { colors.download }
    private var ulColor: Color { colors.upload }

    var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        header
        GlassDivider()

        VStack(alignment: .leading, spacing: 14) {
            ifacePicker
            liveSpeeds
            historySection
            totalsSection
            interfaceSection
        }
        .padding(14)
    }
    .frame(width: 280)
    .background(
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            dlColor.opacity(0.08),
                            Color.clear,
                            ulColor.opacity(0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    )
    .overlay(
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.05),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    )
    .shadow(color: dlColor.opacity(0.12), radius: 20, x: -4, y: 0)
    .shadow(color: ulColor.opacity(0.10), radius: 20, x: 4, y: 0)
    .shadow(color: .black.opacity(0.30), radius: 14, y: 6)
    .opacity(appeared ? 1 : 0)
    .scaleEffect(appeared ? 1 : 0.96)
    .onAppear {
        selectedIface = WidgetDefaults.string(
            key: "selectedInterface",
            widgetId: pluginId,
            default: ""
        )
        monitor.selectedInterface = selectedIface
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            appeared = true
        }
    }
}


    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(dlColor)

            Text("Network Monitor")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            LivePulseDot(color: dlColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.primary.opacity(0.06), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var ifacePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Interface")

            Menu {
                Button {
                    pickInterface("")
                } label: {
                    HStack {
                        Text("All Interfaces")
                        if selectedIface.isEmpty { Image(systemName: "checkmark") }
                    }
                }

                Divider()

                ForEach(monitor.availableInterfaces, id: \.self) { name in
                    Button {
                        pickInterface(name)
                    } label: {
                        HStack {
                            Text(prettyInterfaceName(name))
                            if let ip = monitor.interfaceIPs[name] {
                                Text("· \(ip)").foregroundStyle(.secondary)
                            }
                            if selectedIface == name { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(dlColor)

                    Text(
                        selectedIface.isEmpty
                            ? "All Interfaces"
                            : prettyInterfaceName(selectedIface)
                    )
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(GlassCard())
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var liveSpeeds: some View {
        HStack(spacing: 0) {
            speedBlock(symbol: "arrow.down.circle.fill", title: "Download",
                       speed: monitor.downloadSpeed, color: dlColor)

            GlassDivider(vertical: true, height: 66)

            speedBlock(symbol: "arrow.up.circle.fill", title: "Upload",
                       speed: monitor.uploadSpeed, color: ulColor)
        }
        .background(
            ZStack {
                GlassCard()
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [dlColor.opacity(0.10), Color.clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    LinearGradient(
                        colors: [Color.clear, ulColor.opacity(0.10)],
                        startPoint: .leading, endPoint: .trailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        )
    }

    private func speedBlock(symbol: String, title: String,
                            speed: Double, color: Color) -> some View {
        let fmt = monitor.formattedSpeed(speed, unit: speedUnit)
        return VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(fmt.value)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.primary, color.opacity(0.85), .primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(fmt.unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Usage History")

            ZStack {
                Sparkline(data: monitor.downloadHistory, color: dlColor)
                Sparkline(data: monitor.uploadHistory, color: ulColor)

                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [Color.clear, Color.primary.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 20)
                }

                VStack {
                    Color.white.opacity(0.08).frame(height: 1)
                    Spacer()
                }
            }
            .frame(height: 52)
            .padding(10)
            .background(
                ZStack {
                    GlassCard()
                    LinearGradient(
                        colors: [dlColor.opacity(0.07), Color.clear, ulColor.opacity(0.07)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            )

            HStack(spacing: 12) {
                legendDot(dlColor, "Download")
                legendDot(ulColor, "Upload")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }


    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Session Totals")

            HStack(spacing: 0) {
                totalBlock(symbol: "arrow.down", label: "Downloaded",
                           value: monitor.formattedBytes(monitor.sessionTotalDownload),
                           color: dlColor)

                GlassDivider(vertical: true, height: 44)

                totalBlock(symbol: "arrow.up", label: "Uploaded",
                           value: monitor.formattedBytes(monitor.sessionTotalUpload),
                           color: ulColor)
            }
            .background(GlassCard())
        }
    }

    private func totalBlock(symbol: String, label: String,
                            value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }


    private var interfaceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Details")

            VStack(spacing: 0) {
                infoRow(
                    label: "Interface",
                    value: selectedIface.isEmpty ? "All" : prettyInterfaceName(selectedIface)
                )
                GlassDivider().padding(.leading, 12)
                infoRow(label: "Local IP", value: monitor.localIP)
            }
            .background(GlassCard())
        }
    }


    private func pickInterface(_ name: String) {
        selectedIface = name
        monitor.selectedInterface = name
        UserDefaults.standard.set(name, forKey: "\(pluginId).selectedInterface")
    }

    private func prettyInterfaceName(_ iface: String) -> String {
        guard !iface.isEmpty else { return "All Interfaces" }
        if let display = localizedInterfaceName(for: iface) {
            return "\(display) (\(iface))"
        }
        switch iface {
        case "en0": return "Wi-Fi (\(iface))"
        case "en21": return "USB 10/100/1000 LAN (\(iface))"
        default: return iface
        }
    }

    private func localizedInterfaceName(for bsdName: String) -> String? {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for interface in all {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  bsd == bsdName else { continue }
            if let localized = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?,
               !localized.isEmpty { return localized }
        }
        return nil
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.4)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }
}


private struct GlassCard: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.primary.opacity(0.05))
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
    }
}

private struct GlassDivider: View {
    var vertical: Bool = false
    var height: CGFloat? = nil

    var body: some View {
        if vertical {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.5, height: height)
        } else {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }
}


private struct LivePulseDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 10, height: 10)
                .scaleEffect(pulsing ? 1.8 : 1.0)
                .opacity(pulsing ? 0 : 0.6)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}