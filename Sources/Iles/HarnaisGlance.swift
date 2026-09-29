import Domain

/// Maps Harnais aggregator windows onto Claude, Codex, and Cursor glances.
///
/// Also resolves brands for non-Harnais sources so island marks, accents,
/// and hover titles share one lookup.
enum HarnaisGlance {
    static func applies(to sourceID: String) -> Bool {
        sourceID == ProviderIdentity.harnais.rawValue
    }

    static func resolvedBrand(
        sourceID: String,
        metricIDs: [String] = [],
        descriptor: ComplicationSourceDescriptor? = nil
    ) -> ProviderBrand? {
        if applies(to: sourceID) {
            for metricID in metricIDs {
                let name = descriptor?.metrics.first { $0.id == metricID }?.name
                if let identity = ProviderIdentity.mappedFromHarnais(
                    providerId: sourceID,
                    group: name,
                    label: metricID
                ) {
                    return ProviderBrand(rawValue: identity.rawValue)
                }
            }
            return .harnais
        }
        return ProviderBrand(rawValue: sourceID)
    }

    /// Compact list titles repeat an account only once when every value belongs to it.
    static func metricSummary(
        sourceID: String,
        metricIDs: [String],
        descriptor: ComplicationSourceDescriptor?
    ) -> String {
        let names = metricIDs.map {
            descriptor?.metricName(for: $0) ?? ComplicationMetricDescriptor.fallbackName(for: $0)
        }
        guard let account = accountLabel(sourceID: sourceID, metricIDs: metricIDs, descriptor: descriptor),
              let brand = resolvedBrand(sourceID: sourceID, metricIDs: metricIDs, descriptor: descriptor),
              metricIDs.allSatisfy({ resolvedBrand(sourceID: sourceID, metricIDs: [$0], descriptor: descriptor) == brand })
        else { return names.joined(separator: " + ") }
        let windows = zip(metricIDs, names).map {
            rowLabel(sourceID: sourceID, metricID: $0, metricName: $1)
        }.joined(separator: " + ")
        return "\(brand.title) · \(account) · \(windows)"
    }

    static func rowLabel(sourceID: String, metricID: String, metricName: String) -> String {
        applies(to: sourceID) ? windowCaption(metricID: metricID, metricName: metricName) : metricName
    }

    static func windowCaption(metricID: String, metricName: String) -> String {
        let safeName = UsageQuota.privacySafeTitle(metricName) ?? ""
        let parts = safeName.split(separator: "·").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let token = parts.last ?? safeName
        if let kind = QuotaWindowKind.inferred(from: token) ?? QuotaWindowKind.inferred(from: metricID) {
            return kind.caption
        }
        return token.isEmpty ? "Usage" : token.prefix(1).uppercased() + String(token.dropFirst())
    }

    /// Account aliases belong to the current catalog. Persisted metric keys can
    /// contain obsolete aliases, so they are never used as display names.
    static func accountLabel(
        sourceID: String,
        metricIDs: [String],
        descriptor: ComplicationSourceDescriptor?
    ) -> String? {
        guard applies(to: sourceID), let descriptor else { return nil }
        let labels = metricIDs.compactMap { metricID -> String? in
            guard let metric = descriptor.metrics.first(where: { $0.id == metricID }),
                  let safe = UsageQuota.privacySafeTitle(metric.name)
            else { return nil }
            var parts = safe.split(separator: "·").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            guard let window = parts.last, QuotaWindowKind.parse(window) != nil else { return nil }
            parts.removeLast()
            let brand = resolvedBrand(sourceID: sourceID, metricIDs: [metricID], descriptor: descriptor)
            if let first = parts.first, first.caseInsensitiveCompare(brand?.title ?? "Harnais") == .orderedSame {
                parts.removeFirst()
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        guard labels.count == metricIDs.count, let first = labels.first,
              labels.allSatisfy({ $0.caseInsensitiveCompare(first) == .orderedSame })
        else { return nil }
        return first
    }

    static func slotCaption(
        sourceID: String,
        metricID: String,
        descriptor: ComplicationSourceDescriptor?
    ) -> String {
        let name = UsageQuota.privacySafeTitle(descriptor?.metrics.first { $0.id == metricID }?.name)
        guard applies(to: sourceID) else { return name ?? "Value" }
        let token = name?.split(separator: "·").last.map(String.init) ?? ""
        switch QuotaWindowKind.parse(token) ?? QuotaWindowKind.inferred(from: metricID) {
        case .session: return "Session"
        case .weekly: return "Week"
        case .models: return "Models"
        case .other: return "Other"
        case nil: return "Usage"
        }
    }

    static func detailSubtitle(
        sourceID: String,
        metricIDs: [String],
        metricName: String?,
        descriptor: ComplicationSourceDescriptor?
    ) -> String? {
        guard applies(to: sourceID),
              let metricID = metricIDs.first
        else { return nil }
        let account = accountLabel(sourceID: sourceID, metricIDs: metricIDs, descriptor: descriptor)
        if metricIDs.count > 1 { return account ?? "Usage" }
        let knownName = descriptor?.metrics.first { $0.id == metricID }?.name ?? ""
        let window = windowCaption(metricID: metricID, metricName: knownName)
        if let account {
            return "\(account) · \(window)"
        }
        return window
    }
}
