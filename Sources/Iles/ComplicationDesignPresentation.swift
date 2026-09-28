import Domain
import Foundation

extension ComplicationSourceKind {
    var displayName: String {
        switch self {
        case .usage: "Usage Provider"
        case .system: "System"
        case .time: "Time"
        case .session: "Session"
        case .extensionSource: "Extension"
        }
    }
}

extension ComplicationSourceDescriptor {
    var settingsDomainName: String {
        if id.hasPrefix("developer.") { return "Developer" }
        if id.hasPrefix("services.") { return "Services" }
        if id.hasPrefix("productivity.") { return "Focus" }
        if id.hasPrefix("calendar.") { return "Time & Calendar" }
        if kind == .usage { return "AI Usage" }
        if id.hasPrefix("system.mac") { return "Mac Health" }
        return kind.displayName
    }

    var gallerySourceSubtitle: String {
        configurableKind.map { "\(settingsDomainName) · \($0.title)" } ?? settingsDomainName
    }
}

extension ComplicationCategory {
    var displayName: String {
        switch self {
        case .ai: "AI Usage"
        case .sessions: "Coding Sessions"
        case .time: "Time & Calendar"
        case .mac: "Mac Health"
        case .focus: "Focus"
        case .developer: "Developer"
        case .services: "Services"
        case .extensions: "Extensions"
        }
    }

    var gallerySymbol: String {
        switch self {
        case .ai: "sparkles"
        case .sessions: "terminal"
        case .time: "clock"
        case .mac: "macbook"
        case .focus: "scope"
        case .developer: "hammer"
        case .services: "waveform.path.ecg"
        case .extensions: "puzzlepiece.extension"
        }
    }
}

extension ComplicationAction {
    var displayName: String {
        switch self {
        case .showDetails: "Show Details"
        case .refresh: "Refresh Source"
        case .openDashboard: "Open Dashboard"
        case .none: "Do Nothing"
        }
    }

    var inspectorSymbol: String {
        switch self {
        case .showDetails: "rectangle.on.rectangle"
        case .refresh: "arrow.clockwise"
        case .openDashboard: "globe"
        case .none: "hand.raised.slash"
        }
    }

    var explanation: String {
        switch self {
        case .showDetails: "Opens the focused detail card without leaving the island."
        case .refresh: "Refreshes this source immediately when the complication is clicked."
        case .openDashboard: "Opens the provider dashboard in your default browser."
        case .none: "Keeps the complication glance-only with no click behavior."
        }
    }
}

extension ComplicationMetricKind {
    var inspectorSymbol: String {
        switch self {
        case .gauge: "gauge.with.dots.needle.33percent"
        case .value: "number"
        case .status: "circlebadge"
        case .duration: "timer"
        case .date: "clock"
        }
    }
}

extension ComplicationMetricDescriptor {
    func recommendedFamily(for outputKind: ComplicationMetricKind? = nil) -> ComplicationFamily {
        switch outputKind ?? kind {
        case .gauge: .ring
        case .status: .status
        case .date: .countdown
        case .duration:
            id.localizedCaseInsensitiveContains("remaining") ? .countdown : .value
        case .value: .value
        }
    }
}

/// Keeps an existing complication editable while its source is still loading.
/// Provider metric catalogs become richer after the first snapshot, but the UI
/// must never collapse to an empty Style or Data screen in the meantime.
enum ComplicationMetricFallback {
    static func descriptors(
        metricIDs: [String],
        family: ComplicationFamily
    ) -> [ComplicationMetricDescriptor] {
        metricIDs.map { descriptor(metricID: $0, family: family) }
    }

    static func previewValue(
        for metric: ComplicationMetricDescriptor,
        index: Int
    ) -> ComplicationValue {
        switch metric.kind {
        case .gauge:
            let value = [42.0, 63.0, 78.0][min(index, 2)]
            return .gauge(value: value, range: 0...100, label: "\(Int(value))%")
        case .value:
            return .value("42", unit: metric.unit)
        case .status:
            return .status(label: "Ready", level: .healthy)
        case .duration:
            return .duration(1_500, label: "25m")
        case .date:
            return .date(Date().addingTimeInterval(1_800), label: "30m")
        }
    }

    private static func descriptor(
        metricID: String,
        family: ComplicationFamily
    ) -> ComplicationMetricDescriptor {
        let kind = inferredKind(metricID: metricID, family: family)
        let policy: ComplicationMetricPolicy? = switch kind {
        case .gauge:
            ComplicationMetricPolicy(
                format: .percentage,
                direction: metricID.hasPrefix("quota.") ? .lowerIsBetter : .neutral,
                range: 0...100,
                refreshClass: .periodicNetwork,
                keepsHistory: true
            )
        case .value where family == .trend:
            ComplicationMetricPolicy(format: .text, keepsHistory: true)
        default:
            nil
        }
        return ComplicationMetricDescriptor(
            id: metricID,
            name: ComplicationMetricDescriptor.fallbackName(for: metricID),
            kind: kind,
            policy: policy
        )
    }

    private static func inferredKind(
        metricID: String,
        family: ComplicationFamily
    ) -> ComplicationMetricKind {
        let id = metricID.lowercased()
        if id.hasPrefix("quota.") || id.contains("percent") || id.contains("progress") {
            return .gauge
        }
        if id.contains("reset") || id.contains("deadline") || id.contains("date") {
            return .date
        }
        if id.contains("duration") || id.contains("remaining") || id.contains("elapsed")
            || id.contains("working-time") {
            return .duration
        }
        if id.contains("status") || id.contains("state") || id.contains("health") {
            return .status
        }
        return switch family {
        case .ring, .dualRing, .cluster: .gauge
        case .status, .activity: .status
        case .countdown: .duration
        case .value, .trend, .summary: .value
        }
    }
}

extension ComplicationFamily {
    var inspectorSymbol: String {
        switch self {
        case .ring: "circle.dotted.circle"
        case .dualRing: "circle.circle"
        case .value: "number.square"
        case .status: "checkmark.circle"
        case .activity: "waveform.path"
        case .countdown: "timer"
        case .trend: "chart.xyaxis.line"
        case .summary: "list.bullet"
        case .cluster: "circle.circle"
        }
    }

    var designDescription: String {
        switch self {
        case .ring: "One progress metric wrapped around its source."
        case .dualRing: "Two related progress metrics in a nested glance."
        case .value: "One exact number, duration, date, or short label."
        case .status: "A clear healthy, warning, critical, or inactive state."
        case .activity: "A live state with stronger motion and activity emphasis."
        case .countdown: "Time remaining until an event, reset, or deadline."
        case .trend: "Direction and change for a numeric signal over time."
        case .summary: "Two or three related values joined into one compact glance."
        case .cluster: "Three related progress signals in concentric rings."
        }
    }

    func fitDescription(for kind: ComplicationMetricKind) -> String {
        switch self {
        case .ring: "Progress ring"
        case .dualRing: "Two progress signals"
        case .value: kind == .status ? "State label" : "Exact value"
        case .status: "State indicator"
        case .activity: "Live activity state"
        case .countdown: "Time-remaining glance"
        case .trend: "Directional signal"
        case .summary: "Compact multi-value summary"
        case .cluster: "Three progress rings"
        }
    }
}

extension ComplicationMetricFormat {
    var designName: String {
        switch self {
        case .percentage: "Percentage"
        case .count: "Count"
        case .currency: "Currency"
        case .duration: "Duration"
        case .date: "Date or time"
        case .rate: "Rate"
        case .bytes: "Storage value"
        case .text: "Text"
        case .status: "State"
        }
    }
}

extension ComplicationMetricDirection {
    var designName: String? {
        switch self {
        case .higherIsBetter: "Higher is healthier"
        case .lowerIsBetter: "Lower is healthier"
        case .neutral: nil
        }
    }
}

extension ComplicationTransform {
    var designName: String? {
        switch self {
        case .remaining, .inverse: "Remaining"
        case .countdown: "Countdown"
        case .elapsed: "Elapsed"
        case .delta: "Change"
        case .rate: "Rate"
        case .rollingAverage: "Rolling average"
        case .exhaustionForecast: "Forecast"
        case .threshold: "Threshold state"
        case .sum: "Total"
        case .minimum: "Minimum"
        case .maximum: "Maximum"
        case .ratio: "Ratio"
        case .clamp: "Bounded"
        case .used: nil
        }
    }
}
