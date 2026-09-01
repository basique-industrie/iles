import Domain
import Foundation

/// Stub cookie source. Browser-store access requires an additional dependency;
/// Iles keeps Alibaba on the manual cookie / API-key path instead.
public struct AlibabaBrowserCookieProvider: AlibabaCookieProviding {
    public init() {}

    public func extractBrowserCookies() -> String? { nil }
}
