import Foundation

public protocol NetworkClient: Sendable {
    func request(_ request: URLRequest) async throws -> (Data, URLResponse)
}
