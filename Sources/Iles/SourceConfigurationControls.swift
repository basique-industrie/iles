import AppKit
import Domain
import Infrastructure
import SwiftUI

struct SourceFocusControls: View {
    let source: FocusComplicationSource
    let didChange: () -> Void
    @State private var dailyGoal: Double

    init(source: FocusComplicationSource, didChange: @escaping () -> Void) {
        self.source = source
        self.didChange = didChange
        _dailyGoal = State(initialValue: Double(source.dailyGoalMinutes))
    }

    var body: some View {
        SettingsGroup(
            title: "Focus Timer",
            subtitle: source.currentMode == .idle ? "Ready for a new interval" : "An interval is currently running"
        ) {
            HStack(spacing: 8) {
                QuietButton(title: "Focus 25m", symbol: "scope", prominence: .primary) {
                    source.startFocus(minutes: 25)
                    didChange()
                }
                QuietButton(title: "Focus 50m", symbol: "scope") {
                    source.startFocus(minutes: 50)
                    didChange()
                }
                QuietButton(title: "Break 5m", symbol: "cup.and.saucer") {
                    source.startBreak(minutes: 5)
                    didChange()
                }
                QuietButton(title: "Stop", symbol: "stop.fill", role: .destructive) {
                    source.stop()
                    didChange()
                }
            }

            SettingsHairline()
            HStack {
                Text("Daily goal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IslandChrome.secondaryText)
                Spacer()
                Text(CompactDurationFormatter.hoursMinutes(
                    TimeInterval(dailyGoal * 60),
                    includesZeroMinutes: false
                ))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IslandChrome.text)
                    .monospacedDigit()
            }
            SettingsSlider(
                value: $dailyGoal,
                range: 30...480,
                step: 15
            ) { editing in
                guard !editing else { return }
                source.setDailyGoal(minutes: Int(dailyGoal.rounded()))
                didChange()
            }
            .accessibilityLabel("Daily goal")
            .accessibilityValue("\(Int(dailyGoal)) minutes")
        }
    }
}

struct SourceClockControls: View {
    let source: ClockComplicationSource
    let didChange: () -> Void
    @State private var startHour: Int
    @State private var endHour: Int

    init(source: ClockComplicationSource, didChange: @escaping () -> Void) {
        self.source = source
        self.didChange = didChange
        _startHour = State(initialValue: source.workdayStartHour)
        _endHour = State(initialValue: source.workdayEndHour)
    }

    var body: some View {
        SettingsGroup(
            title: "Workday",
            subtitle: "Used by Workday Progress; local time and calendar rules apply."
        ) {
            HStack(spacing: 8) {
                hourMenu(title: "Starts", selection: $startHour, range: 0...22)
                hourMenu(title: "Ends", selection: $endHour, range: (startHour + 1)...23)
            }
        }
        .onChange(of: startHour) { _, value in
            if endHour <= value { endHour = min(value + 1, 23) }
            save()
        }
        .onChange(of: endHour) { _, _ in save() }
    }

    private func hourMenu(
        title: String,
        selection: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Menu {
            ForEach(Array(range), id: \.self) { hour in
                Button {
                    selection.wrappedValue = hour
                } label: {
                    if selection.wrappedValue == hour {
                        Label(Self.hourLabel(hour), systemImage: "checkmark")
                    } else {
                        Text(Self.hourLabel(hour))
                    }
                }
            }
        } label: {
            SettingsMenuLabel(symbol: "clock", title: "\(title) · \(Self.hourLabel(selection.wrappedValue))")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private func save() {
        source.setWorkday(startHour: startHour, endHour: endHour)
        didChange()
    }

    private static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}

struct SourceGitControls: View {
    let source: GitComplicationSource
    let didChange: () -> Void

    var body: some View {
        SettingsGroup(
            title: "Repository",
            subtitle: source.repositoryPath ?? "Choose the repository Iles should monitor."
        ) {
            HStack {
                Spacer()
                if source.repositoryPath != nil {
                    QuietButton(title: "Clear", symbol: "xmark", role: .destructive) {
                        source.clearRepository()
                        didChange()
                    }
                }
                QuietButton(
                    title: source.repositoryPath == nil ? "Choose…" : "Change…",
                    symbol: "folder",
                    prominence: .primary
                ) {
                    chooseRepository()
                }
            }
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Git Repository"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            source.setRepository(url)
            didChange()
        }
    }
}

struct SourceGitHubControls: View {
    let source: GitHubComplicationSource
    let didChange: () -> Void
    @State private var query: String
    @State private var listings: [GitHubRepositoryChoice] = []
    @State private var loadState: LoadState = .loading
    @State private var validationMessage: String?

    private enum LoadState: Equatable {
        case loading
        case ready
        case unauthenticated
        case failed(String)
    }

    init(source: GitHubComplicationSource, didChange: @escaping () -> Void) {
        self.source = source
        self.didChange = didChange
        _query = State(initialValue: source.repositoryText)
    }

    var body: some View {
        SettingsGroup(
            title: "Repository",
            subtitle: "Uses your existing GitHub CLI login; no token is stored."
        ) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IslandChrome.tertiaryText)
                    TextField("Search or enter owner/repository", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(IslandChrome.text)
                        .onSubmit(selectTypedRepository)
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
                QuietIconButton(
                    symbol: "arrow.clockwise",
                    accessibilityName: "Reload repositories",
                    helpText: "Reload repositories from GitHub CLI"
                ) {
                    Task { await loadRepositories() }
                }
            }

            repositoryList

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IslandChrome.error)
            }

            if source.repository != nil {
                HStack {
                    Spacer()
                    QuietButton(title: "Clear", symbol: "xmark", role: .destructive) {
                        source.clearRepository()
                        query = ""
                        validationMessage = nil
                        didChange()
                    }
                }
            }
        }
        .task {
            await loadRepositories()
        }
    }

    @ViewBuilder
    private var repositoryList: some View {
        switch loadState {
        case .loading:
            SettingsCaption(text: "Loading repositories from GitHub CLI…")
                .padding(.vertical, 8)
        case .unauthenticated:
            SettingsCaption(text: "GitHub CLI is missing or not authenticated. Install gh and run gh auth login.")
        case .failed(let message):
            SettingsCaption(text: message)
        case .ready:
            let rows = visibleListings
            if rows.isEmpty {
                SettingsCaption(text: emptyListMessage)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { listing in
                            repositoryRow(listing)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private var visibleListings: [GitHubRepositoryChoice] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = needle.isEmpty
            ? listings
            : listings.filter { $0.nameWithOwner.localizedCaseInsensitiveContains(needle) }
        guard let typed = GitHubComplicationSource.selectableRepository(from: needle),
              !filtered.contains(where: { $0.nameWithOwner.compare(typed, options: .caseInsensitive) == .orderedSame })
        else { return filtered }
        return [GitHubRepositoryChoice(nameWithOwner: typed, isPrivate: false)] + filtered
    }

    private var emptyListMessage: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No repositories were returned for this GitHub login."
            : "No repositories match this search. Press Return to use owner/repository."
    }

    private func repositoryRow(_ listing: GitHubRepositoryChoice) -> some View {
        let selected = source.repository?.compare(listing.nameWithOwner, options: .caseInsensitive) == .orderedSame
        return Button {
            select(listing.nameWithOwner)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: listing.isPrivate ? "lock.fill" : "book.closed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IslandChrome.tertiaryText)
                    .frame(width: 14)
                Text(listing.nameWithOwner)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(IslandChrome.text)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IslandChrome.text)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(
                selected ? IslandChrome.selectedFill : Color.clear,
                in: RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: IslandChrome.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func loadRepositories() async {
        loadState = .loading
        switch await source.listAccessibleRepositories() {
        case .repositories(let repositories):
            listings = repositories
            if let current = source.repository,
               !listings.contains(where: {
                   $0.nameWithOwner.compare(current, options: .caseInsensitive) == .orderedSame
               }) {
                listings.insert(GitHubRepositoryChoice(nameWithOwner: current, isPrivate: false), at: 0)
            }
            loadState = .ready
        case .unauthenticated:
            listings = []
            loadState = .unauthenticated
        case .failed(let message):
            listings = []
            loadState = .failed(message)
        }
    }

    private func select(_ raw: String) {
        if source.setRepository(raw) {
            query = source.repositoryText
            validationMessage = nil
            didChange()
        } else {
            validationMessage = "Enter owner/repository or a GitHub repository URL."
        }
    }

    private func selectTypedRepository() {
        select(query)
    }
}

struct SourcePermissionControls: View {
    let source: any PermissionComplicationSource
    let didChange: () -> Void

    var body: some View {
        SettingsGroup(
            title: source.permissionName,
            subtitle: "Permission is requested only when you choose to connect this source."
        ) {
            HStack(spacing: 10) {
                SettingsStatusLine(
                    title: source.permissionStatusText,
                    attention: source.permissionStatusText != "Connected"
                )
                Spacer()
                permissionAction
            }
        }
    }

    @ViewBuilder
    private var permissionAction: some View {
        if source.canRequestPermission {
            QuietButton(title: "Connect", symbol: "lock.open", prominence: .primary) {
                Task { @MainActor in
                    _ = await source.requestPermission()
                    didChange()
                }
            }
        } else if source.permissionStatusText != "Connected" {
            QuietButton(title: "Open Settings", symbol: "gear") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
        }
    }
}

struct SourceServiceControls: View {
    let source: ServiceMonitorComplicationSource
    let didChange: () -> Void
    @State private var endpoint: String
    @State private var validationMessage: String?

    init(source: ServiceMonitorComplicationSource, didChange: @escaping () -> Void) {
        self.source = source
        self.didChange = didChange
        _endpoint = State(initialValue: source.endpointText)
    }

    var body: some View {
        SettingsGroup(
            title: "Health Endpoint",
            subtitle: "Sends a HEAD request and stores only the latest samples locally."
        ) {
            IslandTextField(
                title: "Endpoint",
                text: $endpoint,
                prompt: "https://status.example.com/health",
                validationMessage: validationMessage
            ) {
                saveEndpoint()
            }
            if source.endpoint != nil {
                HStack {
                    Spacer()
                    QuietButton(title: "Clear", symbol: "xmark", role: .destructive) {
                        source.clearEndpoint()
                        endpoint = ""
                        validationMessage = nil
                        didChange()
                    }
                }
            }
        }
    }

    private func saveEndpoint() {
        if source.setEndpoint(endpoint) {
            validationMessage = nil
            didChange()
        } else {
            validationMessage = "Enter a complete HTTP or HTTPS URL."
        }
    }
}

struct SourceExtensionTrustControls: View {
    let provider: ExtensionProvider
    let didChange: () -> Void

    var body: some View {
        SettingsDisclosure(
            title: "Local Extension Trust",
            subtitle: provider.isTrusted
                ? "Trusted for this extension fingerprint"
                : "Review scripts before enabling them",
            expanded: !provider.isTrusted
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(provider.scriptCommands, id: \.self) { command in
                    commandRow(command)
                }
                HStack {
                    SettingsCaption(text: "Fingerprint \(String(provider.fingerprint.prefix(12)))… · timeout and 1 MB output limits apply.")
                    Spacer()
                    trustAction
                }
            }
        }
    }

    private func commandRow(_ command: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IslandChrome.secondaryText)
            Text(command)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(IslandChrome.text)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(8)
        .background(IslandChrome.fieldFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var trustAction: some View {
        if provider.isTrusted {
            QuietButton(title: "Revoke Trust", symbol: "lock", role: .destructive) {
                provider.setTrusted(false)
                didChange()
            }
        } else {
            QuietButton(title: "Trust Extension", symbol: "lock.open", prominence: .primary) {
                provider.setTrusted(true)
                didChange()
            }
        }
    }
}
