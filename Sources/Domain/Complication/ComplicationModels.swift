import Foundation

/// The visual families supported by the compact island renderer.
public enum ComplicationFamily: String, Codable, CaseIterable, Sendable {
    case ring
    case dualRing
    case value
    case status
    case activity
    case countdown
    case trend
    case summary
    case cluster

    public var metricLimit: Int {
        switch self {
        case .dualRing: 2
        case .summary, .cluster: 3
        default: 1
        }
    }
}

public enum ComplicationLabelStyle: String, Codable, CaseIterable, Sendable {
    case percentage
    case value
    case compact
    case hidden
}

/// How a bounded usage metric is presented in one complication slot.
/// The source always publishes canonical consumed progress; each ring or value
/// can independently show that progress as used or remaining.
public enum ComplicationValueMode: String, Codable, CaseIterable, Sendable, Hashable {
    case used
    case remaining

    /// Used only on newly added quota rings. Decode still falls back to used.
    public static func remainingDefaults(
        sourceID: String,
        metricIDs: [String],
        family: ComplicationFamily
    ) -> [ComplicationValueMode] {
        let isQuota = sourceID == ProviderIdentity.harnais.rawValue
            || metricIDs.contains { $0.hasPrefix("quota") }
        guard isQuota else { return [] }
        let count = min(max(metricIDs.count, 1), family.metricLimit)
        return Array(repeating: .remaining, count: count)
    }
}

public enum ComplicationTintStyle: String, Codable, CaseIterable, Sendable {
    case source
    case monochrome
    case custom
}

public struct ComplicationTint: Codable, Equatable, Sendable {
    public var style: ComplicationTintStyle
    public var hex: String?

    public init(style: ComplicationTintStyle = .source, hex: String? = nil) {
        self.style = style
        self.hex = style == .custom ? hex : nil
    }

    public static let source = ComplicationTint()
    public static let monochrome = ComplicationTint(style: .monochrome)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let style = ComplicationTintStyle(rawValue: raw), style != .custom {
            self.init(style: style)
        } else {
            self.init(style: .custom, hex: raw.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch style {
        case .source, .monochrome:
            try container.encode(style.rawValue)
        case .custom:
            try container.encode(hex ?? "FFFFFF")
        }
    }
}

public enum ComplicationAction: String, Codable, CaseIterable, Sendable {
    case showDetails
    case refresh
    case openDashboard
    case none
}

public struct ComplicationConfiguration: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var isVisible: Bool
    public var recipeID: String?
    public var sourceID: String
    public var metricIDs: [String]
    public var family: ComplicationFamily
    public var labelStyle: ComplicationLabelStyle
    public var tint: ComplicationTint
    public var slotTints: [ComplicationTint]
    public var slotValueModes: [ComplicationValueMode]
    public var tapAction: ComplicationAction

    public init(
        id: UUID = UUID(),
        isVisible: Bool = true,
        recipeID: String? = nil,
        sourceID: String,
        metricIDs: [String],
        family: ComplicationFamily = .ring,
        labelStyle: ComplicationLabelStyle = .percentage,
        tint: ComplicationTint = .source,
        slotTints: [ComplicationTint] = [],
        slotValueModes: [ComplicationValueMode] = [],
        tapAction: ComplicationAction = .showDetails
    ) {
        self.id = id
        self.isVisible = isVisible
        self.recipeID = recipeID
        self.sourceID = sourceID
        self.metricIDs = Array(metricIDs.prefix(family.metricLimit))
        self.family = family
        self.labelStyle = labelStyle
        self.tint = tint
        self.slotTints = family.metricLimit > 1
            ? Array(slotTints.prefix(family.metricLimit))
            : []
        self.slotValueModes = Array(slotValueModes.prefix(family.metricLimit))
        self.tapAction = tapAction
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case isVisible
        case recipeID
        case sourceID
        case metricIDs
        case family
        case labelStyle
        case tint
        case slotTints
        case slotValueModes
        case tapAction
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        recipeID = try container.decodeIfPresent(String.self, forKey: .recipeID)
        sourceID = try container.decode(String.self, forKey: .sourceID)
        metricIDs = try container.decode([String].self, forKey: .metricIDs)
        family = try container.decode(ComplicationFamily.self, forKey: .family)
        labelStyle = try container.decode(ComplicationLabelStyle.self, forKey: .labelStyle)
        tint = try container.decode(ComplicationTint.self, forKey: .tint)
        slotTints = family.metricLimit > 1
            ? Array((try container.decodeIfPresent([ComplicationTint].self, forKey: .slotTints) ?? []).prefix(family.metricLimit))
            : []
        slotValueModes = Array(
            (try container.decodeIfPresent([ComplicationValueMode].self, forKey: .slotValueModes) ?? [])
                .prefix(family.metricLimit)
        )
        tapAction = try container.decode(ComplicationAction.self, forKey: .tapAction)
        metricIDs = Array(metricIDs.prefix(family.metricLimit))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encodeIfPresent(recipeID, forKey: .recipeID)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(metricIDs, forKey: .metricIDs)
        try container.encode(family, forKey: .family)
        try container.encode(labelStyle, forKey: .labelStyle)
        try container.encode(tint, forKey: .tint)
        if !slotTints.isEmpty {
            try container.encode(slotTints, forKey: .slotTints)
        }
        if !slotValueModes.isEmpty {
            try container.encode(slotValueModes, forKey: .slotValueModes)
        }
        try container.encode(tapAction, forKey: .tapAction)
    }

    public mutating func setFamily(_ family: ComplicationFamily) {
        self.family = family
        metricIDs = Array(metricIDs.prefix(family.metricLimit))
        slotTints = family.metricLimit > 1
            ? Array(slotTints.prefix(family.metricLimit))
            : []
        slotValueModes = Array(slotValueModes.prefix(family.metricLimit))
    }

    public func valueMode(at index: Int) -> ComplicationValueMode {
        slotValueModes.indices.contains(index) ? slotValueModes[index] : .used
    }

    public mutating func setValueMode(_ mode: ComplicationValueMode, at index: Int) {
        guard index >= 0, index < family.metricLimit else { return }
        while slotValueModes.count <= index {
            slotValueModes.append(.used)
        }
        slotValueModes[index] = mode
    }
}

public enum IslandDisplayTarget: Codable, Equatable, Hashable, Sendable {
    case main
    case display(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = raw == "main" ? .main : .display(raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .main: try container.encode("main")
        case .display(let id): try container.encode(id)
        }
    }
}

public enum IslandEdge: String, Codable, CaseIterable, Hashable, Sendable {
    case leading
    case trailing
}

public enum IslandPlacementMode: String, Codable, CaseIterable, Hashable, Sendable {
    case automatic
    case manual
}

public struct IslandPlacementConfiguration: Codable, Equatable, Sendable {
    public var display: IslandDisplayTarget
    public var edge: IslandEdge
    public var mode: IslandPlacementMode
    public var topGap: Double

    public init(
        display: IslandDisplayTarget = .main,
        edge: IslandEdge = .trailing,
        mode: IslandPlacementMode = .automatic,
        topGap: Double = 8
    ) {
        self.display = display
        self.edge = edge
        self.mode = mode
        self.topGap = topGap
    }
}

public struct IslandConfiguration: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var isVisible: Bool
    /// Only explicit account-following collections add rings after refresh.
    public var followsHarnaisAccounts: Bool?
    public var placement: IslandPlacementConfiguration
    public var complications: [ComplicationConfiguration]

    public init(
        id: UUID = UUID(),
        name: String,
        isVisible: Bool = true,
        followsHarnaisAccounts: Bool = false,
        placement: IslandPlacementConfiguration = .init(),
        complications: [ComplicationConfiguration] = []
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.followsHarnaisAccounts = followsHarnaisAccounts
        self.placement = placement
        self.complications = complications
    }

    public var visibleComplications: [ComplicationConfiguration] {
        complications.filter(\.isVisible)
    }
}

public struct IslandWorkspace: Codable, Equatable, Sendable {
    public var islands: [IslandConfiguration]
    /// Placement of the empty-workspace plus pill, reused when the first island is added.
    public var emptyIslandPlacement: IslandPlacementConfiguration

    public init(
        islands: [IslandConfiguration],
        emptyIslandPlacement: IslandPlacementConfiguration = .init()
    ) {
        self.islands = islands
        self.emptyIslandPlacement = emptyIslandPlacement
    }

    public static var defaultWorkspace: IslandWorkspace {
        IslandWorkspace(islands: [])
    }

    public var referencedSourceIDs: Set<String> {
        Set(islands.flatMap(\.complications).map(\.sourceID))
    }

    enum CodingKeys: String, CodingKey {
        case islands
        case emptyIslandPlacement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        islands = try container.decode([IslandConfiguration].self, forKey: .islands)
        emptyIslandPlacement = try container.decodeIfPresent(
            IslandPlacementConfiguration.self,
            forKey: .emptyIslandPlacement
        ) ?? .init()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(islands, forKey: .islands)
        try container.encode(emptyIslandPlacement, forKey: .emptyIslandPlacement)
    }
}

public protocol IslandWorkspaceRepository: Sendable {
    func loadWorkspace() -> IslandWorkspace?
    func saveWorkspace(_ workspace: IslandWorkspace)
}
