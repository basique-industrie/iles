import AppKit
import Domain
import IslandGeometry
import SwiftUI

private struct GalleryCollection: Identifiable {
    struct Item {
        let sourceID: String
        let recipeID: String
    }

    let id: String
    let name: String
    let summary: String
    let symbol: String
    let items: [Item]
}
private enum CatalogFilter: String, CaseIterable, Identifiable {
    case all
    case featured
    case available
    case needsSetup
    case inUse
    case new

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .featured: "Featured"
        case .available: "Available"
        case .needsSetup: "Needs Setup"
        case .inUse: "In Use"
        case .new: "New"
        }
    }
}

struct ComplicationGallery: View {
    @Bindable var runtime: IslandRuntime
    @Binding var isPresented: Bool
    let sourceScopeID: String?
    let configureSource: (String) -> Void
    @State private var search = ""
    @State private var category: ComplicationCategory?
    @State private var filter: CatalogFilter = .featured

    private let primaryFilters: [CatalogFilter] = [.featured, .all, .inUse]

    private var sources: [ComplicationSourceDescriptor] {
        runtime.sourceRegistry.descriptors.filter {
            (sourceScopeID == nil || $0.id == sourceScopeID)
                && !visiblePresets(for: $0).isEmpty
        }.sorted { lhs, rhs in
            let lhsPriority = sourcePriority(lhs)
            let rhsPriority = sourcePriority(rhs)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            let lhsCategory = categoryOrder(for: lhs)
            let rhsCategory = categoryOrder(for: rhs)
            if lhsCategory != rhsCategory { return lhsCategory < rhsCategory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var collections: [GalleryCollection] {
        var result: [GalleryCollection] = []
        if let aiSource = preferredAISource {
            let preferredRecipeIDs = [
                "\(aiSource.id).session-weekly",
                "\(aiSource.id).quota-pair",
                "\(aiSource.id).daily-summary",
                "\(aiSource.id).quota-health",
                "\(aiSource.id).next-reset",
            ]
            let items = preferredRecipeIDs.compactMap { recipeID -> GalleryCollection.Item? in
                aiSource.complications.contains(where: { $0.id == recipeID })
                    ? .init(sourceID: aiSource.id, recipeID: recipeID)
                    : nil
            }
            result.append(GalleryCollection(
                id: "ai-command-center",
                name: "AI Command Center",
                summary: "A stack built from this provider’s available quota signals.",
                symbol: "sparkles",
                items: items
            ))
        }
        result.append(contentsOf: [
            GalleryCollection(
                id: "mac-health",
                name: "Mac Health",
                summary: "Battery, resources, network, and thermal state.",
                symbol: "macbook",
                items: [
                    .init(sourceID: "system.battery", recipeID: "system.battery.charge-ring"),
                    .init(sourceID: "system.mac", recipeID: "system.mac.resources"),
                    .init(sourceID: "system.mac", recipeID: "system.mac.network"),
                    .init(sourceID: "system.mac", recipeID: "system.mac.thermal"),
                ]
            ),
            GalleryCollection(
                id: "coding-focus",
                name: "Coding Focus",
                summary: "Session activity, duration, agents, and focus goal.",
                symbol: "terminal",
                items: [
                    .init(sourceID: "session.claude", recipeID: "session.claude.state"),
                    .init(sourceID: "session.claude", recipeID: "session.claude.duration"),
                    .init(sourceID: "session.claude", recipeID: "session.claude.agents"),
                    .init(sourceID: "productivity.focus", recipeID: "productivity.focus.daily-goal"),
                ]
            ),
            GalleryCollection(
                id: "day-planner",
                name: "Day Planner",
                summary: "Time, workday progress, next event, and reminders.",
                symbol: "calendar.day.timeline.left",
                items: [
                    .init(sourceID: "system.clock", recipeID: "system.clock.current-time"),
                    .init(sourceID: "system.clock", recipeID: "system.clock.workday-progress"),
                    .init(sourceID: "calendar.events", recipeID: "calendar.events.countdown"),
                    .init(sourceID: "calendar.reminders", recipeID: "calendar.reminders.due-today"),
                ]
            ),
            GalleryCollection(
                id: "shipping-dashboard",
                name: "Shipping Dashboard",
                summary: "Repository changes, CI, and deployment health.",
                symbol: "shippingbox",
                items: [
                    .init(sourceID: preferredSourceID(for: .gitRepository), recipeID: "developer.git.status"),
                    .init(sourceID: preferredSourceID(for: .gitRepository), recipeID: "developer.git.changes"),
                    .init(sourceID: preferredSourceID(for: .githubRepository), recipeID: "developer.github.ci"),
                    .init(sourceID: preferredSourceID(for: .githubRepository), recipeID: "developer.github.deployment"),
                ]
            ),
            GalleryCollection(
                id: "service-watch",
                name: "Service Watch",
                summary: "Status, latency, availability, and failures.",
                symbol: "waveform.path.ecg",
                items: [
                    .init(sourceID: preferredSourceID(for: .healthEndpoint), recipeID: "services.endpoint.status"),
                    .init(sourceID: preferredSourceID(for: .healthEndpoint), recipeID: "services.endpoint.latency"),
                    .init(sourceID: preferredSourceID(for: .healthEndpoint), recipeID: "services.endpoint.availability"),
                    .init(sourceID: preferredSourceID(for: .healthEndpoint), recipeID: "services.endpoint.failures"),
                ]
            ),
        ])
        return result
    }

    private var preferredAISource: ComplicationSourceDescriptor? {
        if let selected = runtime.workspaceStore.selectedComplication,
           let descriptor = runtime.descriptor(sourceID: selected.sourceID),
           descriptor.kind == .usage {
            return descriptor
        }
        return runtime.sourceRegistry.descriptors.first { $0.kind == .usage && !$0.complications.isEmpty }
    }

    private func preferredSourceID(for kind: ConfigurableSourceKind) -> String {
        let candidates = runtime.sourceRegistry.descriptors.filter { $0.sourceKindID == kind.sourceKindID }
        if let selected = runtime.workspaceStore.selectedComplication?.sourceID,
           candidates.contains(where: { $0.id == selected }) {
            return selected
        }
        return candidates.first { source in
            let snapshot = runtime.snapshot(sourceID: source.id)
            return snapshot?.availability.state == .available
                && snapshot?.errorDescription == nil
                && snapshot?.values.isEmpty == false
        }?.id ?? candidates.first?.id ?? kind.sourceKindID
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Complication")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    SettingsCaption(text: sourceScopeID.flatMap { runtime.descriptor(sourceID: $0)?.name }
                        .map { "Choose a \($0) glance for \(selectedIslandName)." }
                        ?? "Choose a glance for \(selectedIslandName). Sources and recipes can be added more than once.")
                }
                Spacer()
                newSourceMenu(label: "Add Source")
                    .frame(width: 124)
                QuietIconButton(
                    symbol: "xmark",
                    accessibilityName: "Close gallery",
                    helpText: "Close without adding a complication"
                ) { isPresented = false }
            }
            .padding(16)

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(IslandChrome.tertiaryText)
                    TextField("Search by source, outcome, or metric", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(IslandChrome.tertiaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(
                    IslandChrome.fieldFill,
                    in: RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                        .strokeBorder(IslandChrome.controlBorder, lineWidth: 1)
                }

                IslandSegmentBar(
                    items: primaryFilters,
                    selection: $filter,
                    title: { $0.title }
                )
                .frame(width: 250)

                Menu {
                    Button {
                        category = nil
                    } label: {
                        Label("All Categories", systemImage: category == nil ? "checkmark" : "square.grid.2x2")
                    }
                    Divider()
                    ForEach(ComplicationCategory.allCases, id: \.self) { item in
                        Button {
                            category = item
                        } label: {
                            Label(item.displayName, systemImage: category == item ? "checkmark" : item.gallerySymbol)
                        }
                    }
                } label: {
                    SettingsMenuLabel(
                        symbol: category?.gallerySymbol ?? "square.grid.2x2",
                        title: category?.displayName ?? "All Categories"
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 158)

                Menu {
                    ForEach([CatalogFilter.available, .needsSetup, .new]) { item in
                        Button {
                            filter = item
                        } label: {
                            Label(item.title, systemImage: item == filter ? "checkmark" : "line.3.horizontal.decrease")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryFilters.contains(filter) ? IslandChrome.secondaryText : Color.white)
                        .frame(width: 36, height: 36)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("More filters")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 12) {
                    if sourceScopeID == nil, search.isEmpty, category == nil, filter == .featured {
                        collectionSection
                    }
                    ForEach(sources) { source in
                        sourceGroup(source)
                    }
                    if sources.isEmpty {
                        ContentUnavailableView(
                            "No Complications Found",
                            systemImage: "magnifyingglass",
                            description: Text("Try another source, metric, or style name.")
                        )
                        .foregroundStyle(IslandChrome.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 900, height: 620)
        .background(IslandPalette.popover)
        .preferredColorScheme(.dark)
        .onChange(of: search) { _, value in
            if !value.isEmpty, filter == .featured {
                filter = .all
            }
        }
    }

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(title: "Starter Collections")
                Spacer()
                SettingsCaption(text: "Add a complete island stack")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(collections) { collection in
                        collectionCard(collection)
                    }
                }
            }
        }
    }

    private func collectionCard(_ collection: GalleryCollection) -> some View {
        let resolved = resolvedItems(in: collection)
        let unavailableSource = collection.items.first { item in
            let state = runtime.snapshot(sourceID: item.sourceID)?.availability.state ?? .available
            return state != .available && state != .unsupported
        }?.sourceID
        let supportedItemCount = collection.items.count { item in
            runtime.snapshot(sourceID: item.sourceID)?.availability.state != .unsupported
        }
        let ready = supportedItemCount > 0
            && unavailableSource == nil
            && resolved.count == supportedItemCount
        let unavailableSourceName = unavailableSource.flatMap { runtime.descriptor(sourceID: $0)?.name }
        return Button {
            guard ready else {
                if let unavailableSource {
                    isPresented = false
                    configureSource(unavailableSource)
                }
                return
            }
            guard let islandID = runtime.workspaceStore.selectedIslandID else { return }
            for (source, recipe) in resolved {
                _ = runtime.workspaceStore.addComplication(
                    to: islandID,
                    sourceID: source.id,
                    metricIDs: recipe.metricIDs,
                    family: recipe.family,
                    labelStyle: recipe.labelStyle,
                    recipeID: recipe.id,
                    tint: recipe.tint,
                    tapAction: recipe.tapAction
                )
            }
            for sourceID in Set(resolved.map { $0.0.id }) {
                _ = runtime.refreshSource(sourceID)
            }
            isPresented = false
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: collection.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(IslandChrome.selectedFill, in: Circle())
                    Spacer()
                    StatusChip(text: ready ? "\(resolved.count)" : "Setup")
                }
                Text(collection.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(unavailableSourceName.map { "Connect \($0) to add this stack." } ?? collection.summary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IslandChrome.secondaryText)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(width: 190, height: 110, alignment: .topLeading)
            .background(IslandChrome.fieldFill, in: RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous)
                    .strokeBorder(IslandChrome.controlBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(ready ? "Add \(collection.name)" : "Complete source setup for this collection")
    }

    private func resolvedItems(
        in collection: GalleryCollection
    ) -> [(ComplicationSourceDescriptor, ComplicationRecipe)] {
        collection.items.compactMap { item in
            guard runtime.snapshot(sourceID: item.sourceID)?.availability.state != .unsupported else {
                return nil
            }
            guard let source = runtime.descriptor(sourceID: item.sourceID),
                  let recipe = source.complications.first(where: { $0.id == item.recipeID })
            else { return nil }
            return (source, recipe)
        }
    }

    private func sourceGroup(_ source: ComplicationSourceDescriptor) -> some View {
        let sourceError = runtime.snapshot(sourceID: source.id)?.errorDescription
        let visible = visiblePresets(for: source)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                SourceMark(sourceID: source.id, descriptor: source, size: 16)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    SettingsCaption(text: source.gallerySourceSubtitle)
                }
                Spacer(minLength: 8)
                let status = galleryStatus(for: source)
                if status != "Ready" && status != "Available" {
                    StatusChip(text: status)
                }
                if let kind = source.configurableKind {
                    QuietIconButton(
                        symbol: "plus",
                        accessibilityName: "Add another \(kind.title)",
                        helpText: kind.setupSummary
                    ) {
                        addSource(kind)
                    }
                }
                if sourceError != nil {
                    QuietButton(
                        title: "Configure",
                        symbol: "slider.horizontal.3",
                        prominence: .primary
                    ) {
                        isPresented = false
                        configureSource(source.id)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visible) { preset in
                        galleryCard(source: source, preset: preset)
                            .frame(width: 246)
                    }
                }
            }
            SettingsHairline()
        }
        .padding(.top, 2)
    }

    private func galleryCard(
        source: ComplicationSourceDescriptor,
        preset: ComplicationDescriptor
    ) -> some View {
        let preview = ComplicationConfiguration(
            recipeID: preset.id,
            sourceID: source.id,
            metricIDs: preset.metricIDs,
            family: preset.family,
            labelStyle: preset.labelStyle,
            tint: preset.tint,
            tapAction: preset.tapAction
        )
        let livePreviewValues = runtime.values(for: preview)
        let fixtureValues = ComplicationPreviewFixture.values(for: preset, sourceID: source.id)
        let usesFixture = livePreviewValues.isEmpty && !fixtureValues.isEmpty
        let previewValues = usesFixture ? fixtureValues : livePreviewValues
        let sourceError = runtime.snapshot(sourceID: source.id)?.errorDescription
        let glance = previewValues.first?.displayText ?? (sourceError == nil ? "No data" : "Needs setup")
        let availability = runtime.snapshot(sourceID: source.id)?.availability ?? .available
        let needsSetup = availability.state == .setupRequired
            || availability.state == .permissionRequired
            || availability.recoveryAction == .configure
            || availability.recoveryAction == .requestPermission
            || availability.recoveryAction == .openSettings
        let unavailable = availability.state == .unsupported
            || (availability.state == .failed && !needsSetup)
            || (sourceError != nil && source.kind == .system && !needsSetup)
        return Button {
            guard !unavailable else { return }
            if needsSetup {
                isPresented = false
                configureSource(source.id)
                return
            }
            guard let islandID = runtime.workspaceStore.selectedIslandID else { return }
            _ = runtime.workspaceStore.addComplication(
                to: islandID,
                sourceID: source.id,
                metricIDs: preset.metricIDs,
                family: preset.family,
                labelStyle: preset.labelStyle,
                recipeID: preset.id,
                tint: preset.tint,
                tapAction: preset.tapAction
            )
            _ = runtime.refreshSource(source.id)
            isPresented = false
        } label: {
            HStack(spacing: 9) {
                ComplicationSlotView(
                    complication: preview,
                    descriptor: source,
                    values: previewValues,
                    sourceError: usesFixture ? nil : sourceError,
                    quality: usesFixture ? .cached : runtime.quality(for: preview),
                    trendDirection: usesFixture ? .unknown : runtime.trendDirection(for: preview),
                    renderScale: 0.9
                )
                .frame(width: 42, height: 46)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(preset.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if preset.isNew {
                            Text("NEW")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                    Text(galleryCardSubtitle(source: source, preset: preset, glance: glance))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(IslandChrome.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 5)
                Image(systemName: unavailable ? "xmark" : (needsSetup ? "slider.horizontal.3" : "plus"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(IslandChrome.selectedFill, in: Circle())
            }
            .padding(9)
            .frame(minHeight: 66)
            .background(IslandChrome.fieldFill, in: RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous)
                    .strokeBorder(IslandChrome.controlBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(unavailable)
        .opacity(unavailable ? 0.55 : 1)
        .accessibilityLabel(unavailable
            ? "\(source.name), \(preset.name), unavailable"
            : (needsSetup
                ? "Configure \(source.name) to use \(preset.name)"
                : "Add \(source.name), \(preset.name), \(glance)"))
        .help(unavailable
            ? "This complication is currently unavailable"
            : (needsSetup ? "Configure \(source.name)" : "Add \(preset.name) from \(source.name)"))
    }

    private func galleryCardSubtitle(
        source: ComplicationSourceDescriptor,
        preset: ComplicationDescriptor,
        glance: String
    ) -> String {
        let metricNames = preset.metricIDs.compactMap { source.metricName(for: $0) }
        let detail: String
        switch metricNames.count {
        case 0:
            detail = glance
        case 1:
            detail = metricNames[0]
        default:
            detail = "\(metricNames.count) values"
        }
        return "\(preset.family.displayName) · \(detail)"
    }

    private func newSourceMenu(label: String) -> some View {
        Menu {
            ForEach(ConfigurableSourceKind.allCases) { kind in
                Button {
                    addSource(kind)
                } label: {
                    Label("New \(kind.title)", systemImage: kind.symbol)
                }
            }
        } label: {
            SettingsMenuLabel(symbol: "plus", title: label)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Create an independent Git, GitHub, or health source")
    }

    private func addSource(_ kind: ConfigurableSourceKind) {
        let id = runtime.addSource(kind: kind)
        isPresented = false
        configureSource(id)
    }

    private var selectedIslandName: String {
        runtime.workspaceStore.selectedIsland?.name ?? "the selected island"
    }

    private func sourcePriority(_ source: ComplicationSourceDescriptor) -> Int {
        if source.id == sourceScopeID { return 0 }
        if source.id == runtime.workspaceStore.selectedComplication?.sourceID { return 0 }
        if runtime.workspaceStore.workspace.islands
            .flatMap(\.complications)
            .contains(where: { $0.sourceID == source.id }) { return 1 }
        let snapshot = runtime.snapshot(sourceID: source.id)
        if snapshot?.availability.state == .available, snapshot?.errorDescription == nil { return 2 }
        return 3
    }

    private func categoryOrder(for source: ComplicationSourceDescriptor) -> Int {
        let category = source.complications.first?.category
        return category.flatMap { ComplicationCategory.allCases.firstIndex(of: $0) } ?? 99
    }

    private func galleryStatus(for source: ComplicationSourceDescriptor) -> String {
        if runtime.provider(id: source.id)?.isSyncing == true { return "Syncing" }
        guard let snapshot = runtime.snapshot(sourceID: source.id) else { return "Available" }
        switch snapshot.availability.state {
        case .setupRequired, .permissionRequired: return "Needs Setup"
        case .temporarilyUnavailable: return "Offline"
        case .unsupported, .failed: return "Unavailable"
        case .available: break
        }
        if snapshot.errorDescription != nil {
            return source.kind == .system ? "Unavailable" : "Needs Setup"
        }
        return snapshot.values.isEmpty ? "Available" : "Ready"
    }

    private func presets(for source: ComplicationSourceDescriptor) -> [ComplicationDescriptor] {
        if !source.complications.isEmpty {
            return source.complications.sorted {
                if $0.rank == $1.rank { return $0.name < $1.name }
                return $0.rank > $1.rank
            }
        }
        return source.supportedFamilies.compactMap { family in
            guard let ids = defaultMetricIDs(for: family, source: source) else { return nil }
            return ComplicationDescriptor(
                id: "\(source.id).\(family.rawValue)",
                name: family.displayName,
                sourceID: source.id,
                family: family,
                metricIDs: ids,
                labelStyle: galleryLabel(for: family)
            )
        }
    }

    private func visiblePresets(for source: ComplicationSourceDescriptor) -> [ComplicationDescriptor] {
        let sourceMatches = search.isEmpty
            || ([source.name, source.settingsDomainName] + source.metrics.map(\.name))
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(search)
        return presets(for: source).filter { preset in
            guard category == nil || preset.category == category else { return false }
            guard matchesFilter(preset, source: source) else { return false }
            if search.isEmpty || sourceMatches { return true }
            return ([preset.name, preset.summary, preset.question, preset.family.displayName] + preset.tags)
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(search)
        }
    }

    private func matchesFilter(
        _ preset: ComplicationRecipe,
        source: ComplicationSourceDescriptor
    ) -> Bool {
        let snapshot = runtime.snapshot(sourceID: source.id)
        let availability = snapshot?.availability ?? .available
        let needsSetup = availability.state == .setupRequired
            || availability.state == .permissionRequired
            || availability.recoveryAction == .configure
            || availability.recoveryAction == .requestPermission
            || availability.recoveryAction == .openSettings
        switch filter {
        case .all: return true
        case .featured: return preset.isFeatured
        case .available:
            return availability.state == .available && snapshot?.errorDescription == nil
        case .needsSetup: return needsSetup
        case .inUse:
            return runtime.workspaceStore.workspace.islands
                .flatMap(\.complications)
                .contains { $0.recipeID == preset.id && $0.sourceID == source.id }
        case .new: return preset.isNew
        }
    }

    private func galleryLabel(for family: ComplicationFamily) -> ComplicationLabelStyle {
        switch family {
        case .ring, .dualRing: .percentage
        case .value: .value
        case .status, .activity, .countdown, .summary, .cluster: .compact
        case .trend: .value
        }
    }

    private func defaultMetricIDs(
        for family: ComplicationFamily,
        source: ComplicationSourceDescriptor
    ) -> [String]? {
        let snapshot = runtime.snapshot(sourceID: source.id)
        let available = source.metrics.filter { snapshot?.values[$0.id] != nil }
        switch family {
        case .ring:
            return (available.first(where: { $0.kind == .gauge })
                ?? source.metrics.first(where: { $0.kind == .gauge })).map { [$0.id] }
        case .dualRing:
            if available.contains(where: { $0.id == "quota.session" }),
               available.contains(where: { $0.id == "quota.weekly" }) {
                return ["quota.session", "quota.weekly"]
            }
            let stableQuotaMetrics = available.filter {
                $0.kind == .gauge && $0.id.hasPrefix("quota.key.")
            }
            if stableQuotaMetrics.count >= 2 {
                return Array(stableQuotaMetrics.prefix(2).map(\.id))
            }
            var gauges = available.filter { $0.kind == .gauge }
            if gauges.count < 2 {
                gauges = source.metrics.filter { $0.kind == .gauge }
            }
            guard gauges.count >= 2 else { return nil }
            return Array(gauges.prefix(2).map(\.id))
        case .status:
            return (available.first(where: { $0.kind == .status })
                ?? source.metrics.first(where: { $0.kind == .status })).map { [$0.id] }
        case .value:
            return (available.first ?? source.metrics.first).map { [$0.id] }
        case .activity:
            return (available.first(where: { $0.kind == .status || $0.kind == .duration })
                ?? source.metrics.first(where: { $0.kind == .status || $0.kind == .duration })).map { [$0.id] }
        case .countdown:
            return (available.first(where: {
                ComplicationRecipeValidator.family(.countdown, supports: $0.kind, metric: $0)
            }) ?? source.metrics.first(where: {
                ComplicationRecipeValidator.family(.countdown, supports: $0.kind, metric: $0)
            })).map { [$0.id] }
        case .trend:
            return (available.first(where: {
                ComplicationRecipeValidator.family(.trend, supports: $0.kind, metric: $0)
            }) ?? source.metrics.first(where: {
                ComplicationRecipeValidator.family(.trend, supports: $0.kind, metric: $0)
            })).map { [$0.id] }
        case .summary:
            let candidates = available.isEmpty ? source.metrics : available
            guard candidates.count >= 2 else { return nil }
            return Array(candidates.prefix(3).map(\.id))
        case .cluster:
            let candidates = (available.isEmpty ? source.metrics : available).filter { $0.kind == .gauge }
            guard candidates.count >= 3 else { return nil }
            return Array(candidates.prefix(3).map(\.id))
        }
    }
}
