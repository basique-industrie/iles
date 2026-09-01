import Domain
import Foundation
import Network
import Security

/// Authenticated loopback HTTP receiver for the minimal Claude hook event.
public final class HookHTTPServer: @unchecked Sendable {
    private static let maximumRequestBytes = 64 * 1_024

    private var listener: NWListener?
    private var continuation: AsyncStream<SessionEvent>.Continuation?
    private let requestedPort: UInt16
    private let authenticationToken: String
    private let queue = DispatchQueue(label: "com.jean.iles.hookserver")
    private let stateLock = NSLock()
    private var storedActualPort: UInt16 = 0

    public var actualPort: UInt16 {
        stateLock.withLock { storedActualPort }
    }

    public init(defaultPort: UInt16 = HookConstants.defaultPort) {
        requestedPort = defaultPort
        authenticationToken = Self.makeAuthenticationToken()
    }

    /// Starts the server. Port zero selects an ephemeral loopback port.
    public func start() async throws -> AsyncStream<SessionEvent> {
        let stream = AsyncStream<SessionEvent> { continuation in
            queue.async { self.continuation = continuation }
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }

        let parameters = NWParameters.tcp
        let port = requestedPort == 0
            ? NWEndpoint.Port.any
            : (NWEndpoint.Port(rawValue: requestedPort) ?? .any)
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)

        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let actualPort = listener?.port?.rawValue else { return }
                self.stateLock.withLock { self.storedActualPort = actualPort }
                do {
                    try PortDiscovery.writeConnection(
                        port: Int(actualPort),
                        authenticationToken: self.authenticationToken
                    )
                    AppLog.hooks.info("Hook HTTP server is ready")
                } catch {
                    AppLog.hooks.error("Hook discovery setup failed: \(error.localizedDescription)")
                    listener?.cancel()
                    self.continuation?.finish()
                }
            case .failed(let error):
                AppLog.hooks.error("Hook HTTP server failed: \(error.localizedDescription)")
                self.continuation?.finish()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: queue)
        queue.async { self.listener = listener }
        return stream
    }

    public func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            continuation?.finish()
            continuation = nil
            stateLock.withLock { storedActualPort = 0 }
            PortDiscovery.removePortFile()
            AppLog.hooks.info("Hook HTTP server stopped")
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(from: connection, accumulated: Data())
    }

    private func receiveRequest(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1_024) {
            [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                AppLog.hooks.debug("Hook connection failed: \(error.localizedDescription)")
                self.respond(status: 400, on: connection)
                return
            }

            var requestData = accumulated
            if let data { requestData.append(data) }
            guard requestData.count <= Self.maximumRequestBytes else {
                self.respond(status: 413, on: connection)
                return
            }

            switch HookHTTPRequestParser.parse(
                requestData,
                authenticationToken: self.authenticationToken,
                isComplete: isComplete
            ) {
            case .incomplete:
                self.receiveRequest(from: connection, accumulated: requestData)
            case .rejected(let status):
                self.respond(status: status, on: connection)
            case .accepted(let body):
                guard let event = SessionEventParser.parse(body) else {
                    AppLog.hooks.warning("Rejected an invalid hook event")
                    self.respond(status: 422, on: connection)
                    return
                }
                AppLog.hooks.info("Received hook event: \(event.eventName.rawValue)")
                self.continuation?.yield(event)
                self.respond(status: 204, on: connection)
            }
        }
    }

    private func respond(status: Int, on connection: NWConnection) {
        let reason: String
        switch status {
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 413: reason = "Content Too Large"
        case 422: reason = "Unprocessable Content"
        default: reason = "Error"
        }
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(
            content: Data(response.utf8),
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    private static func makeAuthenticationToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess {
            return Data(bytes).base64EncodedString()
        }
        return UUID().uuidString + UUID().uuidString
    }
}

enum HookHTTPRequestParser {
    enum Result: Equatable {
        case incomplete
        case accepted(Data)
        case rejected(Int)
    }

    static func parse(
        _ data: Data,
        authenticationToken: String,
        isComplete: Bool
    ) -> Result {
        let separator = Data("\r\n\r\n".utf8)
        guard let separatorRange = data.range(of: separator) else {
            return isComplete ? .rejected(400) : .incomplete
        }
        guard separatorRange.lowerBound <= 16 * 1_024,
              let headers = String(data: data[..<separatorRange.lowerBound], encoding: .utf8)
        else { return .rejected(400) }

        let lines = headers.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .rejected(400) }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count == 3 else { return .rejected(400) }
        guard requestParts[0] == "POST" else { return .rejected(405) }
        guard requestParts[1] == "/hook" else { return .rejected(404) }
        guard requestParts[2] == "HTTP/1.1" || requestParts[2] == "HTTP/1.0" else {
            return .rejected(400)
        }

        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .rejected(400) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            fields[name] = value
        }

        guard fields["x-iles-token"] == authenticationToken else {
            return .rejected(401)
        }
        guard let contentLengthValue = fields["content-length"],
              let contentLength = Int(contentLengthValue),
              contentLength >= 0,
              contentLength <= 48 * 1_024
        else { return .rejected(400) }

        let bodyStart = separatorRange.upperBound
        let available = data.count - bodyStart
        guard available >= contentLength else {
            return isComplete ? .rejected(400) : .incomplete
        }
        guard available == contentLength else { return .rejected(400) }
        return .accepted(Data(data[bodyStart..<data.endIndex]))
    }
}
