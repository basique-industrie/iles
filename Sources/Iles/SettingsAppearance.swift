import AppKit

/// App-local appearance; floating islands retain their explicit dark palette.
enum SettingsAppearance: String, CaseIterable {
    case system, light, dark

    var title: String { rawValue.capitalized }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
