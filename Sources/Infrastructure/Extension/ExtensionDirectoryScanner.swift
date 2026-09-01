import CryptoKit
import Foundation
import Domain

/// Result of scanning a single extension directory.
public struct ExtensionScanResult: Sendable {
    public let manifest: ExtensionManifest
    public let directory: URL
    public let fingerprint: String

    public init(manifest: ExtensionManifest, directory: URL, fingerprint: String) {
        self.manifest = manifest
        self.directory = directory
        self.fingerprint = fingerprint
    }
}

/// Scans the extensions directory for valid extension manifests.
public final class ExtensionDirectoryScanner: Sendable {
    public init() {}

    /// Scans a directory for subdirectories containing valid manifest.json files.
    public func scan(directory: URL) -> [ExtensionScanResult] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path()) else {
            return []
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { subDir -> ExtensionScanResult? in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: subDir.path(), isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  (try? subDir.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let fingerprint = Self.fingerprint(directory: subDir) else {
                return nil
            }

            let manifestURL = subDir.appending(path: "manifest.json")
            guard let manifestSize = try? manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  manifestSize <= 1_048_576,
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? ExtensionManifest.parse(from: data) else {
                return nil
            }

            return ExtensionScanResult(
                manifest: manifest,
                directory: subDir,
                fingerprint: fingerprint
            )
        }
    }

    public static func fingerprint(directory: URL) -> String? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return nil }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true
            else { return nil }
            if values.isRegularFile == true { files.append(url) }
        }
        files.sort { $0.path < $1.path }
        var hasher = SHA256()
        for file in files {
            hasher.update(data: Data(file.path.replacingOccurrences(of: directory.path, with: "").utf8))
            guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
            defer { try? handle.close() }
            do {
                while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
                    hasher.update(data: chunk)
                }
            } catch {
                return nil
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
