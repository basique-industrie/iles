import AppKit
import Domain
import Foundation
@testable import Infrastructure
import IslandGeometry
import Observation
@testable import IlesCore

extension IlesSelfTests {
    @MainActor
    static func runSettingsPersistenceTests(_ test: TestHarness) async {
        // MARK: Settings store

        do {
            let shell = Shell.detect(from: "/bin/zsh")
            test.expectEqual(
                shell.whichArguments(for: "codex"),
                ["-l", "-i", "-c", "which codex"],
                "CLI discovery loads interactive version-manager configuration"
            )
            test.expectEqual(
                shell.pathArguments(),
                ["-l", "-i", "-c", "echo $PATH"],
                "subprocess PATH uses the same interactive shell configuration"
            )
            let miseShims = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/mise/shims").path
            test.expect(
                BinaryLocator.commonPaths.contains(miseShims),
                "CLI discovery includes stable mise shims after version upgrades"
            )
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            box.store.write(value: "tenMinutes", key: "app.refreshInterval")
            box.store.write(value: ["claude", "cursor"], key: "workspace.sampleSourceIDs")
            box.store.write(value: true, key: "providers.claude.isEnabled")
            test.expectEqual(box.store.read(key: "app.refreshInterval") as String?, "tenMinutes", "nested string write")
            test.expectEqual(box.store.read(key: "workspace.sampleSourceIDs") as [String]?, ["claude", "cursor"], "array write")
            test.expectEqual(box.store.read(key: "providers.claude.isEnabled") as Bool?, true, "nested bool write")
            box.store.write(value: nil, key: "app.refreshInterval")
            test.expect(box.store.read(key: "app.refreshInterval") as String? == nil, "nil removes key")
            test.expectEqual(box.store.read(key: "workspace.sampleSourceIDs") as [String]?, ["claude", "cursor"], "sibling keys survive")
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            box.settings.setClaudeProbeMode(.api)
            test.expectEqual(box.settings.claudeProbeMode(), .api, "claude probe mode persists")
            box.settings.setRefreshInterval(.off)
            test.expectEqual(box.settings.refreshInterval(), .off, "refresh interval persists")
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            box.settings.saveGithubToken("secure-token")
            test.expectEqual(box.settings.getGithubToken(), "secure-token", "credential is readable")
            test.expectEqual(
                box.secureCredentials.get(forKey: CredentialKey.githubToken),
                "secure-token",
                "credential uses secure storage"
            )
            box.settings.deleteGithubToken()
            test.expect(box.settings.getGithubToken() == nil, "credential deletion clears secure storage")

            let extensionConfig = JSONExtensionConfigRepository(
                settingsStore: box.store,
                secureCredentials: box.secureCredentials
            )
            extensionConfig.setSecretValue("extension-secret", forFieldId: "token", extensionId: "sample")
            test.expectEqual(
                extensionConfig.secretValue(forFieldId: "token", extensionId: "sample"),
                "extension-secret",
                "extension secrets use secure storage"
            )
            test.expectEqual(
                box.secureCredentials.get(forKey: "extension.sample.token"),
                "extension-secret",
                "extension secret has an isolated key"
            )
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let repository = JSONIslandWorkspaceRepository(store: box.store)
            let workspace = IslandWorkspaceStore(repository: repository)
            test.expectEqual(workspace.islands.count, 1, "empty store seeds one island")
            test.expectEqual(
                workspace.islands[0].complications.map(\.sourceID),
                ["claude", "codex", "cursor"],
                "default island seeds Claude, Codex, and Cursor"
            )
            test.expect(
                workspace.selectedComplicationID == nil,
                "opening an island workspace defaults to the island inspector"
            )
            workspace.addIsland()
            test.expectEqual(workspace.islands.count, 2, "island can be added")
            if let secondID = workspace.selectedIslandID {
                _ = workspace.addComplication(
                    to: secondID,
                    sourceID: "claude",
                    metricIDs: ["quota.session", "quota.weekly", "quota.extra"],
                    family: .dualRing
                )
                test.expectEqual(
                    workspace.selectedComplication?.metricIDs,
                    ["quota.session", "quota.weekly"],
                    "dual ring keeps exactly two metrics"
                )
                workspace.updateIsland(secondID) {
                    $0.placement = IslandPlacementConfiguration(
                        display: .display("42"),
                        edge: .leading,
                        mode: .manual,
                        topGap: 77
                    )
                }
                if let complicationID = workspace.selectedComplicationID {
                    workspace.duplicateComplication(complicationID, in: secondID)
                    test.expectEqual(
                        Set(workspace.selectedIsland?.complications.map(\.id) ?? []).count,
                        2,
                        "duplicated complications receive unique instance ids"
                    )
                    let originalOrder = workspace.selectedIsland?.complications.map(\.id) ?? []
                    workspace.moveComplications(from: IndexSet(integer: 0), to: 2, in: secondID)
                    test.expectEqual(
                        workspace.selectedIsland?.complications.map(\.id),
                        Array(originalOrder.reversed()),
                        "complications reorder within an island"
                    )
                    workspace.setComplicationOrder(originalOrder, in: secondID)
                    test.expectEqual(
                        workspace.selectedIsland?.complications.map(\.id),
                        originalOrder,
                        "explicit order restores a drag operation"
                    )
                    workspace.updateComplication(originalOrder[0], in: secondID) { $0.isVisible = false }
                    test.expectEqual(
                        workspace.selectedIsland?.visibleComplications.count,
                        1,
                        "hidden complications stay configured but leave the island"
                    )
                    if let removal = workspace.removeComplication(originalOrder[1], from: secondID) {
                        test.expectEqual(workspace.selectedIsland?.complications.count, 1, "complication removal returns its slot")
                        workspace.restoreComplication(removal)
                        test.expectEqual(
                            workspace.selectedIsland?.complications.map(\.id),
                            originalOrder,
                            "removed complications can be restored in place"
                        )
                    }
                }
                workspace.selectIsland(secondID)
                test.expect(
                    workspace.selectedComplicationID == nil,
                    "selecting an island clears complication selection"
                )
                if let removal = workspace.removeIsland(secondID) {
                    test.expectEqual(workspace.islands.count, 1, "island removal returns its original slot")
                    workspace.restoreIsland(removal)
                    test.expectEqual(workspace.islands.count, 2, "removed islands can be restored")
                    test.expectEqual(workspace.islands[1].id, secondID, "restored islands return to their original position")
                }
            }
            let reloaded = IslandWorkspaceStore(repository: repository)
            test.expectEqual(reloaded.islands.count, 2, "workspace persists without a migration layer")
            test.expectEqual(reloaded.islands[1].placement.edge, .leading, "screen edge persists")
            test.expectEqual(reloaded.islands[1].placement.display, .display("42"), "display target persists")
            test.expectEqual(reloaded.islands[1].placement.topGap, 77, "manual top spacing persists")
            test.expectEqual(
                reloaded.islands[1].visibleComplications.count,
                1,
                "complication visibility persists"
            )
            test.expectEqual(
                reloaded.workspace.referencedSourceIDs,
                Set(["claude", "codex", "cursor"]),
                "source references deduplicate across instances"
            )
        }

        do {
            let id = UUID()
            let data = Data(
                """
                {"id":"\(id.uuidString)","sourceID":"codex","metricIDs":["quota.session"],"family":"ring","labelStyle":"percentage","tint":"source","tapAction":"showDetails"}
                """.utf8
            )
            let decoded = try JSONDecoder().decode(ComplicationConfiguration.self, from: data)
            test.expect(decoded.isVisible, "saved complications without visibility remain visible")
            test.expectEqual(decoded.valueMode(at: 0), .used, "complications default each usage slot to used")
        } catch {
            test.expect(false, "complication defaults decode: \(error)")
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            box.store.write(value: ["islands": "invalid"], key: "workspace")
            let workspace = IslandWorkspaceStore(
                repository: JSONIslandWorkspaceRepository(store: box.store)
            )
            test.expectEqual(workspace.islands.count, 1, "invalid workspace data falls back safely")
        }

    }
}
