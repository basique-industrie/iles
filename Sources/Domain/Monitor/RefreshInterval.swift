import Foundation

/// The user-facing cadence for refreshing provider usage in the background.
///
/// "Off" disables scheduled refresh. The remaining cases map to a 60, 300,
/// 600, or 900-second poll. One minute is the floor to avoid excessive energy
/// use; ten minutes is the default.
public enum RefreshInterval: String, Sendable, Equatable, CaseIterable {
    case off
    case oneMinute
    case fiveMinutes
    case tenMinutes
    case fifteenMinutes

    /// The poll interval in seconds, or `nil` when refresh is off.
    public var seconds: Int? {
        switch self {
        case .off: nil
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .tenMinutes: 600
        case .fifteenMinutes: 900
        }
    }

    /// Short label for the settings picker.
    public var label: String {
        switch self {
        case .off: "Off"
        case .oneMinute: "1 min"
        case .fiveMinutes: "5 min"
        case .tenMinutes: "10 min"
        case .fifteenMinutes: "15 min"
        }
    }
}
