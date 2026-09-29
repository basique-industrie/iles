import AppKit
import SwiftUI

/// Harnais owns accounts; Iles owns usage refresh and the displayed sample age.
struct HarnaisUsageStatusView: View {
    @Bindable var runtime: IslandRuntime

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.jean.harnais.dev")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.jean.harnais")
    }

    var body: some View {
        let provider = runtime.provider(id: HarnaisWeeklyStarter.sourceID)
        IslandCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Accounts from Harnais")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    QuietButton(title: "Open Harnais", symbol: "arrow.up.forward.app") {
                        if let appURL { NSWorkspace.shared.open(appURL) }
                    }
                    .disabled(appURL == nil)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let snapshot = provider?.snapshot {
                            HStack(spacing: 4) {
                                Text("Updated by Iles")
                                Text(snapshot.capturedAt, style: .relative)
                                Text("ago")
                            }
                            Text("\(snapshot.hiddenQuotaTypes.count) hidden rings")
                        } else {
                            Text(provider?.isSyncing == true ? "Fetching account usage…" : "No usage fetched yet")
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(IslandChrome.secondaryText)
                    Spacer()
                    QuietButton(title: provider?.isSyncing == true ? "Refreshing…" : "Refresh now", symbol: "arrow.clockwise") {
                        _ = runtime.refreshSource(HarnaisWeeklyStarter.sourceID)
                    }
                    .disabled(provider?.isSyncing == true)
                }
                if let error = provider?.lastError {
                    SettingsNotice(text: error.localizedDescription, style: .warning)
                } else if let snapshot = provider?.snapshot,
                          Date().timeIntervalSince(snapshot.capturedAt) > runtime.harnaisStaleAfter {
                    SettingsNotice(text: "Usage has not refreshed recently. Retry here to fetch the latest account limits.", style: .warning)
                }
                SettingsCaption(text: "Manage accounts and ring visibility in Harnais. Iles refreshes usage independently using Background updates in Settings, even when Harnais is closed.")
            }
        }
    }
}
