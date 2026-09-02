import Foundation
import Domain
#if canImport(Darwin)
import Darwin
#endif

/// Installs and uninstalls Iles hooks in ~/.claude/settings.json.
public enum HookInstaller {
    static var hookMarker: String {
        AppIdentity.current.hookFunctionName
    }

    /// The settings file path
    public static var settingsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/settings.json"
    }

    /// The hook forwards only the three fields used by Iles. It exits
    /// silently when the app is not running because there is no fixed-port fallback.
    static var hookCommand: String {
        hookCommand(for: .current)
    }

    static func hookCommand(for identity: AppIdentity) -> String {
        let marker = identity.hookFunctionName
        return """
        \(marker)() { PORT_FILE="$HOME/.claude/\(identity.hookPortFileName)"; AUTH_FILE="$HOME/.claude/\(identity.hookAuthFileName)"; [ -r "$PORT_FILE" ] && [ -r "$AUTH_FILE" ] || { cat >/dev/null; return 0; }; BODY=$(/usr/bin/mktemp -t \(identity.hookTempPrefix)) || { cat >/dev/null; return 0; }; /bin/chmod 600 "$BODY"; /bin/cat >"$BODY"; SID=$(/usr/bin/plutil -extract session_id json -o - "$BODY" 2>/dev/null) || { /bin/rm -f "$BODY"; return 0; }; EVENT=$(/usr/bin/plutil -extract hook_event_name json -o - "$BODY" 2>/dev/null) || { /bin/rm -f "$BODY"; return 0; }; CWD=$(/usr/bin/plutil -extract cwd json -o - "$BODY" 2>/dev/null || /usr/bin/printf '""'); /bin/rm -f "$BODY"; PORT=$(/bin/cat "$PORT_FILE" 2>/dev/null); case "$PORT" in ''|*[!0-9]*) return 0;; esac; /usr/bin/printf '{"session_id":%s,"hook_event_name":%s,"cwd":%s}' "$SID" "$EVENT" "$CWD" | /usr/bin/curl --silent --show-error --max-time 2 --request POST "http://127.0.0.1:${PORT}/hook" --header 'Content-Type: application/json' --header @"$AUTH_FILE" --data-binary @- >/dev/null 2>&1 & }; \(marker)
        """
    }

    /// The event names to register hooks for
    static let hookEvents = [
        "SessionStart",
        "SessionEnd",
        "TaskCompleted",
        "SubagentStart",
        "SubagentStop",
        "Stop",
        "UserPromptSubmit",
    ]

    /// Installs hooks into the Claude settings file.
    /// Creates the file and directory if they don't exist.
    /// Preserves existing settings and hooks from other tools.
    ///
    /// Hook format (new matcher-based format):
    /// ```json
    /// {"SessionStart": [{"matcher": ".*", "hooks": [{"type": "command", "command": "..."}]}]}
    /// ```
    public static func install() throws {
        try withSettingsLock {
            var settings = try readOrCreateSettings()
            let originalData = FileManager.default.contents(atPath: settingsPath)
            var hooks = settings["hooks"] as? [String: Any] ?? [String: Any]()

            for event in hookEvents {
                var matcherEntries = hooks[event] as? [[String: Any]] ?? [[String: Any]]()

                matcherEntries.removeAll { entry in
                    containsIlesHook(in: entry)
                }

                matcherEntries.append([
                    "matcher": ".*",
                    "hooks": [
                        [
                            "type": "command",
                            "command": hookCommand,
                        ] as [String: Any]
                    ],
                ])

                hooks[event] = matcherEntries
            }

            settings["hooks"] = hooks
            try writeSettings(settings, replacing: originalData)
        }
    }

    /// Uninstalls Iles hooks from the Claude settings file.
    /// Preserves hooks from other tools.
    public static func uninstall() throws {
        try withSettingsLock {
            guard var settings = try? readOrCreateSettings() else { return }
            let originalData = FileManager.default.contents(atPath: settingsPath)
            guard var hooks = settings["hooks"] as? [String: Any] else { return }

            for event in hookEvents {
                guard var matcherEntries = hooks[event] as? [[String: Any]] else { continue }

                matcherEntries.removeAll { entry in
                    containsIlesHook(in: entry)
                }

                if matcherEntries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = matcherEntries
                }
            }

            if hooks.isEmpty {
                settings.removeValue(forKey: "hooks")
            } else {
                settings["hooks"] = hooks
            }

            try writeSettings(settings, replacing: originalData)
        }
    }

    /// Detects whether Iles hooks are currently installed.
    public static func isInstalled() -> Bool {
        guard let settings = readSettings(),
              let hooks = settings["hooks"] as? [String: Any] else {
            return false
        }

        // Check if at least one event has our hook (in matcher format)
        return hooks.values.contains { value in
            guard let matcherEntries = value as? [[String: Any]] else { return false }
            return matcherEntries.contains { entry in
                containsCurrentIlesHook(in: entry)
            }
        }
    }

    /// Checks if a matcher entry contains an Iles hook command.
    private static func containsIlesHook(in matcherEntry: [String: Any]) -> Bool {
        guard let innerHooks = matcherEntry["hooks"] as? [[String: Any]] else { return false }
        return innerHooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return command.contains(hookMarker)
        }
    }

    private static func containsCurrentIlesHook(in matcherEntry: [String: Any]) -> Bool {
        guard let innerHooks = matcherEntry["hooks"] as? [[String: Any]] else { return false }
        return innerHooks.contains { hook in
            (hook["command"] as? String) == hookCommand
        }
    }

    // MARK: - Private

    enum InstallerError: Error {
        case corruptedSettingsFile(String)
        case concurrentModification
    }

    /// Reads settings, returning empty dict for missing file but throwing on corrupt JSON.
    static func readOrCreateSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsPath) else {
            return [String: Any]()
        }

        guard let data = FileManager.default.contents(atPath: settingsPath) else {
            return [String: Any]()
        }

        // Empty file is treated as empty settings
        if data.isEmpty {
            return [String: Any]()
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.corruptedSettingsFile(
                "Failed to parse \(settingsPath) — file may be corrupted. Fix it manually before retrying."
            )
        }

        return json
    }

    /// For read-only checks (isInstalled) — returns nil on any error.
    static func readSettings() -> [String: Any]? {
        try? readOrCreateSettings()
    }

    private static func writeSettings(_ settings: [String: Any], replacing originalData: Data?) throws {
        let directory = (settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        let currentData = FileManager.default.contents(atPath: settingsPath)
        guard currentData == originalData else {
            throw InstallerError.concurrentModification
        }

        if let originalData, !originalData.isEmpty {
            let backupURL = URL(fileURLWithPath: settingsPath + ".iles-backup")
            try originalData.write(to: backupURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        }

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        let settingsURL = URL(fileURLWithPath: settingsPath)
        try data.write(to: settingsURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsPath)
    }

    private static func withSettingsLock<T>(_ operation: () throws -> T) throws -> T {
        #if canImport(Darwin)
        let lockPath = settingsPath + ".iles-lock"
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return try operation() }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return try operation() }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
        #else
        return try operation()
        #endif
    }
}
