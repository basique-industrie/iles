import Foundation

public protocol ExtensionTrustRepository: Sendable {
    func isTrusted(extensionID: String, fingerprint: String) -> Bool
    func setTrusted(_ trusted: Bool, extensionID: String, fingerprint: String)
}
