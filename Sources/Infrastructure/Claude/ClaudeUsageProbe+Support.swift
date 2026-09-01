import Domain
import Foundation

extension ClaudeUsageProbe {
    // MARK: - Error Detection

    internal func extractUsageError(_ text: String) -> ProbeError? {
        let lower = text.lowercased()

        if (lower.contains("do you trust the files in this folder?") ||
            lower.contains("is this a project you created or one you trust")),
           !lower.contains("current session") {
            AppLog.probes.error("Claude probe blocked: folder trust required")
            return .folderTrustRequired
        }

        if lower.contains("token_expired") || lower.contains("token has expired") {
            AppLog.probes.error("Claude probe failed: token has expired, re-authentication required")
            return .authenticationRequired
        }

        if lower.contains("authentication_error") {
            AppLog.probes.error("Claude probe failed: authentication error, login required")
            return .authenticationRequired
        }

        if lower.contains("not logged in") || lower.contains("please log in") {
            AppLog.probes.error("Claude probe failed: not logged in")
            return .authenticationRequired
        }

        if lower.contains("update required") || lower.contains("please update") {
            AppLog.probes.error("Claude probe failed: CLI update required")
            return .updateRequired
        }

        if lower.contains("/usage is only available for subscription plans") {
            AppLog.probes.info("Claude /usage unavailable for this account: subscription required")
            return .subscriptionRequired
        }

        // Check for rate limit errors, but exclude promotional messages like "rate limits are 2x higher"
        let isRateLimitError = (lower.contains("rate limited") ||
                                lower.contains("rate limit exceeded") ||
                                lower.contains("too many requests")) &&
                               !lower.contains("rate limits are")
        if isRateLimitError {
            AppLog.probes.warning("Claude probe hit rate limit")
            return .executionFailed("Rate limited - too many requests")
        }

        return nil
    }

    internal func extractFolderFromTrustPrompt(_ text: String) -> String? {
        let pattern = #"Do you trust the files in this folder\?\s*(?:\r?\n)+\s*([^\r\n]+)"#
        return extractFirst(pattern: pattern, text: text)
    }

    // MARK: - Helpers

    /// Writes a trust entry for the given directory to ~/.claude.json so the CLI
    /// won't show the workspace trust dialog on next invocation.
    /// Returns true if the write succeeded.
    internal func writeClaudeTrust(for directory: URL) -> Bool {
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
        let claudeJsonURL = (configDir ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent(".claude.json")

        guard FileManager.default.fileExists(atPath: claudeJsonURL.path) else {
            AppLog.probes.warning("\(claudeJsonURL.path) not found, cannot write trust")
            return false
        }

        var root: [String: Any]
        if let data = try? Data(contentsOf: claudeJsonURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = json
        } else {
            AppLog.probes.warning("\(claudeJsonURL.path) is not valid JSON, cannot write trust")
            return false
        }

        if let existing = root["projects"], !(existing is [String: Any]) {
            AppLog.probes.warning("\(claudeJsonURL.path) 'projects' has unexpected type, refusing to overwrite")
            return false
        }
        var projects = root["projects"] as? [String: Any] ?? [:]
        let key = directory.path

        if let existingEntry = projects[key], !(existingEntry is [String: Any]) {
            AppLog.probes.warning("\(claudeJsonURL.path) project entry has unexpected type, refusing to overwrite")
            return false
        }
        var entry = projects[key] as? [String: Any] ?? [:]

        if entry["hasTrustDialogAccepted"] as? Bool == true {
            return false
        }

        entry["hasTrustDialogAccepted"] = true
        projects[key] = entry
        root["projects"] = projects

        do {
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: claudeJsonURL, options: .atomic)
            AppLog.probes.info("Wrote trust for \(key) to \(claudeJsonURL.path)")
            return true
        } catch {
            AppLog.probes.error("Failed to write trust to \(claudeJsonURL.path): \(error.localizedDescription)")
            return false
        }
    }

    internal func probeWorkingDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("Iles", isDirectory: true)
            .appendingPathComponent("Probe", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
