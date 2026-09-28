import Domain
import Foundation
import Infrastructure
@testable import IlesCore

extension IlesSelfTests {
    @MainActor
    static func runHarnaisRefreshTests(_ test: TestHarness) async {
        test.expectEqual(HarnaisRefreshPolicy.staleAfter(interval: .tenMinutes, onBattery: false), 1_200,
                         "ten-minute refreshes stay fresh beyond the former four-minute cutoff")
        test.expectEqual(HarnaisRefreshPolicy.staleAfter(interval: .tenMinutes, onBattery: true), 2_400,
                         "freshness follows the monitor's longer battery cadence")
        test.expectEqual(HarnaisRefreshPolicy.staleAfter(interval: .oneMinute, onBattery: false), 240,
                         "short refresh intervals allow time for account probes")
        test.expectEqual(HarnaisRefreshPolicy.staleAfter(interval: .off, onBattery: false), 900,
                         "manual-only samples still age")
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let feedURL = directory.appendingPathComponent("quotas.json")
            // An invalid persisted feed cannot affect the live command response.
            try Data("obsolete cached data".utf8).write(to: feedURL)
            let fresh = fixture(date: Date(), remaining: 73)
            let executor = HarnaisRefreshExecutor(results: [
                CLIResult(output: fresh),
                CLIResult(output: fixture(date: Date(), remaining: 61)),
                CLIResult(output: "private diagnostic must not reach the UI", exitCode: 1),
                CLIResult(output: fixture(date: Date().addingTimeInterval(-3_600), remaining: 99)),
                CLIResult(output: "invalid JSON"),
            ])
            let probe = HarnaisUsageProbe(configurationDirectory: directory, executor: executor)
            let provider = HarnaisProvider(probe: probe)
            let initial = try await provider.refresh()
            test.expectEqual(initial.quotas.first?.percentRemaining, 73, "Iles reads live command output, not quotas.json")
            test.expect(Date().timeIntervalSince(initial.capturedAt) < 5, "freshness comes from the successful live sample")

            try FileManager.default.removeItem(at: feedURL)
            try Data(#"{"hiddenTypes":["time:Claude · work 7d"]}"#.utf8)
                .write(to: directory.appendingPathComponent("islands.json"))
            let next = try await provider.refresh()
            test.expectEqual(next.quotas.first?.percentRemaining, 61, "a new refresh probes again without a Harnais feed file")
            test.expectEqual(next.hiddenQuotaTypes, ["time:Claude · work 7d"], "ring configuration still comes from Harnais")
            test.expectEqual(await executor.arguments, [["quotas", "--json"], ["quotas", "--json"]],
                             "each refresh queries quotas without requesting a model turn")
            for reason in ["nonzero exit", "old command response", "malformed command response"] {
                do {
                    _ = try await provider.refresh()
                    test.expect(false, "\(reason) must fail instead of reporting fresh values")
                } catch {
                    test.expectEqual(provider.snapshot, next, "\(reason) retains last successful values and their original timestamp")
                    test.expect(provider.lastError != nil, "\(reason) exposes a refresh failure")
                    test.expect(!error.localizedDescription.contains("private diagnostic"), "helper output is not echoed into the UI")
                }
            }
            try Data("invalid preferences".utf8).write(to: directory.appendingPathComponent("islands.json"))
            do {
                _ = try await provider.refresh()
                test.expect(false, "malformed visibility must fail")
            } catch {
                test.expectEqual(await executor.arguments.count, 5, "invalid preferences fail before starting another probe")
            }

            // The registry is the shared gate for manual, startup and background work.
            try FileManager.default.removeItem(at: directory.appendingPathComponent("islands.json"))
            let slow = HarnaisRefreshExecutor(results: [CLIResult(output: fresh)], delay: .milliseconds(50))
            let coalescedProvider = HarnaisProvider(probe: HarnaisUsageProbe(configurationDirectory: directory, executor: slow))
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let workspace = IslandWorkspaceStore(repository: JSONIslandWorkspaceRepository(store: box.store))
            workspace.addIsland()
            _ = workspace.addComplication(to: workspace.islands[0].id, sourceID: "harnais",
                                           metricIDs: ["quota.key.time:Claude · work 7d"], family: .ring)
            let runtime = IslandRuntime.testing(providers: [coalescedProvider], workspaceStore: workspace)
            let first = runtime.refreshSource("harnais")
            let second = runtime.refreshSource("harnais")
            await first?.value
            await second?.value
            test.expectEqual(await slow.arguments.count, 1, "overlapping Iles refresh requests use one account probe")
            test.expectEqual(runtime.quality(for: workspace.islands[0].complications[0]), .live,
                             "successful independent refresh makes the ring live")
        } catch {
            test.expect(false, "independent Harnais refresh: \(error)")
        }
    }

    private static func fixture(date: Date, remaining: Int) -> String {
        """
        {"schemaVersion":1,"capturedAt":"\(ISO8601DateFormatter().string(from: date))","accounts":[
          {"id":"work","provider":"claude","label":"Work","quotas":[
            {"type":"time:Claude · work 7d","percentRemaining":\(remaining),"compactTitle":"7d"}
          ]}
        ]}
        """
    }
}

private actor HarnaisRefreshExecutor: CLIExecutor {
    var arguments: [[String]] = []
    private var results: [CLIResult]
    private let delay: Duration

    init(results: [CLIResult], delay: Duration = .zero) {
        self.results = results
        self.delay = delay
    }

    nonisolated func locate(_ binary: String) -> String? { binary }

    func execute(binary: String, args: [String], input: String?, timeout: TimeInterval,
                 workingDirectory: URL?, autoResponses: [String: String]) async throws -> CLIResult {
        arguments.append(args)
        guard !results.isEmpty else { throw ProbeError.noData }
        let result = results.removeFirst()
        try await Task.sleep(for: delay)
        return result
    }
}
