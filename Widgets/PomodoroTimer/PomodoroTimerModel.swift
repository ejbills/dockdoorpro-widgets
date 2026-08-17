import AppKit
import DockDoorWidgetSDK
import Foundation
import Observation

enum PomodoroPhase: String, Codable, CaseIterable, Identifiable {
    case focus
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus:
            return "Focus"
        case .shortBreak:
            return "Short Break"
        case .longBreak:
            return "Long Break"
        }
    }

    var compactTitle: String {
        switch self {
        case .focus:
            return "FOCUS"
        case .shortBreak:
            return "BREAK"
        case .longBreak:
            return "LONG"
        }
    }

    var symbol: String {
        switch self {
        case .focus: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "leaf.fill"
        }
    }
}

enum PomodoroRunState: String, Codable {
    case idle
    case running
    case paused
}

enum PomodoroAlertStrength: String, CaseIterable {
    case off = "Off"
    case gentle = "Gentle"
    case noticeable = "Noticeable"
    case persistent = "Persistent"
}

enum PomodoroGlowDuration: String, CaseIterable {
    case tenSeconds = "10 Seconds"
    case thirtySeconds = "30 Seconds"
    case oneMinute = "1 Minute"
    case untilAcknowledged = "Until Acknowledged"

    var interval: TimeInterval? {
        switch self {
        case .tenSeconds: return 10
        case .thirtySeconds: return 30
        case .oneMinute: return 60
        case .untilAcknowledged: return nil
        }
    }
}

private struct PomodoroSavedState: Codable {
    var phase: PomodoroPhase
    var runState: PomodoroRunState
    var remainingSeconds: Int
    var totalSeconds: Int
    var endDate: Date?
    var completedToday: Int
    var cycleFocusCount: Int
    var dayKey: String
}

@Observable
final class PomodoroTimerModel {
    private(set) var phase: PomodoroPhase = .focus
    private(set) var runState: PomodoroRunState = .idle
    private(set) var totalSeconds = 25 * 60
    private(set) var completedToday = 0
    private(set) var cycleFocusCount = 0
    private(set) var completionPulse = 0
    private(set) var isAwaitingAcknowledgement = false

    let widgetId: String

    private var storedRemainingSeconds = 25 * 60
    private var endDate: Date?
    private var completionAlertGeneration = 0
    private var attentionGlowGeneration = 0
    private var currentDayKey = ""

    init(widgetId: String) {
        self.widgetId = widgetId
        restore()
        let now = Date()
        normalizeDayIfNeeded(at: now)
        reconcileRestoredTimer(at: now)
        synchronizeIdleDuration()
    }

    var isRunning: Bool { runState == .running }
    var isPaused: Bool { runState == .paused }

    func remainingSeconds(at date: Date) -> Int {
        guard runState == .running, let endDate else {
            return storedRemainingSeconds
        }
        let calculatedSeconds = max(
            0,
            Int(ceil(endDate.timeIntervalSince(date)))
        )
        // A tap can occur between TimelineView ticks, so its current display
        // date may briefly predate the start date by almost one second. Keep
        // that stale tick from showing one second more than the started value.
        return min(storedRemainingSeconds, calculatedSeconds)
    }

    func remainingFraction(at date: Date) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return min(
            1,
            max(0, Double(remainingSeconds(at: date)) / Double(totalSeconds))
        )
    }

    func elapsedFraction(at date: Date) -> Double {
        1 - remainingFraction(at: date)
    }

    func displayTime(at date: Date) -> String {
        let remainingSeconds = remainingSeconds(at: date)
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func compactValue(at date: Date) -> String {
        let remainingSeconds = remainingSeconds(at: date)
        if remainingSeconds >= 60 {
            return String(Int(ceil(Double(remainingSeconds) / 60)))
        }
        return String(remainingSeconds)
    }

    func compactUnit(at date: Date) -> String {
        let remainingSeconds = remainingSeconds(at: date)
        return remainingSeconds >= 60
            ? "MIN"
            : "SEC"
    }

    var statusText: String {
        if isAwaitingAcknowledgement {
            return "Completed"
        }
        switch runState {
        case .idle:
            return "Ready"
        case .running:
            return "In progress"
        case .paused:
            return "Paused"
        }
    }

    var sessionsPerRound: Int {
        let raw = WidgetDefaults.string(
            key: "sessionsPerRound",
            widgetId: widgetId,
            default: "4"
        )
        return min(5, max(2, Int(raw) ?? 4))
    }

    var dailyGoal: Int {
        Int(WidgetDefaults.double(
            key: "dailyGoal",
            widgetId: widgetId,
            default: 8
        )).clamped(to: 1...12)
    }

    var dailyProgress: Double {
        min(1, Double(completedToday) / Double(max(1, dailyGoal)))
    }

    var nextPhase: PomodoroPhase {
        switch phase {
        case .focus:
            return cycleFocusCount + 1 >= sessionsPerRound ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }

    func synchronize(at date: Date) {
        normalizeDayIfNeeded(at: date)
        synchronizeIdleDuration()

        guard runState == .running,
              let endDate,
              endDate <= date else { return }
        storedRemainingSeconds = 0
        finishCurrentPhase(at: date, playSound: true)
    }

    func toggleTimer(at date: Date = Date()) {
        switch runState {
        case .running:
            pause(at: date)
        case .idle, .paused:
            start(at: date)
        }
    }

    func start(at date: Date = Date()) {
        normalizeDayIfNeeded(at: date)
        synchronizeIdleDuration()
        acknowledgeCompletion()
        if storedRemainingSeconds <= 0 {
            configureCurrentPhase()
        }
        runState = .running
        endDate = date.addingTimeInterval(TimeInterval(storedRemainingSeconds))
        persist(at: date)
    }

    func pause(at date: Date = Date()) {
        guard runState == .running else { return }
        acknowledgeCompletion()
        storedRemainingSeconds = remainingSeconds(at: date)
        runState = .paused
        endDate = nil
        persist(at: date)
    }

    func reset() {
        acknowledgeCompletion()
        runState = .idle
        endDate = nil
        configureCurrentPhase()
        persist()
    }

    func skip() {
        acknowledgeCompletion()
        runState = .idle
        endDate = nil
        phase = nextPhase
        configureCurrentPhase()
        persist()
    }

    func selectPhase(_ newPhase: PomodoroPhase) {
        guard newPhase != phase || runState != .idle else { return }
        acknowledgeCompletion()
        phase = newPhase
        runState = .idle
        endDate = nil
        configureCurrentPhase()
        persist()
    }

    private func finishCurrentPhase(at date: Date, playSound: Bool) {
        let completedPhase = phase

        cancelScheduledCompletionSounds()
        beginCompletionAttention()

        if completedPhase == .focus {
            completedToday += 1
            cycleFocusCount += 1
        }

        if playSound {
            playCompletionSound()
        }

        completionPulse += 1

        if completedPhase == .focus {
            if cycleFocusCount >= sessionsPerRound {
                cycleFocusCount = 0
                phase = .longBreak
            } else {
                phase = .shortBreak
            }
        } else {
            phase = .focus
        }

        configureCurrentPhase()
        let shouldAutoStart = phase == .focus
            ? WidgetDefaults.bool(
                key: "autoStartFocus",
                widgetId: widgetId
            )
            : WidgetDefaults.bool(
                key: "autoStartBreaks",
                widgetId: widgetId
            )

        if shouldAutoStart {
            runState = .running
            endDate = date.addingTimeInterval(TimeInterval(storedRemainingSeconds))
        } else {
            runState = .idle
            endDate = nil
        }
        persist(at: date)
    }

    private func configureCurrentPhase() {
        let duration = durationSeconds(for: phase)
        totalSeconds = duration
        storedRemainingSeconds = duration
    }

    private func durationSeconds(for phase: PomodoroPhase) -> Int {
        let minutes: Int
        switch phase {
        case .focus:
            minutes = Int(WidgetDefaults.double(
                key: "focusMinutes",
                widgetId: widgetId,
                default: 25
            )).clamped(to: 15...60)
        case .shortBreak:
            minutes = Int(WidgetDefaults.double(
                key: "shortBreakMinutes",
                widgetId: widgetId,
                default: 5
            )).clamped(to: 3...15)
        case .longBreak:
            minutes = Int(WidgetDefaults.double(
                key: "longBreakMinutes",
                widgetId: widgetId,
                default: 15
            )).clamped(to: 10...30)
        }
        return minutes * 60
    }

    private func synchronizeIdleDuration() {
        guard runState == .idle else { return }
        let desiredDuration = durationSeconds(for: phase)
        if totalSeconds != desiredDuration
            || storedRemainingSeconds != desiredDuration {
            totalSeconds = desiredDuration
            storedRemainingSeconds = desiredDuration
            persist()
        }
    }

    private func normalizeDayIfNeeded(at date: Date) {
        guard currentDayKey != Self.dayKey(for: date) else { return }
        resetForNewDay(at: date)
    }

    private func resetForNewDay(at date: Date) {
        acknowledgeCompletion()
        phase = .focus
        runState = .idle
        endDate = nil
        completedToday = 0
        cycleFocusCount = 0
        configureCurrentPhase()
        persist(at: date)
    }

    private func reconcileRestoredTimer(at date: Date) {
        guard runState == .running, let endDate else {
            if runState == .running {
                runState = .paused
            }
            return
        }

        storedRemainingSeconds = max(0, Int(ceil(endDate.timeIntervalSince(date))))
        if storedRemainingSeconds <= 0 {
            finishCurrentPhase(at: date, playSound: false)
        }
    }

    private func persist(at date: Date = Date()) {
        let state = PomodoroSavedState(
            phase: phase,
            runState: runState,
            remainingSeconds: remainingSeconds(at: date),
            totalSeconds: totalSeconds,
            endDate: endDate,
            completedToday: completedToday,
            cycleFocusCount: cycleFocusCount,
            dayKey: Self.dayKey(for: date)
        )
        currentDayKey = state.dayKey
        guard let data = try? JSONEncoder().encode(state) else { return }
        WidgetDefaults.set(data, key: Self.stateKey, widgetId: widgetId)
    }

    private func restore() {
        guard let data = WidgetDefaults.data(
            key: Self.stateKey,
            widgetId: widgetId
        ),
        let saved = try? JSONDecoder().decode(
            PomodoroSavedState.self,
            from: data
        ) else {
            configureCurrentPhase()
            return
        }

        currentDayKey = saved.dayKey
        phase = saved.phase
        runState = saved.runState
        storedRemainingSeconds = max(0, saved.remainingSeconds)
        totalSeconds = max(1, saved.totalSeconds)
        endDate = saved.endDate
        completedToday = max(0, saved.completedToday)
        cycleFocusCount = max(0, saved.cycleFocusCount)
        // Completion attention is intentionally session-only. Restarting the
        // host clears the glow instead of restoring a stale acknowledgement.
        isAwaitingAcknowledgement = false

        let now = Date()
        if saved.dayKey != Self.dayKey(for: now) {
            resetForNewDay(at: now)
        }
    }

    private func playCompletionSound() {
        let strength = configuredAlertStrength()

        let pattern: [(delay: TimeInterval, name: String)]
        let cycleOffsets: [TimeInterval]
        switch strength {
        case .off:
            return
        case .gentle:
            pattern = [
                (0, "Hero"),
                (1.35, "Ping"),
                (3.0, "Hero"),
            ]
            cycleOffsets = [0]
        case .noticeable:
            pattern = Self.noticeableSoundPattern
            cycleOffsets = [0]
        case .persistent:
            pattern = Self.noticeableSoundPattern
            // Keep the reminder bounded: at most three cycles, and stop as
            // soon as the user acknowledges the completed phase.
            cycleOffsets = [0, 25, 50]
        }

        completionAlertGeneration &+= 1
        let generation = completionAlertGeneration
        for cycleOffset in cycleOffsets {
            for tone in pattern {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + cycleOffset + tone.delay
                ) { [weak self] in
                    guard let self,
                          self.completionAlertGeneration == generation,
                          self.configuredAlertStrength() == strength else { return }
                    self.playSystemSound(named: tone.name)
                }
            }
        }
    }

    private func beginCompletionAttention() {
        attentionGlowGeneration &+= 1
        let generation = attentionGlowGeneration
        isAwaitingAcknowledgement = true

        let duration = PomodoroGlowDuration(
            rawValue: WidgetDefaults.string(
                key: "glowDuration",
                widgetId: widgetId,
                default: PomodoroGlowDuration.thirtySeconds.rawValue
            )
        ) ?? .thirtySeconds
        guard let interval = duration.interval else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self,
                  self.attentionGlowGeneration == generation else { return }
            self.isAwaitingAcknowledgement = false
        }
    }

    private func acknowledgeCompletion() {
        isAwaitingAcknowledgement = false
        attentionGlowGeneration &+= 1
        cancelScheduledCompletionSounds()
    }

    private func cancelScheduledCompletionSounds() {
        completionAlertGeneration &+= 1
    }

    private func configuredAlertStrength() -> PomodoroAlertStrength {
        PomodoroAlertStrength(
            rawValue: WidgetDefaults.string(
                key: "alertStrength",
                widgetId: widgetId,
                default: PomodoroAlertStrength.noticeable.rawValue
            )
        ) ?? .noticeable
    }

    private func playSystemSound(named name: String) {
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.volume = 1
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private static let noticeableSoundPattern: [(delay: TimeInterval, name: String)] = [
        (0, "Hero"),
        (1.25, "Ping"),
        (2.6, "Hero"),
        (5.2, "Ping"),
        (8.0, "Hero"),
    ]

    private static let stateKey = "timerState"

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
