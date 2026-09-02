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
            let shipped = AppIdentity.shipped
            let development = AppIdentity.development
            test.expectEqual(shipped.bundleIdentifier, "com.jean.iles", "shipped bundle id")
            test.expectEqual(development.bundleIdentifier, "com.jean.iles.dev", "dev bundle id")
            test.expect(!shipped.isDevelopment, "shipped identity is not marked development")
            test.expect(development.isDevelopment, "dev identity is marked development")
            test.expectEqual(shipped.displayName, "Iles", "shipped display name")
            test.expectEqual(development.displayName, "Iles Dev", "dev display name")
            test.expectEqual(shipped.dataDirectoryName, ".iles", "shipped settings directory")
            test.expectEqual(development.dataDirectoryName, ".iles-dev", "dev settings directory")
            test.expectEqual(
                shipped.keychainService,
                "com.jean.iles.credentials",
                "shipped Keychain service"
            )
            test.expectEqual(
                development.keychainService,
                "com.jean.iles.dev.credentials",
                "dev Keychain service"
            )
            test.expectEqual(shipped.hookPortFileName, "iles-hook-port", "shipped hook port file")
            test.expectEqual(
                development.hookPortFileName,
                "iles-dev-hook-port",
                "dev hook port file"
            )
            let shippedHook = HookInstaller.hookCommand(for: shipped)
            let developmentHook = HookInstaller.hookCommand(for: development)
            test.expect(shippedHook.contains("__iles_hook()"), "shipped hook function")
            test.expect(developmentHook.contains("__iles_dev_hook()"), "dev hook function")
            test.expect(shippedHook.contains("iles-hook-port"), "shipped hook reads its port file")
            test.expect(
                developmentHook.contains("iles-dev-hook-port"),
                "dev hook reads its port file"
            )
            test.expect(
                !shippedHook.contains("iles-dev-hook-port"),
                "shipped hook does not read the dev port file"
            )
        }

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
            test.expectEqual(workspace.islands.count, 0, "empty store seeds no islands")
            test.expect(
                workspace.selectedIslandID == nil,
                "an empty workspace has no selected island"
            )
            workspace.updateEmptyIslandPlacement {
                $0.mode = .manual
                $0.edge = .leading
                $0.topGap = 144
            }
            workspace.addIsland()
            test.expectEqual(
                workspace.islands[0].placement.edge,
                .leading,
                "the first island keeps the empty-workspace placement"
            )
            test.expectEqual(
                workspace.islands[0].placement.topGap,
                144,
                "the first island keeps the empty-workspace top gap"
            )
            test.expectEqual(
                workspace.islands[0].placement.mode,
                .manual,
                "the first island keeps the empty-workspace placement mode"
            )
            test.expectEqual(workspace.islands.count, 1, "island can be added")
            test.expect(
                workspace.selectedComplicationID == nil,
                "opening an island workspace defaults to the island inspector"
            )
            workspace.addIsland()
            test.expectEqual(workspace.islands.count, 2, "a second island can be added")
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
                Set(["claude"]),
                "source references come only from configured complications"
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
            let decoded = try JSONDecoder().decode(
                IslandWorkspace.self,
                from: Data(#"{"islands":[]}"#.utf8)
            )
            test.expectEqual(decoded.islands.count, 0, "legacy empty workspace decodes")
            test.expectEqual(
                decoded.emptyIslandPlacement.edge,
                .trailing,
                "legacy workspaces default the empty pill to the trailing edge"
            )
        } catch {
            test.expect(false, "legacy empty workspace decodes: \(error)")
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            let workspace = IslandWorkspaceStore(
                repository: JSONIslandWorkspaceRepository(store: box.store)
            )
            workspace.addIsland()
            workspace.updateIsland(workspace.islands[0].id) {
                $0.placement.mode = .manual
                $0.placement.topGap = 96
            }
            _ = workspace.removeIsland(workspace.islands[0].id)
            test.expectEqual(
                workspace.workspace.emptyIslandPlacement.topGap,
                96,
                "removing the last island keeps its placement for the empty pill"
            )
            workspace.addIsland()
            test.expectEqual(
                workspace.islands[0].placement.topGap,
                96,
                "re-adding the first island restores the last empty placement"
            )
        }

        do {
            let box = IsolatedBox.make()
            defer { box.tearDown() }
            box.store.write(value: ["islands": "invalid"], key: "workspace")
            let workspace = IslandWorkspaceStore(
                repository: JSONIslandWorkspaceRepository(store: box.store)
            )
            test.expectEqual(workspace.islands.count, 0, "invalid workspace data falls back to an empty workspace")
        }

    }
}
