import Darwin
import Foundation

/// Coordinates narrowly scoped updates to credential files owned by external CLIs.
/// The latest document is re-read under a companion lock and is never replaced if
/// it changes again before the atomic write.
enum CredentialFileStore {
  enum StoreError: LocalizedError {
    case invalidDocument
    case concurrentModification
    case staleCredentials
    case lockUnavailable

    var errorDescription: String? {
      switch self {
      case .invalidDocument: "Credential file contains invalid JSON"
      case .concurrentModification: "Credential file changed during update"
      case .staleCredentials: "Credential refresh result is older than the current file"
      case .lockUnavailable: "Credential file lock is unavailable"
      }
    }
  }

  static func update(
    at path: String,
    mutation: (inout [String: Any]) throws -> Void
  ) throws {
    try withLock(for: path) {
      let url = URL(fileURLWithPath: path)
      let originalData = try Data(contentsOf: url)
      guard var document = try JSONSerialization.jsonObject(with: originalData) as? [String: Any]
      else {
        throw StoreError.invalidDocument
      }

      try mutation(&document)
      let updatedData = try JSONSerialization.data(
        withJSONObject: document,
        options: [.prettyPrinted, .sortedKeys]
      )

      guard try Data(contentsOf: url) == originalData else {
        throw StoreError.concurrentModification
      }
      try updatedData.write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
  }

  private static func withLock<T>(for path: String, operation: () throws -> T) throws -> T {
    let lockPath = path + ".iles-lock"
    let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw StoreError.lockUnavailable }
    defer { close(descriptor) }
    guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw StoreError.lockUnavailable }
    guard flock(descriptor, LOCK_EX) == 0 else { throw StoreError.lockUnavailable }
    defer { flock(descriptor, LOCK_UN) }
    return try operation()
  }
}
