import Foundation
import Domain

/// Persists extension config values in JSON and secrets in Keychain.
public final class JSONExtensionConfigRepository: ExtensionConfigRepository, @unchecked Sendable {
    private let settingsStore: JSONSettingsStore
    private let secureCredentials: any CredentialRepository

    public init(
        settingsStore: JSONSettingsStore,
        secureCredentials: any CredentialRepository = KeychainCredentialRepository.shared
    ) {
        self.settingsStore = settingsStore
        self.secureCredentials = secureCredentials
    }

    // MARK: - Non-Secret Values

    public func value(forFieldId fieldId: String, extensionId: String) -> String? {
        settingsStore.read(key: "extensions.\(extensionId).\(fieldId)")
    }

    public func setValue(_ value: String?, forFieldId fieldId: String, extensionId: String) {
        settingsStore.write(value: value, key: "extensions.\(extensionId).\(fieldId)")
    }

    // MARK: - Secret Values

    public func secretValue(forFieldId fieldId: String, extensionId: String) -> String? {
        secureCredentials.get(forKey: secretKey(fieldId: fieldId, extensionId: extensionId))
    }

    public func setSecretValue(_ value: String?, forFieldId fieldId: String, extensionId: String) {
        let key = secretKey(fieldId: fieldId, extensionId: extensionId)
        if let value, !value.isEmpty {
            secureCredentials.save(value, forKey: key)
        } else {
            secureCredentials.delete(forKey: key)
        }
    }

    // MARK: - All Values

    public func allValues(forExtensionId extensionId: String, fields: [ConfigField]) -> [String: String] {
        var result: [String: String] = [:]
        for field in fields {
            let stored: String? = if field.isSecret {
                secretValue(forFieldId: field.id, extensionId: extensionId)
            } else {
                value(forFieldId: field.id, extensionId: extensionId)
            }
            if let effective = field.effectiveValue(stored: stored) {
                result[field.id] = effective
            }
        }
        return result
    }

    // MARK: - Private

    private func secretKey(fieldId: String, extensionId: String) -> String {
        "extension.\(extensionId).\(fieldId)"
    }
}
