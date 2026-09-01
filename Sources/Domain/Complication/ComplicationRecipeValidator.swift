import Foundation

public enum ComplicationRecipeValidationIssue: Equatable, Sendable {
    case emptyID
    case emptyName
    case emptySummary
    case emptyQuestion
    case sourceMismatch(expected: String, actual: String)
    case missingMetrics([String])
    case missingCapabilities([ComplicationCapability])
    case incompatibleMetricKinds([String])
    case incompatibleCompatibleFamilies([ComplicationFamily])
    case unsupportedDefaultFamily
    case sourceDoesNotSupportFamily
    case tooManySlots(limit: Int)
    case missingFixtures
    case fixtureMissingMetrics(String, [String])
    case fixtureValueKindMismatch(fixture: String, metricID: String, expected: ComplicationMetricKind, actual: ComplicationMetricKind)
}
public enum ComplicationRecipeValidator {
    public static func issues(
        in recipe: ComplicationRecipe,
        source: ComplicationSourceDescriptor,
        strict: Bool = true
    ) -> [ComplicationRecipeValidationIssue] {
        var issues: [ComplicationRecipeValidationIssue] = []
        if recipe.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.emptyID) }
        if recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.emptyName) }
        if strict, recipe.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.emptySummary) }
        if strict, recipe.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.emptyQuestion) }
        if recipe.sourceID != source.id {
            issues.append(.sourceMismatch(expected: source.id, actual: recipe.sourceID))
        }
        let metricIDs = Set(source.metrics.map(\.id))
        let missing = recipe.metricIDs.filter { !metricIDs.contains($0) }
        if !missing.isEmpty { issues.append(.missingMetrics(missing)) }
        let descriptors = Dictionary(uniqueKeysWithValues: source.metrics.map { ($0.id, $0) })
        let incompatible = recipe.slots.compactMap { slot -> String? in
            guard let metric = descriptors[slot.metricID] else { return nil }
            let inputKind = metric.kind
            let outputKind = resolvedKind(inputKind: inputKind, transforms: slot.transforms)
            return familySupportsMetric(recipe.family, outputKind: outputKind, metric: metric)
                ? nil
                : slot.metricID
        }
        if !incompatible.isEmpty { issues.append(.incompatibleMetricKinds(incompatible)) }
        let outputKinds = recipe.slots.compactMap { slot -> ComplicationMetricKind? in
            guard let inputKind = descriptors[slot.metricID]?.kind else { return nil }
            return resolvedKind(inputKind: inputKind, transforms: slot.transforms)
        }
        let incompatibleFamilies = recipe.compatibleFamilies.filter { family in
            switch family {
            case .dualRing:
                return outputKinds.count < 2 || recipe.slots.contains { slot in
                    guard let metric = descriptors[slot.metricID] else { return false }
                    let outputKind = resolvedKind(inputKind: metric.kind, transforms: slot.transforms)
                    return !familySupportsMetric(family, outputKind: outputKind, metric: metric)
                }
            case .summary:
                return outputKinds.count < 2
            case .cluster:
                return outputKinds.count < 3 || recipe.slots.contains { slot in
                    guard let metric = descriptors[slot.metricID] else { return false }
                    let outputKind = resolvedKind(inputKind: metric.kind, transforms: slot.transforms)
                    return !familySupportsMetric(family, outputKind: outputKind, metric: metric)
                }
            default:
                return recipe.slots.contains { slot in
                    guard let metric = descriptors[slot.metricID] else { return false }
                    let outputKind = resolvedKind(inputKind: metric.kind, transforms: slot.transforms)
                    return !familySupportsMetric(family, outputKind: outputKind, metric: metric)
                }
            }
        }
        if !incompatibleFamilies.isEmpty {
            issues.append(.incompatibleCompatibleFamilies(incompatibleFamilies))
        }
        let capabilities = Set(source.capabilities)
        let missingCapabilities = recipe.requiredCapabilities.filter { !capabilities.contains($0) }
        if !missingCapabilities.isEmpty { issues.append(.missingCapabilities(missingCapabilities)) }
        if !recipe.compatibleFamilies.contains(recipe.family) { issues.append(.unsupportedDefaultFamily) }
        if !source.supportedFamilies.contains(recipe.family) { issues.append(.sourceDoesNotSupportFamily) }
        if recipe.slots.count > recipe.family.metricLimit { issues.append(.tooManySlots(limit: recipe.family.metricLimit)) }
        if strict, recipe.fixtures.isEmpty { issues.append(.missingFixtures) }
        if strict {
            for fixture in recipe.fixtures {
                let missing = recipe.metricIDs.filter { fixture.values[$0] == nil }
                if !missing.isEmpty { issues.append(.fixtureMissingMetrics(fixture.name, missing)) }
                for metricID in recipe.metricIDs {
                    guard let expected = descriptors[metricID]?.kind,
                          let actual = fixture.values[metricID]?.kind,
                          actual != expected
                    else { continue }
                    issues.append(
                        .fixtureValueKindMismatch(
                            fixture: fixture.name,
                            metricID: metricID,
                            expected: expected,
                            actual: actual
                        )
                    )
                }
            }
        }
        return issues
    }

    public static func resolvedKind(
        inputKind: ComplicationMetricKind,
        transforms: [ComplicationTransform]
    ) -> ComplicationMetricKind {
        transforms.reduce(inputKind) { kind, transform in
            switch transform {
            case .used: kind
            case .remaining, .inverse, .clamp, .ratio: .gauge
            case .sum, .minimum, .maximum, .delta, .rate, .rollingAverage: .value
            case .elapsed, .countdown: .duration
            case .threshold: .status
            case .exhaustionForecast: .date
            }
        }
    }

    public static func family(
        _ family: ComplicationFamily,
        supports kind: ComplicationMetricKind,
        metric: ComplicationMetricDescriptor? = nil
    ) -> Bool {
        let kindFits = switch family {
        case .ring, .dualRing, .cluster: kind == .gauge
        case .status: kind == .status
        case .activity: kind == .status || kind == .duration
        case .countdown: kind == .date || kind == .duration
        case .trend: kind == .gauge || kind == .value || kind == .duration
        case .value, .summary: true
        }
        guard kindFits else { return false }
        if (family == .ring || family == .dualRing || family == .cluster), let metric {
            guard metric.policy.range != nil else { return false }
        }
        guard family == .trend, let metric else { return true }
        return metric.policy.keepsHistory || metric.policy.thresholds != nil
    }

    private static func familySupportsMetric(
        _ family: ComplicationFamily,
        outputKind: ComplicationMetricKind,
        metric: ComplicationMetricDescriptor
    ) -> Bool {
        self.family(family, supports: outputKind, metric: metric)
    }
}
