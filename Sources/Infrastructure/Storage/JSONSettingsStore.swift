import Foundation

/// Thread-safe, versioned JSON settings store with recovery and owner-only files.
public final class JSONSettingsStore: @unchecked Sendable {
    public static let shared = JSONSettingsStore()
    public static let currentSchemaVersion = 1

    public enum StoreError: LocalizedError {
        case invalidRoot
        case unsupportedSchema(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidRoot: "Settings are not a valid JSON object"
            case .unsupportedSchema(let version):
                "Settings schema \(version) is newer than this app supports"
            }
        }
    }

    public let fileURL: URL
    private let lock = NSLock()
    private var cachedDictionary: [String: Any]?
    private var cachedSignature: FileSignature?
    private var storedErrorDescription: String?

    public var lastErrorDescription: String? {
        lock.withLock { storedErrorDescription }
    }

    public var backupURL: URL {
        fileURL.appendingPathExtension("backup")
    }

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    public func read<T>(key: String) -> T? {
        let dict = readFile()
        return resolveRead(dict: dict, keyPath: key.split(separator: ".").map(String.init)) as? T
    }

    /// Compatibility API for existing repositories. Failures remain observable
    /// through `lastErrorDescription` and the privacy-safe support log.
    public func write(value: Any?, key: String) {
        do {
            try writeThrowing(value: value, key: key)
        } catch {
            lock.withLock { storedErrorDescription = error.localizedDescription }
            NotificationCenter.default.post(
                name: .settingsStoreError,
                object: self,
                userInfo: ["message": error.localizedDescription]
            )
            AppLog.updates.error("Settings write failed: \(error.localizedDescription)")
        }
    }

    public func writeThrowing(value: Any?, key: String) throws {
        try lock.withLock {
            var dict = readFileUnsafe()
            let parts = key.split(separator: ".").map(String.init)
            let previous = resolveRead(dict: dict, keyPath: parts)
            guard !Self.valuesEqual(previous, value) else { return }
            resolveWrite(dict: &dict, keyPath: parts, value: value)
            dict["_schemaVersion"] = Self.currentSchemaVersion
            try writeFile(dict, createBackup: true)
            cachedDictionary = dict
            cachedSignature = fileSignature()
            storedErrorDescription = nil
        }
    }

    public func readAll() -> [String: Any] {
        readFile()
    }

    public static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".iles/settings.json")
    }

    private func readFile() -> [String: Any] {
        lock.withLock { readFileUnsafe() }
    }

    /// Must be called while holding `lock`.
    private func readFileUnsafe() -> [String: Any] {
        let currentSignature = fileSignature()
        if let cachedDictionary, currentSignature == cachedSignature {
            return cachedDictionary
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = ["_schemaVersion": Self.currentSchemaVersion]
            cachedDictionary = empty
            cachedSignature = nil
            return empty
        }

        do {
            let data = try Data(contentsOf: fileURL)
            var document = try decodeDocument(data)
            let version = document["_schemaVersion"] as? Int ?? 0
            guard version <= Self.currentSchemaVersion else {
                throw StoreError.unsupportedSchema(version)
            }
            if version < Self.currentSchemaVersion {
                document = try migrate(document, from: version)
                try preserve(data, at: backupURL)
                try writeFile(document, createBackup: false)
            } else {
                enforcePermissions()
            }
            cachedDictionary = document
            cachedSignature = fileSignature()
            storedErrorDescription = nil
            return document
        } catch {
            storedErrorDescription = error.localizedDescription
            NotificationCenter.default.post(
                name: .settingsStoreError,
                object: self,
                userInfo: ["message": error.localizedDescription]
            )
            AppLog.updates.error("Settings recovery required: \(error.localizedDescription)")
            let recovered = recoverInvalidSettings()
            cachedDictionary = recovered
            cachedSignature = fileSignature()
            return recovered
        }
    }

    private func decodeDocument(_ data: Data) throws -> [String: Any] {
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StoreError.invalidRoot
        }
        return document
    }

    private func migrate(_ document: [String: Any], from version: Int) throws -> [String: Any] {
        var migrated = document
        switch version {
        case 0:
            migrated["_schemaVersion"] = Self.currentSchemaVersion
        case Self.currentSchemaVersion:
            break
        default:
            throw StoreError.unsupportedSchema(version)
        }
        return migrated
    }

    private func recoverInvalidSettings() -> [String: Any] {
        preserveCorruptFile()
        if let backupData = try? Data(contentsOf: backupURL),
           var backup = try? decodeDocument(backupData) {
            backup["_schemaVersion"] = Self.currentSchemaVersion
            try? writeFile(backup, createBackup: false)
            return backup
        }
        return ["_schemaVersion": Self.currentSchemaVersion]
    }

    private func preserveCorruptFile() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let recoveryURL = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(timestamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: recoveryURL)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: recoveryURL.path
        )
    }

    /// Must be called while holding `lock`.
    private func writeFile(_ dict: [String: Any], createBackup: Bool) throws {
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parentDir.path)

        if createBackup, let current = try? Data(contentsOf: fileURL) {
            try preserve(current, at: backupURL)
        }
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: fileURL, options: .atomic)
        enforcePermissions()
    }

    private func preserve(_ data: Data, at url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func enforcePermissions() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func fileSignature() -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              let modificationDate = attributes[.modificationDate] as? Date
        else { return nil }
        return FileSignature(size: size.uint64Value, modificationDate: modificationDate)
    }

    private func resolveRead(dict: [String: Any], keyPath: [String]) -> Any? {
        guard let first = keyPath.first else { return nil }
        if keyPath.count == 1 { return dict[first] }
        guard let nested = dict[first] as? [String: Any] else { return nil }
        return resolveRead(dict: nested, keyPath: Array(keyPath.dropFirst()))
    }

    private func resolveWrite(dict: inout [String: Any], keyPath: [String], value: Any?) {
        guard let first = keyPath.first else { return }
        if keyPath.count == 1 {
            if let value { dict[first] = value } else { dict.removeValue(forKey: first) }
            return
        }
        var nested = (dict[first] as? [String: Any]) ?? [:]
        resolveWrite(dict: &nested, keyPath: Array(keyPath.dropFirst()), value: value)
        dict[first] = nested
    }

    private static func valuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs as NSObject, rhs as NSObject): lhs.isEqual(rhs)
        default: false
        }
    }

    private struct FileSignature: Equatable {
        let size: UInt64
        let modificationDate: Date
    }
}

public extension Notification.Name {
    static let settingsStoreError = Notification.Name("Iles.settingsStoreError")
}
