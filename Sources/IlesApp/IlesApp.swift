import AppKit
import Infrastructure
import SwiftUI
import IlesCore

@main
struct IlesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Settings…") {
                appDelegate.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Button("Refresh Sources") {
                appDelegate.refresh()
            }
            .keyboardShortcut("r", modifiers: .command)
            Button(appDelegate.usesDemoData ? "Demo Data" : "Live Data") {}
                .disabled(true)
            Divider()
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { appDelegate.launchesAtLogin },
                    set: { appDelegate.setLaunchAtLogin($0) }
                )
            )
            Button("Open Logs") {
                AppLog.openLogsDirectory()
            }
            Divider()
            Button("Quit \(AppIdentity.current.displayName)") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: MenuBarIdentityIcon.symbolName)
                .renderingMode(AppIdentity.current.isDevelopment ? .original : .template)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(AppIdentity.current.isDevelopment ? Color(nsColor: .systemOrange) : Color.primary)
                .accessibilityLabel(AppIdentity.current.displayName)
        }
    }
}
