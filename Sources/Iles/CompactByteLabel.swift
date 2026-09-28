import Domain

/// Keeps a storage amount and its unit readable in the narrow island. The
/// original value remains unchanged for details, accessibility and export.
struct CompactByteLabel: Equatable {
    let amount: String
    let unit: String

    init?(value: ComplicationValue) {
        guard case .value(let text, let explicitUnit) = value else { return nil }
        if let explicitUnit, !explicitUnit.isEmpty {
            amount = text
            unit = explicitUnit
        } else {
            let parts = text.split(whereSeparator: \.isWhitespace)
            guard parts.count > 1, let last = parts.last else { return nil }
            amount = parts.dropLast().joined(separator: " ")
            unit = String(last)
        }
    }
}
