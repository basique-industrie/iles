import Domain
import Foundation

/// Thread-safe TTL cache for a successful snapshot. Quota values move on
/// multi-hour timescales, so a short cache avoids unnecessary rate-limited API
/// requests without materially reducing freshness.
final class SnapshotCache: @unchecked Sendable {
  private var cached: UsageSnapshot?
  private var cachedAt: Date?
  private let ttl: TimeInterval
  private let lock = NSLock()

  init(ttl: TimeInterval) {
    self.ttl = ttl
  }

  func get(now: Date = Date()) -> UsageSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    guard let cached, let cachedAt else { return nil }
    if now.timeIntervalSince(cachedAt) >= ttl {
      self.cached = nil
      self.cachedAt = nil
      return nil
    }
    return cached
  }

  func set(_ snapshot: UsageSnapshot, now: Date = Date()) {
    lock.lock()
    defer { lock.unlock() }
    cached = snapshot
    cachedAt = now
  }
}

/// Holds the active server-requested retry window across probe calls.
final class RateLimitState: @unchecked Sendable {
  private var retryAt: Date?
  private let lock = NSLock()

  func activeRetryAt(now: Date = Date()) -> Date? {
    lock.lock()
    defer { lock.unlock() }
    guard let retryAt else { return nil }
    if retryAt <= now {
      self.retryAt = nil
      return nil
    }
    return retryAt
  }

  func set(retryAt: Date) {
    lock.lock()
    defer { lock.unlock() }
    self.retryAt = retryAt
  }
}

/// Caches credentials briefly while still noticing vendor CLI reauthentication.
final class CredentialCache: @unchecked Sendable {
  private var cached: ClaudeCredentialResult?
  private var cachedAt: Date?
  private let lock = NSLock()
  static let ttl: TimeInterval = 5 * 60

  func get(now: Date = Date()) -> ClaudeCredentialResult? {
    lock.lock()
    defer { lock.unlock() }
    if let cachedAt, now.timeIntervalSince(cachedAt) > Self.ttl {
      cached = nil
      self.cachedAt = nil
      return nil
    }
    return cached
  }

  func set(_ credentials: ClaudeCredentialResult, now: Date = Date()) {
    lock.lock()
    defer { lock.unlock() }
    cached = credentials
    cachedAt = now
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    cached = nil
    cachedAt = nil
  }
}
