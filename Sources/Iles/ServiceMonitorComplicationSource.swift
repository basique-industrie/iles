import Domain
import Foundation
import Infrastructure

@MainActor
final class ServiceMonitorComplicationSource: ComplicationSource {
    private let store: JSONSettingsStore
    private let sourceID: String
    private let placeholderName: String
    private let storagePrefix: String
    private(set) var endpoint: URL?
    private var recentResults: [Bool]
    private var consecutiveFailures: Int
    private var cachedSnapshot: SourceSnapshot

    var descriptor: ComplicationSourceDescriptor {
        ComplicationSourceDescriptor(
            id: sourceID,
            sourceKindID: ConfigurableSourceKind.healthEndpoint.sourceKindID,
            allowsMultipleInstances: true,
            name: endpointName,
            kind: .system,
            symbol: "waveform.path.ecg",
            metrics: Self.metrics,
            supportedFamilies: [.ring, .value, .status, .activity, .trend, .summary],
            complications: FirstPartyComplicationCatalog.serviceRecipes.map { $0.bound(to: sourceID) },
            capabilities: [.networkAccess, .serviceHealth, .shortHistory],
            actionURL: endpoint
        )
    }

    init(
        sourceID: String = ConfigurableSourceKind.healthEndpoint.sourceKindID,
        placeholderName: String = ConfigurableSourceKind.healthEndpoint.title,
        store: JSONSettingsStore = .shared
    ) {
        self.store = store
        self.sourceID = sourceID
        self.placeholderName = placeholderName
        storagePrefix = Self.configurationPrefix(sourceID: sourceID)
        endpoint = (store.read(key: "\(storagePrefix).url") as String?).flatMap(URL.init(string:))
        recentResults = store.read(key: "\(storagePrefix).recent") ?? []
        consecutiveFailures = store.read(key: "\(storagePrefix).failures") ?? 0
        cachedSnapshot = Self.setupSnapshot(sourceID: sourceID)
    }

    var endpointText: String { endpoint?.absoluteString ?? "" }
    var currentSnapshot: SourceSnapshot { cachedSnapshot }

    func refresh(_ kind: RefreshKind) async -> SourceSnapshot {
        guard let endpoint else {
            cachedSnapshot = Self.setupSnapshot(sourceID: sourceID)
            return cachedSnapshot
        }
        let result = await Self.check(endpoint)
        recentResults.append(result.isUp)
        recentResults = Array(recentResults.suffix(50))
        consecutiveFailures = result.isUp ? 0 : consecutiveFailures + 1
        persistHealth()
        cachedSnapshot = snapshot(result: result)
        return cachedSnapshot
    }

    @discardableResult
    func setEndpoint(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else { return false }
        endpoint = url
        recentResults = []
        consecutiveFailures = 0
        store.write(value: url.absoluteString, key: "\(storagePrefix).url")
        persistHealth()
        cachedSnapshot = SourceSnapshot(sourceID: descriptor.id, values: [:], quality: .cached)
        return true
    }

    func clearEndpoint() {
        endpoint = nil
        recentResults = []
        consecutiveFailures = 0
        store.write(value: nil, key: "\(storagePrefix).url")
        store.write(value: nil, key: "\(storagePrefix).recent")
        store.write(value: nil, key: "\(storagePrefix).failures")
        cachedSnapshot = Self.setupSnapshot(sourceID: sourceID)
    }

    private func snapshot(result: HealthCheckResult) -> SourceSnapshot {
        let availability = recentResults.isEmpty
            ? 0
            : Double(recentResults.filter { $0 }.count) / Double(recentResults.count) * 100
        return SourceSnapshot(sourceID: descriptor.id, capturedAt: result.checkedAt, values: [
            "status": .status(label: result.statusText.capitalized, level: result.status),
            "latency": .gauge(
                value: min(Double(result.latencyMs), 3_000),
                range: 0...3_000,
                label: result.formattedLatency
            ),
            "latencyValue": .value(result.formattedLatency, unit: nil),
            "responseCode": .value(result.statusCodeText, unit: nil),
            "availability": .gauge(value: availability, range: 0...100, label: "\(Int(availability.rounded()))%"),
            "lastCheck": .date(result.checkedAt, label: "Now"),
            "failures": .value("\(consecutiveFailures)", unit: nil),
        ])
    }

    private func persistHealth() {
        store.write(value: recentResults, key: "\(storagePrefix).recent")
        store.write(value: consecutiveFailures, key: "\(storagePrefix).failures")
    }

    private static let metrics: [ComplicationMetricDescriptor] = [
        ComplicationMetricDescriptor(id: "status", name: "Service status", kind: .status, symbol: "waveform.path.ecg", policy: ComplicationMetricPolicy(format: .status, refreshClass: .periodicNetwork, staleAfter: 300)),
        ComplicationMetricDescriptor(id: "latency", name: "Latency range", kind: .gauge, symbol: "timer", unit: "ms", policy: ComplicationMetricPolicy(format: .duration, direction: .lowerIsBetter, range: 0...3_000, thresholds: ComplicationThreshold(warning: 1_000, critical: 2_000), refreshClass: .periodicNetwork, staleAfter: 300, keepsHistory: true)),
        ComplicationMetricDescriptor(id: "latencyValue", name: "Latency", kind: .value, symbol: "stopwatch", unit: "ms", policy: ComplicationMetricPolicy(format: .duration, direction: .lowerIsBetter, refreshClass: .periodicNetwork, staleAfter: 300)),
        ComplicationMetricDescriptor(id: "responseCode", name: "Response code", kind: .value, symbol: "curlybraces", policy: ComplicationMetricPolicy(format: .text, refreshClass: .periodicNetwork, staleAfter: 300)),
        ComplicationMetricDescriptor(id: "availability", name: "Recent availability", kind: .gauge, symbol: "chart.line.uptrend.xyaxis", unit: "%", policy: ComplicationMetricPolicy(format: .percentage, direction: .higherIsBetter, range: 0...100, thresholds: ComplicationThreshold(warning: 99, critical: 95), refreshClass: .periodicNetwork, staleAfter: 300, keepsHistory: true)),
        ComplicationMetricDescriptor(id: "lastCheck", name: "Last checked", kind: .date, symbol: "clock", policy: ComplicationMetricPolicy(format: .date, refreshClass: .periodicNetwork, staleAfter: 300)),
        ComplicationMetricDescriptor(id: "failures", name: "Consecutive failures", kind: .value, symbol: "xmark.octagon", policy: ComplicationMetricPolicy(format: .count, direction: .lowerIsBetter, refreshClass: .periodicNetwork, staleAfter: 300)),
    ]

    private nonisolated static func check(_ url: URL) async -> HealthCheckResult {
        let started = ContinuousClock.now
        var code = await responseCode(url: url, method: "HEAD")
        if code == 405 || code == 501 {
            // Some otherwise healthy APIs reject HEAD. Retry with a bounded GET
            // so the health source reports service availability, not method support.
            code = await responseCode(url: url, method: "GET", range: "bytes=0-0")
        }
        let elapsed = started.duration(to: .now)
        let components = elapsed.components
        let milliseconds = Int(components.seconds * 1_000) + Int(components.attoseconds / 1_000_000_000_000_000)
        return HealthCheckResult(url: url, statusCode: code, latencyMs: milliseconds, checkedAt: Date())
    }

    private nonisolated static func responseCode(
        url: URL,
        method: String,
        range: String? = nil
    ) async -> Int {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        do {
            let (_, response) = try await NetworkClients.ephemeral.bytes(for: request)
            return (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return 0
        }
    }

    private nonisolated static func setupSnapshot(sourceID: String) -> SourceSnapshot {
        SourceSnapshot(
            sourceID: sourceID,
            values: [:],
            errorDescription: "Add an HTTP or HTTPS endpoint to enable service complications.",
            quality: .unavailable,
            availability: ComplicationAvailability(
                state: .setupRequired,
                message: "Add a service endpoint.",
                recoveryAction: .configure
            )
        )
    }

    private var endpointName: String {
        guard let endpoint else { return placeholderName }
        let host = endpoint.host ?? placeholderName
        let path = endpoint.path == "/" ? "" : endpoint.path
        return path.isEmpty ? host : "\(host)\(path)"
    }

    private static func configurationPrefix(sourceID: String) -> String {
        if sourceID == ConfigurableSourceKind.healthEndpoint.sourceKindID {
            return "services.endpoint"
        }
        return "sourceInstances.\(sourceID.replacingOccurrences(of: ".", with: "_"))"
    }
}
