import Domain
import CryptoKit
import Foundation

public final class JSONExtensionTrustRepository: ExtensionTrustRepository, @unchecked Sendable {
    private let store: JSONSettingsStore

    public init(store: JSONSettingsStore = .shared) {
        self.store = store
    }

    public func isTrusted(extensionID: String, fingerprint: String) -> Bool {
        store.read(key: key(extensionID)) as String? == fingerprint
    }

    public func setTrusted(_ trusted: Bool, extensionID: String, fingerprint: String) {
        store.write(value: trusted ? fingerprint : nil, key: key(extensionID))
    }

    private func key(_ extensionID: String) -> String {
        let digest = SHA256.hash(data: Data(extensionID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "extensions.trust.\(digest)"
    }
}
