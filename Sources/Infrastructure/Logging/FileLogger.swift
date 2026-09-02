import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// File-based logger that writes to the identity-specific support log.
/// Provides user-accessible logs for debugging and support.
///
/// Thread-safety: All file operations are serialized on a dedicated dispatch queue.
/// The class is marked `Sendable` because:
/// - `fileURL` and `maxFileSize` are immutable after init
/// - `queue` is a serial queue that serializes all mutable state access
/// - Timestamp formatting happens inside the serial queue
public final class FileLogger: @unchecked Sendable {
    public static let shared = FileLogger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.jean.iles.FileLogger")
    private let maxFileSize: UInt64
    private var fileHandle: FileHandle?
    private var currentFileSize: UInt64?
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return formatter
    }()

    /// The directory containing log files
    public var logsDirectory: URL {
        fileURL.deletingLastPathComponent()
    }

    private convenience init() {
        self.init(fileURL: AppIdentity.current.logFileURL)
    }

    init(fileURL: URL, maxFileSize: UInt64 = 5 * 1024 * 1024) {
        let logsDir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: logsDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: logsDir.path)
        } catch {
            NSLog("[FileLogger] Failed to create logs directory at %@: %@", logsDir.path, error.localizedDescription)
        }
        self.fileURL = fileURL
        self.maxFileSize = maxFileSize
    }

    /// Creates a thread-safe timestamp string.
    /// Called only from within the serial queue.
    private func timestamp() -> String {
        timestampFormatter.string(from: Date())
    }

    /// Log levels matching OSLog conventions
    public enum Level: String, Sendable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }

    /// Write a log entry to the file
    public func log(_ level: Level, category: String, message: String) {
        queue.async { [self] in
            let ts = timestamp()
            let safeMessage = LogRedactor.redact(message)
            let line = "[\(ts)] [\(level.rawValue)] [\(category)] \(safeMessage)\n"

            if let data = line.data(using: .utf8) {
                _ = writingHandle()
                rotateIfNeeded(incomingBytes: UInt64(data.count))
                if let handle = writingHandle() {
                    handle.write(data)
                    currentFileSize = (currentFileSize ?? 0) + UInt64(data.count)
                }
            }
        }
    }

    /// Rotate based on the tracked handle offset instead of stat-ing the file
    /// for every log message.
    private func rotateIfNeeded(incomingBytes: UInt64) {
        guard let currentFileSize,
              currentFileSize + incomingBytes > maxFileSize else { return }

        try? fileHandle?.close()
        fileHandle = nil
        self.currentFileSize = nil
        let oldURL = fileURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: fileURL, to: oldURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: oldURL.path)
    }

    private func writingHandle() -> FileHandle? {
        if let fileHandle { return fileHandle }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(
                atPath: fileURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        fileHandle = try? FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()
        currentFileSize = fileHandle?.offsetInFile
        return fileHandle
    }

    /// Open the logs directory in Finder
    public func openLogsDirectory() {
        NSWorkspace.shared.open(logsDirectory)
    }

    /// Open the current log file in TextEdit
    public func openCurrentLogFile() {
        NSWorkspace.shared.open(fileURL)
    }

    /// Deletes current and rotated diagnostics. New entries recreate the file
    /// with owner-only permissions.
    public func clear() {
        queue.sync { [self] in
            try? fileHandle?.close()
            fileHandle = nil
            currentFileSize = nil
            try? FileManager.default.removeItem(at: fileURL)
            let oldURL = fileURL.deletingPathExtension().appendingPathExtension("old.log")
            try? FileManager.default.removeItem(at: oldURL)
        }
    }

    /// Copies the already-redacted current log only after an explicit user action.
    public func exportCurrentLog(to destination: URL) throws {
        try queue.sync { [self] in
            try fileHandle?.synchronize()
            let data = (try? Data(contentsOf: fileURL)) ?? Data()
            try data.write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
    }
}
