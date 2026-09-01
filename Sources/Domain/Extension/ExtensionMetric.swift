import Foundation

/// A generic metric value displayed by extension sections.
/// Used for custom data that doesn't fit the standard quota/cost/daily models.
public struct ExtensionMetric: Sendable, Equatable, Codable {
    /// Stable identifier used by complication configurations. Older extension
    /// payloads may omit it; the adapter then falls back to the metric index.
    public let id: String?
    public let label: String
    public let value: String
    public let unit: String
    public let icon: String?
    public let color: String?
    public let delta: MetricDelta?
    public let progress: Double?
    public let kind: ComplicationMetricKind?
    public let numericValue: Double?
    public let rangeLower: Double?
    public let rangeUpper: Double?
    public let statusLevel: StatusLevel?
    public let duration: TimeInterval?
    public let date: Date?

    /// Section this metric belongs to when produced by an aggregating
    /// provider (e.g. Oh My Pi account rows). `nil` metrics render in the
    /// flat metrics grid used by extension scripts.
    public let group: String?

    public init(
        id: String? = nil,
        label: String,
        value: String,
        unit: String,
        icon: String? = nil,
        color: String? = nil,
        delta: MetricDelta? = nil,
        progress: Double? = nil,
        kind: ComplicationMetricKind? = nil,
        numericValue: Double? = nil,
        rangeLower: Double? = nil,
        rangeUpper: Double? = nil,
        statusLevel: StatusLevel? = nil,
        duration: TimeInterval? = nil,
        date: Date? = nil,
        group: String? = nil
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.unit = unit
        self.icon = icon
        self.color = color
        self.delta = delta
        self.progress = progress
        self.kind = kind
        self.numericValue = numericValue
        self.rangeLower = rangeLower
        self.rangeUpper = rangeUpper
        self.statusLevel = statusLevel
        self.duration = duration
        self.date = date
        self.group = group
    }
}

/// Comparison delta for a metric (e.g., "Vs Mar 16 -$701.58 (98.6%)")
public struct MetricDelta: Sendable, Equatable, Codable {
    public let vs: String
    public let value: String
    public let percent: Double?

    public init(vs: String, value: String, percent: Double? = nil) {
        self.vs = vs
        self.value = value
        self.percent = percent
    }
}

/// Status information for a status banner section.
public struct StatusInfo: Sendable, Equatable, Codable {
    public let text: String
    public let level: StatusLevel

    public init(text: String, level: StatusLevel) {
        self.text = text
        self.level = level
    }
}

/// Severity level for status banners.
public enum StatusLevel: String, Sendable, Equatable, Codable {
    case healthy
    case warning
    case critical
    case inactive
}
