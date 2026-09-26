import DockDoorWidgetSDK
import Foundation
import Observation
import SwiftUI

let codexUsageWidgetId = "codex-usage"

final class CodexUsagePlugin: WidgetPlugin, DockDoorWidgetProvider {
    @MainActor private lazy var model = CodexUsageModel()

    var id: String { codexUsageWidgetId }
    var name: String { "Codex Usage" }
    var iconSymbol: String { "gauge.with.dots.needle.67percent" }
    var widgetDescription: String { "Read-only Codex dashboard with usage limits, sampled token analytics, model themes, and movable cards" }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(CodexUsageCompactView(size: size, isVertical: isVertical, model: model))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        AnyView(CodexUsagePanelView(model: model, dismiss: dismiss))
    }

    func settingsSchema() -> [WidgetSetting] {
        [
            .picker(
                key: "modelTheme",
                label: "Widget Theme",
                options: CodexTheme.allCases.map(\.rawValue),
                defaultValue: "Luna"
            ),
            .picker(key: "cardDensity", label: "Card Density", options: ["Compact", "Standard", "Spacious"], defaultValue: "Standard"),
            .toggle(key: "animateArtwork", label: "Animate Model Artwork", defaultValue: true),
        ]
    }
}

@MainActor
private struct CodexUsageCompactView: View {
    let size: CGSize
    let isVertical: Bool
    let model: CodexUsageModel
    private var snapshot: CodexUsageSnapshot { model.snapshot }
    @State private var now = Date()
    private var theme: CodexTheme { CodexTheme.current(widgetId: codexUsageWidgetId) }

    private var dim: CGFloat { min(size.width, size.height) }
    private var isExtended: Bool {
        isVertical ? size.height > size.width * 1.5 : size.width > size.height * 1.5
    }
    private var card: CodexUsageCard { snapshot.card(at: now) }
    // The host clips content to the dock card, so leave a margin rather than
    // running the ring and its glow into the slot edge.
    private var contentInset: CGFloat { max(2, dim * 0.05) }
    private var ringSize: CGFloat { min(max(dim * 0.60, 20), 34) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { timeline in
        Group {
            if isExtended {
                extendedLayout
            } else {
                compactLayout
            }
        }
        .padding(contentInset)
        .task(id: timeline.date) {
            now = timeline.date
            await model.tick()
        }
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 1) {
            UsageRing(
                percentRemaining: card.percentRemaining ?? snapshot.primaryPercent,
                size: ringSize,
                lineWidth: max(3, dim * 0.055),
                theme: theme
            )
            Text(card.shortLabel)
                .font(.system(size: max(9, min(dim * 0.21, 12)), weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(.primary)
    }

    private var extendedLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: max(3, dim * 0.08)) {
                    UsageRing(
                        percentRemaining: card.percentRemaining ?? snapshot.primaryPercent,
                        size: ringSize,
                        lineWidth: max(3, dim * 0.052),
                        theme: theme
                    )
                    usageLabels(alignment: .center)
                }
            } else {
                HStack(spacing: max(4, dim * 0.05)) {
                    UsageRing(
                        percentRemaining: card.percentRemaining ?? snapshot.primaryPercent,
                        size: ringSize,
                        lineWidth: max(3, dim * 0.052),
                        theme: theme
                    )
                    usageLabels(alignment: .leading)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .foregroundStyle(.primary)
    }

    private func usageLabels(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(card.title)
                .font(.system(size: max(10, min(dim * 0.24, 13)), weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(card.subtitle)
                .font(.system(size: max(8, min(dim * 0.18, 9.5)), weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .layoutPriority(1)
    }

}

struct UsageRing: View {
    let percentRemaining: Double?
    let size: CGFloat
    let lineWidth: CGFloat
    let theme: CodexTheme
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var hasData: Bool { percentRemaining?.isFinite == true }
    private var clamped: Double { hasData ? min(max(percentRemaining ?? 0, 0), 1) : 0 }
    /// The theme owns the healthy palette; a low budget still overrides it,
    /// since in the dock the ring is the only thing the user can read.
    private var warningColor: Color? {
        guard hasData else { return nil }
        switch clamped {
        case 0.45...: return nil
        case 0.20 ..< 0.45: return .orange
        default: return .red
        }
    }
    private var colors: [Color] {
        guard let warningColor else { return theme.colors }
        return [warningColor.opacity(0.72), warningColor, warningColor.opacity(0.92)]
    }
    private var glowColor: Color { warningColor ?? theme.accent }
    private var glowBlur: CGFloat { max(2, lineWidth * 0.55) }
    // The host clips widget content to the dock card, so the blurred glow and
    // the drop shadow have to stay inside the frame it hands us.
    private var glowInset: CGFloat { lineWidth * 0.28 + glowBlur * 0.6 }

    var body: some View {
        ZStack {
            ZStack {
                Circle()
                    .stroke(theme.accent.opacity(0.14), lineWidth: lineWidth)
                if hasData {
                    Circle()
                        .trim(from: 0, to: clamped)
                        .stroke(
                            AngularGradient(colors: colors, center: .center),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    if clamped > 0 {
                        Circle()
                            .trim(from: 0, to: clamped)
                            .stroke(
                                AngularGradient(colors: colors, center: .center),
                                style: StrokeStyle(lineWidth: lineWidth * 1.55, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .blur(radius: glowBlur)
                            .opacity(0.55)
                    }
                }
            }
            .padding(glowInset)
            VStack(spacing: -1) {
                Text(hasData ? "\(Int((clamped * 100).rounded()))" : "--")
                    .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                    .monospacedDigit()
                if hasData {
                    Text("%")
                        .font(.system(size: size * 0.15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .minimumScaleFactor(0.65)
        }
        .frame(width: size, height: size)
        .background(isDark ? Color.black.opacity(0.16) : Color.white.opacity(0.55), in: Circle())
        .shadow(color: hasData ? glowColor.opacity(0.42) : .clear, radius: max(2, size * 0.09), y: 1)
        .overlay {
            if theme == .astra && clamped > 0 {
                AstraRingSparkles(progress: clamped, ringSize: size - glowInset * 2, lineWidth: lineWidth, canvasSize: size)
            }
        }
        .accessibilityLabel("Codex usage remaining")
        .accessibilityValue(hasData ? "\(Int((clamped * 100).rounded())) percent" : "No data")
    }
}

struct UsageStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.callout.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct CodexUsageSnapshot {
    let limits: [CodexUsageLimit]
    let creditsBalance: String?
    let modelContext: CodexModelContext?
    let sourceUpdatedAt: Date?
    let sourceDescription: String?

    init(
        limits: [CodexUsageLimit],
        creditsBalance: String?,
        modelContext: CodexModelContext?,
        sourceUpdatedAt: Date? = nil,
        sourceDescription: String? = nil
    ) {
        self.limits = limits
        self.creditsBalance = creditsBalance
        self.modelContext = modelContext
        self.sourceUpdatedAt = sourceUpdatedAt
        self.sourceDescription = sourceDescription
    }

    static let empty = CodexUsageSnapshot(limits: [], creditsBalance: nil, modelContext: nil)

    var primaryLimit: CodexUsageLimit? { limits.first }

    var primaryPercent: Double? { primaryLimit?.percentRemaining }
    var modelSummary: String { modelContext?.summary ?? "Model unavailable" }
    var primaryTitle: String { primaryLimit?.percentLabel ?? "No data" }
    var primarySubtitle: String {
        primaryLimit.map { "\($0.name) - \($0.resetLabel)" } ?? "Run a Codex session to record usage"
    }

    func freshnessWarning(now: Date) -> String? {
        guard sourceDescription != nil else { return nil }
        guard let sourceUpdatedAt else { return "Account snapshot timestamp is unavailable." }
        guard now.timeIntervalSince(sourceUpdatedAt) > 15 * 60 else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Showing stale account data · updated \(formatter.localizedString(for: sourceUpdatedAt, relativeTo: now))"
    }

    func resetSummary(now: Date) -> String {
        guard let primaryLimit else { return "No local usage data yet" }
        if let resetDate = primaryLimit.resetDate {
            let interval = max(0, resetDate.timeIntervalSince(now))
            let days = Int(interval / 86400)
            let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
            let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            if days > 0 { return "Resets in \(days)d \(hours)h" }
            return hours > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(minutes)m"
        }
        return primaryLimit.resetLabel == "No reset date" ? "No reset date in local snapshot" : "Resets \(primaryLimit.resetLabel)"
    }

    func card(at date: Date) -> CodexUsageCard {
        var cards = limits.map { limit in
            CodexUsageCard(
                title: limit.percentLabel,
                subtitle: "\(limit.shortName) - \(limit.resetLabel)",
                shortLabel: limit.shortName,
                percentRemaining: limit.percentRemaining
            )
        }
        if let modelContext {
            cards.append(CodexUsageCard(
                title: modelContext.modelLabel,
                subtitle: "\(modelContext.reasoningLabel) effort",
                shortLabel: modelContext.shortModelLabel,
                percentRemaining: nil
            ))
        }
        if let creditsBalance {
            cards.append(CodexUsageCard(
                title: creditsBalance,
                subtitle: "Current credits",
                shortLabel: "Credits",
                percentRemaining: nil
            ))
        }
        guard !cards.isEmpty else {
            return CodexUsageCard(title: "No data", subtitle: "No snapshot yet", shortLabel: "Usage", percentRemaining: nil)
        }
        let index = Int(date.timeIntervalSinceReferenceDate / 4) % cards.count
        return cards[index]
    }

    func withModelContext(_ context: CodexModelContext?) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            limits: limits,
            creditsBalance: creditsBalance,
            modelContext: context ?? modelContext,
            sourceUpdatedAt: sourceUpdatedAt,
            sourceDescription: sourceDescription
        )
    }
}

struct CodexUsageCard {
    let title: String
    let subtitle: String
    let shortLabel: String
    let percentRemaining: Double?
}

struct CodexModelContext {
    let model: String?
    let reasoning: String?

    var modelLabel: String {
        guard let model, !model.isEmpty else { return "Model unavailable" }
        switch model.lowercased() {
        case let value where value.contains("astra"): return "Astra"
        case let value where value.contains("luna"): return "Luna"
        case let value where value.contains("terra"): return "Terra"
        case let value where value.contains("sol"): return "Sol"
        default: return model
        }
    }

    var shortModelLabel: String {
        modelLabel.count > 10 ? String(modelLabel.prefix(10)) : modelLabel
    }

    var reasoningLabel: String {
        guard let reasoning, !reasoning.isEmpty else { return "Reasoning unavailable" }
        switch reasoning.lowercased() {
        case "none": return "None"
        case "minimal": return "Minimal"
        case "low": return "Low"
        case "medium": return "Medium"
        case "high": return "High"
        case "xhigh": return "XHigh"
        case "max": return "Max"
        case "ultra": return "Ultra"
        default: return reasoning.capitalized
        }
    }

    var summary: String {
        switch (model, reasoning) {
        case (.some, .some): return "\(modelLabel) · \(reasoningLabel)"
        case (.some, nil): return modelLabel
        case (nil, .some): return "Model unavailable · \(reasoningLabel)"
        case (nil, nil): return "Model unavailable"
        }
    }
}

struct CodexUsageLimit: Identifiable {
    let id: String
    let name: String
    let percentRemaining: Double
    let resetDate: Date?
    let resetLabel: String
    let systemImage: String

    init(name: String, percentRemaining: Double, resetDate: Date? = nil, resetLabel: String, systemImage: String) {
        self.id = name
        self.name = name
        self.percentRemaining = min(max(percentRemaining, 0), 1)
        self.resetDate = resetDate
        self.resetLabel = resetLabel
        self.systemImage = systemImage
    }

    var percentLabel: String { "\(Int((percentRemaining * 100).rounded()))% left" }
    /// Model-prefixed names ("Astra 5h", "Astra Weekly") must keep their window
    /// suffix, otherwise the dock cycler shows two cards labelled the same.
    var shortName: String {
        var window = name
        if let astra = name.range(of: "astra ", options: [.caseInsensitive, .anchored]) {
            window = String(name[astra.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if window.isEmpty { return "Astra" }
        if window.localizedCaseInsensitiveContains("spark") { return "Spark" }
        if window.localizedCaseInsensitiveContains("general") { return "General" }
        return window.count > 10 ? String(window.prefix(10)) : window
    }
    var tint: Color {
        switch percentRemaining {
        case 0.45...: return Color(red: 0.13, green: 0.72, blue: 1.00)
        case 0.20..<0.45: return .orange
        default: return .red
        }
    }
}

private enum CodexUsageStore {
    private static let usageURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex/usage.json")

    static func read() -> CodexUsageSnapshot {
        // usage.json is an optional override for people maintaining the file
        // with their own tooling; Codex's own session logs are the default source.
        if let override = readUsageFile() {
            return override.withModelContext(CodexSessionsStore.latestModelContext())
        }
        return CodexSessionsStore.read() ?? .empty
    }

    private static func readUsageFile() -> CodexUsageSnapshot? {
        guard let data = try? Data(contentsOf: usageURL),
              let file = try? JSONDecoder().decode(CodexUsageFile.self, from: data)
        else {
            return nil
        }

        let decodedLimits = (file.limits ?? []).map { record in
            CodexUsageLimit(
                name: record.name,
                percentRemaining: record.normalizedRemainingPercent,
                resetDate: parseDate(record.resetAt),
                resetLabel: record.resetLabel ?? "No reset date",
                systemImage: record.systemImage ?? defaultSymbol(for: record.name)
            )
        }

        let limits: [CodexUsageLimit]
        if decodedLimits.isEmpty {
            let remaining = normalizedRemaining(
                remaining: file.percentRemaining ?? file.remainingPercent,
                used: file.percentUsed ?? file.usedPercent,
                amountRemaining: file.remaining,
                amountLimit: file.limit
            ) ?? 1
            limits = [CodexUsageLimit(
                name: file.title ?? "General",
                percentRemaining: remaining,
                resetDate: parseDate(file.resetAt),
                resetLabel: file.resetLabel ?? "No reset date",
                systemImage: "gauge.with.dots.needle.67percent"
            )]
        } else {
            limits = decodedLimits
        }

        let updatedAt = parseDate(file.updatedAt) ?? modificationDate(for: usageURL)
        return CodexUsageSnapshot(
            limits: limits,
            creditsBalance: file.creditsBalance,
            modelContext: nil,
            sourceUpdatedAt: updatedAt,
            sourceDescription: file.source ?? "Local usage snapshot"
        )
    }

    private static func normalizedRemaining(
        remaining: Double?,
        used: Double?,
        amountRemaining: Int64?,
        amountLimit: Int64?
    ) -> Double? {
        if let remaining {
            return CodexUsageStore.fraction(fromPercent: remaining)
        }
        if let used {
            return 1 - CodexUsageStore.fraction(fromPercent: used)
        }
        if let amountRemaining, let amountLimit, amountLimit > 0 {
            return min(max(Double(amountRemaining) / Double(amountLimit), 0), 1)
        }
        return nil
    }

    /// `usage.json` percentages are whole numbers, so `1` is 1% and `100` is
    /// 100%. Values below 1 are still read as 0...1 fractions.
    static func fraction(fromPercent value: Double) -> Double {
        let fraction = value >= 1 ? value / 100 : value
        return min(max(fraction, 0), 1)
    }

    private static func defaultSymbol(for name: String) -> String {
        (name.localizedCaseInsensitiveContains("spark") || name.localizedCaseInsensitiveContains("astra"))
            ? "sparkles" : "gauge.with.dots.needle.67percent"
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func modificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
}

/// Reads the newest `rate_limits` snapshot Codex records in its own session
/// rollout logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`). Read-only;
/// data is as fresh as the user's last Codex turn.
enum CodexSessionsStore {
    private static let sessionsURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex/sessions")

    static func read() -> CodexUsageSnapshot? {
        let files = recentRolloutFiles(limit: 8)
        let modelContext = latestModelContext(in: files)
        for fileURL in files {
            if let snapshot = latestSnapshot(in: fileURL) {
                return snapshot.withModelContext(modelContext)
            }
        }
        return modelContext.map { CodexUsageSnapshot(limits: [], creditsBalance: nil, modelContext: $0) }
    }

    static func latestModelContext() -> CodexModelContext? {
        latestModelContext(in: recentRolloutFiles(limit: 8))
    }

    // Directory and file names sort chronologically (YYYY/MM/DD, timestamped
    // filenames), so descending lexical order walks newest-first.
    static func recentRolloutFiles(limit: Int) -> [URL] {
        let fm = FileManager.default
        func children(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var files: [URL] = []
        for year in children(sessionsURL) {
            for month in children(year) {
                for day in children(month) {
                    files.append(contentsOf: children(day).filter {
                        $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl"
                    })
                    if files.count >= limit { return Array(files.prefix(limit)) }
                }
            }
        }
        return files
    }

    private static func latestSnapshot(in fileURL: URL) -> CodexUsageSnapshot? {
        latestLine(in: fileURL, marker: "\"rate_limits\"", decode: decodeSnapshot)
    }

    /// Codex writes one `turn_context` line per turn with the model and effort
    /// in use; older builds only recorded them in `thread_settings_applied`.
    /// Like the rate limits, only the newest line matters, so this is a
    /// backwards marker search rather than a decode of every line: rollout
    /// files run to tens of megabytes and this is called every few seconds.
    private static func latestModelContext(in files: [URL]) -> CodexModelContext? {
        for marker in ["\"turn_context\"", "\"thread_settings_applied\""] {
            for fileURL in files {
                if let context = latestLine(in: fileURL, marker: marker, decode: decodeModelContext) {
                    return context
                }
            }
        }
        return nil
    }

    /// Walks a rollout file backwards from the last occurrence of `marker`,
    /// returning the first line `decode` accepts.
    private static func latestLine<T>(in fileURL: URL, marker: String, decode: (Data) -> T?) -> T? {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
        let marker = Data(marker.utf8)
        let newline = UInt8(ascii: "\n")
        var searchRange = data.range(of: marker, options: .backwards)
        while let markerRange = searchRange {
            let lineStart = data[..<markerRange.lowerBound].lastIndex(of: newline)
                .map { data.index(after: $0) } ?? data.startIndex
            let lineEnd = data[markerRange.lowerBound...].firstIndex(of: newline) ?? data.endIndex
            if let value = decode(data.subdata(in: lineStart..<lineEnd)) {
                return value
            }
            searchRange = data[..<lineStart].range(of: marker, options: .backwards)
        }
        return nil
    }

    private static func decodeModelContext(from line: Data) -> CodexModelContext? {
        guard let decoded = try? JSONDecoder().decode(RolloutLine.self, from: line),
              let payload = decoded.payload
        else { return nil }

        let model: String?
        let effort: String?
        if decoded.type == "turn_context" {
            model = payload.contextModel
            effort = payload.contextEffort
        } else if decoded.type == "event_msg", payload.type == "thread_settings_applied" {
            model = payload.threadSettings?.model
            effort = payload.threadSettings?.reasoningEffort
        } else {
            return nil
        }

        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEffort = effort?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmedModel?.isEmpty == false || trimmedEffort?.isEmpty == false else { return nil }
        return CodexModelContext(
            model: trimmedModel?.isEmpty == false ? trimmedModel : nil,
            reasoning: trimmedEffort?.isEmpty == false ? trimmedEffort : nil
        )
    }

    private static func decodeSnapshot(from line: Data) -> CodexUsageSnapshot? {
        guard let decoded = try? JSONDecoder().decode(RolloutLine.self, from: line),
              let rateLimits = decoded.payload?.rateLimits
        else { return nil }

        var limits: [CodexUsageLimit] = []
        let isAstra = [rateLimits.limitName, rateLimits.limitID].compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains("astra") }
        let prefix = isAstra ? "Astra " : ""
        if let window = rateLimits.primary, let used = window.usedPercent {
            limits.append(limit(named: prefix + windowName(minutes: window.windowMinutes, fallback: "5h"), usedPercent: used, resetsAt: window.resetsAt))
        }
        if let window = rateLimits.secondary, let used = window.usedPercent {
            limits.append(limit(named: prefix + windowName(minutes: window.windowMinutes, fallback: "Weekly"), usedPercent: used, resetsAt: window.resetsAt))
        }
        guard !limits.isEmpty else { return nil }
        return CodexUsageSnapshot(limits: limits, creditsBalance: nil, modelContext: nil)
    }

    private static func limit(named name: String, usedPercent: Double, resetsAt: Double?) -> CodexUsageLimit {
        let resetDate = resetsAt.map { Date(timeIntervalSince1970: $0) }
        return CodexUsageLimit(
            name: name,
            percentRemaining: 1 - usedPercent / 100,
            resetDate: resetDate,
            resetLabel: resetDate.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "No reset date",
            systemImage: name.localizedCaseInsensitiveContains("astra") ? "sparkles" : "gauge.with.dots.needle.67percent"
        )
    }

    private static func windowName(minutes: Double?, fallback: String) -> String {
        guard let minutes, minutes > 0 else { return fallback }
        if minutes.truncatingRemainder(dividingBy: 10080) == 0 {
            let weeks = Int(minutes / 10080)
            return weeks == 1 ? "Weekly" : "\(weeks)w"
        }
        if minutes.truncatingRemainder(dividingBy: 1440) == 0 { return "\(Int(minutes / 1440))d" }
        if minutes.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(minutes / 60))h" }
        return "\(Int(minutes))m"
    }

    private struct RolloutLine: Decodable {
        let type: String?
        let payload: Payload?

        struct Payload: Decodable {
            let rateLimits: RateLimits?
            let type: String?
            let threadSettings: ThreadSettings?
            let model: String?
            let effort: String?
            let reasoningEffort: String?
            let collaborationMode: CollaborationMode?

            enum CodingKeys: String, CodingKey {
                case rateLimits = "rate_limits"
                case type
                case threadSettings = "thread_settings"
                case model
                case effort
                case reasoningEffort = "reasoning_effort"
                case collaborationMode = "collaboration_mode"
            }

            var contextModel: String? {
                model ?? collaborationMode?.settings?.model
            }

            var contextEffort: String? {
                effort ?? reasoningEffort ?? collaborationMode?.settings?.reasoningEffort
            }

            struct CollaborationMode: Decodable {
                let settings: Settings?

                struct Settings: Decodable {
                    let model: String?
                    let reasoningEffort: String?

                    enum CodingKeys: String, CodingKey {
                        case model
                        case reasoningEffort = "reasoning_effort"
                    }
                }
            }

            struct ThreadSettings: Decodable {
                let model: String?
                let reasoningEffort: String?

                enum CodingKeys: String, CodingKey {
                    case model
                    case reasoningEffort = "reasoning_effort"
                }
            }
        }
    }

    private struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
        let limitName: String?
        let limitID: String?

        enum CodingKeys: String, CodingKey {
            case primary, secondary
            case limitName = "limit_name"
            case limitID = "limit_id"
        }

        struct Window: Decodable {
            let usedPercent: Double?
            let windowMinutes: Double?
            let resetsAt: Double?

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case windowMinutes = "window_minutes"
                case resetsAt = "resets_at"
            }
        }
    }
}

private struct CodexUsageFile: Decodable {
    let updatedAt: String?
    let source: String?
    let title: String?
    let creditsBalance: String?
    let remaining: Int64?
    let limit: Int64?
    let resetAt: String?
    let resetLabel: String?
    let percentRemaining: Double?
    let remainingPercent: Double?
    let percentUsed: Double?
    let usedPercent: Double?
    let limits: [CodexUsageLimitRecord]?
}

private struct CodexUsageLimitRecord: Decodable {
    let name: String
    let resetAt: String?
    let resetLabel: String?
    let percentRemaining: Double?
    let remainingPercentValue: Double?
    let percentUsed: Double?
    let usedPercent: Double?
    let remaining: Int64?
    let limit: Int64?
    let systemImage: String?

    var normalizedRemainingPercent: Double {
        if let value = percentRemaining ?? remainingPercentValue {
            return CodexUsageStore.fraction(fromPercent: value)
        }
        if let value = percentUsed ?? usedPercent {
            return 1 - CodexUsageStore.fraction(fromPercent: value)
        }
        if let remaining, let limit, limit > 0 {
            return min(max(Double(remaining) / Double(limit), 0), 1)
        }
        return 1
    }

    enum CodingKeys: String, CodingKey {
        case name
        case resetAt
        case resetLabel
        case percentRemaining
        case remainingPercentValue = "remainingPercent"
        case percentUsed
        case usedPercent
        case remaining
        case limit
        case systemImage
    }
}

/// Shared by this plugin's dock and panel; concurrent timeline ticks coalesce.
@Observable
@MainActor
final class CodexUsageModel {
    private(set) var snapshot = CodexUsageSnapshot.empty
    private(set) var lastRead: Date?
    private(set) var analytics = CodexAnalyticsSnapshot.empty
    var layout = CodexDashboardLayout.restore() {
        didSet { layout.save() }
    }
    private let analyticsReader = CodexUsageAnalyticsReader()
    private var isReading = false
    private var isReadingAnalytics = false

    func tickAnalytics() async {
        guard !isReadingAnalytics else { return }
        isReadingAnalytics = true
        analytics = await analyticsReader.read()
        isReadingAnalytics = false
    }

    func tick(minimumInterval: TimeInterval = 5) async {
        guard !isReading, lastRead.map({ Date().timeIntervalSince($0) >= minimumInterval }) ?? true else { return }
        isReading = true
        let value = await Task.detached(priority: .utility) { CodexUsageStore.read() }.value
        snapshot = value
        lastRead = Date()
        isReading = false
    }
}
