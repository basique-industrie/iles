import IlesCore
import SwiftUI

@main
struct IlesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The extra is an AppKit status item. This scene only satisfies SwiftUI.
        Window("Iles", id: "iles.keep-alive") {
            EmptyView()
                .frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
