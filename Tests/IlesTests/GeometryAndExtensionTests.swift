import AppKit
import Domain
import Foundation
import Infrastructure
import IslandGeometry
import Observation
@testable import IlesCore

extension IlesSelfTests {
    @MainActor
    static func runGeometryAndExtensionTests(_ test: TestHarness) async {
        // MARK: Geometry

        let threeRowBounds = CGRect(x: 0, y: 0, width: IslandMetrics.width,
                                    height: IslandMetrics.height(forProviderCount: 3))
        let islandPath = IslandShape().path(in: threeRowBounds)
        for index in 0..<3 {
            test.expectEqual(IslandMetrics.ringCenterY(index: index), CGFloat(45 + index * 56),
                             "detail pointers follow the center of each redesigned ring")
            let rowEnd = IslandMetrics.topPadding + CGFloat(index) * (IslandMetrics.itemHeight + IslandMetrics.itemSpacing)
                + IslandMetrics.itemHeight - 1
            let inset = (IslandMetrics.width - IslandMetrics.textWidth) / 2
            test.expect(islandPath.contains(CGPoint(x: inset, y: rowEnd)),
                        "percentage labels stay inside the curved island at row \(index)")
        }


        IslandMetrics.assertLayoutInvariants()
        test.expect(true, "layout invariants")
        test.expectEqual(
            IslandPlacement.clampedTopGap(8, islandHeight: 200, visibleHeight: 800),
            8,
            "default top gap stays put"
        )
        test.expectEqual(
            IslandPlacement.clampedTopGap(-20, islandHeight: 200, visibleHeight: 800),
            IslandMetrics.topGap,
            "gap cannot go under the menu bar"
        )
        test.expectEqual(
            IslandPlacement.clampedTopGap(900, islandHeight: 200, visibleHeight: 800),
            800 - 200 - IslandPlacement.bottomGap,
            "gap cannot push the island off the bottom"
        )
        test.expectEqual(
            IslandPlacement.topGap(
                movingFrom: 40,
                mouseDeltaY: 12,
                islandHeight: 200,
                visibleHeight: 800
            ),
            28,
            "mouse up slides the island up"
        )
        test.expectEqual(
            IslandPlacement.originY(topGap: 8, islandHeight: 200, visibleMaxY: 900),
            692,
            "origin hangs from the visible top"
        )
        test.expectEqual(IslandMetrics.height(forProviderCount: 0), IslandMetrics.joinDepth * 2, "empty island is just the S-joins")
        test.expectEqual(
            IslandMetrics.maxProviderCount(forHeight: IslandMetrics.height(forProviderCount: 3)),
            3,
            "height and capacity invert for 3"
        )
        let dualRingCenterlineGap = (
            (IslandMetrics.ringSize - IslandMetrics.ringStroke)
                - (IslandMetrics.dualRingInnerSize - IslandMetrics.dualRingInnerStroke)
        ) / 2
        let dualRingVisibleGap = dualRingCenterlineGap
            - (IslandMetrics.ringStroke + IslandMetrics.dualRingInnerStroke) / 2
        test.expect(dualRingVisibleGap >= 1, "dual-ring strokes retain a visible one-point gap")
        test.expect(
            IslandMetrics.dualRingInnerSize - IslandMetrics.dualRingInnerStroke * 2
                >= IslandMetrics.markSize + 2,
            "dual-ring center glyph retains optical clearance"
        )
        test.expectEqual(
            IslandMetrics.clusterRingStroke,
            IslandMetrics.ringStroke,
            "trio ring tracks match single-ring weight"
        )
        test.expectEqual(
            IslandMetrics.clusterAccentStroke,
            IslandMetrics.accentStroke,
            "trio progress arcs match single-ring weight"
        )
        let clusterSizes = [
            IslandMetrics.ringSize,
            IslandMetrics.clusterMiddleSize,
            IslandMetrics.clusterInnerSize
        ]
        for pair in zip(clusterSizes, clusterSizes.dropFirst()) {
            test.expect(
                (pair.0 - pair.1) / 2 - IslandMetrics.clusterRingStroke >= 1,
                "trio rings retain a visible one-point gap"
            )
        }
        for count in 1...14 {
            let height = IslandMetrics.height(forProviderCount: count)
            test.expectEqual(
                IslandMetrics.maxProviderCount(forHeight: height),
                count,
                "height and capacity invert for \(count)"
            )
            test.expect(
                IslandMetrics.ringCenterY(index: count - 1) + IslandMetrics.ringSize / 2 <= height - IslandMetrics.topPadding + 0.5,
                "last ring fits in height for \(count)"
            )
        }
        test.expectEqual(
            IslandMetrics.ringCenterY(index: 1) - IslandMetrics.ringCenterY(index: 0),
            IslandMetrics.itemHeight + IslandMetrics.itemSpacing,
            "rings are evenly spaced"
        )

        // MARK: Refresh interval

        test.expectEqual(RefreshInterval.allCases.count, 5, "all refresh options are available")
        test.expect(RefreshInterval.off.seconds == nil, "off has no seconds")
        test.expectEqual(RefreshInterval.oneMinute.seconds, 60, "one minute is 60s")
        test.expectEqual(RefreshInterval.tenMinutes.seconds, 600, "ten minutes is 600s")
        test.expectEqual(
            ConfigField(id: "apiKey", label: "API key", type: .secret).environmentVariableName,
            "ILES_API_KEY",
            "extension config uses the Iles environment prefix"
        )
        test.expectEqual(
            ConfigField(id: "base url;", label: "Base URL", type: .string).environmentVariableName,
            "ILES_BASE_URL_",
            "extension config sanitizes environment variable names"
        )
        do {
            let manifest = try ExtensionManifest.parse(from: Data("""
            {
              "schemaVersion": 2,
              "id": "service-health",
              "name": "Service Health",
              "version": "1.0.0",
              "category": "services",
              "metrics": [
                { "id": "latency", "name": "Latency", "kind": "gauge", "unit": "ms" }
              ],
              "sections": [
                { "id": "health", "type": "metricsRow", "probe": { "command": "health.sh" } }
              ],
              "complications": [
                {
                  "id": "latency-ring",
                  "name": "Latency",
                  "shortName": "Latency",
                  "summary": "Response latency for the configured service.",
                  "question": "How quickly is the service responding?",
                  "tags": ["latency", "service"],
                  "family": "ring",
                  "compatibleFamilies": ["ring", "value"],
                  "slots": [{ "metricID": "latency", "transforms": [] }],
                  "labelStyle": "value",
                  "tint": "source",
                  "tapAction": "showDetails",
                  "rank": 10,
                  "isFeatured": true,
                  "isNew": true,
                  "fixtures": []
                }
              ]
            }
            """.utf8))
            test.expectEqual(manifest.complications.count, 1, "extension declares complication presets")
            test.expectEqual(manifest.complications[0].slots.map(\.metricID), ["latency"], "extension recipe keeps stable metric ids")
        } catch {
            test.expect(false, "extension complication manifest parses: \(error)")
        }

        do {
            _ = try ExtensionManifest.parse(from: Data("""
            {
              "schemaVersion": 1,
              "id": "legacy",
              "name": "Legacy",
              "version": "1.0.0",
              "category": "extensions",
              "metrics": [],
              "sections": [{ "id": "status", "type": "statusBanner", "probe": { "command": "probe.sh" } }],
              "complications": []
            }
            """.utf8))
            test.expect(false, "extension schema v1 is rejected instead of migrated")
        } catch let error as ExtensionManifestError {
            if case .unsupportedSchema(1) = error {
                test.expect(true, "extension schema v1 is rejected instead of migrated")
            } else {
                test.expect(false, "legacy extension reports the schema error: \(error)")
            }
        } catch {
            test.expect(false, "legacy extension reports a manifest error: \(error)")
        }

        do {
            _ = try ExtensionManifest.parse(from: Data("""
            {
              "schemaVersion": 2,
              "id": "invalid-recipe",
              "name": "Invalid Recipe",
              "version": "1.0.0",
              "category": "extensions",
              "metrics": [{ "id": "known", "name": "Known", "kind": "value" }],
              "sections": [{ "id": "status", "type": "statusBanner", "probe": { "command": "probe.sh" } }],
              "complications": [{
                "id": "missing-metric",
                "name": "Missing Metric",
                "shortName": "Missing",
                "summary": "Invalid on purpose.",
                "question": "Does validation catch this?",
                "tags": [],
                "family": "value",
                "compatibleFamilies": ["value"],
                "slots": [{ "metricID": "unknown", "transforms": [] }],
                "labelStyle": "value",
                "tint": "source",
                "tapAction": "showDetails",
                "rank": 0,
                "isFeatured": false,
                "isNew": false,
                "fixtures": []
              }]
            }
            """.utf8))
            test.expect(false, "extension recipes cannot reference undeclared metrics")
        } catch let error as ExtensionManifestError {
            if case .unknownComplicationMetrics("missing-metric", ["unknown"]) = error {
                test.expect(true, "extension recipes cannot reference undeclared metrics")
            } else {
                test.expect(false, "invalid extension recipe reports the metric error: \(error)")
            }
        } catch {
            test.expect(false, "invalid extension recipe reports a manifest error: \(error)")
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let trust = JSONExtensionTrustRepository(store: box.store)
            test.expect(!trust.isTrusted(extensionID: "sample.extension", fingerprint: "first"), "extensions begin untrusted")
            trust.setTrusted(true, extensionID: "sample.extension", fingerprint: "first")
            test.expect(trust.isTrusted(extensionID: "sample.extension", fingerprint: "first"), "trust is bound to a fingerprint")
            test.expect(!trust.isTrusted(extensionID: "sample.extension", fingerprint: "changed"), "changing extension files revokes effective trust")

            let manifest = ExtensionManifest(
                id: "sample.extension",
                name: "Sample Extension",
                version: "2.0.0",
                sections: [
                    ExtensionSection(id: "health", type: .statusBanner, probeCommand: "probe.sh"),
                ]
            )
            let extensionDirectory = box.directory.appendingPathComponent("sample-extension", isDirectory: true)
            try? FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
            let scriptURL = extensionDirectory.appendingPathComponent("probe.sh")
            try? Data("#!/bin/sh\nprintf '%s' '{\"status\":{\"text\":\"Ready\",\"level\":\"healthy\"}}'\n".utf8)
                .write(to: scriptURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            guard let trustedFingerprint = ExtensionDirectoryScanner.fingerprint(directory: extensionDirectory) else {
                test.expect(false, "extension fixture has a fingerprint")
                return
            }
            let executor = RecordingCLIExecutor(
                result: CLIResult(output: #"{"status":{"text":"Ready","level":"healthy"}}"#)
            )
            let probe = ScriptProbe(
                scriptPath: "probe.sh",
                sectionID: "health",
                extensionDir: extensionDirectory,
                providerId: "extension.sample.extension",
                sectionType: .statusBanner,
                cliExecutor: executor,
                manifest: manifest,
                fingerprint: trustedFingerprint,
                trustRepository: trust
            )
            do {
                _ = try await probe.probe()
                test.expect(false, "untrusted extension scripts never execute")
            } catch {
                test.expectEqual(executor.executionCount, 0, "untrusted extension scripts never execute")
            }

            trust.setTrusted(true, extensionID: manifest.id, fingerprint: trustedFingerprint)
            do {
                let snapshot = try await probe.probe()
                test.expectEqual(executor.executionCount, 1, "trusted extension script executes once")
                test.expectEqual(snapshot.extensionMetrics?.first?.id, "health", "status sections retain their stable metric id")
                test.expectEqual(snapshot.extensionMetrics?.first?.kind, .status, "status sections emit a typed metric")
            } catch {
                test.expect(false, "trusted extension script output parses: \(error)")
            }

            trust.setTrusted(false, extensionID: manifest.id, fingerprint: trustedFingerprint)
            test.expect(!trust.isTrusted(extensionID: manifest.id, fingerprint: trustedFingerprint), "trust can be explicitly revoked")
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let extensions = box.directory.appendingPathComponent("extensions", isDirectory: true)
            let sample = extensions.appendingPathComponent("sample", isDirectory: true)
            try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: true)
            let manifest = Data("""
            {
              "schemaVersion": 2,
              "id": "fingerprint-test",
              "name": "Fingerprint Test",
              "version": "1.0.0",
              "category": "extensions",
              "metrics": [],
              "sections": [{ "id": "status", "type": "statusBanner", "probe": { "command": "probe.sh" } }],
              "complications": []
            }
            """.utf8)
            try manifest.write(to: sample.appendingPathComponent("manifest.json"))
            let script = sample.appendingPathComponent("probe.sh")
            try Data("first".utf8).write(to: script)
            let scanner = ExtensionDirectoryScanner()
            let first = scanner.scan(directory: extensions)
            test.expectEqual(first.count, 1, "extension scanner accepts a contained regular-file bundle")
            try Data("second".utf8).write(to: script)
            let second = scanner.scan(directory: extensions)
            test.expect(first.first?.fingerprint != second.first?.fingerprint, "editing any extension file changes its trust fingerprint")

            let outside = box.directory.appendingPathComponent("outside.sh")
            try Data("outside".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(
                at: sample.appendingPathComponent("linked.sh"),
                withDestinationURL: outside
            )
            test.expect(scanner.scan(directory: extensions).isEmpty, "extension bundles containing symlinks are rejected")
        } catch {
            test.expect(false, "extension fingerprint fixture is created: \(error)")
        }

        do {
            let data = Data("""
            {
              "quotas": [
                {
                  "type": "time:Claude · work 5h",
                  "percentRemaining": 62,
                  "group": "Claude · work",
                  "compactTitle": "5h"
                }
              ]
            }
            """.utf8)
            let decoded = try SectionData.decode(from: data, type: .quotaGrid, providerId: "harnais")
            if case .quotas(let quotas) = decoded, let quota = quotas.first {
                test.expectEqual(quota.group, "Claude · work", "quotaGrid JSON preserves group")
                test.expectEqual(quota.quotaType, .timeLimit("Claude · work 5h"), "quotaGrid type keys do not double the time prefix")
                test.expectEqual(quota.compactTitle, "5h", "quotaGrid JSON preserves compactTitle")
            } else {
                test.expect(false, "quotaGrid JSON decodes into quotas")
            }
        } catch {
            test.expect(false, "quotaGrid group decode: \(error)")
        }

        do {
            // Harnais probe v1.1 contract: quotas + capturedAt/stale/refreshTriggered/harnesses.
            // SectionData must tolerate the extra keys (RawQuotaOutput.quotas optional).
            let data = Data("""
            {
              "quotas": [
                {
                  "type": "session",
                  "percentRemaining": 42,
                  "group": "Claude · Work",
                  "compactTitle": "Session"
                }
              ],
              "capturedAt": "2026-09-18T00:00:00Z",
              "stale": false,
              "refreshTriggered": false,
              "harnesses": {
                "connections": [],
                "lastApply": {"at": null, "names": [], "files": null, "hiddenRings": []}
              }
            }
            """.utf8)
            let decoded = try SectionData.decode(from: data, type: .quotaGrid, providerId: "harnais")
            if case .quotas(let quotas) = decoded {
                test.expectEqual(quotas.count, 1, "harnais probe v1.1 decodes despite extra keys")
            } else {
                test.expect(false, "harnais probe v1.1 decodes into quotas")
            }
        } catch {
            test.expect(false, "harnais probe v1.1 decode: \(error)")
        }

        do {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            let encoded = try encoder.encode(SourceSnapshot(sourceID: "claude", values: [:]))
            guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                test.expect(false, "SourceSnapshot encodes as a JSON object")
                return
            }
            object.removeValue(forKey: "quotaGroups")
            let stripped = try JSONSerialization.data(withJSONObject: object)
            let legacy = try decoder.decode(SourceSnapshot.self, from: stripped)
            test.expect(legacy.quotaGroups == nil, "legacy snapshots without quotaGroups still decode")
        } catch {
            test.expect(false, "legacy SourceSnapshot decode: \(error)")
        }

    }
}
