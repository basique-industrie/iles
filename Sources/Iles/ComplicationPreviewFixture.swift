import Domain
import Foundation

enum ComplicationPreviewFixture {
    static func values(for recipe: ComplicationRecipe, sourceID: String) -> [ComplicationValue] {
        guard let fixture = recipe.fixtures.first(where: { $0.state == .normal }) ?? recipe.fixtures.first else {
            return []
        }
        let snapshot = SourceSnapshot(
            sourceID: sourceID,
            capturedAt: Date(timeIntervalSince1970: 0),
            values: fixture.values,
            quality: .cached
        )
        let resolved = ComplicationTransformEngine.resolve(
            recipe: recipe,
            snapshot: snapshot,
            context: ComplicationTransformContext(now: Date(timeIntervalSince1970: 0))
        )
        return resolved.isEmpty ? recipe.metricIDs.compactMap { fixture.values[$0] } : resolved
    }
}
