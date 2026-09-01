import Foundation

extension URLSession: NetworkClient {
    public func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Stateless network session for bearer-token and local monitoring requests.
/// It does not persist cookies, credentials, responses, or disk cache entries.
public enum NetworkClients {
    public static let ephemeral: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}
