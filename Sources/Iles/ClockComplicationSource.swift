import Domain
import Foundation
import Infrastructure

@MainActor
final class ClockComplicationSource: ComplicationSource {
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let store: JSONSettingsStore

    init(
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        store: JSONSettingsStore = .shared
    ) {
        self.calendar = calendar
        self.now = now
        self.store = store
    }

    var workdayStartHour: Int { min(max(store.read(key: "clock.workdayStartHour") ?? 9, 0), 22) }
    var workdayEndHour: Int { min(max(store.read(key: "clock.workdayEndHour") ?? 17, workdayStartHour + 1), 23) }

    func setWorkday(startHour: Int, endHour: Int) {
        let start = min(max(startHour, 0), 22)
        let end = min(max(endHour, start + 1), 23)
        store.write(value: start, key: "clock.workdayStartHour")
        store.write(value: end, key: "clock.workdayEndHour")
    }

    let descriptor = ComplicationSourceDescriptor(
        id: "system.clock",
        name: "Clock",
        kind: .time,
        symbol: "clock",
        metrics: [
            ComplicationMetricDescriptor(id: "dayProgress", name: "Day progress", kind: .gauge, symbol: "sun.max", unit: "%"),
            ComplicationMetricDescriptor(id: "workdayProgress", name: "Workday progress", kind: .gauge, symbol: "briefcase", unit: "%"),
            ComplicationMetricDescriptor(id: "weekProgress", name: "Week progress", kind: .gauge, symbol: "calendar", unit: "%"),
            ComplicationMetricDescriptor(id: "monthProgress", name: "Month progress", kind: .gauge, symbol: "calendar", unit: "%"),
            ComplicationMetricDescriptor(id: "yearProgress", name: "Year progress", kind: .gauge, symbol: "calendar.badge.clock", unit: "%"),
            ComplicationMetricDescriptor(id: "time", name: "Current time", kind: .date, symbol: "clock"),
            ComplicationMetricDescriptor(id: "endOfDay", name: "End of day", kind: .date, symbol: "moon.stars"),
        ],
        supportedFamilies: [.ring, .value, .countdown],
        complications: FirstPartyComplicationCatalog.clockRecipes
    )

    var currentSnapshot: SourceSnapshot { snapshot(at: now()) }
    func refresh(_ kind: RefreshKind) async -> SourceSnapshot { currentSnapshot }

    private func snapshot(at date: Date) -> SourceSnapshot {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        let timeLabel = String(format: "%02d:%02d", time.hour ?? 0, time.minute ?? 0)
        let start = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return SourceSnapshot(sourceID: descriptor.id, capturedAt: date, values: [
            "time": .date(date, label: timeLabel),
            "dayProgress": progressValue(date: date, start: start, end: endOfDay),
            "workdayProgress": progressValue(
                date: date,
                start: calendar.date(bySettingHour: workdayStartHour, minute: 0, second: 0, of: date) ?? start,
                end: calendar.date(bySettingHour: workdayEndHour, minute: 0, second: 0, of: date) ?? endOfDay
            ),
            "weekProgress": intervalProgress(component: .weekOfYear, date: date),
            "monthProgress": intervalProgress(component: .month, date: date),
            "yearProgress": intervalProgress(component: .year, date: date),
            "endOfDay": .date(
                endOfDay,
                label: CompactDurationFormatter.hoursMinutes(endOfDay.timeIntervalSince(date))
            ),
        ])
    }

    private func intervalProgress(component: Calendar.Component, date: Date) -> ComplicationValue {
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            return .gauge(value: 0, range: 0...1, label: "—")
        }
        return progressValue(date: date, start: interval.start, end: interval.end)
    }

    private func progressValue(date: Date, start: Date, end: Date) -> ComplicationValue {
        let total = max(end.timeIntervalSince(start), 1)
        let elapsed = min(max(date.timeIntervalSince(start), 0), total)
        let percent = elapsed / total * 100
        return .gauge(value: percent, range: 0...100, label: "\(Int(percent.rounded()))%")
    }

}
