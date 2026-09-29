import AppKit
import Domain
import Infrastructure
import SwiftUI

struct GeneralSettingsPane: View {
    @Bindable var runtime: IslandRuntime
    private let settings = JSONSettingsRepository.shared
    @AppStorage("settingsAppearance") private var appearance: SettingsAppearance = .system
    @State private var interval: RefreshInterval = .tenMinutes
    @State private var launchAtLogin = false
    @State private var hideBuiltInWhenHarnais = false
    @State private var confirmsLogDeletion = false
    @State private var settingsError: String?

    var body: some View {
        SettingsPage {
            SettingsPageHeader(title: "Settings", subtitle: "Appearance, startup and background updates.")

            IslandCard(padding: 16) {
                SettingsGroup(title: "Appearance", subtitle: "Islands keep their own colors in every appearance.") {
                    IslandSegmentBar(items: SettingsAppearance.allCases, selection: $appearance, title: \.title)
                }
            }

            IslandCard(padding: 0) {
                SettingsToggleRow(title: "Open Iles at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in launchAtLogin = LaunchAtLogin.setEnabled(value) }
            }

            IslandCard(padding: 16) {
                SettingsGroup(title: "Background updates", subtitle: "Applies to network sources. Local data uses its own refresh interval.") {
                    IslandSegmentBar(items: RefreshInterval.allCases, selection: $interval, title: { $0.label })
                        .onChange(of: interval) { _, value in
                            settings.setRefreshInterval(value)
                            runtime.applyRefreshInterval()
                        }
                }
            }

            SettingsDisclosure(title: "Advanced", subtitle: "Standalone AI providers") {
                SettingsToggleRow(title: "Hide standalone providers supplied by Harnais", isOn: $hideBuiltInWhenHarnais)
                    .onChange(of: hideBuiltInWhenHarnais) { _, value in
                        settings.setHideBuiltInAIWhenHarnais(value)
                        runtime.applyHarnaisOverlap()
                    }
            }
            SettingsHairline()

            SettingsDisclosure(
                title: "Diagnostics",
                subtitle: "Logs and local configuration"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    MetricPair(title: "Settings file", value: JSONSettingsStore.defaultFileURL().path)
                    MetricPair(title: "Log file", value: AppIdentity.current.logFileURL.path)
                    if let settingsError {
                        Label(settingsError, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(IslandChrome.error)
                    }
                    SettingsHairline()
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            logLocationActions
                            logExportActions
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            logLocationActions
                            logExportActions
                        }
                    }
                    SettingsCaption(text: "Support logs are redacted, limited in size, and exported only when you choose a destination.")
                }
            }
        }
        .onAppear {
            interval = settings.refreshInterval()
            launchAtLogin = LaunchAtLogin.isEnabled
            hideBuiltInWhenHarnais = settings.hideBuiltInAIWhenHarnais()
            settingsError = JSONSettingsStore.shared.lastErrorDescription
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsStoreError)) { notification in
            settingsError = notification.userInfo?["message"] as? String
        }
        .confirmationDialog(
            "Delete \(AppIdentity.current.displayName) logs?",
            isPresented: $confirmsLogDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Logs", role: .destructive) { AppLog.clearLogs() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the current and rotated local diagnostic logs.")
        }
    }

    private var logLocationActions: some View {
        HStack(spacing: 8) {
            QuietButton(title: "Open Current Log", symbol: "doc.text") { AppLog.openCurrentLogFile() }
            QuietButton(title: "Show Logs in Finder", symbol: "folder") { AppLog.openLogsDirectory() }
        }
        .fixedSize()
    }

    private var logExportActions: some View {
        HStack(spacing: 8) {
            QuietButton(title: "Export Support Log", symbol: "square.and.arrow.up") { exportSupportLog() }
            QuietButton(title: "Clear Logs", symbol: "trash") { confirmsLogDeletion = true }
        }
        .fixedSize()
    }

    private func exportSupportLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = AppIdentity.current.supportLogExportFileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try AppLog.exportCurrentLog(to: destination)
        } catch {
            AppLog.ui.error("Support log export failed: \(error.localizedDescription)")
        }
    }
}

struct AboutSettingsPane: View {
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "14" }
    private var copyright: String { Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "Copyright © 2026" }

    var body: some View {
        SettingsPage {
            SettingsPageHeader(title: "About Iles", subtitle: "Desktop widgets for usage and local data.")
            IslandCard(padding: 0) {
                VStack(spacing: 9) {
                    if let url = Bundle.main.url(forResource: "Iles", withExtension: "icns"),
                       let icon = NSImage(contentsOf: url) {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 80, height: 80)
                            .accessibilityHidden(true)
                    }
                    Text(AppIdentity.current.displayName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(IslandChrome.text)
                    Text(
                        AppIdentity.current.isDevelopment
                            ? "Development build"
                            : "Widgets at your screen’s edge"
                    )
                        .font(.system(size: 14))
                        .foregroundStyle(IslandChrome.secondaryText)
                    Text("Version \(version) (\(build))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(IslandChrome.tertiaryText)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            }

            Text("Your usage data stays on this Mac. Iles has no analytics, advertising, or telemetry.")
                .font(.system(size: 13))
                .foregroundStyle(IslandChrome.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                QuietButton(title: "Source code") {
                    openProjectPage("")
                }
                QuietButton(title: "Privacy") {
                    openProjectPage("blob/main/PRIVACY.md")
                }
                QuietButton(title: "Licenses") {
                    openProjectPage("blob/main/THIRD_PARTY_NOTICES.md")
                }
                QuietButton(title: "Security") {
                    openProjectPage("blob/main/SECURITY.md")
                }
            }
            .frame(maxWidth: .infinity)

            Text(copyright)
                .font(.system(size: 12))
                .foregroundStyle(IslandChrome.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func openProjectPage(_ path: String) {
        let base = "https://github.com/basique-industrie/iles/"
        guard let url = URL(string: base + path) else { return }
        NSWorkspace.shared.open(url)
    }
}
