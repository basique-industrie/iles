import AppKit
import Infrastructure
import IslandGeometry
import SwiftUI

/// Normal-level Settings window. The island stays above it; this window does not.
@MainActor
final class SettingsController {
    private var window: NSWindow?
    private let runtime: IslandRuntime
    private var settingsObserver: NSObjectProtocol?

    init(runtime: IslandRuntime) {
        self.runtime = runtime
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .showIslandSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.show()
            }
        }
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1240, height: 720),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = AppIdentity.current.displayName
            window.level = .normal
            window.isOpaque = true
            window.backgroundColor = IslandChrome.backgroundNSColor
            window.titlebarAppearsTransparent = true
            window.appearance = nil
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.minSize = NSSize(width: 1120, height: 680)
            let host = ScaleAwareHostingView(rootView: IslandSettingsView(runtime: runtime))
            host.wantsLayer = true
            window.contentView = host
            self.window = window
        }
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if !window.isVisible {
            window.center()
        }
        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
