/// Cursor's dashboard pools. Probes emit these types; the island and Settings
/// look them up — they must not be restated as string literals.
public enum CursorQuotaPool: Sendable {
    public static let modelsName = "Cursor Models"
    public static let otherName = "Other Models"
    public static let monthlyName = QuotaWindowName.monthly
    public static let onDemandName = QuotaWindowName.onDemand
    public static let teamName = QuotaWindowName.team

    public static var models: QuotaType { .timeLimit(modelsName) }
    public static var other: QuotaType { .timeLimit(otherName) }
    public static var monthly: QuotaType { .timeLimit(monthlyName) }
    public static var onDemand: QuotaType { .timeLimit(onDemandName) }
    public static var team: QuotaType { .timeLimit(teamName) }
}
