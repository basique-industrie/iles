import Domain
import Foundation
import Infrastructure

@MainActor
final class SessionComplicationSource: ComplicationSource {
    private let monitor: SessionMonitor
    private let isTrackingEnabled: @Sendable () -> Bool

    init(
        monitor: SessionMonitor,
        isTrackingEnabled: @escaping @Sendable () -> Bool = {
            JSONSettingsRepository.shared.isHookEnabled()
        }
    ) {
        self.monitor = monitor
        self.isTrackingEnabled = isTrackingEnabled
    }

    let descriptor = ComplicationSourceDescriptor(
        id: "session.claude",
        name: "Claude Code Session",
        kind: .session,
        symbol: "terminal",
        metrics: [
            ComplicationMetricDescriptor(id: "state", name: "Session state", kind: .status, symbol: "terminal"),
            ComplicationMetricDescriptor(id: "duration", name: "Duration", kind: .duration, symbol: "timer"),
            ComplicationMetricDescriptor(id: "tasks", name: "Completed tasks", kind: .value, symbol: "checkmark.square"),
            ComplicationMetricDescriptor(id: "agents", name: "Active agents", kind: .value, symbol: "person.2"),
            ComplicationMetricDescriptor(id: "project", name: "Current project", kind: .value, symbol: "folder"),
        ],
        supportedFamilies: [.value, .status, .activity, .summary],
        complications: FirstPartyComplicationCatalog.sessionRecipes,
        capabilities: [.sessionActivity]
    )

    var currentSnapshot: SourceSnapshot {
        guard isTrackingEnabled() else {
            return SourceSnapshot(
                sourceID: descriptor.id,
                values: [
                    "state": .status(label: "Off", level: .inactive),
                    "duration": .duration(0, label: "—"),
                    "tasks": .value("—", unit: nil),
                    "agents": .value("—", unit: nil),
                    "project": .value("—", unit: nil),
                ],
                errorDescription: "Enable Claude Code session tracking in Sources to receive live events.",
                quality: .unavailable,
                availability: ComplicationAvailability(
                    state: .setupRequired,
                    message: "Enable Claude Code hooks.",
                    recoveryAction: .configure
                )
            )
        }
        guard let session = monitor.activeSession else {
            return SourceSnapshot(sourceID: descriptor.id, values: [
                "state": .status(label: "Idle", level: .inactive),
                "duration": .duration(0, label: "0m"),
                "tasks": .value("0", unit: nil),
                "agents": .value("0", unit: nil),
                "project": .value("—", unit: nil),
            ])
        }
        let level: StatusLevel = switch session.phase {
        case .active, .subagentsWorking: .healthy
        case .stopped, .ended: .inactive
        }
        return SourceSnapshot(sourceID: descriptor.id, values: [
            "state": .status(label: session.phase.label, level: level),
            "duration": .duration(session.duration, label: session.durationDescription),
            "tasks": .value("\(session.completedTaskCount)", unit: nil),
            "agents": .value("\(session.activeSubagentCount)", unit: nil),
            "project": .value(URL(fileURLWithPath: session.cwd).lastPathComponent, unit: nil),
        ])
    }

    func refresh(_ kind: RefreshKind) async -> SourceSnapshot { currentSnapshot }
}
