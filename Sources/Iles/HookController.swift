import Domain
import Foundation
import Infrastructure

/// Starts the local hook server when Claude Code session tracking is enabled.
@MainActor
final class HookController {
    private let runtime: IslandRuntime
    private let server = HookHTTPServer()
    private var serverTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init(runtime: IslandRuntime) {
        self.runtime = runtime
        observer = NotificationCenter.default.addObserver(
            forName: .hookSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile()
            }
        }
    }

    func reconcile() {
        let enabled = JSONSettingsRepository.shared.isHookEnabled()
        if enabled {
            do {
                if !HookInstaller.isInstalled() {
                    try HookInstaller.install()
                }
                start()
            } catch {
                stop()
                AppLog.hooks.error("Hook installation failed: \(error.localizedDescription)")
            }
        } else {
            stop()
            do {
                try HookInstaller.uninstall()
            } catch {
                AppLog.hooks.error("Hook removal failed: \(error.localizedDescription)")
            }
        }
        runtime.sessionTrackingDidChange()
    }

    func start() {
        serverTask?.cancel()
        server.stop()
        serverTask = Task { [runtime, server] in
            do {
                let events = try await server.start()
                AppLog.hooks.info("Hook server started")
                for await event in events {
                    guard !event.isIlesProbe else { continue }
                    runtime.sessionMonitor.processEvent(event)
                    runtime.sessionDidChange()
                }
            } catch {
                AppLog.hooks.error("Hook server failed: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        serverTask?.cancel()
        serverTask = nil
        server.stop()
    }

}
