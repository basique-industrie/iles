import Foundation

/// Represents a parsed extension manifest (manifest.json).
/// Each extension defines one or more sections, each with its own probe command.
public struct ExtensionManifest: Sendable, Equatable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let version: String
    public let description: String?
    public let icon: String?
    public let colors: ExtensionColors?
    public let dashboardURL: URL?
    public let statusPageURL: URL?
    public let configFields: [ConfigField]
    public let sections: [ExtensionSection]
    public let category: ComplicationCategory
    public let metrics: [ExtensionMetricDefinition]
    public let complications: [ExtensionComplicationDescriptor]

    /// Whether this extension declares any user-configurable fields.
    public var hasConfig: Bool { !configFields.isEmpty }

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        icon: String? = nil,
        colors: ExtensionColors? = nil,
        dashboardURL: URL? = nil,
        statusPageURL: URL? = nil,
        configFields: [ConfigField] = [],
        sections: [ExtensionSection],
        category: ComplicationCategory = .extensions,
        metrics: [ExtensionMetricDefinition] = [],
        complications: [ExtensionComplicationDescriptor] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.icon = icon
        self.colors = colors
        self.dashboardURL = dashboardURL
        self.statusPageURL = statusPageURL
        self.configFields = configFields
        self.sections = sections
        self.category = category
        self.metrics = metrics
        self.complications = complications
    }

    /// Parses a manifest from JSON data.
    public static func parse(from data: Data) throws -> ExtensionManifest {
        let decoder = JSONDecoder()
        let raw = try decoder.decode(RawManifest.self, from: data)

        guard raw.schemaVersion == Self.currentSchemaVersion else {
            throw ExtensionManifestError.unsupportedSchema(raw.schemaVersion)
        }

        guard Self.isValidIdentifier(raw.id),
              !raw.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !raw.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ExtensionManifestError.invalidIdentity }

        let configFields = raw.config ?? []
        let configIDs = configFields.map(\.id)
        let environmentNames = configFields.map(\.environmentVariableName)
        guard configIDs.allSatisfy(Self.isValidIdentifier),
              Set(configIDs).count == configIDs.count,
              Set(environmentNames).count == environmentNames.count,
              configFields.allSatisfy({
                  !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && ($0.type != .choice || $0.options?.isEmpty == false)
              })
        else { throw ExtensionManifestError.invalidConfigFields }

        guard !raw.sections.isEmpty else {
            throw ExtensionManifestError.emptySections
        }

        let sectionIDs = raw.sections.map(\.id)
        guard sectionIDs.allSatisfy(Self.isValidIdentifier),
              Set(sectionIDs).count == sectionIDs.count
        else { throw ExtensionManifestError.invalidSectionIdentifiers }

        let metricIDs = raw.metrics.map(\.id)
        guard metricIDs.allSatisfy(Self.isValidIdentifier),
              raw.metrics.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw ExtensionManifestError.invalidMetricIdentity }
        guard Set(metricIDs).count == metricIDs.count else {
            throw ExtensionManifestError.duplicateMetricID
        }
        let complicationIDs = raw.complications.map(\.id)
        guard complicationIDs.allSatisfy(Self.isValidIdentifier),
              Set(complicationIDs).count == complicationIDs.count
        else { throw ExtensionManifestError.invalidComplicationIdentifiers }
        let knownMetricIDs = Set(metricIDs)
        let metricKinds = Dictionary(uniqueKeysWithValues: raw.metrics.map { ($0.id, $0.kind) })
        for complication in raw.complications {
            guard !complication.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !complication.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !complication.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !complication.slots.isEmpty,
                  complication.slots.count <= complication.family.metricLimit,
                  complication.compatibleFamilies.contains(complication.family)
            else { throw ExtensionManifestError.invalidComplication(complication.id) }
            let missing = complication.slots.map(\.metricID).filter { !knownMetricIDs.contains($0) }
            guard missing.isEmpty else {
                throw ExtensionManifestError.unknownComplicationMetrics(complication.id, missing)
            }
            let incompatible = complication.slots.contains { slot in
                guard let inputKind = metricKinds[slot.metricID] else { return false }
                let outputKind = ComplicationRecipeValidator.resolvedKind(
                    inputKind: inputKind,
                    transforms: slot.transforms
                )
                return !ComplicationRecipeValidator.family(complication.family, supports: outputKind)
            }
            guard !incompatible else {
                throw ExtensionManifestError.invalidComplication(complication.id)
            }
        }

        let sections = try raw.sections.map { rawSection -> ExtensionSection in
            guard let type = SectionType(rawValue: rawSection.type) else {
                throw ExtensionManifestError.unknownSectionType(rawSection.type)
            }

            let probeConfig: ProbeConfig
            if let builtIn = rawSection.probe.builtIn, builtIn == "healthCheck",
               let urlString = rawSection.probe.url,
               let url = URL(string: urlString),
               let scheme = url.scheme?.lowercased(),
               ["http", "https"].contains(scheme),
               url.host != nil {
                probeConfig = .healthCheck(url: url)
            } else if let command = rawSection.probe.command,
                      Self.isSafeRelativeScriptPath(command) {
                probeConfig = .script(command)
            } else {
                throw ExtensionManifestError.invalidProbeConfig(rawSection.id)
            }

            let interval = rawSection.probe.interval ?? 60
            let timeout = rawSection.probe.timeout ?? 10
            guard interval >= 1, interval <= 86_400, timeout >= 1, timeout <= 60 else {
                throw ExtensionManifestError.invalidProbeTiming(rawSection.id)
            }

            return ExtensionSection(
                id: rawSection.id,
                type: type,
                probeConfig: probeConfig,
                refreshInterval: interval,
                timeout: timeout
            )
        }

        return ExtensionManifest(
            schemaVersion: raw.schemaVersion,
            id: raw.id,
            name: raw.name,
            version: raw.version,
            description: raw.description,
            icon: raw.icon,
            colors: raw.colors,
            dashboardURL: raw.dashboardURL.flatMap { URL(string: $0) },
            statusPageURL: raw.statusPageURL.flatMap { URL(string: $0) },
            configFields: raw.config ?? [],
            sections: sections,
            category: raw.category,
            metrics: raw.metrics,
            complications: raw.complications
        )
    }

    private static func isSafeRelativeScriptPath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains(".."),
              !path.contains("\0"),
              path.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else { return false }
        return true
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 120 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Supporting Types

public struct ExtensionColors: Sendable, Equatable, Codable {
    public let primary: String
    public let gradient: [String]?

    public init(primary: String, gradient: [String]? = nil) {
        self.primary = primary
        self.gradient = gradient
    }
}

public struct ExtensionMetricDefinition: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let kind: ComplicationMetricKind
    public let unit: String?
    public let policy: ComplicationMetricPolicy?

    public init(
        id: String,
        name: String,
        kind: ComplicationMetricKind,
        unit: String? = nil,
        policy: ComplicationMetricPolicy? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.unit = unit
        self.policy = policy
    }
}

/// Optional gallery presets declared by an extension. Metric IDs match the
/// stable `id` fields emitted in extension metrics.
public struct ExtensionComplicationDescriptor: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let shortName: String
    public let summary: String
    public let question: String
    public let tags: [String]
    public let family: ComplicationFamily
    public let compatibleFamilies: [ComplicationFamily]
    public let slots: [ComplicationMetricSlot]
    public let labelStyle: ComplicationLabelStyle
    public let tint: ComplicationTint
    public let tapAction: ComplicationAction
    public let rank: Int
    public let isFeatured: Bool
    public let isNew: Bool
    public let fixtures: [ComplicationFixture]

    public init(
        id: String,
        name: String,
        shortName: String? = nil,
        summary: String,
        question: String,
        tags: [String],
        family: ComplicationFamily,
        compatibleFamilies: [ComplicationFamily],
        slots: [ComplicationMetricSlot],
        labelStyle: ComplicationLabelStyle,
        tint: ComplicationTint = .source,
        tapAction: ComplicationAction = .showDetails,
        rank: Int = 0,
        isFeatured: Bool = false,
        isNew: Bool = false,
        fixtures: [ComplicationFixture]
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName ?? name
        self.summary = summary
        self.question = question
        self.tags = tags
        self.family = family
        self.compatibleFamilies = compatibleFamilies
        self.slots = Array(slots.prefix(family.metricLimit))
        self.labelStyle = labelStyle
        self.tint = tint
        self.tapAction = tapAction
        self.rank = rank
        self.isFeatured = isFeatured
        self.isNew = isNew
        self.fixtures = fixtures
    }

    public func recipe(sourceID: String, category: ComplicationCategory) -> ComplicationRecipe {
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
            rank: rank,
            isFeatured: isFeatured,
            isNew: isNew,
            fixtures: fixtures
        )
    }
}

public enum ExtensionManifestError: Error, LocalizedError {
    case unsupportedSchema(Int)
    case invalidIdentity
    case invalidConfigFields
    case emptySections
    case invalidSectionIdentifiers
    case invalidMetricIdentity
    case duplicateMetricID
    case invalidComplicationIdentifiers
    case invalidComplication(String)
    case unknownComplicationMetrics(String, [String])
    case unknownSectionType(String)
    case invalidProbeConfig(String)
    case invalidProbeTiming(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "Unsupported extension schema version \(version); expected \(ExtensionManifest.currentSchemaVersion)"
        case .invalidIdentity:
            "Extension id, name, and version must be non-empty; ids may use letters, numbers, periods, hyphens, and underscores"
        case .invalidConfigFields:
            "Extension configuration fields need unique ids and environment names, non-empty labels, and options for choices"
        case .emptySections:
            "Extension manifest must have at least one section"
        case .invalidSectionIdentifiers:
            "Extension section identifiers must be valid and unique"
        case .invalidMetricIdentity:
            "Extension metrics need a valid identifier and non-empty name"
        case .duplicateMetricID:
            "Extension metric identifiers must be unique"
        case .invalidComplicationIdentifiers:
            "Extension complication identifiers must be valid and unique"
        case .invalidComplication(let id):
            "Complication '\(id)' has incomplete copy, slots, or family compatibility"
        case .unknownComplicationMetrics(let complicationID, let metricIDs):
            "Complication '\(complicationID)' references unknown metrics: \(metricIDs.joined(separator: ", "))"
        case .unknownSectionType(let type):
            "Unknown section type: '\(type)'"
        case .invalidProbeConfig(let sectionId):
            "Section '\(sectionId)' must have either 'command' or 'builtIn' + 'url' in probe config"
        case .invalidProbeTiming(let sectionId):
            "Section '\(sectionId)' has an invalid refresh interval or timeout"
        }
    }
}

// MARK: - Raw JSON Decoding Types

private struct RawManifest: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let version: String
    let description: String?
    let icon: String?
    let colors: ExtensionColors?
    let dashboardURL: String?
    let statusPageURL: String?
    let config: [ConfigField]?
    let sections: [RawSection]
    let category: ComplicationCategory
    let metrics: [ExtensionMetricDefinition]
    let complications: [ExtensionComplicationDescriptor]
}

private struct RawSection: Codable {
    let id: String
    let type: String
    let probe: RawProbe
}

private struct RawProbe: Codable {
    let command: String?
    let builtIn: String?
    let url: String?
    let interval: TimeInterval?
    let timeout: TimeInterval?
}
