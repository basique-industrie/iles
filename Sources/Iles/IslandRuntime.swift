import AppKit
import Domain
import Foundation
import Infrastructure
import IslandGeometry
import Observation

struct ComplicationSelection: Equatable, Sendable {
    let islandID: UUID
    let complicationID: UUID
}

enum ComplicationTrendDirection: Equatable, Sendable {
    case up
    case down
    case flat
    case unknown
}

/// Keeps inexpensive live metrics responsive without promoting every local
/// source to the same high-frequency cadence.
struct LocalSourceRefreshSchedule: Equatable, Sendable {
    let fastSourceIDs: Set<String>
    let slowSourceIDs: Set<String>
    let tickInterval: TimeInterval
    private(set) var elapsedSinceSlowRefresh: TimeInterval = 0

    init(
        fastSourceIDs: Set<String>,
        slowSourceIDs: Set<String>,
        tracksActiveSession: Bool
    ) {
        self.fastSourceIDs = fastSourceIDs
        self.slowSourceIDs = slowSourceIDs
        tickInterval = tracksActiveSession ? 1 : (fastSourceIDs.isEmpty ? 30 : 2)
    }

    mutating func sourceIDsForNextTick() -> Set<String> {
        var sourceIDs = fastSourceIDs
        elapsedSinceSlowRefresh += tickInterval
        if elapsedSinceSlowRefresh >= 30 {
            sourceIDs.formUnion(slowSourceIDs)
            elapsedSinceSlowRefresh = 0
        }
        return sourceIDs
    }
}

@MainActor
@Observable
private final class SourceSnapshotBox {
    var value: SourceSnapshot?

    init(_ value: SourceSnapshot? = nil) {
        self.value = value
    }
}

/// Coordinates the configured workspace, source registry, refresh cadence, and
/// shared complication selection. Rendering and window placement live outside
/// the runtime so more islands do not multiply source work.
@MainActor
@Observable
final class IslandRuntime {
    private(set) var allProviders: [any AIProvider]
    let usesDemoData: Bool
    let workspaceStore: IslandWorkspaceStore
    let sessionMonitor: SessionMonitor
    let sourceRegistry: ComplicationSourceRegistry

    var settingsSection: SettingsSection = .overview
    var selection: ComplicationSelection?
    var isWindowPinned = false
    var pointerOverPopover = false

    @ObservationIgnored private var pointerOverIslands = Set<UUID>()
    @ObservationIgnored private var hoverDismissTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var localMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var history = ComplicationHistoryBuffer()
    @ObservationIgnored private var snapshotBoxes: [String: SourceSnapshotBox] = [:]
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let powerStateProvider: (any PowerStateProvider)?
    @ObservationIgnored var islandTopGapPreviewHandler: ((UUID, Double?) -> Void)?

    static func make() -> IslandRuntime {
        let demo = CommandLine.arguments.contains("--demo")
        let settings = JSONSettingsRepository.shared
        let providers = IslandProviders.makeAll(demo: demo, settings: settings)
        return IslandRuntime(
            providers: providers,
            usesDemoData: demo,
            workspaceStore: IslandWorkspaceStore(),
            powerStateProvider: SystemPowerStateProvider()
        )
    }

    static func testing(
        providers: [any AIProvider],
        workspaceStore: IslandWorkspaceStore,
        usesDemoData: Bool = true
    ) -> IslandRuntime {
        IslandRuntime(
            providers: providers,
            usesDemoData: usesDemoData,
            workspaceStore: workspaceStore,
            powerStateProvider: nil
        )
    }

    private init(
        providers: [any AIProvider],
        usesDemoData: Bool,
        workspaceStore: IslandWorkspaceStore,
        powerStateProvider: (any PowerStateProvider)?
    ) {
        allProviders = providers
        self.usesDemoData = usesDemoData
        self.workspaceStore = workspaceStore
        self.powerStateProvider = powerStateProvider
        let sessions = SessionMonitor()
        sessionMonitor = sessions
        sourceRegistry = ComplicationSourceRegistry(
            providers: providers,
            sessionMonitor: sessions,
            includeLegacyBattery: workspaceStore.workspace.referencedSourceIDs.contains("system.battery")
        )
        workspaceStore.onWorkspaceChange = { [weak self] in
            self?.workspaceDidChange()
        }
    }

    var selectedIsland: IslandConfiguration? {
        guard let id = selection?.islandID else { return nil }
        return workspaceStore.island(id: id)
    }

    var selectedComplication: ComplicationConfiguration? {
        guard let selection,
              let island = workspaceStore.island(id: selection.islandID)
        else { return nil }
        return island.complications.first { $0.id == selection.complicationID }
    }

    /// AI sources are drawn from saved islands, including hidden islands and rings.
    /// Keep the full registry intact so reducing the catalog never removes configuration.
    var catalogSources: [ComplicationSourceDescriptor] {
        let used = Set(workspaceStore.islands.flatMap(\.complications).map(\.sourceID))
        return sourceRegistry.descriptors.filter {
            $0.kind != .usage || used.contains($0.id)
                || ($0.id == HarnaisWeeklyStarter.sourceID && provider(id: $0.id)?.snapshot != nil)
        }
    }

    var referencedSourceIDs: [String] {
        Array(Set(workspaceStore.visibleIslands.flatMap(\.visibleComplications).map(\.sourceID))).sorted()
    }

    func isHiddenBySource(_ complication: ComplicationConfiguration) -> Bool {
        guard complication.sourceID == HarnaisWeeklyStarter.sourceID,
              let snapshot = provider(id: complication.sourceID)?.snapshot,
              !complication.metricIDs.isEmpty else { return false }
        return complication.metricIDs.contains { metricID in
            snapshot.hiddenQuotaTypes.contains { metricID == "quota.key.\($0)" }
        }
    }

    func visibleComplications(on island: IslandConfiguration) -> [ComplicationConfiguration] {
        island.visibleComplications.filter { !isHiddenBySource($0) }
    }

    func start() {
        IslandMetrics.assertLayoutInvariants()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        AppLog.ui.info("Iles \(version) starting (\(usesDemoData ? "demo" : "live"))")
        hasStarted = true
        seedCurrentSnapshots()
        startInitialRefresh()
        restartBackgroundMonitor()
        restartLocalMonitor()
    }

    func attachExtensions() {
        guard !usesDemoData else { return }
        let extras = ExtensionRegistry(
            settingsRepository: JSONSettingsRepository.shared,
            configRepository: JSONExtensionConfigRepository(settingsStore: .shared)
        ).makeProviders()
        guard !extras.isEmpty else { return }
        let firstPartyHarnaisID = ProviderIdentity.harnais.rawValue
        let harnaisExtensionID = "ext-\(firstPartyHarnaisID)"
        for provider in extras where !allProviders.contains(where: { $0.id == provider.id }) {
            if provider.id == harnaisExtensionID,
               allProviders.contains(where: { $0.id == firstPartyHarnaisID }) {
                continue
            }
            allProviders.append(provider)
            sourceRegistry.register(provider: provider)
        }
        seedCurrentSnapshots()
        restartBackgroundMonitor()
    }

    func stop() {
        hasStarted = false
        hoverDismissTask?.cancel()
        refreshTask?.cancel()
        monitorTask?.cancel()
        localMonitorTask?.cancel()
        sourceRegistry.cancelRefreshes()
    }

    func isRefreshingSource(_ id: String) -> Bool {
        sourceRegistry.refreshingSourceIDs.contains(id) || provider(id: id)?.isSyncing == true
    }

    func refreshNow() {
        BinaryLocator.invalidateCaches()
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshSources(kind: .interactive)
        }
    }

    func refreshSource(_ id: String) -> Task<Void, Never>? {
        guard sourceRegistry.source(id: id) != nil else { return nil }
        pinIfInteracting()
        return Task { [weak self] in
            await self?.refreshSources(ids: [id], kind: .interactive)
        }
    }

    @discardableResult
    func refreshProvider(_ id: String) -> Task<Void, Never>? {
        refreshSource(id)
    }

    func applyRefreshInterval() {
        restartBackgroundMonitor()
    }

    func applyHarnaisOverlap() {
        let settings = JSONSettingsRepository.shared
        let builtins = IslandProviders.makeAll(demo: usesDemoData, settings: settings)
        let existingByID = Dictionary(uniqueKeysWithValues: allProviders.map { ($0.id, $0) })
        let extras = allProviders.filter { $0 is ExtensionProvider }
        let mergedBuiltins = builtins.map { existingByID[$0.id] ?? $0 }
        let nextIDs = Set(mergedBuiltins.map(\.id)).union(extras.map(\.id))
        for provider in allProviders where !nextIDs.contains(provider.id) {
            sourceRegistry.unregister(id: provider.id)
            snapshotBoxes[provider.id] = nil
        }
        for provider in mergedBuiltins where existingByID[provider.id] == nil {
            sourceRegistry.register(provider: provider)
        }
        allProviders = mergedBuiltins + extras.filter { extra in
            !mergedBuiltins.contains(where: { $0.id == extra.id })
        }
        seedCurrentSnapshots()
        restartBackgroundMonitor()
    }

    /// Routes a continuous placement preview directly to the window
    /// coordinator without invalidating the observable workspace.
    func previewIslandTopGap(_ islandID: UUID, value: Double?) {
        islandTopGapPreviewHandler?(islandID, value)
    }

    func provider(id: String) -> (any AIProvider)? {
        allProviders.first { $0.id == id }
    }

    func snapshot(sourceID: String) -> SourceSnapshot? {
        // Refresh tasks publish snapshots into this observable cache. Avoid
        // recomputing IOKit, Mach, formatter, or provider values from view bodies.
        snapshotBox(for: sourceID).value ?? sourceRegistry.snapshot(sourceID: sourceID)
    }

    func descriptor(sourceID: String) -> ComplicationSourceDescriptor? {
        sourceRegistry.descriptor(sourceID: sourceID)
    }

    @discardableResult
    func addSource(kind: ConfigurableSourceKind) -> String {
        let id = sourceRegistry.addSource(kind: kind)
        if let snapshot = sourceRegistry.snapshot(sourceID: id) {
            publish(snapshot, sourceID: id)
        }
        return id
    }

    @discardableResult
    func removeSource(_ id: String) -> Bool {
        guard !workspaceStore.workspace.referencedSourceIDs.contains(id),
              sourceRegistry.removeSource(id: id)
        else { return false }
        snapshotBoxes[id] = nil
        restartLocalMonitor()
        return true
    }

    func values(for complication: ComplicationConfiguration) -> [ComplicationValue] {
        let slots = slotValues(for: complication)
        guard slots.contains(where: { $0.value != nil }) else { return [] }
        // Keep absent slots in place: an inner-ring reading must never become
        // the outer-ring reading when a provider omits one metric.
        return slots.map { $0.value ?? .value("—", unit: nil) }
    }

    func trendDirection(for complication: ComplicationConfiguration) -> ComplicationTrendDirection {
        guard complication.family == .trend,
              let metricID = complication.metricIDs.first,
              let snapshot = snapshot(sourceID: complication.sourceID),
              let current = snapshot.values[metricID].flatMap(Self.numericValue),
              let previous = history.context(
                  sourceID: complication.sourceID,
                  before: snapshot.capturedAt
              ).history[metricID]?.last?.value
        else { return .unknown }

        var comparison: ComplicationTrendDirection
        if abs(current - previous) < 0.000_1 {
            comparison = .flat
        } else {
            comparison = current > previous ? .up : .down
        }
        let transforms = complication.recipeID.flatMap { recipeID in
            sourceRegistry.recipe(id: recipeID, sourceID: complication.sourceID)
        }?.slots.first?.transforms ?? []
        let recipeInverts = transforms.reduce(false) { inverted, transform in
            transform == .remaining || transform == .inverse ? !inverted : inverted
        }
        let presentationInverts = complication.valueMode(at: 0) == .remaining
        if recipeInverts != presentationInverts {
            if comparison == .up { comparison = .down }
            else if comparison == .down { comparison = .up }
        }
        return comparison
    }

    func resolvedSlots(
        for complication: ComplicationConfiguration
    ) -> [(metricID: String, value: ComplicationValue)] {
        slotValues(for: complication).compactMap { slot in
            slot.value.map { (slot.metricID, $0) }
        }
    }

    private func slotValues(
        for complication: ComplicationConfiguration
    ) -> [(metricID: String, value: ComplicationValue?)] {
        guard let source = snapshot(sourceID: complication.sourceID) else { return [] }
        if let recipeID = complication.recipeID,
           let recipe = sourceRegistry.recipe(id: recipeID, sourceID: complication.sourceID) {
            let needsHistory = recipe.slots.contains { slot in
                slot.transforms.contains(where: \.requiresHistory)
            }
            let context = needsHistory
                ? history.context(sourceID: complication.sourceID, before: source.capturedAt)
                : ComplicationTransformContext()
            return recipe.slots.enumerated().map { index, slot in
                let value = ComplicationTransformEngine.resolve(
                    slot: slot,
                    snapshot: source,
                    context: context
                ).map { ComplicationTransformEngine.present($0, as: complication.valueMode(at: index)) }
                return (slot.metricID, value)
            }
        }
        return complication.metricIDs.enumerated().map { index, metricID in
            let value = source.values[metricID].map {
                ComplicationTransformEngine.present($0, as: complication.valueMode(at: index))
            }
            return (metricID, value)
        }
    }

    var harnaisStaleAfter: TimeInterval {
        HarnaisRefreshPolicy.staleAfter(
            interval: JSONSettingsRepository.shared.refreshInterval(),
            onBattery: powerStateProvider?.isOnBattery == true
        )
    }

    func quality(for complication: ComplicationConfiguration) -> ComplicationSampleQuality {
        guard let snapshot = snapshot(sourceID: complication.sourceID) else { return .unavailable }
        if snapshot.quality == .unavailable || snapshot.quality == .failed || snapshot.quality == .stale {
            return snapshot.quality
        }
        if snapshot.errorDescription != nil, snapshot.values.isEmpty { return .failed }
        let slots = slotValues(for: complication)
        if slots.isEmpty || slots.contains(where: { $0.value == nil }) { return .unavailable }
        guard let descriptor = descriptor(sourceID: complication.sourceID) else { return snapshot.quality }
        let staleLimits = complication.metricIDs.compactMap { metricID in
            descriptor.metrics.first { $0.id == metricID }?.policy.staleAfter
        }
        let limit = complication.sourceID == HarnaisWeeklyStarter.sourceID ? harnaisStaleAfter : staleLimits.min()
        if let limit, Date().timeIntervalSince(snapshot.capturedAt) > limit { return .stale }
        return snapshot.quality
    }

    func editSelectedWidget() {
        guard let selection else { return }
        workspaceStore.selectIsland(selection.islandID)
        workspaceStore.selectedComplicationID = selection.complicationID
        settingsSection = .islands
        dismissWindow()
        NotificationCenter.default.post(name: .showIslandSettings, object: nil)
    }

    func handleTap(islandID: UUID, complication: ComplicationConfiguration) {
        switch complication.tapAction {
        case .showDetails:
            let next = ComplicationSelection(islandID: islandID, complicationID: complication.id)
            if selection == next, isWindowPinned {
                dismissWindow()
            } else {
                selection = next
                isWindowPinned = true
                refreshIfNeeded(complication.sourceID)
            }
        case .refresh:
            _ = refreshSource(complication.sourceID)
        case .openDashboard:
            if let url = provider(id: complication.sourceID)?.dashboardURL
                ?? descriptor(sourceID: complication.sourceID)?.actionURL {
                NSWorkspace.shared.open(url)
            }
        case .none:
            break
        }
    }

    func hoverSelect(islandID: UUID, complicationID: UUID) {
        guard !isWindowPinned else { return }
        hoverDismissTask?.cancel()
        selection = ComplicationSelection(islandID: islandID, complicationID: complicationID)
    }

    func dismissWindow() {
        selection = nil
        isWindowPinned = false
    }

    func pinIfInteracting() {
        guard selection != nil else { return }
        isWindowPinned = true
    }

    func setPointerOverIsland(_ islandID: UUID, _ over: Bool) {
        if over {
            pointerOverIslands.insert(islandID)
        } else {
            pointerOverIslands.remove(islandID)
        }
        reconcileHover()
    }

    func setPointerOverPopover(_ over: Bool) {
        pointerOverPopover = over
        reconcileHover()
    }

    func sessionDidChange() {
        if let snapshot = sourceRegistry.snapshot(sourceID: "session.claude") {
            publish(snapshot, sourceID: "session.claude")
        }
        restartLocalMonitor()
    }

    func sessionTrackingDidChange() {
        sessionDidChange()
    }

    private func seedCurrentSnapshots() {
        for id in referencedSourceIDs {
            if let snapshot = sourceRegistry.snapshot(sourceID: id) {
                publish(snapshot, sourceID: id)
                recordHistory(sourceID: id, snapshot: snapshot)
            }
        }
    }

    /// Startup must not depend on the first periodic monitor tick. Provider
    /// descriptors are snapshot-backed, so delaying this refresh also leaves
    /// their complication catalogs and style choices empty after launch.
    ///
    /// Harnais is included even when it is not on an island so configured
    /// accounts are available in the catalog before the first widget is added.
    private func startInitialRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshSources(ids: self.initialRefreshSourceIDs, kind: .interactive)
        }
    }

    var initialRefreshSourceIDs: [String] {
        var ids = referencedSourceIDs
        let harnaisID = ProviderIdentity.harnais.rawValue
        if !usesDemoData,
           allProviders.contains(where: { $0.id == harnaisID }),
           !ids.contains(harnaisID) {
            ids.append(harnaisID)
        }
        return ids
    }

    private func restartBackgroundMonitor() {
        monitorTask?.cancel()
        guard let seconds = JSONSettingsRepository.shared.refreshInterval().seconds else {
            AppLog.monitor.info("Background refresh is off; complications update on demand")
            return
        }
        let interval = max(seconds, 60)
        AppLog.monitor.info("Background refresh every \(Int(interval)) seconds")
        let powerStateProvider = self.powerStateProvider
        monitorTask = Task { [weak self, powerStateProvider] in
            var powerEvents = powerStateProvider?.events().makeAsyncIterator()
            var refreshImmediately = false
            while !Task.isCancelled {
                while powerStateProvider?.isDisplayAsleep == true, !Task.isCancelled {
                    guard await powerEvents?.next() != nil else { return }
                    refreshImmediately = true
                }
                guard !Task.isCancelled else { return }

                if !refreshImmediately {
                    let effectiveInterval = powerStateProvider?.isOnBattery == true
                        ? interval * 2
                        : interval
                    do {
                        try await Task.sleep(for: .seconds(effectiveInterval))
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                guard powerStateProvider?.isDisplayAsleep != true else { continue }
                await self?.refreshSources(kind: .background)
                refreshImmediately = false
            }
        }
    }

    /// Provider refresh is user-configurable and may be off. Clock,
    /// and active-session values still need a lightweight local cadence.
    private func restartLocalMonitor() {
        localMonitorTask?.cancel()
        guard hasStarted else { return }

        let localIDs = Set(referencedSourceIDs.filter { id in
            Self.localSourceIDs.contains(id)
                || descriptor(sourceID: id)?.sourceKindID == ConfigurableSourceKind.gitRepository.sourceKindID
        })
        guard !localIDs.isEmpty else {
            localMonitorTask = nil
            return
        }

        let usedComplications = workspaceStore.visibleIslands.flatMap(\.visibleComplications)
        let usedMetricIDsBySource = Dictionary(grouping: usedComplications, by: \.sourceID)
            .mapValues { Set($0.flatMap(\.metricIDs)) }
        let tracksActiveSession = localIDs.contains("session.claude")
            && JSONSettingsRepository.shared.isHookEnabled()
            && sessionMonitor.activeSession != nil
        var fastIDs = Set(localIDs.filter { id in
            guard let descriptor = sourceRegistry.descriptor(sourceID: id) else { return false }
            let usedMetricIDs = usedMetricIDsBySource[id] ?? []
            return descriptor.metrics.contains {
                usedMetricIDs.contains($0.id) && $0.policy.refreshClass == .liveLocal
            }
        })
        if tracksActiveSession { fastIDs.insert("session.claude") }
        let scheduleTemplate = LocalSourceRefreshSchedule(
            fastSourceIDs: fastIDs,
            slowSourceIDs: localIDs.subtracting(fastIDs),
            tracksActiveSession: tracksActiveSession
        )
        localMonitorTask = Task { [weak self] in
            var schedule = scheduleTemplate
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(schedule.tickInterval))
                } catch {
                    return
                }
                guard let self else { return }
                let sourceIDs = schedule.sourceIDsForNextTick()
                guard !sourceIDs.isEmpty else { continue }
                let refreshed = await self.sourceRegistry.refresh(sourceIDs: sourceIDs, kind: .background)
                for (id, snapshot) in refreshed {
                    self.publish(snapshot, sourceID: id)
                    self.recordHistory(sourceID: id, snapshot: snapshot)
                }
            }
        }
    }

    private func workspaceDidChange() {
        seedCurrentSnapshots()
        restartLocalMonitor()
    }

    private func refreshSources(kind: RefreshKind) async {
        await refreshSources(ids: referencedSourceIDs, kind: kind)
    }

    private func refreshSources(ids: [String], kind: RefreshKind) async {
        let qos: QualityOfService = kind == .background ? .utility : .default
        let refreshed = await ProbeExecutionContext.$qualityOfService.withValue(qos) {
            await sourceRegistry.refresh(sourceIDs: ids, kind: kind)
        }
        for (sourceID, snapshot) in refreshed {
            publish(snapshot, sourceID: sourceID)
            recordHistory(sourceID: sourceID, snapshot: snapshot)
        }
    }

    private func refreshIfNeeded(_ sourceID: String) {
        let source = snapshot(sourceID: sourceID)
        guard source?.values.isEmpty != false else { return }
        _ = refreshSource(sourceID)
    }

    private func recordHistory(sourceID: String, snapshot: SourceSnapshot) {
        guard let descriptor = sourceRegistry.descriptor(sourceID: sourceID) else { return }
        history.record(sourceID: sourceID, snapshot: snapshot, metrics: descriptor.metrics)
    }

    private func snapshotBox(for sourceID: String) -> SourceSnapshotBox {
        if let box = snapshotBoxes[sourceID] { return box }
        let box = SourceSnapshotBox()
        snapshotBoxes[sourceID] = box
        return box
    }

    private func publish(_ snapshot: SourceSnapshot, sourceID: String) {
        let box = snapshotBox(for: sourceID)
        if box.value != snapshot {
            box.value = snapshot
        }
        if sourceID == HarnaisWeeklyStarter.sourceID {
            reconcileHarnaisGlances()
        }
    }

    private func reconcileHarnaisGlances() {
        guard let snapshot = provider(id: HarnaisWeeklyStarter.sourceID)?.snapshot,
              let descriptor = descriptor(sourceID: HarnaisWeeklyStarter.sourceID)
        else { return }
        let wanted = HarnaisWeeklyStarter.glanceRecipes(in: snapshot, descriptor: descriptor)
        let live = HarnaisWeeklyStarter.liveNamedRecipes(in: snapshot, descriptor: descriptor)
        for islandID in workspaceStore.visibleIslands.map(\.id) {
            guard var island = workspaceStore.island(id: islandID) else { continue }
            if !live.isEmpty {
                let rebinds = HarnaisWeeklyStarter.rebindPairs(on: island, live: live)
                for rebind in rebinds {
                    workspaceStore.updateComplication(rebind.complicationID, in: islandID) { item in
                        item.recipeID = rebind.recipe.id
                        item.metricIDs = rebind.recipe.metricIDs
                    }
                }
                // Missing quotas can be a temporary provider failure. Retain the saved layout.
                island = workspaceStore.island(id: islandID) ?? island
            }
            let missing = HarnaisWeeklyStarter.missingRecipes(
                on: island,
                snapshot: snapshot,
                descriptor: descriptor
            )
            guard !missing.isEmpty else { continue }
            let capacity = IslandMetrics.maxProviderCount(
                forHeight: IslandMetrics.maximumHeight(
                    visibleFrameHeight: NSScreen.main?.visibleFrame.height ?? 900
                )
            )
            let room = max(0, capacity - island.visibleComplications.count)
            guard room > 0 else { continue }
            workspaceStore.addComplications(
                to: islandID,
                recipes: Array(missing.prefix(room)),
                insertionIndex: { recipe, current in
                    HarnaisWeeklyStarter.insertionIndex(for: recipe, on: current, wanted: wanted)
                }
            )
        }
    }

    private func reconcileHover() {
        hoverDismissTask?.cancel()
        guard !isWindowPinned, pointerOverIslands.isEmpty, !pointerOverPopover else { return }
        hoverDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            if self.pointerOverIslands.isEmpty, !self.pointerOverPopover {
                self.selection = nil
            }
        }
    }

    private static func numericValue(_ value: ComplicationValue) -> Double? {
        switch value {
        case .gauge(let number, _, _): number
        case .value(let text, _): Double(text.replacingOccurrences(of: ",", with: "."))
        case .duration(let interval, _): interval
        case .date(let date, _): date.timeIntervalSince1970
        case .status: nil
        }
    }

    private static let localSourceIDs: Set<String> = [
        "session.claude",
        "system.battery",
        "system.clock",
        "system.mac",
        "productivity.focus",
        "developer.git",
        "calendar.events",
        "calendar.reminders",
    ]
}
