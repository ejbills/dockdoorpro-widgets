import AppKit
import Combine
import DockDoorWidgetSDK
import Foundation

enum PomodoroPhase: String, Codable, CaseIterable, Identifiable {
    case focus
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus:
            return PomodoroL10n.text("专注", "Focus")
        case .shortBreak:
            return PomodoroL10n.text("短休息", "Short Break")
        case .longBreak:
            return PomodoroL10n.text("长休息", "Long Break")
        }
    }

    var compactTitle: String {
        switch self {
        case .focus:
            return PomodoroL10n.text("专注", "FOCUS")
        case .shortBreak:
            return PomodoroL10n.text("休息", "BREAK")
        case .longBreak:
            return PomodoroL10n.text("长休", "LONG")
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

final class PomodoroTimerModel: ObservableObject {
    @Published private(set) var phase: PomodoroPhase = .focus
    @Published private(set) var runState: PomodoroRunState = .idle
    @Published private(set) var remainingSeconds = 25 * 60
    @Published private(set) var totalSeconds = 25 * 60
    @Published private(set) var completedToday = 0
    @Published private(set) var cycleFocusCount = 0
    @Published private(set) var completionPulse = 0

    let widgetId: String

    private var endDate: Date?
    private var ticker: Timer?
    private var defaultsObserver: NSObjectProtocol?

    init(widgetId: String) {
        self.widgetId = widgetId
        restore()
        normalizeDayIfNeeded()
        reconcileRestoredTimer()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.settingsDidChange()
        }
    }

    deinit {
        ticker?.invalidate()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    var isRunning: Bool { runState == .running }
    var isPaused: Bool { runState == .paused }

    var remainingFraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(remainingSeconds) / Double(totalSeconds)))
    }

    var elapsedFraction: Double { 1 - remainingFraction }

    var displayTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var compactValue: String {
        if remainingSeconds >= 60 {
            return String(Int(ceil(Double(remainingSeconds) / 60)))
        }
        return String(remainingSeconds)
    }

    var compactUnit: String {
        remainingSeconds >= 60
            ? PomodoroL10n.text("分", "MIN")
            : PomodoroL10n.text("秒", "SEC")
    }

    var statusText: String {
        switch runState {
        case .idle:
            return PomodoroL10n.text("准备开始", "Ready")
        case .running:
            return PomodoroL10n.text("进行中", "In progress")
        case .paused:
            return PomodoroL10n.text("已暂停", "Paused")
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

    func toggleTimer() {
        switch runState {
        case .running:
            pause()
        case .idle, .paused:
            start()
        }
    }

    func start() {
        normalizeDayIfNeeded()
        if remainingSeconds <= 0 {
            configureCurrentPhase()
        }
        runState = .running
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        startTicker()
        persist()
    }

    func pause() {
        guard runState == .running else { return }
        updateRemainingTime()
        runState = .paused
        endDate = nil
        stopTicker()
        persist()
    }

    func reset() {
        stopTicker()
        runState = .idle
        endDate = nil
        configureCurrentPhase()
        persist()
    }

    func skip() {
        stopTicker()
        runState = .idle
        endDate = nil
        phase = nextPhase
        configureCurrentPhase()
        persist()
    }

    func selectPhase(_ newPhase: PomodoroPhase) {
        guard newPhase != phase || runState != .idle else { return }
        stopTicker()
        phase = newPhase
        runState = .idle
        endDate = nil
        configureCurrentPhase()
        persist()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        normalizeDayIfNeeded()
        guard runState == .running else { return }
        updateRemainingTime()
        if remainingSeconds <= 0 {
            finishCurrentPhase(playSound: true)
        }
    }

    private func updateRemainingTime() {
        guard let endDate else { return }
        let next = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        if next != remainingSeconds {
            remainingSeconds = next
        }
    }

    private func finishCurrentPhase(playSound: Bool) {
        stopTicker()
        let completedPhase = phase

        if completedPhase == .focus {
            completedToday += 1
            cycleFocusCount += 1
        }

        if playSound,
           WidgetDefaults.bool(
               key: "playSound",
               widgetId: widgetId,
               default: true
           ) {
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
            endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            startTicker()
        } else {
            runState = .idle
            endDate = nil
        }
        persist()
    }

    private func configureCurrentPhase() {
        let duration = durationSeconds(for: phase)
        totalSeconds = duration
        remainingSeconds = duration
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

    private func settingsDidChange() {
        let desiredDuration = durationSeconds(for: phase)
        if runState == .idle,
           (totalSeconds != desiredDuration || remainingSeconds != desiredDuration) {
            totalSeconds = desiredDuration
            remainingSeconds = desiredDuration
            persist()
        } else {
            objectWillChange.send()
        }
    }

    private func normalizeDayIfNeeded() {
        let today = Self.dayKey()
        let stored = UserDefaults.standard.string(forKey: Self.dayKeyStorageKey(widgetId))
        guard stored != today else { return }
        completedToday = 0
        cycleFocusCount = 0
        UserDefaults.standard.set(today, forKey: Self.dayKeyStorageKey(widgetId))
        persist()
    }

    private func reconcileRestoredTimer() {
        guard runState == .running, let endDate else {
            if runState == .running {
                runState = .paused
            }
            return
        }

        remainingSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        if remainingSeconds <= 0 {
            finishCurrentPhase(playSound: false)
        } else {
            startTicker()
        }
    }

    private func persist() {
        let state = PomodoroSavedState(
            phase: phase,
            runState: runState,
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds,
            endDate: endDate,
            completedToday: completedToday,
            cycleFocusCount: cycleFocusCount,
            dayKey: Self.dayKey()
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.stateStorageKey(widgetId))
        UserDefaults.standard.set(
            Self.dayKey(),
            forKey: Self.dayKeyStorageKey(widgetId)
        )
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(
            forKey: Self.stateStorageKey(widgetId)
        ),
        let saved = try? JSONDecoder().decode(
            PomodoroSavedState.self,
            from: data
        ) else {
            configureCurrentPhase()
            return
        }

        phase = saved.phase
        runState = saved.runState
        remainingSeconds = max(0, saved.remainingSeconds)
        totalSeconds = max(1, saved.totalSeconds)
        endDate = saved.endDate
        completedToday = max(0, saved.completedToday)
        cycleFocusCount = max(0, saved.cycleFocusCount)

        if saved.dayKey != Self.dayKey() {
            completedToday = 0
            cycleFocusCount = 0
        }
    }

    private func playCompletionSound() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private static func stateStorageKey(_ widgetId: String) -> String {
        "widget.\(widgetId).timerState"
    }

    private static func dayKeyStorageKey(_ widgetId: String) -> String {
        "widget.\(widgetId).timerDay"
    }

    private static func dayKey() -> String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: Date()
        )
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
