import AppKit
import Infrastructure

/// Menu extra owned by AppKit so Iles Dev can keep a colored mark.
///
/// SwiftUI `MenuBarExtra` restores a template image after launch. Owning the
/// `NSStatusItem` keeps the Dev tint on a public API.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private unowned let appDelegate: AppDelegate
    private let statusItem: NSStatusItem
    private let launchAtLoginItem: NSMenuItem

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        super.init()
        install()
    }

    private func install() {
        let identity = AppIdentity.current
        let button = statusItem.button
        button?.image = MenuBarIdentityIcon.image(for: identity)
        button?.toolTip = identity.displayName
        button?.setAccessibilityTitle(identity.displayName)
        statusItem.menu = makeMenu()
        statusItem.isVisible = true
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let refresh = NSMenuItem(
            title: "Refresh Sources",
            action: #selector(refreshSources),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        let logs = NSMenuItem(
            title: "Open Logs",
            action: #selector(openLogs),
            keyEquivalent: ""
        )
        logs.target = self
        menu.addItem(logs)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit \(AppIdentity.current.displayName)",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginItem.state = appDelegate.launchesAtLogin ? .on : .off
    }

    @objc private func showSettings() {
        appDelegate.showSettings()
    }

    @objc private func refreshSources() {
        appDelegate.refresh()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        appDelegate.setLaunchAtLogin(!appDelegate.launchesAtLogin)
    }

    @objc private func openLogs() {
        AppLog.openLogsDirectory()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
