import Domain
import Foundation

/// One primary Harnais ring per account for the starter collection.
///
/// Prefers a weekly window; Cursor uses Models when there is no 7-day window.
/// Islands that opt in pick up newly published accounts. Missing or renamed
/// windows retain their saved configuration until the user selects new data.
enum HarnaisWeeklyStarter {
    static let sourceID = ProviderIdentity.harnais.rawValue
    static let collectionID = "harnais-weekly"

    struct Rebind: Equatable {
        let complicationID: UUID
        let recipe: ComplicationRecipe
    }

    static func glanceQuotas(in snapshot: UsageSnapshot) -> [UsageQuota] {
        snapshot.quotaGroups.compactMap { group in
            group.quotas.first(where: \.isWeeklyWindow)
                ?? group.quotas.first(where: \.isAccountGlanceWindow)
        }
    }

    static func recipeID(for quota: UsageQuota) -> String {
        "\(sourceID).quota-\(FirstPartyComplicationCatalog.stableIDComponent(quota.quotaType.quotaKey))"
    }

    static func glanceRecipes(
        in snapshot: UsageSnapshot,
        descriptor: ComplicationSourceDescriptor
    ) -> [ComplicationRecipe] {
        glanceQuotas(in: snapshot).compactMap { quota in
            descriptor.complications.first { $0.id == recipeID(for: quota) }
        }
    }

    /// Named time-window recipes currently published by Harnais, in feed order.
    static func liveNamedRecipes(
        in snapshot: UsageSnapshot,
        descriptor: ComplicationSourceDescriptor
    ) -> [ComplicationRecipe] {
        snapshot.quotas.compactMap { quota in
            guard case .timeLimit = quota.quotaType else { return nil }
            return descriptor.complications.first { $0.id == recipeID(for: quota) }
        }
    }

    /// Repair metric drift only when the saved recipe still exists. Provider and
    /// window names cannot establish account identity after a rename or failure.
    static func rebindPairs(
        on island: IslandConfiguration,
        live: [ComplicationRecipe]
    ) -> [Rebind] {
        island.complications.compactMap { item in
            guard item.sourceID == sourceID,
                  let recipeID = item.recipeID,
                  let recipe = live.first(where: { $0.id == recipeID }),
                  item.metricIDs != recipe.metricIDs
            else { return nil }
            return Rebind(complicationID: item.id, recipe: recipe)
        }
    }

    /// Only islands explicitly following Harnais accounts receive new glances.
    /// Custom islands and their session/weekly pairs keep their saved contents.
    static func missingRecipes(
        on island: IslandConfiguration,
        snapshot: UsageSnapshot,
        descriptor: ComplicationSourceDescriptor
    ) -> [ComplicationRecipe] {
        guard island.followsHarnaisAccounts == true else { return [] }
        let wanted = glanceRecipes(in: snapshot, descriptor: descriptor)
        guard !wanted.isEmpty else { return [] }

        let presentRecipeIDs = Set(island.complications.compactMap(\.recipeID))
        let presentMetrics = Set(
            island.complications
                .filter { $0.sourceID == sourceID }
                .flatMap(\.metricIDs)
        )
        return wanted.filter { recipe in
            !contains(recipe, recipeIDs: presentRecipeIDs, metrics: presentMetrics)
        }
    }

    /// Index that keeps new glances in Harnais account order among existing rings.
    static func insertionIndex(
        for recipe: ComplicationRecipe,
        on island: IslandConfiguration,
        wanted: [ComplicationRecipe]
    ) -> Int {
        let wantedIndex = wanted.firstIndex { $0.id == recipe.id } ?? wanted.count
        let predecessors = Array(wanted.prefix(wantedIndex))
        let predecessorIDs = Set(predecessors.map(\.id))
        let predecessorMetrics = Set(predecessors.flatMap(\.metricIDs))
        if let last = island.complications.lastIndex(where: { item in
            if let recipeID = item.recipeID, predecessorIDs.contains(recipeID) {
                return true
            }
            return item.sourceID == sourceID
                && item.metricIDs.contains(where: predecessorMetrics.contains)
        }) {
            return last + 1
        }
        return island.complications.firstIndex { $0.sourceID == sourceID }
            ?? island.complications.count
    }

    private static func contains(
        _ recipe: ComplicationRecipe,
        recipeIDs: Set<String>,
        metrics: Set<String>
    ) -> Bool {
        recipeIDs.contains(recipe.id)
            || recipe.metricIDs.contains(where: metrics.contains)
    }

}
