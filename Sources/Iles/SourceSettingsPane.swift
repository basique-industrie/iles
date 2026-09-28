import AppKit
import Domain
import Infrastructure
import IslandGeometry
import SwiftUI

private enum SourceListFilter: String, CaseIterable, Identifiable {
    case all
    case inUse
    case needsSetup
    case usage
    case system
    case time
    case session
    case focus
    case developer
    case services
    case extensions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Sources"
        case .inUse: "In Use"
        case .needsSetup: "Needs Setup"
        case .usage: "Usage Providers"
        case .system: "Mac Health"
        case .time: "Time & Calendar"
        case .session: "Sessions"
        case .focus: "Focus"
        case .developer: "Developer"
        case .services: "Services"
        case .extensions: "Extensions"
        }
    }
}

private enum SourceOperationalState: Equatable {
    case ready
    case stale
    case syncing
    case needsSetup
    case unavailable
    case available

    var title: String {
        switch self {
        case .ready: "Ready"
        case .stale: "Out of date"
        case .syncing: "Syncing"
        case .needsSetup: "Needs Setup"
        case .unavailable: "Unavailable"
        case .available: "Available"
        }
    }

    var symbol: String {
        switch self {
        case .ready: "circle.fill"
        case .stale: "clock.badge.exclamationmark"
        case .syncing: "arrow.triangle.2.circlepath"
        case .needsSetup: "exclamationmark.circle.fill"
        case .unavailable: "xmark.circle.fill"
        case .available: "circle"
        }
    }
}

struct SourceSettingsPane: View {
    private struct SourceListEntry: Identifiable {
        let source: ComplicationSourceDescriptor
        let usageCount: Int
        let state: SourceOperationalState
        let originalIndex: Int

        var id: String { source.id }
    }

    @Bindable var runtime: IslandRuntime
    @Binding var selectedSourceID: String
    let browseComplications: () -> Void
    @State private var search = ""
    @State private var filter: SourceListFilter = .all
    @State private var providerReadiness: [String: Bool] = [:]

    private var filteredSources: [SourceListEntry] {
        let counts = sourceUsageCounts
        return runtime.catalogSources.enumerated().compactMap { index, source in
            let entry = SourceListEntry(
                source: source,
                usageCount: counts[source.id, default: 0],
                state: operationalState(for: source),
                originalIndex: index
            )
            return matchesSearch(source) && matchesFilter(entry) ? entry : nil
        }.sorted { lhs, rhs in
            let lhsInUse = lhs.usageCount > 0
            let rhsInUse = rhs.usageCount > 0
            if lhsInUse != rhsInUse { return lhsInUse }
            if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
            return lhs.originalIndex < rhs.originalIndex
        }
    }

    var body: some View {
        let sources = filteredSources
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        SectionLabel(title: filter.title)
                        Spacer()
                        Menu {
                            ForEach(ConfigurableSourceKind.allCases) { kind in
                                Button {
                                    selectedSourceID = runtime.addSource(kind: kind)
                                } label: {
                                    Label("New \(kind.title)", systemImage: kind.symbol)
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(IslandChrome.secondaryText)
                                .frame(width: 28, height: 28)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .accessibilityLabel("Add source")
                        .help("Add another Git, GitHub, or health source")
                    }
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(IslandChrome.tertiaryText)
                            TextField("Search sources", text: $search)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(IslandChrome.text)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            IslandChrome.fieldFill,
                            in: RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                                .strokeBorder(IslandChrome.controlBorder, lineWidth: 1)
                        }

                        Menu {
                            ForEach(SourceListFilter.allCases) { item in
                                Button {
                                    filter = item
                                } label: {
                                    Label(item.title, systemImage: item == filter ? "checkmark" : "line.3.horizontal.decrease")
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(IslandChrome.text)
                                .frame(width: 28, height: 28)
                                .background(IslandChrome.fieldFill, in: RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: IslandChrome.fieldRadius, style: .continuous)
                                        .strokeBorder(IslandChrome.controlBorder, lineWidth: 1)
                                }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .accessibilityLabel("Filter sources")
                        .help("Filter sources")
                    }
                }
                .padding(10)

                SettingsHairline()

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sources) { entry in
                            sourceRow(entry)
                        }
                        if sources.isEmpty {
                            SettingsCaption(text: "No sources match this search and filter.")
                                .padding(14)
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: 260)
            .background(IslandChrome.sidebarFill)

            Rectangle().fill(IslandChrome.hairline).frame(width: 1)

            sourceDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: runtime.catalogSources.map(\.id), initial: true) { _, ids in
            guard !ids.contains(selectedSourceID) else { return }
            selectedSourceID = runtime.catalogSources.first(where: { $0.kind == .usage })?.id
                ?? ids.first ?? ""
        }
    }

    private func sourceRow(_ entry: SourceListEntry) -> some View {
        let source = entry.source
        let selected = source.id == selectedSourceID
        let state = entry.state
        return Button { selectedSourceID = source.id } label: {
            HStack(spacing: 10) {
                SourceMark(sourceID: source.id, descriptor: source, size: 18, tint: .labelColor)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(IslandChrome.text)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Text(state.title)
                        if entry.usageCount > 0 { Text("· \(entry.usageCount) widgets") }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(state == .stale || state == .needsSetup ? IslandChrome.warning : IslandChrome.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(selected ? IslandChrome.track : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(source.name), \(state.title), used \(entry.usageCount) times")
        .task(id: source.id) { await checkUsageProviderReadiness(for: source) }
    }

    @ViewBuilder
    private var sourceDetail: some View {
        if let source = runtime.catalogSources.first(where: { $0.id == selectedSourceID }) {
            let state = operationalState(for: source)
            SettingsPage(maxWidth: 800, alignment: .top) {
                HStack(spacing: 10) {
                    SourceMark(sourceID: source.id, descriptor: source, size: 18, tint: .labelColor)
                        .frame(width: 28, height: 28)
                    PageTitle(title: source.name)
                    Spacer()
                    if state == .needsSetup || state == .unavailable {
                        SettingsStatusLine(title: state.title, attention: true)
                    }
                    QuietButton(
                        title: "Add widget",
                        symbol: "plus",
                        prominence: .primary
                    ) {
                        browseComplications()
                    }
                    .disabled(state == .needsSetup || state == .unavailable)
                    Menu {
                        Button {
                            _ = runtime.refreshSource(source.id)
                        } label: {
                            Label("Refresh Source", systemImage: "arrow.clockwise")
                        }
                        if let url = runtime.provider(id: source.id)?.dashboardURL ?? source.actionURL {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label(
                                    source.sourceKindID == ConfigurableSourceKind.gitRepository.sourceKindID
                                        ? "Open Repository"
                                        : "Open Dashboard",
                                    systemImage: source.sourceKindID == ConfigurableSourceKind.gitRepository.sourceKindID
                                        ? "folder"
                                        : "arrow.up.forward.app"
                                )
                            }
                        }
                        if let kind = source.configurableKind {
                            Divider()
                            Button {
                                selectedSourceID = runtime.addSource(kind: kind)
                            } label: {
                                Label("Add Another \(kind.title)", systemImage: "plus")
                            }
                            if source.id != kind.sourceKindID {
                                Button(role: .destructive) {
                                    if runtime.removeSource(source.id) {
                                        selectedSourceID = kind.sourceKindID
                                    }
                                } label: {
                                    Label("Remove Source", systemImage: "trash")
                                }
                                .disabled(usageCount(for: source.id) > 0)
                            }
                        }
                    } label: {
                        RowActionGlyph(symbol: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help("Source actions")
                }

                if let brand = ProviderBrand(rawValue: source.id),
                   state == .needsSetup || state == .unavailable {
                    SettingsNotice(text: brand.setupInstruction, style: .warning)
                } else if let error = runtime.snapshot(sourceID: source.id)?.errorDescription {
                    SettingsNotice(text: error, style: .warning)
                }

                if source.id == HarnaisWeeklyStarter.sourceID {
                    HarnaisUsageStatusView(runtime: runtime)
                }

                if hasConfigurationSection(for: source), state == .needsSetup || state == .unavailable {
                    sourceConfigurationSection(source, state: state)
                    SettingsHairline()
                }

                sourceComplicationSection(source)
                    .task(id: source.id) {
                        await loadSelectedUsageSource(source)
                    }

                if hasConfigurationSection(for: source), state != .needsSetup && state != .unavailable {
                    SettingsHairline()
                    sourceConfigurationSection(source, state: state)
                    SettingsHairline()
                }

                SettingsDisclosure(
                    title: "Available data",
                    subtitle: "\(source.metrics.count) values available for custom widgets"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(source.metrics) { metric in
                            HStack(spacing: 9) {
                                Image(systemName: metric.symbol ?? metric.kind.inspectorSymbol)
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(IslandChrome.text)
                                    .frame(width: 26, height: 26)
                                    .background(IslandChrome.fieldFill, in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(metric.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(IslandChrome.text)
                                    Text(metricSourceSummary(metric))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(IslandChrome.tertiaryText)
                                }
                                Spacer()
                                Text(metricDisplayValue(metric, source: source))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(IslandChrome.secondaryText)
                                    .monospacedDigit()
                            }
                            if metric.id != source.metrics.last?.id { SettingsHairline() }
                        }
                    }
                }
                .id(source.id)
            }
        }
    }

    private func sourceComplicationSection(_ source: ComplicationSourceDescriptor) -> some View {
        let recommendations = source.complications.sorted {
            if $0.isFeatured != $1.isFeatured { return $0.isFeatured && !$1.isFeatured }
            if $0.rank != $1.rank { return $0.rank > $1.rank }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return SettingsGroup(title: "Widgets") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(Array(recommendations.prefix(6))) { preset in
                    sourceComplicationCard(source: source, preset: preset)
                }
            }
            if recommendations.count > 6 {
                QuietButton(title: "View All", symbol: "chevron.right") {
                    browseComplications()
                }
            }
        }
    }

    private func hasConfigurationSection(for source: ComplicationSourceDescriptor) -> Bool {
        if let brand = ProviderBrand(rawValue: source.id) {
            return brand.hasInAppConfiguration
        }
        return source.id == "session.claude"
            || source.id == "system.clock"
            || source.id == "productivity.focus"
            || source.sourceKindID == ConfigurableSourceKind.gitRepository.sourceKindID
            || source.sourceKindID == ConfigurableSourceKind.githubRepository.sourceKindID
            || runtime.sourceRegistry.source(id: source.id) is any PermissionComplicationSource
            || source.sourceKindID == ConfigurableSourceKind.healthEndpoint.sourceKindID
            || (runtime.provider(id: source.id) as? ExtensionProvider)?.requiresTrust == true
            || source.kind == .extensionSource
    }

    @ViewBuilder
    private func sourceConfigurationSection(
        _ source: ComplicationSourceDescriptor,
        state: SourceOperationalState
    ) -> some View {
        if let brand = ProviderBrand(rawValue: source.id) {
            ProviderConfigSection(
                runtime: runtime,
                brand: brand,
                expanded: state == .needsSetup || state == .unavailable
            )
            if brand == .claude { claudeSessionLink }
        } else if source.id == "session.claude" {
            SettingsCaption(text: "Receives live session, task, and subagent events from Claude Code.")
            ClaudeHooksSection(runtime: runtime)
        } else if source.id == "system.clock",
                  let clock = runtime.sourceRegistry.source(id: source.id) as? ClockComplicationSource {
            SourceClockControls(source: clock) {
                _ = runtime.refreshSource(source.id)
            }
        } else if source.id == "productivity.focus",
                  let focus = runtime.sourceRegistry.source(id: source.id) as? FocusComplicationSource {
            SourceFocusControls(source: focus) {
                _ = runtime.refreshSource(source.id)
            }
        } else if source.sourceKindID == ConfigurableSourceKind.gitRepository.sourceKindID,
                  let git = runtime.sourceRegistry.source(id: source.id) as? GitComplicationSource {
            SourceGitControls(source: git) {
                _ = runtime.refreshSource(source.id)
            }
        } else if source.sourceKindID == ConfigurableSourceKind.githubRepository.sourceKindID,
                  let github = runtime.sourceRegistry.source(id: source.id) as? GitHubComplicationSource {
            SourceGitHubControls(source: github) {
                _ = runtime.refreshSource(source.id)
            }
        } else if let permissionSource = runtime.sourceRegistry.source(id: source.id) as? any PermissionComplicationSource {
            SourcePermissionControls(source: permissionSource) {
                _ = runtime.refreshSource(source.id)
            }
        } else if source.sourceKindID == ConfigurableSourceKind.healthEndpoint.sourceKindID,
                  let service = runtime.sourceRegistry.source(id: source.id) as? ServiceMonitorComplicationSource {
            SourceServiceControls(source: service) {
                _ = runtime.refreshSource(source.id)
            }
        } else if let extensionProvider = runtime.provider(id: source.id) as? ExtensionProvider,
                  extensionProvider.requiresTrust {
            SourceExtensionTrustControls(provider: extensionProvider) {
                _ = runtime.refreshSource(source.id)
            }
        } else if source.kind == .extensionSource {
            SettingsCaption(text: "Extension parameters come from its manifest and local configuration.")
        }
    }

    private func sourceComplicationCard(
        source: ComplicationSourceDescriptor,
        preset: ComplicationDescriptor
    ) -> some View {
        let state = operationalState(for: source)
        let isAvailable = state == .ready || state == .available || state == .syncing || state == .stale
        return ComplicationRecipeCard(runtime: runtime, source: source, preset: preset, configureSource: {}) {
            if runtime.workspaceStore.selectedIsland == nil { runtime.workspaceStore.addIsland() }
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
            runtime.settingsSection = .islands
        }
        .disabled(!isAvailable)
    }

    private var claudeSessionLink: some View {
        let enabled = JSONSettingsRepository.shared.isHookEnabled()
        let status = enabled ? (HookInstaller.isInstalled() ? "Installed" : "Needs Attention") : "Off"
        return SettingsGroup(
            title: "Linked Source",
            subtitle: "Session tracking is managed by the dedicated Claude Code source."
        ) {
            HStack(spacing: 10) {
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IslandChrome.text)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude Code Sessions")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(IslandChrome.text)
                    SettingsStatusLine(title: status, attention: status == "Needs Attention")
                }
                Spacer(minLength: 10)
                QuietButton(title: "Manage", symbol: "arrow.right", prominence: .primary) {
                    selectedSourceID = "session.claude"
                }
            }
        }
    }

    private func usageCount(for sourceID: String) -> Int {
        sourceUsageCounts[sourceID, default: 0]
    }

    private var sourceUsageCounts: [String: Int] {
        runtime.workspaceStore.workspace.islands
            .flatMap(\.complications)
            .reduce(into: [:]) { counts, complication in
                counts[complication.sourceID, default: 0] += 1
            }
    }

    private func operationalState(for source: ComplicationSourceDescriptor) -> SourceOperationalState {
        if runtime.provider(id: source.id)?.isSyncing == true { return .syncing }
        if let snapshot = runtime.snapshot(sourceID: source.id) {
            switch snapshot.availability.state {
            case .setupRequired, .permissionRequired: return .needsSetup
            case .failed where snapshot.availability.recoveryAction == .configure
                || snapshot.availability.recoveryAction == .openSettings:
                return .needsSetup
            case .temporarilyUnavailable, .unsupported, .failed: return .unavailable
            case .available: break
            }
            if snapshot.errorDescription != nil {
                if source.kind == .system { return .unavailable }
                return .needsSetup
            }
            if !snapshot.values.isEmpty {
                if source.id == HarnaisWeeklyStarter.sourceID,
                   Date().timeIntervalSince(snapshot.capturedAt) > runtime.harnaisStaleAfter { return .stale }
                return .ready
            }
        }
        if source.kind == .usage, providerReadiness[source.id] == false {
            return .needsSetup
        }
        return .available
    }

    private func checkUsageProviderReadiness(for source: ComplicationSourceDescriptor) async {
        guard source.kind == .usage,
              providerReadiness[source.id] == nil,
              let provider = runtime.provider(id: source.id)
        else { return }
        if let snapshot = runtime.snapshot(sourceID: source.id),
           snapshot.availability.state != .available
            || snapshot.errorDescription != nil
            || !snapshot.values.isEmpty {
            return
        }
        providerReadiness[source.id] = await provider.isAvailable()
    }

    private func loadSelectedUsageSource(_ source: ComplicationSourceDescriptor) async {
        guard source.kind == .usage || source.kind == .extensionSource else { return }
        await checkUsageProviderReadiness(for: source)
        if providerReadiness[source.id] == false { return }
        if runtime.snapshot(sourceID: source.id)?.values.isEmpty == false { return }
        _ = await runtime.refreshSource(source.id)?.value
    }

    private func matchesSearch(_ source: ComplicationSourceDescriptor) -> Bool {
        guard !search.isEmpty else { return true }
        let terms = ([source.name, source.settingsDomainName] + source.metrics.map(\.name)).joined(separator: " ")
        return terms.localizedCaseInsensitiveContains(search)
    }

    private func matchesFilter(_ entry: SourceListEntry) -> Bool {
        let source = entry.source
        return switch filter {
        case .all: true
        case .inUse: entry.usageCount > 0
        case .needsSetup:
            [.needsSetup, .unavailable].contains(entry.state)
        case .usage: source.kind == .usage
        case .system: source.id.hasPrefix("system.") && source.id != "system.clock"
        case .time: source.id == "system.clock" || source.id.hasPrefix("calendar.")
        case .session: source.kind == .session
        case .focus: source.id.hasPrefix("productivity.")
        case .developer: source.id.hasPrefix("developer.")
        case .services: source.id.hasPrefix("services.")
        case .extensions: source.kind == .extensionSource
        }
    }

    private func metricDisplayValue(
        _ metric: ComplicationMetricDescriptor,
        source: ComplicationSourceDescriptor
    ) -> String {
        guard let snapshot = runtime.snapshot(sourceID: source.id) else { return "Not loaded" }
        if let value = snapshot.values[metric.id] { return value.displayText }
        if snapshot.availability.state == .setupRequired
            || snapshot.availability.state == .permissionRequired {
            return "After setup"
        }
        return snapshot.errorDescription == nil ? "Not available" : "Unavailable"
    }

    private func metricSourceSummary(_ metric: ComplicationMetricDescriptor) -> String {
        let family: ComplicationFamily = switch metric.kind {
        case .gauge: .ring
        case .status: .status
        case .date: .countdown
        case .duration, .value: .value
        }
        let direction = metric.policy.direction.designName.map { " · \($0)" } ?? ""
        return "\(metric.policy.format.designName) · Best as \(family.displayName)\(direction)"
    }
}
