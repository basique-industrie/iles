import Foundation

/// Represents a hook event received from Claude Code.
/// These events map directly to Claude Code's hook system events.
public struct SessionEvent: Sendable, Equatable, Codable {
    /// The session ID from Claude Code
    public let sessionId: String

    /// The type of hook event
    public let eventName: EventName

    /// The working directory where Claude Code is running
    public let cwd: String

    /// When this event was received
    public let receivedAt: Date

    public init(
        sessionId: String,
        eventName: EventName,
        cwd: String,
        receivedAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.eventName = eventName
        self.cwd = cwd
        self.receivedAt = receivedAt
    }

    /// Whether this event originates from Iles’ own quota probe.
    ///
    /// Iles refreshes quotas by spawning `claude /usage` in
    /// `<AppSupport>/Iles/Probe`. Claude Code fires SessionStart/SessionEnd
    /// hooks for that run, which loop back into the app's hook server. These
    /// events must be ignored so routine background polling doesn't pollute the
    /// recent-sessions list.
    /// (issue #172)
    public var isIlesProbe: Bool {
        let components = ((cwd as NSString).standardizingPath as NSString).pathComponents
        let suffix = Array(components.suffix(2))
        return suffix == ["Iles", "Probe"]
    }

    /// The types of hook events from Claude Code
    public enum EventName: String, Sendable, Equatable, Codable {
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case taskCompleted = "TaskCompleted"
        case subagentStart = "SubagentStart"
        case subagentStop = "SubagentStop"
        case stop = "Stop"
        /// Fires at the start of every turn (before Claude processes the prompt).
        /// Used to revive a session out of `.stopped` so the indicator tracks
        /// real activity instead of sticking on the end-of-turn `Stop`.
        case userPromptSubmit = "UserPromptSubmit"
    }
}
