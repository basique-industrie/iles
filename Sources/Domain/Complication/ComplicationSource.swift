import Foundation

public enum ComplicationSourceKind: String, Codable, CaseIterable, Sendable {
    case usage
    case system
    case time
    case session
    case extensionSource
}

public enum ComplicationMetricKind: String, Codable, Sendable {
    case gauge
    case value
    case status
    case duration
    case date
}

public struct ComplicationMetricDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: ComplicationMetricKind
    /// Optional SF Symbol that expresses this metric's meaning at a glance.
    public let symbol: String?
    public let unit: String?
    public let policy: ComplicationMetricPolicy

    public init(
        id: String,
        name: String,
        kind: ComplicationMetricKind,
        symbol: String? = nil,
        unit: String? = nil,
        policy: ComplicationMetricPolicy? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.symbol = symbol
        self.unit = unit
        self.policy = policy ?? ComplicationMetricPolicy(
            format: Self.defaultFormat(for: kind),
            range: kind == .gauge ? 0...100 : nil
        )
    }

    private static func defaultFormat(for kind: ComplicationMetricKind) -> ComplicationMetricFormat {
        switch kind {
        case .gauge: .percentage
        case .value: .text
        case .status: .status
        case .duration: .duration
        case .date: .date
        }
    }

    /// Produces safe user-facing copy for a persisted metric that is no longer
    /// advertised by its source. Optional provider windows can legitimately
    /// disappear between refreshes, but their implementation IDs must never
    /// leak into the interface.
    public static func fallbackName(for metricID: String) -> String {
        let quotaPrefix = "quota.key."
        if metricID.hasPrefix(quotaPrefix) {
            let key = String(metricID.dropFirst(quotaPrefix.count))
            if let quota = QuotaType(quotaKey: key) {
                return quota.title(style: .row)
            }
        }

        let leaf = metricID.split(separator: ".").last.map(String.init) ?? metricID
        let separated = leaf
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .unicodeScalars
            .reduce(into: "") { result, scalar in
                if CharacterSet.uppercaseLetters.contains(scalar),
                   let previous = result.unicodeScalars.last,
                   CharacterSet.lowercaseLetters.contains(previous) {
                    result.append(" ")
                }
                result.unicodeScalars.append(scalar)
            }

        let words = separated.split(whereSeparator: \Character.isWhitespace)
        guard !words.isEmpty else { return "Metric" }
        let acronyms = Set(["ai", "api", "cpu", "gpu", "http", "id", "ram", "url"])
        return words.map { word in
            let value = String(word)
            return acronyms.contains(value.lowercased()) ? value.uppercased() : value.capitalized
        }.joined(separator: " ")
    }
}

public struct ComplicationSourceDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// Stable identity shared by every configurable instance of this source.
    public let sourceKindID: String
    public let allowsMultipleInstances: Bool
    public let name: String
    public let kind: ComplicationSourceKind
    public let symbol: String
    public let accentHex: String?
    public let metrics: [ComplicationMetricDescriptor]
    public let supportedFamilies: [ComplicationFamily]
    public let complications: [ComplicationDescriptor]
    public let capabilities: [ComplicationCapability]
    public let actionURL: URL?

    public init(
        id: String,
        sourceKindID: String? = nil,
        allowsMultipleInstances: Bool = false,
        name: String,
        kind: ComplicationSourceKind,
        symbol: String,
        accentHex: String? = nil,
        metrics: [ComplicationMetricDescriptor],
        supportedFamilies: [ComplicationFamily],
        complications: [ComplicationDescriptor] = [],
        capabilities: [ComplicationCapability] = [],
        actionURL: URL? = nil
    ) {
        self.id = id
        self.sourceKindID = sourceKindID ?? id
        self.allowsMultipleInstances = allowsMultipleInstances
        self.name = name
        self.kind = kind
        self.symbol = symbol
        self.accentHex = accentHex
        self.metrics = metrics
        self.supportedFamilies = supportedFamilies
        self.complications = complications
        self.capabilities = capabilities
        self.actionURL = actionURL
    }

    public func metricName(for metricID: String) -> String {
        metrics.first { $0.id == metricID }?.name
            ?? ComplicationMetricDescriptor.fallbackName(for: metricID)
    }
}

public enum ComplicationValue: Codable, Equatable, Sendable {
    case gauge(value: Double, range: ClosedRange<Double>, label: String)
    case value(String, unit: String?)
    case status(label: String, level: StatusLevel)
    case duration(TimeInterval, label: String)
    case date(Date, label: String)

    public var kind: ComplicationMetricKind {
        switch self {
        case .gauge: .gauge
        case .value: .value
        case .status: .status
        case .duration: .duration
        case .date: .date
        }
    }

    public var displayText: String {
        switch self {
        case .gauge(let value, let range, let label):
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            return label.isEmpty ? "\(Int((fraction * 100).rounded()))%" : label
        case .value(let value, let unit):
            return unit.map { "\(value) \($0)" } ?? value
        case .status(let label, _), .duration(_, let label), .date(_, let label):
            return label
        }
    }

    public var progress: Double? {
        guard case .gauge(let value, let range, _) = self else { return nil }
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }
}

public struct SourceSnapshot: Codable, Equatable, Sendable {
    public let sourceID: String
    public let capturedAt: Date
    public let values: [String: ComplicationValue]
    public let errorDescription: String?
    public let quality: ComplicationSampleQuality
    public let availability: ComplicationAvailability

    public init(
        sourceID: String,
        capturedAt: Date = Date(),
        values: [String: ComplicationValue],
        errorDescription: String? = nil,
        quality: ComplicationSampleQuality = .live,
        availability: ComplicationAvailability = .available
    ) {
        self.sourceID = sourceID
        self.capturedAt = capturedAt
        self.values = values
        self.errorDescription = errorDescription
        self.quality = quality
        self.availability = availability
    }
}

@MainActor
public protocol ComplicationSource: Sendable {
    /// Stable identity used by registries without forcing construction of a
    /// potentially dynamic descriptor during every lookup.
    var id: String { get }
    var descriptor: ComplicationSourceDescriptor { get }
    var currentSnapshot: SourceSnapshot { get }
    func refresh(_ kind: RefreshKind) async -> SourceSnapshot
}

public extension ComplicationSource {
    var id: String { descriptor.id }
}
