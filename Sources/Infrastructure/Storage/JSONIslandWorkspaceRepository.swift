import Domain
import Foundation

/// Persists the workspace inside the versioned settings document.
public final class JSONIslandWorkspaceRepository: IslandWorkspaceRepository, @unchecked Sendable {
    public static let shared = JSONIslandWorkspaceRepository(store: .shared)

    private let store: JSONSettingsStore

    public init(store: JSONSettingsStore) {
        self.store = store
    }

    public func loadWorkspace() -> IslandWorkspace? {
        guard let object: [String: Any] = store.read(key: "workspace"),
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return try? JSONDecoder().decode(IslandWorkspace.self, from: data)
    }

    public var containsWorkspaceData: Bool {
        let object: [String: Any]? = store.read(key: "workspace")
        return object != nil
    }

    public func saveWorkspace(_ workspace: IslandWorkspace) {
        guard let data = try? JSONEncoder().encode(workspace),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            AppLog.updates.error("Workspace encoding failed")
            return
        }
        store.write(value: object, key: "workspace")
    }
}
