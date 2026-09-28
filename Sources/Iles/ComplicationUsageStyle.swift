import Domain
import SwiftUI

/// Colors and bounds shared by the compact rings and their detail bars.
struct ComplicationUsageStyle {
    let complication: ComplicationConfiguration
    let descriptor: ComplicationSourceDescriptor?

    static func clampedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    func accent(at index: Int) -> Color {
        let tint = complication.slotTints.indices.contains(index)
            ? complication.slotTints[index] : complication.tint
        switch tint.style {
        case .monochrome: return .white.opacity(0.82)
        case .custom: return Color(hex: tint.hex) ?? .white
        case .source:
            let ids = complication.metricIDs.indices.contains(index)
                ? [complication.metricIDs[index]] : complication.metricIDs
            return ComplicationSourceStyle.accent(sourceID: complication.sourceID,
                                                  descriptor: descriptor, metricIDs: ids)
        }
    }

    func color(at index: Int, value: ComplicationValue?) -> Color {
        guard let value, let number = numericValue(value),
              complication.metricIDs.indices.contains(index),
              let metric = descriptor?.metrics.first(where: { $0.id == complication.metricIDs[index] }),
              let rawThresholds = metric.policy.thresholds
        else { return accent(at: index) }
        let recipe = complication.recipeID.flatMap { id in descriptor?.complications.first { $0.id == id } }
        var transforms = recipe.flatMap { $0.slots.indices.contains(index) ? $0.slots[index].transforms : nil } ?? []
        if complication.valueMode(at: index) == .remaining { transforms.append(.remaining) }
        let direction = metric.policy.direction.transformed(by: transforms)
        let thresholds = rawThresholds.transformed(by: transforms, in: metric.policy.range)
        switch direction {
        case .higherIsBetter:
            if let critical = thresholds.critical, number <= critical { return .red }
            if let warning = thresholds.warning, number <= warning { return .orange }
        case .lowerIsBetter, .neutral:
            if let critical = thresholds.critical, number >= critical { return .red }
            if let warning = thresholds.warning, number >= warning { return .orange }
        }
        return accent(at: index)
    }

    func intensity(at index: Int) -> Double {
        complication.family == .dualRing && index == 1 && !complication.slotTints.indices.contains(1) ? 0.68 : 1
    }

    private func numericValue(_ value: ComplicationValue) -> Double? {
        switch value {
        case .gauge(let number, _, _): return number
        case .value(let text, _): return Double(text.replacingOccurrences(of: ",", with: "."))
        case .duration(let interval, _): return interval
        case .date(let date, _): return date.timeIntervalSince1970
        case .status: return nil
        }
    }
}
