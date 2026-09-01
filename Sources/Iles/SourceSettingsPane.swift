import AppKit
import Domain
import Infrastructure
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
    case syncing
    case needsSetup
    case unavailable
    case available

    var title: String {
        switch self {
        case .ready: "Ready"
        case .syncing: "Syncing"
        case .needsSetup: "Needs Setup"
        case .unavailable: "Unavailable"
        case .available: "Available"
        }
    }

    var symbol: String {
        switch self {
        case .ready: "circle.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .needsSetup: "exclamationmark.circle.fill"
        case .unavailable: "xmark.circle.fill"
        case .available: "circle"
        }
    }
}

private struct SourceStateAccessory: View {
    let state: SourceOperationalState

    @ViewBuilder
    var body: some View {
        switch state {
        case .ready, .available:
            EmptyView()
        case .syncing:
            statusBadge("Syncing", symbol: state.symbol)
        case .needsSetup:
            statusBadge("Setup", symbol: state.symbol)
        case .unavailable:
            statusBadge("Offline", symbol: state.symbol)
        }
    }

    private func statusBadge(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(IslandChrome.secondaryText)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(IslandChrome.fieldFill, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(IslandChrome.controlBorder.opacity(0.72), lineWidth: 1)
            }
            .accessibilityLabel(state.title)
            .help(state.title)
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
        return runtime.sourceRegistry.descriptors.enumerated().compactMap { index, source in
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
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(IslandChrome.secondaryText)
                                .frame(width: 26, height: 26)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .accessibilityLabel("Add source")
                        .help("Add another Git, GitHub, or health source")
                    }
                    HStack(spacing: 7) {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(IslandChrome.tertiaryText)
                            TextField("Search sources", text: $search)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 32)
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
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
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
            .frame(width: IslandChrome.sidebarWidth)
            .background(IslandChrome.sidebarFill)

            Rectangle().fill(IslandChrome.hairline).frame(width: 1)

            sourceDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func sourceRow(_ entry: SourceListEntry) -> some View {
        let source = entry.source
        let selected = source.id == selectedSourceID
        let count = entry.usageCount
        let state = entry.state
        return Button { selectedSourceID = source.id } label: {
            HStack(spacing: 8) {
                SourceMark(sourceID: source.id, descriptor: source, size: 13)
                    .frame(width: 24, height: 24)
                    .background(IslandChrome.fieldFill, in: Circle())
                Text(source.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                HStack(spacing: 5) {
                    if count > 0 {
                        Text("\(count)×")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(IslandChrome.secondaryText)
                            .padding(.horizontal, 5)
                            .frame(height: 18)
                            .background(IslandChrome.fieldFill, in: Capsule(style: .continuous))
                    }
                    SourceStateAccessory(state: state)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(
                selected
                    ? IslandChrome.selectedFill
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? IslandChrome.selectionBorder : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(source.name), \(source.settingsDomainName), \(state.title)\(count > 0 ? ", used \(count) times" : "")")
        .task(id: source.id) {
            await checkUsageProviderReadiness(for: source)
        }
    }

    @ViewBuilder
    private var sourceDetail: some View {
        if let source = runtime.descriptor(sourceID: selectedSourceID) {
            let state = operationalState(for: source)
            SettingsPage(maxWidth: 800, alignment: .top) {
                HStack(spacing: 10) {
                    SourceMark(sourceID: source.id, descriptor: source, size: 18)
                        .frame(width: 28, height: 28)
                    PageTitle(title: source.name)
                    Spacer()
                    if state == .needsSetup || state == .unavailable {
                        SettingsStatusLine(title: state.title, attention: true)
                    }
                    QuietButton(
                        title: "Add",
                        symbol: "plus",
                        prominence: .primary
                    ) {
                        browseComplications()
                    }
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

                sourceComplicationSection(source)

                if hasConfigurationSection(for: source) {
                    SettingsHairline()
                    sourceConfigurationSection(source, state: state)
                    SettingsHairline()
                }

                SettingsDisclosure(
                    title: "Advanced Metrics",
                    subtitle: "\(source.metrics.count) raw values available to complication designs"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(source.metrics) { metric in
                            HStack(spacing: 9) {
                                Image(systemName: metric.symbol ?? metric.kind.inspectorSymbol)
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(IslandChrome.fieldFill, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(metric.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white)
                                    Text(metricSourceSummary(metric))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(IslandChrome.tertiaryText)
                                }
                                Spacer()
                                Text(metricDisplayValue(metric, source: source))
                                    .font(.system(size: 11, weight: .semibold))
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
        return SettingsGroup(title: "Complications") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(recommendations.prefix(6))) { preset in
                        sourceComplicationCard(source: source, preset: preset)
                    }
                }
                .padding(.vertical, 1)
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
        let preview = ComplicationConfiguration(
            recipeID: preset.id,
            sourceID: source.id,
            metricIDs: preset.metricIDs,
            family: preset.family,
            labelStyle: preset.labelStyle,
            tint: preset.tint,
            tapAction: preset.tapAction
        )
        let live = runtime.values(for: preview)
        let fixture = ComplicationPreviewFixture.values(for: preset, sourceID: source.id)
        let previewValues = live.isEmpty ? fixture : live
        let state = operationalState(for: source)
        let isAvailable = state == .ready || state == .available || state == .syncing

        return Button {
            guard isAvailable,
                  let islandID = runtime.workspaceStore.selectedIslandID
            else { return }
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
        } label: {
            HStack(spacing: 9) {
                ComplicationSlotView(
                    complication: preview,
                    descriptor: source,
                    values: previewValues,
                    sourceError: live.isEmpty ? nil : runtime.snapshot(sourceID: source.id)?.errorDescription,
                    quality: live.isEmpty ? .cached : runtime.quality(for: preview),
                    trendDirection: live.isEmpty ? .unknown : runtime.trendDirection(for: preview),
                    renderScale: 0.98
                )
                .frame(width: 52, height: 58)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(preset.family.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(IslandChrome.secondaryText)
                }
                Spacer(minLength: 2)
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(IslandChrome.secondaryText)
            }
            .padding(.horizontal, 10)
            .frame(width: 190, height: 68)
            .background(IslandChrome.fieldFill, in: RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous)
                    .strokeBorder(IslandChrome.controlBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.5)
        .help(isAvailable ? preset.question : "Finish source setup before adding this complication")
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
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code Sessions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
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
            if !snapshot.values.isEmpty { return .ready }
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
