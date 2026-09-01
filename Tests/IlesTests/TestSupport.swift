import AppKit
import Domain
import Foundation
import Infrastructure
import IslandGeometry
import Observation
@testable import IlesCore

@MainActor
final class TestHarness {
    private(set) var failed = 0
    private(set) var passed = 0

    func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: String = #fileID,
        line: Int = #line
    ) {
        if condition() {
            passed += 1
        } else {
            failed += 1
            FileHandle.standardError.write(Data("FAIL \(file):\(line) \(message)\n".utf8))
        }
    }

    func expectEqual<T: Equatable & Sendable>(
        _ got: T,
        _ want: T,
        _ message: String,
        file: String = #fileID,
        line: Int = #line
    ) {
        expect(got == want, "\(message) (got \(got), want \(want))", file: file, line: line)
    }

    func finish() -> Int {
        if failed == 0 {
            FileHandle.standardOutput.write(Data("IlesSelfTests: \(passed) passed\n".utf8))
        } else {
            FileHandle.standardError.write(Data("IlesSelfTests: \(failed) failed, \(passed) passed\n".utf8))
        }
        return failed == 0 ? 0 : 1
    }
}

struct IsolatedBox {
    let directory: URL
    let store: JSONSettingsStore
    let settings: JSONSettingsRepository
    let secureCredentials: MemoryCredentials

    static func make() -> IsolatedBox {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("iles-tests-\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = JSONSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let secureCredentials = MemoryCredentials()
        let settings = JSONSettingsRepository(
            store: store,
            secureCredentials: secureCredentials
        )
        return IsolatedBox(
            directory: directory,
            store: store,
            settings: settings,
            secureCredentials: secureCredentials
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }
}

final class MemoryCredentials: CredentialRepository, @unchecked Sendable {
    private var values: [String: String] = [:]

    func save(_ value: String, forKey key: String) {
        values[key] = value
    }

    func get(forKey key: String) -> String? {
        values[key]
    }

    func delete(forKey key: String) -> Bool {
        values.removeValue(forKey: key)
        return values[key] == nil
    }

    func exists(forKey key: String) -> Bool {
        values[key] != nil
    }
}

final class RecordingCLIExecutor: CLIExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @Sendable ([String]) -> CLIResult
    private var count = 0

    init(result: CLIResult) {
        handler = { _ in result }
    }

    init(handler: @escaping @Sendable ([String]) -> CLIResult) {
        self.handler = handler
    }

    var executionCount: Int {
        lock.withLock { count }
    }

    func locate(_ binary: String) -> String? { binary }

    func execute(
        binary: String,
        args: [String],
        input: String?,
        timeout: TimeInterval,
        workingDirectory: URL?,
        autoResponses: [String: String]
    ) async throws -> CLIResult {
        lock.withLock { count += 1 }
        return handler(args)
    }
}

final class LockedDate: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var value: Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(interval) }
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}

@MainActor
@Observable
final class CountingProvider: AIProvider {
    let id: String
    let name: String
    let cliCommand: String
    var dashboardURL: URL? { nil }
    var isSyncing = false
    var snapshot: UsageSnapshot?
    var lastError: Error?
    var refreshCalls: [RefreshKind] = []
    var delay: Duration = .zero
    var percentRemaining: Double = 40
    var emptyQuotas = false

    init(id: String) {
        self.id = id
        self.name = id
        self.cliCommand = id
    }

    func isAvailable() async -> Bool { true }

    func refresh() async throws -> UsageSnapshot {
        try await refresh(.interactive)
    }

    func refresh(_ kind: RefreshKind) async throws -> UsageSnapshot {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        refreshCalls.append(kind)
        let snapshot = UsageSnapshot(
            providerId: id,
            quotas: emptyQuotas ? [] : [UsageQuota(percentRemaining: percentRemaining, quotaType: .session, providerId: id)],
            capturedAt: Date()
        )
        self.snapshot = snapshot
        return snapshot
    }
}
