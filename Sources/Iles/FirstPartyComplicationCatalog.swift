import Domain
import Foundation

enum FirstPartyComplicationCatalog {
    // Recipe packs and the dynamic provider factory live in focused extensions.

    static func stableIDComponent(_ value: String) -> String {
        let normalized = value.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let component = String(normalized).split(separator: "-").joined(separator: "-")
        return component.isEmpty ? "custom" : component
    }

    static func valueRecipe(
        id: String,
        name: String,
        summary: String,
        question: String,
        sourceID: String,
        metricID: String,
        tags: [String],
        rank: Int,
        capabilities: [ComplicationCapability],
        fixtureValue: ComplicationValue = .value("12.40", unit: "USD")
    ) -> ComplicationRecipe {
        ComplicationRecipe(
            id: id,
            name: name,
            summary: summary,
            question: question,
            sourceID: sourceID,
            category: .ai,
            tags: tags,
            family: .value,
            compatibleFamilies: [.value],
            slots: [ComplicationMetricSlot(metricID: metricID)],
            labelStyle: .value,
            requiredCapabilities: capabilities,
            rank: rank,
            fixtures: [
                ComplicationFixture(
                    name: "Typical",
                    state: .normal,
                    values: [metricID: fixtureValue]
                ),
            ]
        )
    }

    static func recipe(
        id: String,
        name: String,
        summary: String,
        question: String,
        sourceID: String,
        category: ComplicationCategory,
        tags: [String],
        family: ComplicationFamily,
        metricIDs: [String],
        transforms: [[ComplicationTransform]] = [],
        labelStyle: ComplicationLabelStyle = .percentage,
        rank: Int,
        featured: Bool = false
    ) -> ComplicationRecipe {
        let slots = metricIDs.enumerated().map { index, metricID in
            ComplicationMetricSlot(
                metricID: metricID,
                transforms: transforms.indices.contains(index) ? transforms[index] : []
            )
        }
        let values = Dictionary(uniqueKeysWithValues: metricIDs.map { metricID in
            (metricID, fixtureValue(metricID: metricID, family: family))
        })
        return ComplicationRecipe(
            id: id,
            name: name,
            summary: summary,
            question: question,
            sourceID: sourceID,
            category: category,
            tags: tags,
            family: family,
            compatibleFamilies: compatibleFamilies(for: family),
            slots: slots,
            labelStyle: labelStyle,
            requiredCapabilities: capabilities(for: category, sourceID: sourceID),
            rank: rank,
            isFeatured: featured,
            isNew: family == .countdown || family == .trend || family == .summary || family == .cluster,
            fixtures: [ComplicationFixture(name: "Typical", state: .normal, values: values)]
        )
    }

    static func fixtureValue(metricID: String, family: ComplicationFamily) -> ComplicationValue {
        if metricID == "lastCheck" {
            return .date(Date().addingTimeInterval(-7_200), label: "2h")
        }
        if metricID == "latency" {
            return .gauge(value: 180, range: 0...3_000, label: "180 ms")
        }
        let statusMetricIDs: Set<String> = [
            "state", "power", "health", "status", "network", "thermal", "lowPower",
            "sync", "ci", "deployment", "currentState",
        ]
        if statusMetricIDs.contains(metricID) {
            return .status(label: "Healthy", level: .healthy)
        }
        let dateMetricIDs: Set<String> = [
            "time", "endOfDay", "nextStart", "nextDue", "lastCheck",
        ]
        if dateMetricIDs.contains(metricID) {
            return .date(Date(timeIntervalSince1970: 7_200), label: "2h")
        }
        let durationMetricIDs: Set<String> = [
            "remaining", "elapsed", "duration", "uptime", "lastCommit", "lastRun", "nextDuration",
        ]
        if durationMetricIDs.contains(metricID) {
            return .duration(1_500, label: "25m")
        }
        let gaugeMetricIDs: Set<String> = [
            "dayProgress", "workdayProgress", "weekProgress", "monthProgress", "yearProgress",
            "level", "cpu", "memory", "storage", "storageAvailable", "progress", "dailyGoal", "meetingProgress",
            "latency", "availability",
        ]
        if gaugeMetricIDs.contains(metricID) {
            return .gauge(value: 42, range: 0...100, label: "42%")
        }
        return .value("42", unit: nil)
    }

    static func compatibleFamilies(for family: ComplicationFamily) -> [ComplicationFamily] {
        switch family {
        case .ring: [.ring, .value]
        case .dualRing: [.dualRing, .summary]
        case .value: [.value]
        case .status: [.status, .activity]
        case .activity: [.activity, .status]
        case .countdown: [.countdown, .value]
        case .trend: [.trend, .value]
        case .summary: [.summary]
        case .cluster: [.cluster]
        }
    }

    static func capabilities(
        for category: ComplicationCategory,
        sourceID: String
    ) -> [ComplicationCapability] {
        switch category {
        case .ai: [.quota]
        case .sessions: [.sessionActivity]
        case .time where sourceID == "calendar.events": [.calendarRead]
        case .time where sourceID == "calendar.reminders": [.remindersRead]
        case .time: []
        case .mac: [.systemHealth]
        case .focus: [.shortHistory]
        case .developer: [.repositoryRead]
        case .services: [.networkAccess, .serviceHealth]
        case .extensions: []
        }
    }
}
