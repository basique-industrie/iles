import Foundation

/// Represents an active or recent Claude Code session.
/// Tracks session lifecycle, subagent activity, and task completion.
public struct ClaudeSession: Sendable, Equatable, Identifiable {
    public let id: String
    public let cwd: String
    public let startedAt: Date
    public private(set) var phase: Phase
    public private(set) var activeSubagentCount: Int
    public private(set) var completedTaskCount: Int
    public private(set) var endedAt: Date?

    public init(
        id: String,
        cwd: String,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.cwd = cwd
        self.startedAt = startedAt
        self.phase = .active
        self.activeSubagentCount = 0
        self.completedTaskCount = 0
    }

    /// The current phase of the session
    public enum Phase: String, Sendable, Equatable {
        case active
        case subagentsWorking
        case stopped
        case ended

        /// Human-readable label for this phase
        public var label: String {
            switch self {
            case .active: return "Active"
            case .subagentsWorking: return "Agents Working"
            case .stopped: return "Stopped"
            case .ended: return "Ended"
            }
        }
    }

    // MARK: - Mutations

    /// Records a subagent starting work. Subagent activity also revives a
    /// `.stopped` session: a new turn is clearly underway, so the indicator
    /// should reflect work rather than staying stuck on the previous turn's stop.
    public mutating func subagentStarted() {
        guard phase != .ended else { return }
        activeSubagentCount += 1
        updatePhase()
    }

    /// Records a subagent stopping work
    public mutating func subagentStopped() {
        guard phase != .ended else { return }
        activeSubagentCount = max(0, activeSubagentCount - 1)
        updatePhase()
    }

    /// Revives a stopped/idle session when a new turn begins (UserPromptSubmit).
    /// `Stop` fires at the end of every turn, so without this a session would be
    /// stuck `.stopped` for the rest of its life. No-op once ended.
    public mutating func resume() {
        guard phase != .ended else { return }
        updatePhase()
    }

    /// Records a task completion
    public mutating func taskCompleted() {
        guard phase != .ended else { return }
        completedTaskCount += 1
    }

    /// Marks the session as stopped (Claude Code stopped responding)
    public mutating func stop() {
        guard phase != .ended else { return }
        phase = .stopped
        activeSubagentCount = 0
    }

    /// Marks the session as ended
    public mutating func end(at date: Date = Date()) {
        phase = .ended
        activeSubagentCount = 0
        endedAt = date
    }

    /// Whether this session is still active (not ended)
    public var isActive: Bool {
        phase != .ended
    }

    /// Duration of the session so far
    public var duration: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    /// Human-readable duration string
    public var durationDescription: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    // MARK: - Private

    private mutating func updatePhase() {
        if activeSubagentCount > 0 {
            phase = .subagentsWorking
        } else {
            phase = .active
        }
    }
}
