import Domain
import Foundation
import Infrastructure

@MainActor
final class FocusComplicationSource: ComplicationSource {
    enum Mode: String, Sendable {
        case idle
        case focus
        case breakTime
    }

    private struct State {
        var mode: Mode = .idle
        var startedAt: Date?
        var endsAt: Date?
        var duration: TimeInterval = 0
        var dayKey: String = ""
        var focusedSeconds: TimeInterval = 0
        var completedSessions: Int = 0
        var completedDays: [String] = []
    }

    private let store: JSONSettingsStore
    private let now: @Sendable () -> Date
    private var state: State
    private var cachedStreakDay = ""
    private var cachedStreakDays: [String] = []
    private var cachedStreakValue = 0

    let descriptor = ComplicationSourceDescriptor(
        id: "productivity.focus",
        name: "Focus",
        kind: .time,
        symbol: "scope",
        metrics: [
            ComplicationMetricDescriptor(id: "state", name: "Focus state", kind: .status, symbol: "scope", policy: ComplicationMetricPolicy(format: .status, refreshClass: .eventDriven)),
            ComplicationMetricDescriptor(id: "progress", name: "Session progress", kind: .gauge, symbol: "timer", unit: "%", policy: ComplicationMetricPolicy(format: .percentage, range: 0...100, refreshClass: .liveLocal)),
            ComplicationMetricDescriptor(id: "remaining", name: "Time remaining", kind: .duration, symbol: "timer", policy: ComplicationMetricPolicy(format: .duration, refreshClass: .liveLocal)),
            ComplicationMetricDescriptor(id: "elapsed", name: "Time elapsed", kind: .duration, symbol: "stopwatch", policy: ComplicationMetricPolicy(format: .duration, refreshClass: .liveLocal)),
            ComplicationMetricDescriptor(id: "dailyGoal", name: "Daily focus goal", kind: .gauge, symbol: "target", unit: "%", policy: ComplicationMetricPolicy(format: .percentage, range: 0...100, refreshClass: .liveLocal, keepsHistory: true)),
            ComplicationMetricDescriptor(id: "sessions", name: "Sessions today", kind: .value, symbol: "checkmark.circle", policy: ComplicationMetricPolicy(format: .count, refreshClass: .eventDriven)),
            ComplicationMetricDescriptor(id: "streak", name: "Focus streak", kind: .value, symbol: "flame", unit: "days", policy: ComplicationMetricPolicy(format: .count, refreshClass: .periodicLocal)),
        ],
        supportedFamilies: [.ring, .dualRing, .value, .status, .activity, .countdown, .trend, .summary],
        complications: FirstPartyComplicationCatalog.focusRecipes,
        capabilities: [.shortHistory]
    )

    init(
        store: JSONSettingsStore = .shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
        state = Self.load(from: store)
        normalizeDay(at: now())
    }

    var currentMode: Mode {
        reconcile(at: now())
        return state.mode
    }

    var currentSnapshot: SourceSnapshot {
        snapshot(at: now())
    }

    var dailyGoalMinutes: Int {
        min(max(store.read(key: "focus.dailyGoalMinutes") ?? 120, 15), 720)
    }

    func refresh(_ kind: RefreshKind) async -> SourceSnapshot {
        currentSnapshot
    }

    func startFocus(minutes: Int) {
        start(mode: .focus, minutes: minutes)
    }

    func startBreak(minutes: Int) {
        stopCurrent(at: now())
        start(mode: .breakTime, minutes: minutes)
    }

    func stop() {
        stopCurrent(at: now())
    }

    func setDailyGoal(minutes: Int) {
        store.write(value: min(max(minutes, 15), 720), key: "focus.dailyGoalMinutes")
        persist()
    }

    private func start(mode: Mode, minutes: Int) {
        let date = now()
        normalizeDay(at: date)
        if state.mode == .focus { stopCurrent(at: date) }
        let duration = TimeInterval(max(minutes, 1) * 60)
        state.mode = mode
        state.startedAt = date
        state.endsAt = date.addingTimeInterval(duration)
        state.duration = duration
        persist()
    }

    private func snapshot(at date: Date) -> SourceSnapshot {
        reconcile(at: date)
        let active = state.mode != .idle
        let elapsed = active ? min(max(date.timeIntervalSince(state.startedAt ?? date), 0), state.duration) : 0
        let remaining = active ? max((state.endsAt ?? date).timeIntervalSince(date), 0) : 0
        let progress = state.duration > 0 && active ? elapsed / state.duration * 100 : 0
        let dailySeconds = state.focusedSeconds + (state.mode == .focus ? elapsed : 0)
        let dailyGoalSeconds = TimeInterval(dailyGoalMinutes * 60)
        let dailyPercent = min(dailySeconds / dailyGoalSeconds * 100, 100)

        let stateValue: ComplicationValue
        switch state.mode {
        case .idle: stateValue = .status(label: "Ready", level: .inactive)
        case .focus: stateValue = .status(label: "Focusing", level: .healthy)
        case .breakTime: stateValue = .status(label: "Break", level: .warning)
        }

        return SourceSnapshot(sourceID: descriptor.id, capturedAt: date, values: [
            "state": stateValue,
            "progress": .gauge(value: progress, range: 0...100, label: "\(Int(progress.rounded()))%"),
            "remaining": .duration(remaining, label: Self.durationLabel(remaining)),
            "elapsed": .duration(elapsed, label: Self.durationLabel(elapsed)),
            "dailyGoal": .gauge(value: dailyPercent, range: 0...100, label: Self.durationLabel(dailySeconds)),
            "sessions": .value("\(state.completedSessions)", unit: nil),
            "streak": .value("\(streakValue())", unit: "days"),
        ])
    }

    private func reconcile(at date: Date) {
        normalizeDay(at: date)
        guard state.mode != .idle, let endsAt = state.endsAt, date >= endsAt else { return }
        if state.mode == .focus {
            recordFocus(seconds: state.duration, completed: true)
        }
        clearSession()
        persist()
    }

    private func stopCurrent(at date: Date) {
        normalizeDay(at: date)
        guard state.mode != .idle else { return }
        if state.mode == .focus {
            let elapsed = min(max(date.timeIntervalSince(state.startedAt ?? date), 0), state.duration)
            recordFocus(seconds: elapsed, completed: false)
        }
        clearSession()
        persist()
    }

    private func recordFocus(seconds: TimeInterval, completed: Bool) {
        guard seconds > 0 else { return }
        state.focusedSeconds += seconds
        if completed { state.completedSessions += 1 }
        if state.focusedSeconds >= TimeInterval(dailyGoalMinutes * 60),
           !state.completedDays.contains(state.dayKey) {
            state.completedDays.append(state.dayKey)
            state.completedDays = Array(state.completedDays.suffix(60))
        }
    }

    private func clearSession() {
        state.mode = .idle
        state.startedAt = nil
        state.endsAt = nil
        state.duration = 0
    }

    private func normalizeDay(at date: Date) {
        let key = Self.dayKey(for: date)
        guard state.dayKey != key else { return }
        state.dayKey = key
        state.focusedSeconds = 0
        state.completedSessions = 0
        clearSession()
        persist()
    }

    private func persist() {
        var object: [String: Any] = [
            "mode": state.mode.rawValue,
            "duration": state.duration,
            "day": state.dayKey,
            "focusedSeconds": state.focusedSeconds,
            "completedSessions": state.completedSessions,
            "completedDays": state.completedDays,
        ]
        if let startedAt = state.startedAt { object["startedAt"] = startedAt.timeIntervalSince1970 }
        if let endsAt = state.endsAt { object["endsAt"] = endsAt.timeIntervalSince1970 }
        store.write(value: object, key: "focus")
    }

    private static func load(from store: JSONSettingsStore) -> State {
        guard let object: [String: Any] = store.read(key: "focus") else { return State() }
        var state = State()
        state.mode = (object["mode"] as? String).flatMap(Mode.init(rawValue:)) ?? .idle
        state.duration = (object["duration"] as? NSNumber)?.doubleValue ?? 0
        state.dayKey = object["day"] as? String ?? ""
        state.focusedSeconds = (object["focusedSeconds"] as? NSNumber)?.doubleValue ?? 0
        state.completedSessions = (object["completedSessions"] as? NSNumber)?.intValue ?? 0
        state.completedDays = object["completedDays"] as? [String] ?? []
        if let timestamp = (object["startedAt"] as? NSNumber)?.doubleValue {
            state.startedAt = Date(timeIntervalSince1970: timestamp)
        }
        if let timestamp = (object["endsAt"] as? NSNumber)?.doubleValue {
            state.endsAt = Date(timeIntervalSince1970: timestamp)
        }
        return state
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func streak(in completedDays: [String], through today: String) -> Int {
        guard !completedDays.isEmpty else { return 0 }
        let parts = today.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              var date = Calendar.current.date(
                  from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
              )
        else { return 0 }
        let completed = Set(completedDays)
        var count = 0
        while completed.contains(dayKey(for: date)) {
            count += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return count
    }

    private func streakValue() -> Int {
        guard cachedStreakDay != state.dayKey || cachedStreakDays != state.completedDays else {
            return cachedStreakValue
        }
        cachedStreakDay = state.dayKey
        cachedStreakDays = state.completedDays
        cachedStreakValue = Self.streak(in: state.completedDays, through: state.dayKey)
        return cachedStreakValue
    }

    private static func durationLabel(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds / 60 % 60
        let seconds = totalSeconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }
}
