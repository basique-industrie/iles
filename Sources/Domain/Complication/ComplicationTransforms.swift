import Foundation

public struct ComplicationHistoryPoint: Codable, Equatable, Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct ComplicationTransformContext: Sendable {
    public let now: Date
    public let history: [String: [ComplicationHistoryPoint]]

    public init(now: Date = Date(), history: [String: [ComplicationHistoryPoint]] = [:]) {
        self.now = now
        self.history = history
    }
}

/// Small bounded history buffer for the handful of metrics that opt into trend
/// semantics. It deliberately avoids a database and never grows with catalog
/// entries that are not currently being sampled.
public struct ComplicationHistoryBuffer: Sendable {
    private var points: [String: [ComplicationHistoryPoint]] = [:]
    public let retention: TimeInterval
    public let maximumPointsPerMetric: Int
    public let minimumSampleInterval: TimeInterval

    public init(
        retention: TimeInterval = 7 * 86_400,
        maximumPointsPerMetric: Int = 720,
        minimumSampleInterval: TimeInterval = 30
    ) {
        self.retention = max(retention, 60)
        self.maximumPointsPerMetric = max(maximumPointsPerMetric, 2)
        self.minimumSampleInterval = max(minimumSampleInterval, 0)
    }

    public mutating func record(
        sourceID: String,
        snapshot: SourceSnapshot,
        metrics: [ComplicationMetricDescriptor]
    ) {
        let historyMetricIDs = metrics.filter(\.policy.keepsHistory).map(\.id)
        let cutoff = snapshot.capturedAt.addingTimeInterval(-retention)
        for metricID in historyMetricIDs {
            guard let number = snapshot.values[metricID]?.historyNumber else { continue }
            let key = Self.key(sourceID: sourceID, metricID: metricID)
            var samples = points[key, default: []]
            if samples.last?.date == snapshot.capturedAt {
                samples[samples.count - 1] = ComplicationHistoryPoint(date: snapshot.capturedAt, value: number)
            } else if let last = samples.last,
                      snapshot.capturedAt.timeIntervalSince(last.date) < minimumSampleInterval {
                // Live metrics can refresh every second or two. Preserve the
                // prior point for trend comparison without allocating history
                // entries at display-frame cadence.
                continue
            } else {
                samples.removeAll { $0.date < cutoff }
                samples.append(ComplicationHistoryPoint(date: snapshot.capturedAt, value: number))
            }
            if samples.count > maximumPointsPerMetric {
                samples.removeFirst(samples.count - maximumPointsPerMetric)
            }
            points[key] = samples
        }
    }

    public func context(
        sourceID: String,
        now: Date = Date(),
        before cutoff: Date? = nil
    ) -> ComplicationTransformContext {
        let prefix = sourceID + "::"
        let sourcePoints = points.reduce(into: [String: [ComplicationHistoryPoint]]()) { result, item in
            guard item.key.hasPrefix(prefix) else { return }
            let eligible = cutoff.map { date in item.value.filter { $0.date < date } } ?? item.value
            result[String(item.key.dropFirst(prefix.count))] = eligible
        }
        return ComplicationTransformContext(now: now, history: sourcePoints)
    }

    public func pointCount(sourceID: String, metricID: String) -> Int {
        points[Self.key(sourceID: sourceID, metricID: metricID)]?.count ?? 0
    }

    private static func key(sourceID: String, metricID: String) -> String {
        sourceID + "::" + metricID
    }
}

public enum ComplicationTransformEngine {
    public static func present(
        _ value: ComplicationValue,
        as mode: ComplicationValueMode
    ) -> ComplicationValue {
        guard mode == .remaining,
              case .gauge(let raw, let range, _) = value
        else { return value }
        let remaining = range.upperBound - (raw - range.lowerBound)
        return gauge(remaining, range: range)
    }

    public static func resolve(
        recipe: ComplicationRecipe,
        snapshot: SourceSnapshot,
        context: ComplicationTransformContext = ComplicationTransformContext()
    ) -> [ComplicationValue] {
        recipe.slots.compactMap { resolve(slot: $0, snapshot: snapshot, context: context) }
    }

    public static func resolve(
        slot: ComplicationMetricSlot,
        snapshot: SourceSnapshot,
        context: ComplicationTransformContext = ComplicationTransformContext()
    ) -> ComplicationValue? {
        guard var value = snapshot.values[slot.metricID] else { return nil }
        for transform in slot.transforms {
            guard let transformed = apply(
                transform,
                to: value,
                metricID: slot.metricID,
                values: snapshot.values,
                context: context
            ) else { return nil }
            value = transformed
        }
        return value
    }

    private static func apply(
        _ transform: ComplicationTransform,
        to value: ComplicationValue,
        metricID: String,
        values: [String: ComplicationValue],
        context: ComplicationTransformContext
    ) -> ComplicationValue? {
        switch transform {
        case .used:
            return value
        case .remaining, .inverse:
            guard case .gauge(let raw, let range, _) = value else { return nil }
            let remaining = range.upperBound - (raw - range.lowerBound)
            return gauge(remaining, range: range)
        case .clamp(let lower, let upper):
            guard upper > lower, let number = value.numericValue else { return nil }
            let clamped = min(max(number, lower), upper)
            return gauge(clamped, range: lower...upper)
        case .ratio(let denominatorMetricID):
            guard let numerator = value.numericValue,
                  let denominator = values[denominatorMetricID]?.numericValue,
                  denominator != 0
            else { return nil }
            return gauge(numerator / denominator * 100, range: 0...100)
        case .sum(let metricIDs):
            return aggregate(metricIDs, values: values, operation: { $0.reduce(0, +) })
        case .minimum(let metricIDs):
            return aggregate(metricIDs, values: values, operation: { $0.min() })
        case .maximum(let metricIDs):
            return aggregate(metricIDs, values: values, operation: { $0.max() })
        case .delta:
            guard let current = value.numericValue,
                  let previous = context.history[metricID]?.last?.value
            else { return nil }
            return .value(Self.compactNumber(current - previous), unit: nil)
        case .rate(let period):
            guard period > 0,
                  let current = value.numericValue,
                  let previous = context.history[metricID]?.last,
                  context.now > previous.date
            else { return nil }
            let elapsed = context.now.timeIntervalSince(previous.date)
            return .value(Self.compactNumber((current - previous.value) / elapsed * period), unit: nil)
        case .elapsed:
            guard case .date(let date, _) = value else { return nil }
            let seconds = max(context.now.timeIntervalSince(date), 0)
            return .duration(seconds, label: Self.durationLabel(seconds))
        case .countdown:
            guard case .date(let date, _) = value else { return nil }
            let seconds = max(date.timeIntervalSince(context.now), 0)
            return .duration(seconds, label: Self.durationLabel(seconds))
        case .threshold(let warning, let critical, let direction):
            guard let number = value.numericValue else { return nil }
            let level: StatusLevel
            switch direction {
            case .higherIsBetter:
                level = number <= critical ? .critical : (number <= warning ? .warning : .healthy)
            case .lowerIsBetter, .neutral:
                level = number >= critical ? .critical : (number >= warning ? .warning : .healthy)
            }
            return .status(label: Self.compactNumber(number), level: level)
        case .rollingAverage(let window):
            guard window > 0 else { return nil }
            let cutoff = context.now.addingTimeInterval(-window)
            var samples = context.history[metricID, default: []]
                .filter { $0.date >= cutoff }
                .map(\.value)
            if let current = value.numericValue { samples.append(current) }
            guard !samples.isEmpty else { return nil }
            return .value(Self.compactNumber(samples.reduce(0, +) / Double(samples.count)), unit: nil)
        case .exhaustionForecast:
            guard case .gauge(let raw, let range, _) = value,
                  let previous = context.history[metricID]?.last,
                  context.now > previous.date,
                  raw > previous.value
            else { return nil }
            let unitsPerSecond = (raw - previous.value) / context.now.timeIntervalSince(previous.date)
            guard unitsPerSecond > 0 else { return nil }
            let remaining = max(range.upperBound - raw, 0)
            let date = context.now.addingTimeInterval(remaining / unitsPerSecond)
            return .date(date, label: Self.durationLabel(date.timeIntervalSince(context.now)))
        }
    }

    private static func aggregate(
        _ metricIDs: [String],
        values: [String: ComplicationValue],
        operation: ([Double]) -> Double?
    ) -> ComplicationValue? {
        let numbers = metricIDs.compactMap { values[$0]?.numericValue }
        guard numbers.count == metricIDs.count, let result = operation(numbers) else { return nil }
        return .value(compactNumber(result), unit: nil)
    }

    private static func gauge(_ value: Double, range: ClosedRange<Double>) -> ComplicationValue {
        let span = range.upperBound - range.lowerBound
        let progress = span > 0 ? (value - range.lowerBound) / span : 0
        return .gauge(
            value: value,
            range: range,
            label: "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
        )
    }

    private static func compactNumber(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }

    private static func durationLabel(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded()), 0)
        let days = seconds / 86_400
        if days > 0 { return "\(days)d" }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}


private extension ComplicationValue {
    var numericValue: Double? {
        switch self {
        case .gauge(let value, _, _): value
        case .value(let value, _): Double(value.replacingOccurrences(of: ",", with: "."))
        case .duration(let interval, _): interval
        case .date(let date, _): date.timeIntervalSince1970
        case .status: nil
        }
    }

    var historyNumber: Double? { numericValue }
}
