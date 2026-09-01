import Domain
import Foundation
import Infrastructure

@MainActor
final class ProviderComplicationSource: ComplicationSource {
    let provider: any AIProvider
    var id: String { provider.id }
    private var cachedDescriptor: ComplicationSourceDescriptor?
    private var cachedDescriptorSnapshotDate: Date?

    init(provider: any AIProvider) {
        self.provider = provider
    }

    var descriptor: ComplicationSourceDescriptor {
        // Reading the observable snapshot keeps SwiftUI tracking intact while
        // avoiding a full metric/catalog rebuild on every view read.
        let snapshot = provider.snapshot
        if let cachedDescriptor,
           cachedDescriptorSnapshotDate == snapshot?.capturedAt {
            return cachedDescriptor
        }
        let dashboardURL = provider.dashboardURL
        let brand = ProviderBrand(rawValue: provider.id)
        let title = brand?.title ?? provider.name
        var metrics: [ComplicationMetricDescriptor] = []
        func appendMetric(_ metric: ComplicationMetricDescriptor) {
            guard !metrics.contains(where: { $0.id == metric.id }) else { return }
            metrics.append(metric)
        }
        if let extensionProvider = provider as? ExtensionProvider {
            metrics.append(contentsOf: extensionProvider.manifest.metrics.map {
                ComplicationMetricDescriptor(
                    id: $0.id,
                    name: $0.name,
                    kind: $0.kind,
                    unit: $0.unit,
                    policy: $0.policy
                )
            })
        }
        let quotas = snapshot?.quotas ?? []
        let boundedQuotas = quotas.filter { !$0.isDollarBased }
        if snapshot?.sessionQuota != nil {
            appendMetric(ComplicationMetricDescriptor(id: "quota.session", name: "Current session", kind: .gauge, symbol: "timer", unit: "%", policy: usagePolicy))
        }
        if snapshot?.weeklyQuota != nil {
            appendMetric(ComplicationMetricDescriptor(id: "quota.weekly", name: "Weekly", kind: .gauge, symbol: "calendar", unit: "%", policy: usagePolicy))
        }
        if !boundedQuotas.isEmpty {
            appendMetric(ComplicationMetricDescriptor(id: "status.overall", name: "Overall status", kind: .status, symbol: "checkmark.shield"))
        }
        if snapshot?.quotas.contains(where: { $0.resetsAt != nil }) == true {
            metrics.append(ComplicationMetricDescriptor(
                id: "reset.next",
                name: "Next quota reset",
                kind: .date,
                symbol: "arrow.clockwise.circle",
                policy: ComplicationMetricPolicy(
                    format: .date,
                    privacy: .personal,
                    refreshClass: .periodicNetwork,
                    staleAfter: 900
                )
            ))
        }
        if let primary = ProviderQuotaPolicy.primaryQuota(providerId: provider.id, in: snapshot),
           primary.burnRate != nil,
           Self.hasReliableWindowDuration(primary) {
            metrics.append(ComplicationMetricDescriptor(
                id: "pace.primary",
                name: "Primary burn pace",
                kind: .value,
                symbol: "speedometer",
                unit: "×",
                policy: ComplicationMetricPolicy(
                    format: .rate,
                    direction: .lowerIsBetter,
                    thresholds: ComplicationThreshold(warning: 1.2, critical: 1.6),
                    privacy: .personal,
                    refreshClass: .periodicNetwork,
                    staleAfter: 900,
                    keepsHistory: true
                )
            ))
        }
        if snapshot?.costUsage != nil {
            metrics.append(ComplicationMetricDescriptor(id: "cost.total", name: "Total cost", kind: .value, symbol: "dollarsign.circle", unit: "USD"))
            if snapshot?.costUsage?.budget != nil {
                metrics.append(contentsOf: [
                    ComplicationMetricDescriptor(id: "cost.budget.used", name: "Budget used", kind: .gauge, symbol: "chart.pie", unit: "%", policy: usagePolicy),
                    ComplicationMetricDescriptor(id: "cost.budget.remaining", name: "Budget remaining", kind: .value, symbol: "banknote", unit: "USD"),
                ])
            }
        }
        if brand == .claude || brand == .mistral || snapshot?.dailyUsageReport != nil {
            metrics.append(contentsOf: Self.dailyUsageMetrics.filter { dailyMetric in
                !metrics.contains(where: { $0.id == dailyMetric.id })
            })
        }
        for quota in snapshot?.quotas ?? [] {
            if quota.quotaType == .session || quota.quotaType == .weekly { continue }
            if quota.isDollarBased {
                let id = Self.balanceMetricID(for: quota)
                guard !metrics.contains(where: { $0.id == id }) else { continue }
                metrics.append(
                    ComplicationMetricDescriptor(
                        id: id,
                        name: "\(quota.quotaType.title(style: .row, providerId: provider.id)) balance",
                        kind: .value,
                        symbol: "banknote",
                        unit: quota.currency,
                        policy: ComplicationMetricPolicy(
                            format: .currency,
                            direction: .higherIsBetter,
                            privacy: .personal,
                            refreshClass: .periodicNetwork,
                            staleAfter: 900
                        )
                    )
                )
                continue
            }
            let id = "quota.key.\(quota.quotaType.quotaKey)"
            guard !metrics.contains(where: { $0.id == id }) else { continue }
            metrics.append(
                ComplicationMetricDescriptor(
                    id: id,
                    name: quota.quotaType.title(style: .row, providerId: provider.id),
                    kind: .gauge,
                    symbol: "gauge.with.dots.needle.50percent",
                    unit: "%",
                    policy: usagePolicy
                )
            )
        }
        for (index, metric) in (snapshot?.extensionMetrics ?? []).enumerated() {
            let id = metric.id ?? "extension.\(index)"
            if let extensionProvider = provider as? ExtensionProvider,
               !extensionProvider.manifest.metrics.contains(where: { $0.id == id }) {
                continue
            }
            guard !metrics.contains(where: { $0.id == id }) else { continue }
            metrics.append(
                ComplicationMetricDescriptor(
                    id: id,
                    name: metric.label,
                    kind: metric.kind ?? (metric.progress == nil ? .value : .gauge),
                    unit: metric.unit.isEmpty ? nil : metric.unit
                )
            )
        }
        let declaredFamilies: [ComplicationFamily]
        if let extensionProvider = provider as? ExtensionProvider,
           !extensionProvider.manifest.complications.isEmpty {
            declaredFamilies = extensionProvider.manifest.complications.flatMap(\.compatibleFamilies).reduce(into: []) {
                if !$0.contains($1) { $0.append($1) }
            }
        } else {
            var families: [ComplicationFamily] = []
            let gaugeCount = metrics.count { $0.kind == .gauge }
            if gaugeCount > 0 { families.append(.ring) }
            if gaugeCount > 1 { families.append(.dualRing) }
            if !metrics.isEmpty { families.append(.value) }
            if metrics.contains(where: { $0.kind == .status }) { families.append(.status) }
            if metrics.contains(where: { $0.kind == .status || $0.kind == .duration }) { families.append(.activity) }
            if metrics.contains(where: { $0.kind == .date || $0.kind == .duration }) {
                families.append(.countdown)
            }
            if metrics.contains(where: {
                ComplicationRecipeValidator.family(.trend, supports: $0.kind, metric: $0)
            }) {
                families.append(.trend)
            }
            if metrics.count >= 2 { families.append(.summary) }
            if gaugeCount >= 3 { families.append(.cluster) }
            declaredFamilies = families
        }
        let complicationPresets: [ComplicationDescriptor]
        if let extensionProvider = provider as? ExtensionProvider {
            complicationPresets = extensionProvider.manifest.complications.map {
                $0.recipe(sourceID: provider.id, category: extensionProvider.manifest.category)
            }
        } else {
            complicationPresets = FirstPartyComplicationCatalog.providerRecipes(
                sourceID: provider.id,
                metrics: metrics
            )
        }
        let descriptor = ComplicationSourceDescriptor(
            id: provider.id,
            name: title,
            kind: provider is ExtensionProvider ? .extensionSource : .usage,
            symbol: brand?.symbol ?? "gauge.with.dots.needle.50percent",
            metrics: metrics,
            supportedFamilies: declaredFamilies,
            complications: complicationPresets,
            capabilities: providerCapabilities(metrics: metrics),
            actionURL: dashboardURL
        )
        cachedDescriptor = descriptor
        cachedDescriptorSnapshotDate = snapshot?.capturedAt
        return descriptor
    }

    var currentSnapshot: SourceSnapshot {
        makeSnapshot()
    }

    func refresh(_ kind: RefreshKind) async -> SourceSnapshot {
        do {
            _ = try await provider.refresh(kind)
        } catch {
            AppLog.providers.error("\(provider.id): \(error.localizedDescription)")
        }
        cachedDescriptor = nil
        cachedDescriptorSnapshotDate = nil
        return makeSnapshot()
    }

    private func makeSnapshot() -> SourceSnapshot {
        if let extensionProvider = provider as? ExtensionProvider,
           extensionProvider.requiresTrust,
           !extensionProvider.isTrusted {
            return SourceSnapshot(
                sourceID: provider.id,
                values: [:],
                errorDescription: "Review and trust this local extension before its scripts can run.",
                quality: .unavailable,
                availability: ComplicationAvailability(
                    state: .setupRequired,
                    message: "Extension trust is required.",
                    recoveryAction: .configure
                )
            )
        }
        guard let snapshot = provider.snapshot else {
            let error = provider.lastError?.localizedDescription
            return SourceSnapshot(
                sourceID: provider.id,
                values: [:],
                errorDescription: error,
                quality: error == nil ? .cached : .unavailable,
                availability: error == nil
                    ? .available
                    : ComplicationAvailability(
                        state: .setupRequired,
                        message: error,
                        recoveryAction: .configure
                    )
            )
        }
        var values: [String: ComplicationValue] = [:]
        if let quota = ProviderQuotaPolicy.primaryQuota(providerId: provider.id, in: snapshot),
           !quota.isDollarBased,
           let burnRate = quota.burnRate,
           Self.hasReliableWindowDuration(quota) {
            values["pace.primary"] = .value(String(format: "%.1f", burnRate), unit: "×")
        }
        if let quota = snapshot.sessionQuota {
            values["quota.session"] = value(for: quota)
        }
        if let quota = snapshot.weeklyQuota {
            values["quota.weekly"] = value(for: quota)
        }
        let boundedQuotas = snapshot.quotas.filter { !$0.isDollarBased }
        if let next = snapshot.quotas
            .compactMap({ quota -> (UsageQuota, Date)? in
                guard let reset = quota.resetsAt, reset > Date() else { return nil }
                return (quota, reset)
            })
            .min(by: { $0.1 < $1.1 }) {
            let title = next.0.compactTitle
                ?? next.0.quotaType.title(style: .compact, providerId: provider.id)
            values["reset.next"] = .date(
                next.1,
                label: "\(title) · \(CompactDurationFormatter.hoursMinutes(next.1.timeIntervalSinceNow))"
            )
        }
        if let overallStatus = boundedQuotas.map(\.status).max() {
            let constrained = boundedQuotas.first { $0.status == overallStatus }
            let label = constrained.map {
                "\($0.quotaType.title(style: .compact, providerId: provider.id)) \(statusLabel(overallStatus))"
            } ?? statusLabel(overallStatus)
            values["status.overall"] = .status(label: label, level: statusLevel(overallStatus))
        }
        for quota in snapshot.quotas {
            if quota.isDollarBased {
                if let balance = quota.formattedDollarRemaining {
                    values[Self.balanceMetricID(for: quota)] = .value(balance, unit: nil)
                }
                continue
            }
            if quota.quotaType == .session || quota.quotaType == .weekly { continue }
            values["quota.key.\(quota.quotaType.quotaKey)"] = value(for: quota)
        }
        if let cost = snapshot.costUsage {
            values["cost.total"] = .value(cost.formattedCost, unit: nil)
            if let percent = cost.budgetPercentUsedFromBuiltIn {
                values["cost.budget.used"] = .gauge(
                    value: percent,
                    range: 0...100,
                    label: "\(Int(percent.rounded()))%"
                )
            }
            if let remaining = cost.budgetRemaining {
                values["cost.budget.remaining"] = .value(Self.currencyLabel(remaining), unit: nil)
            }
        }
        if let daily = snapshot.dailyUsageReport {
            let cost = NSDecimalNumber(decimal: daily.today.totalCost).doubleValue
            values["daily.cost"] = .value(String(format: "%.2f", cost), unit: "USD")
            values["daily.tokens"] = .value(daily.today.formattedTokens, unit: nil)
            values["daily.sessions"] = .value("\(daily.today.sessionCount)", unit: nil)
            values["daily.working-time"] = .duration(
                daily.today.workingTime,
                label: daily.today.formattedWorkingTime
            )
        }
        for (index, metric) in (snapshot.extensionMetrics ?? []).enumerated() {
            let id = metric.id ?? "extension.\(index)"
            let declaredMetric = (provider as? ExtensionProvider)?.manifest.metrics.first { $0.id == id }
            if provider is ExtensionProvider, declaredMetric == nil { continue }
            switch declaredMetric?.kind ?? metric.kind ?? (metric.progress == nil ? .value : .gauge) {
            case .gauge:
                let lower = metric.rangeLower ?? 0
                let upper = metric.rangeUpper ?? 100
                let raw = metric.numericValue
                    ?? metric.progress.map { progress in
                        progress <= 1 ? lower + progress * (upper - lower) : progress
                    }
                    ?? Double(metric.value)
                guard let raw else { continue }
                values[id] = .gauge(
                    value: raw,
                    range: lower...max(upper, lower + 1),
                    label: metric.value + (metric.unit.isEmpty ? "" : " \(metric.unit)")
                )
            case .status:
                values[id] = .status(label: metric.value, level: metric.statusLevel ?? .inactive)
            case .duration:
                guard let duration = metric.duration ?? metric.numericValue ?? Double(metric.value) else { continue }
                values[id] = .duration(duration, label: metric.value)
            case .date:
                guard let date = metric.date else { continue }
                values[id] = .date(date, label: metric.value)
            case .value:
                values[id] = .value(metric.value, unit: metric.unit.isEmpty ? nil : metric.unit)
            }
        }
        let errorDescription = provider.lastError?.localizedDescription
        return SourceSnapshot(
            sourceID: provider.id,
            capturedAt: snapshot.capturedAt,
            values: values,
            errorDescription: errorDescription,
            quality: errorDescription == nil ? .live : .stale,
            availability: errorDescription == nil
                ? .available
                : ComplicationAvailability(
                    state: .temporarilyUnavailable,
                    message: "Showing the last successful provider snapshot.",
                    recoveryAction: .retry
                )
        )
    }

    private func value(for quota: UsageQuota) -> ComplicationValue {
        return .gauge(
            value: quota.percentUsed,
            range: 0...100,
            label: "\(Int(quota.percentUsed.rounded()))%"
        )
    }

    private var usagePolicy: ComplicationMetricPolicy {
        ComplicationMetricPolicy(
            format: .percentage,
            direction: .lowerIsBetter,
            range: 0...100,
            thresholds: ComplicationThreshold(warning: 75, critical: 90),
            privacy: .personal,
            refreshClass: .periodicNetwork,
            staleAfter: 900,
            keepsHistory: true
        )
    }

    private static let dailyUsageMetrics: [ComplicationMetricDescriptor] = [
        ComplicationMetricDescriptor(
            id: "daily.cost",
            name: "Cost today",
            kind: .value,
            symbol: "dollarsign.circle",
            unit: "USD",
            policy: ComplicationMetricPolicy(
                format: .currency,
                direction: .lowerIsBetter,
                privacy: .personal,
                refreshClass: .periodicLocal,
                staleAfter: 900,
                keepsHistory: true
            )
        ),
        ComplicationMetricDescriptor(
            id: "daily.tokens",
            name: "Tokens today",
            kind: .value,
            symbol: "number.circle",
            policy: ComplicationMetricPolicy(
                format: .count,
                direction: .lowerIsBetter,
                privacy: .personal,
                refreshClass: .periodicLocal,
                staleAfter: 900,
                keepsHistory: true
            )
        ),
        ComplicationMetricDescriptor(
            id: "daily.sessions",
            name: "Sessions today",
            kind: .value,
            symbol: "rectangle.stack",
            policy: ComplicationMetricPolicy(
                format: .count,
                privacy: .personal,
                refreshClass: .periodicLocal,
                staleAfter: 900,
                keepsHistory: true
            )
        ),
        ComplicationMetricDescriptor(
            id: "daily.working-time",
            name: "Working time today",
            kind: .duration,
            symbol: "timer",
            policy: ComplicationMetricPolicy(
                format: .duration,
                privacy: .personal,
                refreshClass: .periodicLocal,
                staleAfter: 900,
                keepsHistory: true
            )
        ),
    ]

    private static func balanceMetricID(for quota: UsageQuota) -> String {
        "balance.key.\(quota.quotaType.quotaKey)"
    }

    private static func hasReliableWindowDuration(_ quota: UsageQuota) -> Bool {
        if quota.windowDuration != nil { return true }
        switch quota.quotaType {
        case .session, .weekly:
            return true
        case .timeLimit(let name):
            return name.localizedCaseInsensitiveCompare(QuotaWindowName.monthly) == .orderedSame
        case .modelSpecific:
            return false
        }
    }

    private func providerCapabilities(metrics: [ComplicationMetricDescriptor]) -> [ComplicationCapability] {
        var capabilities: [ComplicationCapability] = []
        if metrics.contains(where: { $0.kind == .status }) { capabilities.append(.status) }
        if metrics.contains(where: { $0.id.hasPrefix("quota.") }) { capabilities.append(.quota) }
        if metrics.contains(where: { $0.id.hasPrefix("cost.") }) { capabilities.append(.cost) }
        if metrics.contains(where: { $0.id.hasPrefix("reset.") }) { capabilities.append(.resetDate) }
        if metrics.contains(where: { $0.policy.keepsHistory }) { capabilities.append(.shortHistory) }
        return capabilities
    }

    private static func currencyLabel(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private func statusLabel(_ status: QuotaStatus) -> String {
        switch status {
        case .healthy: "Healthy"
        case .warning: "Low"
        case .critical: "Critical"
        case .depleted: "Empty"
        }
    }

    private func statusLevel(_ status: QuotaStatus) -> StatusLevel {
        switch status {
        case .healthy: .healthy
        case .warning: .warning
        case .critical, .depleted: .critical
        }
    }
}
