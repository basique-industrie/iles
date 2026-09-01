/// Shared quota-window labels emitted by several provider probes.
/// Cursor's dashboard pools live in `CursorQuotaPool` and reuse these names.
public enum QuotaWindowName: Sendable {
    public static let monthly = "Monthly"
    public static let onDemand = "On-Demand"
    public static let team = "Team"

    public static var monthlyQuota: QuotaType { .timeLimit(monthly) }
    public static var onDemandQuota: QuotaType { .timeLimit(onDemand) }
    public static var teamQuota: QuotaType { .timeLimit(team) }
}
