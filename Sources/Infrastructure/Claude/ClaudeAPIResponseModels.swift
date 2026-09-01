import Foundation

// MARK: - Response Models

struct UsageResponse: Decodable {
    let fiveHour: UsageQuotaData?
    let sevenDay: UsageQuotaData?
    let sevenDaySonnet: UsageQuotaData?
    let sevenDayOpus: UsageQuotaData?
    let extraUsage: ExtraUsageData?
    let spend: SpendData?
    let limits: [LimitEntry]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage = "extra_usage"
        case spend
        case limits
    }
}

/// Entry in the newer generic `limits` array. Model-scoped limits (e.g. Fable)
/// are reported here as `kind: "weekly_scoped"` with the model in `scope`,
/// instead of dedicated `seven_day_<model>` fields.
struct LimitEntry: Decodable {
    let kind: String?
    let percent: Double?
    let resetsAt: String?
    let scope: LimitScope?

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case resetsAt = "resets_at"
        case scope
    }
}

struct LimitScope: Decodable {
    let model: LimitScopeModel?
}

struct LimitScopeModel: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct UsageQuotaData: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct SpendData: Decodable {
    let used: MoneyData?
    let limit: MoneyData?
    let enabled: Bool?

    /// The decoded (used, cap) pair, or `nil` when the shape is disabled or
    /// invalid. A `nil` cap inside the pair means genuinely uncapped
    /// (`limit` absent or JSON null). A present-but-invalid `limit` poisons
    /// the whole shape instead of silently reading as "no monthly cap".
    var costPair: (used: Decimal, cap: Decimal?)? {
        guard enabled == true, let used = used?.amount else { return nil }
        guard let limit else { return (used, nil) }
        guard let cap = limit.amount else { return nil }
        return (used, cap)
    }
}

struct MoneyData: Decodable {
    let amountMinor: Decimal?
    let currency: String?
    let exponent: Int?

    /// Negative spend is not a valid payload state; reject the row rather
    /// than silently flipping the sign.
    var amount: Decimal? {
        guard let amountMinor, amountMinor >= 0, let exponent, exponent >= 0 else { return nil }
        return Decimal(sign: .plus, exponent: -exponent, significand: amountMinor)
    }

    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency
        case exponent
    }
}

struct ExtraUsageData: Decodable {
    let isEnabled: Bool?
    let usedCredits: Decimal?
    let monthlyLimit: Decimal?
    let decimalPlaces: Int?

    /// Same cap semantics as `SpendData.costPair`: absent/null limit means
    /// uncapped; a present-but-invalid limit invalidates the shape.
    var costPair: (used: Decimal, cap: Decimal?)? {
        guard isEnabled == true, let used = usedAmount else { return nil }
        guard monthlyLimit != nil else { return (used, nil) }
        guard let cap = monthlyLimitAmount else { return nil }
        return (used, cap)
    }

    var usedAmount: Decimal? {
        scaledAmount(usedCredits)
    }

    var monthlyLimitAmount: Decimal? {
        scaledAmount(monthlyLimit)
    }

    private func scaledAmount(_ amount: Decimal?) -> Decimal? {
        guard let amount, amount >= 0 else { return nil }
        let places = decimalPlaces ?? 2
        guard places >= 0 else { return nil }
        return Decimal(sign: .plus, exponent: -places, significand: amount)
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
        case decimalPlaces = "decimal_places"
    }
}

struct TokenRefreshResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct TokenErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
