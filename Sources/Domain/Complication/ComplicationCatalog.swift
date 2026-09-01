import Foundation

/// Product-level grouping used by the complication gallery. Categories describe
/// the question a recipe answers, independently of the concrete data source.
public enum ComplicationCategory: String, Codable, CaseIterable, Sendable {
    case ai
    case sessions
    case time
    case mac
    case focus
    case developer
    case services
    case extensions
}

/// Presentation semantics for a metric. The older gauge/value distinction is
/// still exposed by `ComplicationMetricKind`; this type supplies enough meaning
/// for formatting, transformations, thresholds, and catalog discovery.
public enum ComplicationMetricFormat: String, Codable, CaseIterable, Sendable {
    case percentage
    case count
    case currency
    case duration
    case date
    case rate
    case bytes
    case text
    case status
}

public enum ComplicationMetricDirection: String, Codable, CaseIterable, Sendable {
    case higherIsBetter
    case lowerIsBetter
    case neutral
}

public enum ComplicationPrivacy: String, Codable, CaseIterable, Sendable {
    case publicData
    case personal
    case sensitive
}

/// Refresh classes are intentionally semantic rather than fixed timers. The
/// runtime maps them to a cadence and can coalesce sources used by many islands.
public enum ComplicationRefreshClass: String, Codable, CaseIterable, Sendable {
    case eventDriven
    case liveLocal
    case periodicLocal
    case periodicNetwork
    case onDemand
}

public enum ComplicationSampleQuality: String, Codable, CaseIterable, Sendable {
    case live
    case cached
    case stale
    case unavailable
    case failed
}

public enum ComplicationAvailabilityState: String, Codable, CaseIterable, Sendable {
    case available
    case setupRequired
    case permissionRequired
    case temporarilyUnavailable
    case unsupported
    case failed
}

public enum ComplicationRecoveryAction: String, Codable, CaseIterable, Sendable {
    case configure
    case requestPermission
    case retry
    case openSettings
    case none
}

public struct ComplicationAvailability: Codable, Equatable, Sendable {
    public let state: ComplicationAvailabilityState
    public let message: String?
    public let recoveryAction: ComplicationRecoveryAction

    public init(
        state: ComplicationAvailabilityState = .available,
        message: String? = nil,
        recoveryAction: ComplicationRecoveryAction = .none
    ) {
        self.state = state
        self.message = message
        self.recoveryAction = recoveryAction
    }

    public static let available = ComplicationAvailability()
}

/// A source capability is more stable than a provider-specific metric ID and
/// allows one recipe to bind to several compatible providers.
public enum ComplicationCapability: String, Codable, CaseIterable, Sendable {
    case quota
    case cost
    case resetDate
    case status
    case sessionActivity
    case calendarRead
    case remindersRead
    case systemHealth
    case repositoryRead
    case networkAccess
    case serviceHealth
    case shortHistory
}

public struct ComplicationThreshold: Codable, Equatable, Sendable {
    public let warning: Double?
    public let critical: Double?

    public init(warning: Double? = nil, critical: Double? = nil) {
        self.warning = warning
        self.critical = critical
    }
}

public struct ComplicationMetricPolicy: Codable, Equatable, Sendable {
    public let format: ComplicationMetricFormat
    public let direction: ComplicationMetricDirection
    public let range: ClosedRange<Double>?
    public let thresholds: ComplicationThreshold?
    public let privacy: ComplicationPrivacy
    public let refreshClass: ComplicationRefreshClass
    public let staleAfter: TimeInterval?
    public let keepsHistory: Bool
    public let accessibilityLabel: String?

    public init(
        format: ComplicationMetricFormat,
        direction: ComplicationMetricDirection = .neutral,
        range: ClosedRange<Double>? = nil,
        thresholds: ComplicationThreshold? = nil,
        privacy: ComplicationPrivacy = .publicData,
        refreshClass: ComplicationRefreshClass = .periodicLocal,
        staleAfter: TimeInterval? = nil,
        keepsHistory: Bool = false,
        accessibilityLabel: String? = nil
    ) {
        self.format = format
        self.direction = direction
        self.range = range
        self.thresholds = thresholds
        self.privacy = privacy
        self.refreshClass = refreshClass
        self.staleAfter = staleAfter
        self.keepsHistory = keepsHistory
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum ComplicationTransform: Codable, Equatable, Sendable {
    case used
    case remaining
    case inverse
    case clamp(lower: Double, upper: Double)
    case ratio(denominatorMetricID: String)
    case sum(metricIDs: [String])
    case minimum(metricIDs: [String])
    case maximum(metricIDs: [String])
    case delta
    case rate(per: TimeInterval)
    case elapsed
    case countdown
    case threshold(warning: Double, critical: Double, direction: ComplicationMetricDirection)
    case rollingAverage(window: TimeInterval)
    case exhaustionForecast
}

public extension ComplicationTransform {
    var requiresHistory: Bool {
        switch self {
        case .delta, .rate, .rollingAverage, .exhaustionForecast:
            true
        case .used, .remaining, .inverse, .clamp, .ratio, .sum,
             .minimum, .maximum, .elapsed, .countdown, .threshold:
            false
        }
    }
}

public extension ComplicationMetricDirection {
    func transformed(by transforms: [ComplicationTransform]) -> Self {
        transforms.reduce(self) { current, transform in
            guard transform == .remaining || transform == .inverse else { return current }
            return switch current {
            case .higherIsBetter: .lowerIsBetter
            case .lowerIsBetter: .higherIsBetter
            case .neutral: .neutral
            }
        }
    }
}

public extension ComplicationThreshold {
    func transformed(
        by transforms: [ComplicationTransform],
        in range: ClosedRange<Double>? = nil
    ) -> Self {
        let range = range ?? 0...100
        return transforms.reduce(self) { current, transform in
            guard transform == .remaining || transform == .inverse else { return current }
            func inverted(_ value: Double?) -> Double? {
                value.map { range.upperBound - ($0 - range.lowerBound) }
            }
            return ComplicationThreshold(
                warning: inverted(current.warning),
                critical: inverted(current.critical)
            )
        }
    }
}

public struct ComplicationMetricSlot: Codable, Equatable, Sendable {
    public let metricID: String
    public let transforms: [ComplicationTransform]

    public init(metricID: String, transforms: [ComplicationTransform] = []) {
        self.metricID = metricID
        self.transforms = transforms
    }
}

public enum ComplicationFixtureState: String, Codable, CaseIterable, Sendable {
    case normal
    case warning
    case critical
    case stale
    case unavailable
}

public struct ComplicationFixture: Codable, Equatable, Sendable {
    public let name: String
    public let state: ComplicationFixtureState
    public let values: [String: ComplicationValue]

    public init(
        name: String,
        state: ComplicationFixtureState,
        values: [String: ComplicationValue]
    ) {
        self.name = name
        self.state = state
        self.values = values
    }
}

/// A curated, ready-to-add catalog item. Recipes own sensible visual defaults;
/// a complication instance stores only the selected recipe and user overrides.
public struct ComplicationRecipe: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let shortName: String
    public let summary: String
    public let question: String
    public let sourceID: String
    public let category: ComplicationCategory
    public let tags: [String]
    public let family: ComplicationFamily
    public let compatibleFamilies: [ComplicationFamily]
    public let slots: [ComplicationMetricSlot]
    public let labelStyle: ComplicationLabelStyle
    public let tint: ComplicationTint
    public let tapAction: ComplicationAction
    public let requiredCapabilities: [ComplicationCapability]
    public let rank: Int
    public let isFeatured: Bool
    public let isNew: Bool
    public let fixtures: [ComplicationFixture]

    public var metricIDs: [String] {
        Array(slots.map(\.metricID).prefix(family.metricLimit))
    }

    public init(
        id: String,
        name: String,
        shortName: String? = nil,
        summary: String = "",
        question: String = "",
        sourceID: String,
        category: ComplicationCategory = .extensions,
        tags: [String] = [],
        family: ComplicationFamily,
        compatibleFamilies: [ComplicationFamily] = [],
        slots: [ComplicationMetricSlot],
        labelStyle: ComplicationLabelStyle = .percentage,
        tint: ComplicationTint = .source,
        tapAction: ComplicationAction = .showDetails,
        requiredCapabilities: [ComplicationCapability] = [],
        rank: Int = 0,
        isFeatured: Bool = false,
        isNew: Bool = false,
        fixtures: [ComplicationFixture] = []
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName ?? name
        self.summary = summary
        self.question = question
        self.sourceID = sourceID
        self.category = category
        self.tags = tags
        self.family = family
        self.compatibleFamilies = compatibleFamilies.isEmpty ? [family] : compatibleFamilies
        self.slots = Array(slots.prefix(family.metricLimit))
        self.labelStyle = labelStyle
        self.tint = tint
        self.tapAction = tapAction
        self.requiredCapabilities = requiredCapabilities
        self.rank = rank
        self.isFeatured = isFeatured
        self.isNew = isNew
        self.fixtures = fixtures
    }

    /// Rebinds a source-kind recipe to one concrete source instance. Recipe IDs
    /// intentionally remain stable within a kind; the source ID disambiguates
    /// instances in the gallery and workspace.
    public func bound(to sourceID: String) -> ComplicationRecipe {
        ComplicationRecipe(
            id: id,
            name: name,
            shortName: shortName,
            summary: summary,
            question: question,
            sourceID: sourceID,
            category: category,
            tags: tags,
            family: family,
            compatibleFamilies: compatibleFamilies,
            slots: slots,
            labelStyle: labelStyle,
            tint: tint,
            tapAction: tapAction,
            requiredCapabilities: requiredCapabilities,
            rank: rank,
            isFeatured: isFeatured,
            isNew: isNew,
            fixtures: fixtures
        )
    }

    /// Compact initializer retained for first-party declarations. This is not a
    /// migration path: it constructs the catalog-v2 recipe directly.
    public init(
        id: String,
        name: String,
        sourceID: String,
        family: ComplicationFamily,
        metricIDs: [String],
        labelStyle: ComplicationLabelStyle = .percentage
    ) {
        self.init(
            id: id,
            name: name,
            sourceID: sourceID,
            family: family,
            slots: metricIDs.map { ComplicationMetricSlot(metricID: $0) },
            labelStyle: labelStyle
        )
    }
}

public typealias ComplicationDescriptor = ComplicationRecipe
