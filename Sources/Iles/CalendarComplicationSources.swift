@preconcurrency import EventKit
import Domain
import Foundation

@MainActor
final class CalendarDataStore {
    struct ReminderRecord: Sendable {
        let title: String
        let dueDate: Date?
    }

    let eventStore = EKEventStore()

    var eventAuthorization: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    var reminderAuthorization: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestEventAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    func requestReminderAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    func events(from start: Date, to end: Date) -> [EKEvent] {
        eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
    }

    func incompleteReminders() async -> [ReminderRecord] {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map {
                    ReminderRecord(title: $0.title, dueDate: $0.dueDateComponents?.date)
                })
            }
        }
    }

    static func hasReadAccess(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }
}

@MainActor
protocol PermissionComplicationSource: AnyObject {
    var permissionName: String { get }
    var permissionStatusText: String { get }
    var canRequestPermission: Bool { get }
    func requestPermission() async -> Bool
}

@MainActor
final class CalendarComplicationSource: ComplicationSource, PermissionComplicationSource {
    private let dataStore: CalendarDataStore
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var cachedSnapshot: SourceSnapshot
    private var cachedEvents: [EKEvent] = []
    private var eventsFetchedAt: Date?

    let permissionName = "Calendar Access"

    let descriptor = ComplicationSourceDescriptor(
        id: "calendar.events",
        name: "Calendar",
        kind: .time,
        symbol: "calendar",
        metrics: [
            ComplicationMetricDescriptor(id: "currentState", name: "Current event", kind: .status, symbol: "person.2", policy: ComplicationMetricPolicy(format: .status, privacy: .sensitive, refreshClass: .periodicLocal, staleAfter: 60)),
            ComplicationMetricDescriptor(id: "nextTitle", name: "Next event", kind: .value, symbol: "calendar", policy: ComplicationMetricPolicy(format: .text, privacy: .sensitive, refreshClass: .periodicLocal, staleAfter: 60)),
            ComplicationMetricDescriptor(id: "nextStart", name: "Next event start", kind: .date, symbol: "calendar.badge.clock", policy: ComplicationMetricPolicy(format: .date, privacy: .sensitive, refreshClass: .periodicLocal, staleAfter: 60)),
            ComplicationMetricDescriptor(id: "nextDuration", name: "Next event duration", kind: .duration, symbol: "timer", policy: ComplicationMetricPolicy(format: .duration, privacy: .sensitive, refreshClass: .periodicLocal, staleAfter: 60)),
            ComplicationMetricDescriptor(id: "meetingProgress", name: "Meeting progress", kind: .gauge, symbol: "chart.pie", unit: "%", policy: ComplicationMetricPolicy(format: .percentage, range: 0...100, privacy: .sensitive, refreshClass: .liveLocal, staleAfter: 10)),
            ComplicationMetricDescriptor(id: "eventsToday", name: "Events today", kind: .value, symbol: "calendar.badge", policy: ComplicationMetricPolicy(format: .count, privacy: .personal, refreshClass: .periodicLocal, staleAfter: 60)),
        ],
        supportedFamilies: [.ring, .value, .status, .activity, .countdown, .summary],
        complications: FirstPartyComplicationCatalog.calendarRecipes,
        capabilities: [.calendarRead]
    )

    init(
        dataStore: CalendarDataStore,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.dataStore = dataStore
        self.calendar = calendar
        self.now = now
        cachedSnapshot = Self.permissionSnapshot(status: dataStore.eventAuthorization)
    }

    var currentSnapshot: SourceSnapshot { cachedSnapshot }

    var permissionStatusText: String {
        switch dataStore.eventAuthorization {
        case .fullAccess: "Connected"
        case .notDetermined: "Not Requested"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .writeOnly: "Read Access Required"
        default: "Unavailable"
        }
    }

    var canRequestPermission: Bool {
        dataStore.eventAuthorization == .notDetermined
    }

    func requestPermission() async -> Bool {
        let granted = await dataStore.requestEventAccess()
        eventsFetchedAt = nil
        cachedSnapshot = makeSnapshot(at: now())
        return granted
    }

    func refresh(_ kind: RefreshKind) async -> SourceSnapshot {
        cachedSnapshot = makeSnapshot(at: now())
        return cachedSnapshot
    }

    private func makeSnapshot(at date: Date) -> SourceSnapshot {
        guard CalendarDataStore.hasReadAccess(dataStore.eventAuthorization) else {
            return Self.permissionSnapshot(status: dataStore.eventAuthorization)
        }
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        let horizon = calendar.date(byAdding: .day, value: 7, to: date) ?? endOfDay
        let events: [EKEvent]
        if let eventsFetchedAt, date.timeIntervalSince(eventsFetchedAt) < 30 {
            events = cachedEvents
        } else {
            events = dataStore.events(from: startOfDay, to: horizon).filter { !$0.isAllDay }
            cachedEvents = events
            eventsFetchedAt = date
        }
        let eventsToday = events.filter { $0.startDate < endOfDay && $0.endDate > startOfDay }
        let current = events.first { $0.startDate <= date && $0.endDate > date }
        let next = events.first { $0.startDate > date }
        let displayEvent = current ?? next

        var values: [String: ComplicationValue] = [
            "eventsToday": .value("\(eventsToday.count)", unit: nil),
            "currentState": current.map { .status(label: "In \($0.title ?? "Meeting")", level: .warning) }
                ?? .status(label: next == nil ? "Free" : "Available", level: .healthy),
        ]
        if let displayEvent {
            values["nextTitle"] = .value(displayEvent.title?.isEmpty == false ? displayEvent.title : "Untitled Event", unit: nil)
            let duration = max(displayEvent.endDate.timeIntervalSince(displayEvent.startDate), 0)
            values["nextDuration"] = .duration(duration, label: CompactDurationFormatter.hoursMinutes(duration))
        }
        if let next {
            values["nextStart"] = .date(next.startDate, label: Self.countdownLabel(to: next.startDate, from: date))
        }
        if let current {
            let duration = max(current.endDate.timeIntervalSince(current.startDate), 1)
            let elapsed = min(max(date.timeIntervalSince(current.startDate), 0), duration)
            let progress = elapsed / duration * 100
            values["meetingProgress"] = .gauge(value: progress, range: 0...100, label: "\(Int(progress.rounded()))%")
        }
        return SourceSnapshot(sourceID: descriptor.id, capturedAt: date, values: values)
    }

    private static func permissionSnapshot(status: EKAuthorizationStatus) -> SourceSnapshot {
        let denied = status == .denied || status == .restricted || status == .writeOnly
        return SourceSnapshot(
            sourceID: "calendar.events",
            values: [:],
            errorDescription: denied
                ? "Calendar read access is disabled. Enable it in System Settings to use event complications."
                : "Connect Calendar to add event and meeting complications.",
            quality: .unavailable,
            availability: ComplicationAvailability(
                state: .permissionRequired,
                message: "Calendar access is required.",
                recoveryAction: denied ? .openSettings : .requestPermission
            )
        )
    }

    private static func countdownLabel(to target: Date, from date: Date) -> String {
        CompactDurationFormatter.hoursMinutes(target.timeIntervalSince(date))
    }
}

@MainActor
final class ReminderComplicationSource: ComplicationSource, PermissionComplicationSource {
    private let dataStore: CalendarDataStore
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var cachedSnapshot: SourceSnapshot

    let permissionName = "Reminders Access"

    let descriptor = ComplicationSourceDescriptor(
        id: "calendar.reminders",
        name: "Reminders",
        kind: .time,
        symbol: "checklist",
        metrics: [
            ComplicationMetricDescriptor(id: "dueToday", name: "Due today", kind: .value, symbol: "checklist", policy: ComplicationMetricPolicy(format: .count, privacy: .sensitive, refreshClass: .periodicLocal, staleAfter: 60)),
            ComplicationMetricDescriptor(id: "overdue", name: "Overdue", kind: .value, symbol: "exclamationmark.triangle", policy: ComplicationMetricPolicy(format: .count, direction: .lowerIsBetter, privacy: .sensitive, refreshClass: .periodicLocal, staleAfter: 60)),
            ComplicationMetricDescriptor(id: "nextTitle", name: "Next reminder", kind: .value, symbol: "list.bullet.clipboard", policy: ComplicationMetricPolicy(format: .text, privacy: .sensitive, refreshClass: .periodicLocal, staleAfter: 60)),
            ComplicationMetricDescriptor(id: "nextDue", name: "Next due date", kind: .date, symbol: "calendar.badge.clock", policy: ComplicationMetricPolicy(format: .date, privacy: .sensitive, refreshClass: .periodicLocal, staleAfter: 60)),
            ComplicationMetricDescriptor(id: "state", name: "Reminder status", kind: .status, symbol: "checkmark.circle", policy: ComplicationMetricPolicy(format: .status, privacy: .sensitive, refreshClass: .periodicLocal, staleAfter: 60)),
        ],
        supportedFamilies: [.value, .status, .countdown, .summary],
        complications: FirstPartyComplicationCatalog.reminderRecipes,
        capabilities: [.remindersRead]
    )

    init(
        dataStore: CalendarDataStore,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.dataStore = dataStore
        self.calendar = calendar
        self.now = now
        cachedSnapshot = Self.permissionSnapshot(status: dataStore.reminderAuthorization)
    }

    var currentSnapshot: SourceSnapshot { cachedSnapshot }

    var permissionStatusText: String {
        switch dataStore.reminderAuthorization {
        case .fullAccess: "Connected"
        case .notDetermined: "Not Requested"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .writeOnly: "Read Access Required"
        default: "Unavailable"
        }
    }

    var canRequestPermission: Bool {
        dataStore.reminderAuthorization == .notDetermined
    }

    func requestPermission() async -> Bool {
        let granted = await dataStore.requestReminderAccess()
        cachedSnapshot = await makeSnapshot(at: now())
        return granted
    }

    func refresh(_ kind: RefreshKind) async -> SourceSnapshot {
        cachedSnapshot = await makeSnapshot(at: now())
        return cachedSnapshot
    }

    private func makeSnapshot(at date: Date) async -> SourceSnapshot {
        guard CalendarDataStore.hasReadAccess(dataStore.reminderAuthorization) else {
            return Self.permissionSnapshot(status: dataStore.reminderAuthorization)
        }
        let reminders = await dataStore.incompleteReminders()
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        let dueToday = reminders.filter { reminder in
            guard let due = reminder.dueDate else { return false }
            return due >= start && due < end
        }
        let overdue = reminders.filter { ($0.dueDate ?? .distantFuture) < date }
        let next = reminders
            .filter { ($0.dueDate ?? .distantPast) >= date }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .first

        var values: [String: ComplicationValue] = [
            "dueToday": .value("\(dueToday.count)", unit: nil),
            "overdue": .value("\(overdue.count)", unit: nil),
            "state": .status(
                label: overdue.isEmpty ? "On Track" : "\(overdue.count) Overdue",
                level: overdue.isEmpty ? .healthy : .critical
            ),
        ]
        if let next {
            values["nextTitle"] = .value(next.title, unit: nil)
            if let dueDate = next.dueDate {
                values["nextDue"] = .date(
                    dueDate,
                    label: CompactDurationFormatter.hoursMinutes(dueDate.timeIntervalSince(date))
                )
            }
        }
        return SourceSnapshot(sourceID: descriptor.id, capturedAt: date, values: values)
    }

    private static func permissionSnapshot(status: EKAuthorizationStatus) -> SourceSnapshot {
        let denied = status == .denied || status == .restricted || status == .writeOnly
        return SourceSnapshot(
            sourceID: "calendar.reminders",
            values: [:],
            errorDescription: denied
                ? "Reminders access is disabled. Enable it in System Settings to use reminder complications."
                : "Connect Reminders to add task and due-date complications.",
            quality: .unavailable,
            availability: ComplicationAvailability(
                state: .permissionRequired,
                message: "Reminders access is required.",
                recoveryAction: denied ? .openSettings : .requestPermission
            )
        )
    }
}
