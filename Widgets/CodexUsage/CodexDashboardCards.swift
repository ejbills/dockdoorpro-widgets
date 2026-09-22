import SwiftUI
import Charts

struct CodexDashboardCardContent: View {
    let card: CodexDashboardCard
    let snapshot: CodexUsageSnapshot
    let analytics: CodexAnalyticsSnapshot
    let lastRead: Date?
    let now: Date
    let theme: CodexTheme
    let hours: Int
    let modelFilter: String

    private var samples: [CodexTokenSample] {
        analytics.samples.filter {
            (hours == 0 || $0.date >= now.addingTimeInterval(-Double(hours) * 3600)) &&
            (modelFilter == "All models" || $0.model == modelFilter)
        }
    }
    private var input: Int { samples.reduce(0) { $0 + $1.input } }
    private var output: Int { samples.reduce(0) { $0 + $1.output } }
    private var cached: Int { samples.reduce(0) { $0 + $1.cached } }
    private var period: String { hours == 0 ? "Sampled logs" : hours == 24 ? "Past 24 hours · sampled logs" : "Past 7 days · sampled logs" }

    private var scope: String { period + (modelFilter == "All models" ? "" : " · " + friendlyModel(modelFilter)) }

    @ViewBuilder var body: some View {
        switch card {
        case .quota: quota
        case .limits: limits
        case .totals: totals
        case .daily: activityChart(hourly: false)
        case .hourly: activityChart(hourly: true)
        case .context: context
        case .pulse: pulse
        case .model: modelIdentity
        case .mix: mix
        case .efficiency: efficiency
        case .sources: sources
        case .sessions: sessions
        }
    }

    private var quota: some View {
        HStack(spacing: 12) {
            UsageRing(percentRemaining: snapshot.primaryPercent, size: 76, lineWidth: 7, theme: theme)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.primaryTitle).font(.title2.weight(.bold))
                Text(snapshot.primaryLimit?.name ?? "No usage recorded")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(snapshot.resetSummary(now: now)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var limits: some View {
        VStack(spacing: 10) {
            if snapshot.limits.isEmpty { empty("Run a Codex session to record usage limits.") }
            ForEach(snapshot.limits) { limit in
                HStack(spacing: 8) {
                    Image(systemName: limit.systemImage).foregroundStyle(theme.accent).frame(width: 18)
                    Text(limit.name).font(.caption.weight(.semibold))
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(limit.percentLabel).font(.caption.monospacedDigit().weight(.bold))
                        Text(limit.resetLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if let credits = snapshot.creditsBalance { row("Credits", credits) }
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(scope).font(.caption2).foregroundStyle(.secondary)
            Text(codexTokenLabel(input + output)).font(.title.weight(.bold)).monospacedDigit()
            HStack {
                UsageStat(title: "Input", value: codexTokenLabel(input))
                UsageStat(title: "Output", value: codexTokenLabel(output))
                UsageStat(title: "Events", value: "\(samples.count)")
            }
            Text("Cached input is part of input; reasoning is part of output.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private struct Bucket: Identifiable {
        let date: Date
        let tokens: Int
        var id: Date { date }
    }
    private func buckets(hourly: Bool) -> [Bucket] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: samples) { sample in
            calendar.dateInterval(of: hourly ? .hour : .day, for: sample.date)?.start ?? sample.date
        }
        return groups.map { Bucket(date: $0.key, tokens: $0.value.reduce(0) { $0 + $1.total }) }.sorted { $0.date < $1.date }
    }
    private func activityChart(hourly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scope).font(.caption2).foregroundStyle(.secondary)
            if samples.isEmpty { empty("No token events in this sample and period.") }
            else {
                Chart(buckets(hourly: hourly)) { bucket in
                    BarMark(x: .value("Time", bucket.date, unit: hourly ? .hour : .day), y: .value("Tokens", bucket.tokens))
                        .foregroundStyle(theme.accent.gradient)
                        .cornerRadius(3)
                }
                 .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: hourly ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel { if let tokens = value.as(Int.self) { Text(codexTokenLabel(tokens)) } }
                    }
                }
                .frame(height: 120)
                .accessibilityLabel(hourly ? "Sampled hourly token activity" : "Sampled daily token activity")
                Text("\(samples.count) recorded events · \(codexTokenLabel(input + output)) tokens")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session = analytics.latest, let tokens = session.contextTokens, let window = session.contextWindow, window > 0 {
                let fraction = min(1, max(0, Double(tokens) / Double(window)))
                HStack {
                    Text("\(Int(fraction * 100))% used").font(.title2.weight(.bold))
                    Spacer()
                    Text("\(codexTokenLabel(tokens)) / \(codexTokenLabel(window))").font(.caption.monospacedDigit())
                }
                ProgressView(value: fraction).tint(theme.accent)
                Text("Latest recorded context · \(friendlyModel(session.model))").font(.caption2).foregroundStyle(.secondary)
                Text("Usage can change after compaction. This is separate from account quota.").font(.caption2).foregroundStyle(.secondary)
            } else { empty("No context-window measurement in the sampled logs.") }
        }
    }

    private var pulse: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.modelSummary).font(.callout.weight(.bold))
            HStack {
                UsageStat(title: "Sessions", value: "\(analytics.sessions.count)")
                UsageStat(title: "Events", value: "\(analytics.samples.count)")
            }
            if let last = analytics.latest?.lastEvent {
                HStack {
                    Text("Last token event").font(.caption2)
                    Text(last, style: .relative).font(.caption2.monospacedDigit())
                }.foregroundStyle(.secondary)
            }
            Text("Activity sampled from recent local logs.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var modelIdentity: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let current = snapshot.modelContext {
                let identity = CodexTheme.identity(for: current.model) ?? theme
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.modelLabel).font(.title2.weight(.bold))
                    Text(current.reasoningLabel).font(.callout.weight(.semibold))
                }
                .foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 3)
                .padding(14).frame(maxWidth: .infinity, minHeight: 90, alignment: .bottomLeading)
                .background {
                    GeometryReader { geometry in
                        CodexIdentityArtwork(identity: identity, isEmphasized: true)
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 12))
                if let identifier = current.model { Text(identifier).font(.caption.monospaced()).textSelection(.enabled) }
            } else { empty("No recorded model context yet.") }
            Text("Latest local session record. Change new-chat defaults in Codex.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var mix: some View {
        let grouped = Dictionary(grouping: samples, by: \.model).map { (model: $0.key, tokens: $0.value.reduce(0) { $0 + $1.total }) }.sorted { $0.tokens > $1.tokens }
        return VStack(alignment: .leading, spacing: 10) {
            Text(scope).font(.caption2).foregroundStyle(.secondary)
            if grouped.isEmpty { empty("No attributed token samples yet.") }
            ForEach(grouped.prefix(6), id: \.model) { item in
                VStack(alignment: .leading, spacing: 4) {
                    row(friendlyModel(item.model), codexTokenLabel(item.tokens))
                    ProgressView(value: Double(item.tokens), total: Double(max(1, input + output))).tint(theme.accent)
                }
            }
        }
    }

    private var efficiency: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(scope).font(.caption2).foregroundStyle(.secondary)
            if input > 0 {
                Text("\(Int(Double(cached) / Double(input) * 100))% cached").font(.title2.weight(.bold))
                ProgressView(value: Double(cached), total: Double(input)).tint(theme.accent)
                row("Cached input", codexTokenLabel(cached))
                row("Uncached input", codexTokenLabel(max(0, input - cached)))
                row("Reasoning output", codexTokenLabel(samples.reduce(0) { $0 + $1.reasoning }))
                Text("Observed token reuse, not a billing estimate.").font(.caption2).foregroundStyle(.secondary)
            } else { empty("No input-token samples for this period.") }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Account limits recorded", snapshot.limits.isEmpty ? "No" : "Yes")
            row("Model recorded", snapshot.modelContext == nil ? "No" : "Yes")
            if let lastRead { row("Limits last checked", lastRead.formatted(date: .omitted, time: .shortened)) }
            row("Logs sampled", "\(analytics.sessions.count) / 8")
            row("Last analytics read", "\(analytics.readMilliseconds) ms")
            row("New bytes read", codexTokenLabel(analytics.bytesRead))
            if analytics.unavailableFiles > 0 { row("Unavailable logs", "\(analytics.unavailableFiles)") }
            Text("Limits come from local session records or usage.json. Check time is not the age of those limits.").font(.caption2).foregroundStyle(.secondary)
            Text("Analytics retain up to 512 events per log and decode at most 1 MB of new event data per changed log every 30 seconds. Sampled totals exclude older history.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if analytics.sessions.isEmpty { empty("No readable recent sessions.") }
            ForEach(Array(analytics.sessions.prefix(6).enumerated()), id: \.element.id) { index, session in
                VStack(alignment: .leading, spacing: 3) {
                    row("Session \(index + 1) · \(friendlyModel(session.model))", "\(session.sampleCount) events")
                    if let last = session.lastEvent { Text(last, style: .relative).font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Text("Ordered by latest sampled token event.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func friendlyModel(_ value: String) -> String {
        CodexModelContext(model: value, reasoning: nil).modelLabel
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption)
            Spacer(minLength: 8)
            Text(value).font(.caption.monospacedDigit().weight(.semibold))
        }
    }
    private func empty(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
