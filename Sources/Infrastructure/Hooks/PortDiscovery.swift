import Foundation

/// Manages the identity-specific Claude hook port and auth files.
public enum PortDiscovery {
    public static var portFilePath: String {
        AppIdentity.current.hookPortFileURL.path
    }

    public static var authenticationHeaderFilePath: String {
        AppIdentity.current.hookAuthFileURL.path
    }

    /// Writes the port number to the discovery file.
    /// Creates the ~/.claude directory if it doesn't exist.
    public static func writeConnection(port: Int, authenticationToken: String) throws {
        let path = portFilePath
        let directory = (path as NSString).deletingLastPathComponent

        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        try secureWrite("\(port)\n", to: path)
        try secureWrite(
            "X-Iles-Token: \(authenticationToken)\n",
            to: authenticationHeaderFilePath
        )
    }

    /// Reads the port number from the discovery file.
    /// Returns nil if the file doesn't exist or contains invalid data.
    public static func readPort() -> Int? {
        guard let content = try? String(contentsOfFile: portFilePath, encoding: .utf8) else {
            return nil
        }
        return Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Removes the port discovery file.
    public static func removePortFile() {
        try? FileManager.default.removeItem(atPath: portFilePath)
        try? FileManager.default.removeItem(atPath: authenticationHeaderFilePath)
    }

    private static func secureWrite(_ value: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try Data(value.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
    }
}
