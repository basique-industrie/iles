import Foundation

/// API region for Alibaba Coding Plan
public enum AlibabaRegion: String, CaseIterable, Sendable {
    case international = "intl"
    case chinaMainland = "cn"

    public var displayName: String {
        switch self {
        case .international:
            "International"
        case .chinaMainland:
            "China Mainland"
        }
    }
}
