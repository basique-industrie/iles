import Domain
import Foundation
import Infrastructure

enum ConfigurableSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case gitRepository
    case githubRepository
    case healthEndpoint

    var id: String { rawValue }

    var sourceKindID: String {
        switch self {
        case .gitRepository: "developer.git"
        case .githubRepository: "developer.github"
        case .healthEndpoint: "services.endpoint"
        }
    }

    var title: String {
        switch self {
        case .gitRepository: "Git Repository"
        case .githubRepository: "GitHub Repository"
        case .healthEndpoint: "Health Endpoint"
        }
    }

    var pluralTitle: String {
        switch self {
        case .gitRepository: "Git Repositories"
        case .githubRepository: "GitHub Repositories"
        case .healthEndpoint: "Health Endpoints"
        }
    }

    var symbol: String {
        switch self {
        case .gitRepository: "arrow.triangle.branch"
        case .githubRepository: "chevron.left.forwardslash.chevron.right"
        case .healthEndpoint: "waveform.path.ecg"
        }
    }

    var setupSummary: String {
        switch self {
        case .gitRepository: "Monitor another local working tree, branch, and sync state."
        case .githubRepository: "Monitor Actions, reviews, and deployments for another repository."
        case .healthEndpoint: "Monitor another HTTP health URL independently."
        }
    }

    func placeholderName(number: Int) -> String {
        number <= 1 ? title : "\(title) \(number)"
    }
}

struct ConfigurableSourceInstanceRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: ConfigurableSourceKind
    let placeholderName: String
}

/// Persists only user-created source instances. The three built-in first
/// instances retain their stable IDs, while every additional instance receives
/// an independent ID and configuration namespace.
final class ConfigurableSourceInstanceCatalog: @unchecked Sendable {
    private static let key = "sourceInstances.catalog"
    private let store: JSONSettingsStore

    init(store: JSONSettingsStore = .shared) {
        self.store = store
    }

    func records() -> [ConfigurableSourceInstanceRecord] {
        guard let encoded: String = store.read(key: Self.key),
              let data = encoded.data(using: .utf8),
              let records = try? JSONDecoder().decode([ConfigurableSourceInstanceRecord].self, from: data)
        else { return [] }
        var seen = Set<String>()
        return records.filter {
            $0.id.hasPrefix($0.kind.sourceKindID + ".")
                && seen.insert($0.id).inserted
        }
    }

    func add(kind: ConfigurableSourceKind) -> ConfigurableSourceInstanceRecord {
        var current = records()
        let existingNames = Set(current.filter { $0.kind == kind }.map(\.placeholderName))
        var number = 2
        while existingNames.contains(kind.placeholderName(number: number)) { number += 1 }
        let record = ConfigurableSourceInstanceRecord(
            id: "\(kind.sourceKindID).\(UUID().uuidString.lowercased())",
            kind: kind,
            placeholderName: kind.placeholderName(number: number)
        )
        current.append(record)
        save(current)
        return record
    }

    @discardableResult
    func remove(id: String) -> Bool {
        var current = records()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        current.remove(at: index)
        save(current)
        return true
    }

    private func save(_ records: [ConfigurableSourceInstanceRecord]) {
        guard let data = try? JSONEncoder().encode(records),
              let encoded = String(data: data, encoding: .utf8)
        else { return }
        store.write(value: encoded, key: Self.key)
    }
}

extension ComplicationSourceDescriptor {
    var configurableKind: ConfigurableSourceKind? {
        ConfigurableSourceKind.allCases.first { $0.sourceKindID == sourceKindID }
    }
}
