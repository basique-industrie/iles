import Domain
import Infrastructure
import Observation
import SwiftUI

struct ComplicationRemoval: Sendable {
    let islandID: UUID
    let complication: ComplicationConfiguration
    let index: Int
    let wasFollowingHarnaisAccounts: Bool
}

struct IslandRemoval: Sendable {
    let island: IslandConfiguration
    let index: Int
}

/// Editable, persisted source of truth for every island and complication.
@MainActor
@Observable
final class IslandWorkspaceStore {
    private(set) var workspace: IslandWorkspace
    var selectedIslandID: UUID?
    var selectedComplicationID: UUID?

    @ObservationIgnored private let repository: any IslandWorkspaceRepository
    @ObservationIgnored var onWorkspaceChange: (() -> Void)?

    init(repository: any IslandWorkspaceRepository = JSONIslandWorkspaceRepository.shared) {
        self.repository = repository
        let loaded = repository.loadWorkspace()
        let initial = Self.sanitized(loaded ?? .defaultWorkspace)
        workspace = initial
        selectedIslandID = initial.islands.first?.id
        selectedComplicationID = nil
        if loaded == nil {
            let containsInvalidPersistedWorkspace =
                (repository as? JSONIslandWorkspaceRepository)?.containsWorkspaceData == true
            if !containsInvalidPersistedWorkspace {
                repository.saveWorkspace(initial)
            } else {
                AppLog.updates.error("Workspace could not be decoded; preserved existing data for recovery")
            }
        }
    }

    var islands: [IslandConfiguration] { workspace.islands }
    var visibleIslands: [IslandConfiguration] { islands.filter(\.isVisible) }

    var selectedIsland: IslandConfiguration? {
        guard let selectedIslandID else { return nil }
        return islands.first { $0.id == selectedIslandID }
    }

    var selectedComplication: ComplicationConfiguration? {
        guard let selectedComplicationID else { return nil }
        return selectedIsland?.complications.first { $0.id == selectedComplicationID }
    }

    func island(id: UUID) -> IslandConfiguration? {
        islands.first { $0.id == id }
    }

    func selectIsland(_ id: UUID) {
        guard island(id: id) != nil else { return }
        selectedIslandID = id
        selectedComplicationID = nil
    }

    func addIsland() {
        let number = islands.count + 1
        let placement = islands.isEmpty
            ? workspace.emptyIslandPlacement
            : IslandPlacementConfiguration(
                mode: .automatic,
                topGap: 8 + Double((islands.count % 4) * 120)
            )
        let island = IslandConfiguration(
            name: "Island \(number)",
            placement: placement
        )
        workspace.islands.append(island)
        selectedIslandID = island.id
        selectedComplicationID = nil
        persist()
    }

    func duplicateIsland(_ id: UUID) {
        guard let index = workspace.islands.firstIndex(where: { $0.id == id }) else { return }
        let source = workspace.islands[index]
        var placement = source.placement
        placement.mode = .automatic
        placement.topGap += 64
        let copy = IslandConfiguration(
            name: uniqueName(base: "\(source.name) Copy"),
            isVisible: source.isVisible,
            followsHarnaisAccounts: source.followsHarnaisAccounts == true,
            placement: placement,
            complications: source.complications.map {
                ComplicationConfiguration(
                    isVisible: $0.isVisible,
                    recipeID: $0.recipeID,
                    sourceID: $0.sourceID,
                    metricIDs: $0.metricIDs,
                    family: $0.family,
                    labelStyle: $0.labelStyle,
                    tint: $0.tint,
                    slotTints: $0.slotTints,
                    slotValueModes: $0.slotValueModes,
                    tapAction: $0.tapAction
                )
            }
        )
        workspace.islands.insert(copy, at: index + 1)
        selectedIslandID = copy.id
        selectedComplicationID = nil
        persist()
    }

    @discardableResult
    func removeIsland(_ id: UUID) -> IslandRemoval? {
        guard let index = workspace.islands.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = workspace.islands.remove(at: index)
        if workspace.islands.isEmpty {
            workspace.emptyIslandPlacement = removed.placement
        }
        if selectedIslandID == id {
            selectedIslandID = workspace.islands.isEmpty
                ? nil
                : workspace.islands[min(index, workspace.islands.count - 1)].id
            selectedComplicationID = nil
        }
        persist()
        return IslandRemoval(island: removed, index: index)
    }

    func restoreIsland(_ removal: IslandRemoval) {
        guard !workspace.islands.contains(where: { $0.id == removal.island.id }) else { return }
        let index = min(max(removal.index, 0), workspace.islands.count)
        workspace.islands.insert(removal.island, at: index)
        selectedIslandID = removal.island.id
        selectedComplicationID = nil
        persist()
    }

    func updateEmptyIslandPlacement(_ update: (inout IslandPlacementConfiguration) -> Void) {
        update(&workspace.emptyIslandPlacement)
        persist()
    }

    func updateIsland(_ id: UUID, _ update: (inout IslandConfiguration) -> Void) {
        guard let index = workspace.islands.firstIndex(where: { $0.id == id }) else { return }
        update(&workspace.islands[index])
        workspace.islands[index].name = normalizedName(workspace.islands[index].name)
        persist()
    }

    @discardableResult
    func addComplication(
        to islandID: UUID,
        sourceID: String,
        metricIDs: [String],
        family: ComplicationFamily,
        labelStyle: ComplicationLabelStyle? = nil,
        recipeID: String? = nil,
        tint: ComplicationTint = .source,
        tapAction: ComplicationAction = .showDetails,
        slotValueModes: [ComplicationValueMode]? = nil
    ) -> UUID? {
        guard let index = workspace.islands.firstIndex(where: { $0.id == islandID }) else { return nil }
        let complication = ComplicationConfiguration(
            recipeID: recipeID,
            sourceID: sourceID,
            metricIDs: metricIDs,
            family: family,
            labelStyle: labelStyle ?? (family == .status ? .compact : .percentage),
            tint: tint,
            slotValueModes: slotValueModes
                ?? ComplicationValueMode.remainingDefaults(
                    sourceID: sourceID,
                    metricIDs: metricIDs,
                    family: family
                ),
            tapAction: tapAction
        )
        workspace.islands[index].complications.append(complication)
        selectedIslandID = islandID
        selectedComplicationID = complication.id
        persist()
        return complication.id
    }

    func addComplications(
        to islandID: UUID,
        recipes: [ComplicationRecipe],
        select: Bool = false,
        insertionIndex: ((ComplicationRecipe, IslandConfiguration) -> Int)? = nil
    ) {
        guard let index = workspace.islands.firstIndex(where: { $0.id == islandID }),
              !recipes.isEmpty
        else { return }
        for recipe in recipes {
            let complication = ComplicationConfiguration(
                recipeID: recipe.id,
                sourceID: recipe.sourceID,
                metricIDs: recipe.metricIDs,
                family: recipe.family,
                labelStyle: recipe.labelStyle,
                tint: recipe.tint,
                slotValueModes: ComplicationValueMode.remainingDefaults(
                    sourceID: recipe.sourceID,
                    metricIDs: recipe.metricIDs,
                    family: recipe.family
                ),
                tapAction: recipe.tapAction
            )
            let count = workspace.islands[index].complications.count
            let at = insertionIndex?(recipe, workspace.islands[index]) ?? count
            workspace.islands[index].complications.insert(
                complication,
                at: min(max(at, 0), count)
            )
        }
        if select, let last = workspace.islands[index].complications.last {
            selectedIslandID = islandID
            selectedComplicationID = last.id
        }
        persist()
    }

    func duplicateComplication(_ id: UUID, in islandID: UUID) {
        guard let islandIndex = workspace.islands.firstIndex(where: { $0.id == islandID }),
              let index = workspace.islands[islandIndex].complications.firstIndex(where: { $0.id == id })
        else { return }
        let source = workspace.islands[islandIndex].complications[index]
        let copy = ComplicationConfiguration(
            isVisible: source.isVisible,
            recipeID: source.recipeID,
            sourceID: source.sourceID,
            metricIDs: source.metricIDs,
            family: source.family,
            labelStyle: source.labelStyle,
            tint: source.tint,
            slotTints: source.slotTints,
            slotValueModes: source.slotValueModes,
            tapAction: source.tapAction
        )
        workspace.islands[islandIndex].complications.insert(copy, at: index + 1)
        selectedComplicationID = copy.id
        persist()
    }

    @discardableResult
    func removeComplication(_ id: UUID, from islandID: UUID) -> ComplicationRemoval? {
        guard let islandIndex = workspace.islands.firstIndex(where: { $0.id == islandID }),
              let index = workspace.islands[islandIndex].complications.firstIndex(where: { $0.id == id })
        else { return nil }
        let wasFollowing = workspace.islands[islandIndex].followsHarnaisAccounts == true
        let removed = workspace.islands[islandIndex].complications.remove(at: index)
        if removed.sourceID == HarnaisWeeklyStarter.sourceID {
            // A manually reduced collection becomes a custom island. Otherwise
            // reconciliation would immediately recreate the widget just deleted.
            workspace.islands[islandIndex].followsHarnaisAccounts = false
        }
        if selectedComplicationID == id {
            let items = workspace.islands[islandIndex].complications
            selectedComplicationID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
        }
        persist()
        return ComplicationRemoval(islandID: islandID, complication: removed, index: index,
                                   wasFollowingHarnaisAccounts: wasFollowing)
    }

    func restoreComplication(_ removal: ComplicationRemoval) {
        guard let islandIndex = workspace.islands.firstIndex(where: { $0.id == removal.islandID }),
              !workspace.islands[islandIndex].complications.contains(where: { $0.id == removal.complication.id })
        else { return }
        let index = min(max(removal.index, 0), workspace.islands[islandIndex].complications.count)
        workspace.islands[islandIndex].complications.insert(removal.complication, at: index)
        if removal.complication.sourceID == HarnaisWeeklyStarter.sourceID,
           removal.wasFollowingHarnaisAccounts {
            workspace.islands[islandIndex].followsHarnaisAccounts = true
        }
        selectedIslandID = removal.islandID
        selectedComplicationID = removal.complication.id
        persist()
    }

    func updateComplication(
        _ id: UUID,
        in islandID: UUID,
        _ update: (inout ComplicationConfiguration) -> Void
    ) {
        guard let islandIndex = workspace.islands.firstIndex(where: { $0.id == islandID }),
              let complicationIndex = workspace.islands[islandIndex].complications.firstIndex(where: { $0.id == id })
        else { return }
        update(&workspace.islands[islandIndex].complications[complicationIndex])
        let family = workspace.islands[islandIndex].complications[complicationIndex].family
        workspace.islands[islandIndex].complications[complicationIndex].metricIDs = Array(
            workspace.islands[islandIndex].complications[complicationIndex].metricIDs.prefix(family.metricLimit)
        )
        workspace.islands[islandIndex].complications[complicationIndex].slotTints = family.metricLimit > 1
            ? Array(workspace.islands[islandIndex].complications[complicationIndex].slotTints.prefix(family.metricLimit))
            : []
        workspace.islands[islandIndex].complications[complicationIndex].slotValueModes = Array(
            workspace.islands[islandIndex].complications[complicationIndex].slotValueModes.prefix(family.metricLimit)
        )
        persist()
    }

    func moveComplications(from offsets: IndexSet, to destination: Int, in islandID: UUID) {
        guard let index = workspace.islands.firstIndex(where: { $0.id == islandID }) else { return }
        workspace.islands[index].complications.move(
            fromOffsets: offsets,
            toOffset: min(max(destination, 0), workspace.islands[index].complications.count)
        )
        persist()
    }

    func setComplicationOrder(_ orderedIDs: [UUID], in islandID: UUID) {
        guard let index = workspace.islands.firstIndex(where: { $0.id == islandID }) else { return }
        let current = workspace.islands[index].complications
        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let ordered = orderedIDs.compactMap { byID[$0] }
        let included = Set(ordered.map(\.id))
        workspace.islands[index].complications = ordered + current.filter { !included.contains($0.id) }
        persist()
    }

    private func persist() {
        workspace = Self.sanitized(workspace)
        repository.saveWorkspace(workspace)
        onWorkspaceChange?()
    }

    private func uniqueName(base: String) -> String {
        let names = Set(islands.map(\.name))
        guard names.contains(base) else { return base }
        var suffix = 2
        while names.contains("\(base) \(suffix)") { suffix += 1 }
        return "\(base) \(suffix)"
    }

    private func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Island" : String(trimmed.prefix(48))
    }

    private static func sanitized(_ workspace: IslandWorkspace) -> IslandWorkspace {
        var copy = workspace
        var islandIDs = Set<UUID>()
        for index in copy.islands.indices {
            if !islandIDs.insert(copy.islands[index].id).inserted {
                let old = copy.islands[index]
                copy.islands[index] = IslandConfiguration(
                    name: old.name,
                    isVisible: old.isVisible,
                    followsHarnaisAccounts: old.followsHarnaisAccounts == true,
                    placement: old.placement,
                    complications: old.complications
                )
            }
            var complicationIDs = Set<UUID>()
            copy.islands[index].complications = copy.islands[index].complications.filter {
                !$0.sourceID.isEmpty && !$0.metricIDs.isEmpty && complicationIDs.insert($0.id).inserted
            }
        }
        return copy
    }
}
