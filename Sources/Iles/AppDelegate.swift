import AppKit
import Infrastructure

/// Accessory-app lifecycle: configured island workspace, Settings, and hook server.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: IslandRuntime?
    private var controller: IslandController?
    private var settingsController: SettingsController?
    private var hookController: HookController?

    public var launchesAtLogin: Bool {
        LaunchAtLogin.isEnabled
    }

    public var usesDemoData: Bool {
        runtime?.usesDemoData == true
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableSuddenTermination()

        if Self.activateExistingInstanceIfNeeded() {
            NSApp.terminate(nil)
            return
        }

        let runtime = IslandRuntime.make()
        self.runtime = runtime
        let controller = IslandController(runtime: runtime)
        self.controller = controller
        self.settingsController = SettingsController(runtime: runtime)
        self.hookController = HookController(runtime: runtime)
        controller.show()
        runtime.start()
        MenuBarIdentityIcon.applyDevelopmentTintIfNeeded()
        hookController?.reconcile()
        if CommandLine.arguments.contains("--open-settings") {
            showSettings()
        }
        Task { @MainActor in
            runtime.attachExtensions()
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.show()
        return false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hookController?.stop()
        runtime?.stop()
        controller?.tearDown()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func refresh() {
        runtime?.refreshNow()
    }

    public func showSettings() {
        settingsController?.show()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        _ = LaunchAtLogin.setEnabled(enabled)
    }

    private static func activateExistingInstanceIfNeeded() -> Bool {
        let identifier = Bundle.main.bundleIdentifier ?? AppIdentity.shippedBundleIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing = others.first else { return false }
        existing.activate()
        return true
    }
}
