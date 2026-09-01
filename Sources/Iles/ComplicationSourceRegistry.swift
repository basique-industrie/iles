import Domain
import Foundation
import Infrastructure
import Observation

/// One registry for built-in, provider-backed, and extension-backed sources.
@MainActor
@Observable
final class ComplicationSourceRegistry {
    private(set) var sources: [any ComplicationSource]
    @ObservationIgnored private var sourcesByID: [String: any ComplicationSource] = [:]
    @ObservationIgnored private var inFlightRefreshes: [String: InFlightRefresh] = [:]
    private let configurableCatalog: ConfigurableSourceInstanceCatalog
    private let settingsStore: JSONSettingsStore

    init(
        providers: [any AIProvider],
        sessionMonitor: SessionMonitor,
        settingsStore: JSONSettingsStore = .shared
    ) {
        self.settingsStore = settingsStore
        configurableCatalog = ConfigurableSourceInstanceCatalog(store: settingsStore)
        let calendarStore = CalendarDataStore()
        sources = providers.map { ProviderComplicationSource(provider: $0) }
        sources.append(BatteryComplicationSource())
        sources.append(MacSystemComplicationSource())
        sources.append(ClockComplicationSource(store: settingsStore))
        sources.append(FocusComplicationSource(store: settingsStore))
        sources.append(GitComplicationSource(store: settingsStore))
        sources.append(GitHubComplicationSource(store: settingsStore))
        sources.append(CalendarComplicationSource(dataStore: calendarStore))
        sources.append(ReminderComplicationSource(dataStore: calendarStore))
        sources.append(ServiceMonitorComplicationSource(store: settingsStore))
        sources.append(SessionComplicationSource(monitor: sessionMonitor))
        sources.append(contentsOf: configurableCatalog.records().map {
            Self.makeConfigurableSource(record: $0, store: settingsStore)
        })
        sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
    }

    var descriptors: [ComplicationSourceDescriptor] {
        sources.map(\.descriptor).sorted {
            if $0.kind == $1.kind { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }

    func source(id: String) -> (any ComplicationSource)? {
        sourcesByID[id]
    }

    func register(provider: any AIProvider) {
        guard source(id: provider.id) == nil else { return }
        let source = ProviderComplicationSource(provider: provider)
        sources.append(source)
        sourcesByID[source.id] = source
    }

    @discardableResult
    func addSource(kind: ConfigurableSourceKind) -> String {
        let record = configurableCatalog.add(kind: kind)
        let source = Self.makeConfigurableSource(record: record, store: settingsStore)
        sources.append(source)
        sourcesByID[source.id] = source
        return record.id
    }

    @discardableResult
    func removeSource(id: String) -> Bool {
        guard let source = sourcesByID[id],
              let index = sources.firstIndex(where: { $0.id == id }),
              source.descriptor.id != source.descriptor.sourceKindID,
              configurableCatalog.remove(id: id)
        else { return false }
        if let git = source as? GitComplicationSource { git.clearRepository() }
        if let github = source as? GitHubComplicationSource { github.clearRepository() }
        if let endpoint = source as? ServiceMonitorComplicationSource { endpoint.clearEndpoint() }
        sources.remove(at: index)
        sourcesByID[id] = nil
        return true
    }

    func snapshot(sourceID: String) -> SourceSnapshot? {
        source(id: sourceID)?.currentSnapshot
    }

    func descriptor(sourceID: String) -> ComplicationSourceDescriptor? {
        source(id: sourceID)?.descriptor
    }

    func recipe(id: String, sourceID: String) -> ComplicationRecipe? {
        descriptor(sourceID: sourceID)?.complications.first { $0.id == id }
    }

    /// Refreshes each referenced source at most once, even if several islands or
    /// complication instances reference it.
    func refresh(sourceIDs: some Sequence<String>, kind: RefreshKind) async -> [String: SourceSnapshot] {
        var seen = Set<String>()
        let unique = sourceIDs.filter { seen.insert($0).inserted }
        return await withTaskGroup(of: (String, SourceSnapshot).self) { group in
            for id in unique {
                guard let source = source(id: id) else { continue }
                group.addTask {
                    let snapshot = await self.refreshSingleFlight(source: source, kind: kind)
                    return (id, snapshot)
                }
            }
            var snapshots: [String: SourceSnapshot] = [:]
            for await (id, snapshot) in group { snapshots[id] = snapshot }
            return snapshots
        }
    }

    func cancelRefreshes() {
        for refresh in inFlightRefreshes.values { refresh.task.cancel() }
        inFlightRefreshes.removeAll()
    }

    private func refreshSingleFlight(
        source: any ComplicationSource,
        kind: RefreshKind
    ) async -> SourceSnapshot {
        if let existing = inFlightRefreshes[source.id] {
            return await existing.task.value
        }

        let token = UUID()
        let task = Task { await source.refresh(kind) }
        inFlightRefreshes[source.id] = InFlightRefresh(token: token, task: task)
        let snapshot = await task.value
        if inFlightRefreshes[source.id]?.token == token {
            inFlightRefreshes[source.id] = nil
        }
        return snapshot
    }

    private struct InFlightRefresh {
        let token: UUID
        let task: Task<SourceSnapshot, Never>
    }

    private static func makeConfigurableSource(
        record: ConfigurableSourceInstanceRecord,
        store: JSONSettingsStore
    ) -> any ComplicationSource {
        switch record.kind {
        case .gitRepository:
            GitComplicationSource(
                sourceID: record.id,
                placeholderName: record.placeholderName,
                store: store
            )
        case .githubRepository:
            GitHubComplicationSource(
                sourceID: record.id,
                placeholderName: record.placeholderName,
                store: store
            )
        case .healthEndpoint:
            ServiceMonitorComplicationSource(
                sourceID: record.id,
                placeholderName: record.placeholderName,
                store: store
            )
        }
    }
}
