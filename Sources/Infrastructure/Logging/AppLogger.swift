import Foundation
import OSLog

/// Dual-output logger that writes to both OSLog (for developers) and file (for users).
///
/// This facade provides category-specific loggers that output to:
/// 1. **OSLog** - For Console.app, live streaming, and development debugging
/// 2. **File** - For user-accessible logs at ~/Library/Logs/Iles/Iles.log
///
/// ## Usage Examples
///
/// ```swift
/// // Monitor operations
/// AppLog.monitor.info("Starting refresh for \(providers.count) providers")
///
/// // Probe execution
/// AppLog.probes.debug("Executing Claude CLI probe")
/// AppLog.probes.error("CLI probe failed: \(error.localizedDescription)")
///
/// // Sensitive data - use sanitized messages for file logs
/// AppLog.credentials.info("Token loaded for provider")
/// ```
///
/// ## Log Levels
///
/// | Level | File Output | OSLog Persistence |
/// |-------|-------------|-------------------|
/// | debug | No | Memory only |
/// | info | Yes | With `log collect` |
/// | warning | Yes | Always persisted |
/// | error | Yes | Always persisted |
///
/// ## Viewing Logs
///
/// **File logs (for users):**
/// ```
/// ~/Library/Logs/Iles/Iles.log
/// ```
///
/// **OSLog (for developers):**
/// ```bash
/// log show --predicate 'subsystem == "com.jean.iles"' --info --debug --last 1h
/// ```
public enum AppLog {
    /// Logger for quota monitoring operations
    public static let monitor = CategoryLogger(category: "monitor")

    /// Logger for AI provider operations
    public static let providers = CategoryLogger(category: "providers")

    /// Logger for usage probe operations
    public static let probes = CategoryLogger(category: "probes")

    /// Logger for network operations
    public static let network = CategoryLogger(category: "network")

    /// Logger for credential operations
    public static let credentials = CategoryLogger(category: "credentials")

    /// Logger for UI operations
    public static let ui = CategoryLogger(category: "ui")

    /// Logger for update operations
    public static let updates = CategoryLogger(category: "updates")

    /// Logger for hook operations (Claude Code session tracking)
    public static let hooks = CategoryLogger(category: "hooks")

    /// Open the logs directory in Finder
    public static func openLogsDirectory() {
        FileLogger.shared.openLogsDirectory()
    }

    public static func openCurrentLogFile() {
        FileLogger.shared.openCurrentLogFile()
    }

    public static func clearLogs() {
        FileLogger.shared.clear()
    }

    public static func exportCurrentLog(to destination: URL) throws {
        try FileLogger.shared.exportCurrentLog(to: destination)
    }

    /// The URL to the logs directory
    public static var logsDirectoryURL: URL {
        FileLogger.shared.logsDirectory
    }
}

/// A category-specific logger that outputs to private OSLog entries and a
/// centrally redacted, bounded support log.
public struct CategoryLogger: Sendable {
    private let category: String
    private let osLogger: Logger

    init(category: String) {
        self.category = category
        let subsystem = Bundle.main.bundleIdentifier ?? "com.jean.iles"
        self.osLogger = Logger(subsystem: subsystem, category: category)
    }

    /// Log a private debug message to OSLog only.
    public func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .private)")
    }

    /// Log an informational message to private OSLog and the support log.
    public func info(_ message: String) {
        osLogger.info("\(message, privacy: .private)")
        FileLogger.shared.log(.info, category: category, message: message)
    }

    /// Log a notice to private OSLog and the support log.
    public func notice(_ message: String) {
        osLogger.notice("\(message, privacy: .private)")
        FileLogger.shared.log(.info, category: category, message: message)
    }

    /// Log a warning to private OSLog and the support log.
    public func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .private)")
        FileLogger.shared.log(.warning, category: category, message: message)
    }

    /// Log an error to private OSLog and the support log.
    public func error(_ message: String) {
        osLogger.error("\(message, privacy: .private)")
        FileLogger.shared.log(.error, category: category, message: message)
    }
}
