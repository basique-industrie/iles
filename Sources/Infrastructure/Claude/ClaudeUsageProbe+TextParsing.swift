import Domain
import Foundation

extension ClaudeUsageProbe {
    // MARK: - Text Parsing Helpers

    /// Renders raw terminal output into clean text using SwiftTerm.
    /// Properly handles cursor movements, screen clearing, and other control sequences.
    internal func renderTerminalOutput(_ text: String) -> String {
        terminalRenderer.render(text)
    }

    internal func extractPercent(labelSubstring: String, text: String) -> Int? {
        let lines = text.components(separatedBy: .newlines)
        let label = labelSubstring.lowercased()

        for (idx, line) in lines.enumerated() where line.lowercased().contains(label) {
            let window = lines.dropFirst(idx).prefix(12)
            for candidate in window {
                if let pct = percentFromLine(candidate) {
                    return pct
                }
            }
        }
        return nil
    }

    internal func extractPercent(labelSubstrings: [String], text: String) -> Int? {
        for label in labelSubstrings {
            if let value = extractPercent(labelSubstring: label, text: text) {
                return value
            }
        }
        return nil
    }

    internal func percentFromLine(_ line: String) -> Int? {
        let pattern = #"([0-9]{1,3})\s*%\s*(used|left)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 3,
              let valRange = Range(match.range(at: 1), in: line),
              let kindRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        let rawVal = Int(line[valRange]) ?? 0
        let isUsed = line[kindRange].lowercased().contains("used")
        return isUsed ? max(0, 100 - rawVal) : rawVal
    }

    internal func extractReset(labelSubstring: String, text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        let label = labelSubstring.lowercased()

        for (idx, line) in lines.enumerated() where line.lowercased().contains(label) {
            let window = lines.dropFirst(idx).prefix(14)
            for candidate in window {
                let lower = candidate.lowercased()
                // Look for "resets" or time indicators like "2h" or "30m"
                if lower.contains("reset") ||
                   (lower.contains("in") && (lower.contains("h") || lower.contains("m"))) {
                    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    return deduplicateResetText(trimmed)
                }
            }
        }
        return nil
    }

    /// Removes duplicate "Resets..." text caused by terminal redraw artifacts.
    ///
    /// The Claude CLI redraws the screen using cursor positioning. Wide Unicode characters
    /// (progress bar blocks) can cause column misalignment, resulting in the reset text
    /// being appended to itself on a single line, e.g.:
    /// `"Resets 4:59pm (America/New_York)Resets 4:59pm (America/New_York)"`
    ///
    /// This method detects such duplication and returns only the last occurrence.
    internal func deduplicateResetText(_ text: String) -> String {
        // Find all positions where "Resets" (case-insensitive) starts in the original text
        var positions: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let range = text.range(of: "resets", options: .caseInsensitive, range: searchStart..<text.endIndex) {
            positions.append(range)
            searchStart = text.index(after: range.lowerBound)
        }

        // If there's more than one "Resets", take the last occurrence
        if positions.count > 1, let lastRange = positions.last {
            return String(text[lastRange.lowerBound...]).trimmingCharacters(in: .whitespaces)
        }

        return text
    }

    internal func extractEmail(text: String) -> String? {
        // Try old format first: "Account: email" or "Email: email"
        let oldPattern = #"(?i)(?:Account|Email):\s*([^\s@]+@[^\s@]+)"#
        if let email = extractFirst(pattern: oldPattern, text: text) {
            return email
        }

        // Try header format: "Opus 4.5 · Claude Max · email@example.com's Organization"
        // Stop at apostrophe (') to not capture the "'s" part
        let headerPattern = #"·\s*Claude\s+(?:Max|Pro)\s*·\s*([^\s@]+@[^\s@']+)"#
        return extractFirst(pattern: headerPattern, text: text)
    }

    internal func extractOrganization(text: String) -> String? {
        // Try old format first: "Organization: org" or "Org: org"
        let oldPattern = #"(?i)(?:Org|Organization):\s*([^\n]+)"#
        if let org = extractFirst(pattern: oldPattern, text: text) {
            return org.trimmingCharacters(in: .whitespaces)
        }

        // Try header format: "Opus 4.5 · Claude Max · email@example.com's Organization"
        // or "Opus 4.5 · Claude Pro · Organization"
        let headerPattern = #"·\s*Claude\s+(?:Max|Pro)\s*·\s*([^\n]+)"#
        if let match = extractFirst(pattern: headerPattern, text: text) {
            return match.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    internal func extractLoginMethod(text: String) -> String? {
        let pattern = #"(?i)login\s+method:\s*([^\n]+)"#
        return extractFirst(pattern: pattern, text: text)?.trimmingCharacters(in: .whitespaces)
    }

    internal func extractFirst(pattern: String, text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        // Terminal renderer pads lines with spaces - always trim the result
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    internal func cleanResetText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // If it doesn't start with "Resets", add it
        if trimmed.lowercased().hasPrefix("reset") {
            return trimmed
        }
        return "Resets \(trimmed)"
    }

    internal func parseResetDate(_ text: String?) -> Date? {
        guard let text else { return nil }

        // Try relative duration first: "2h 15m", "30m", "2d"
        if let relativeDate = parseRelativeDuration(text) {
            return relativeDate
        }

        // Try absolute date/time: "4:59pm (America/New_York)", "Jan 15, 3:30pm (TZ)", etc.
        return parseAbsoluteDate(text)
    }

    /// Parses relative duration strings like "2h 15m", "30m", "2d"
    func parseRelativeDuration(_ text: String) -> Date? {
        var totalSeconds: TimeInterval = 0

        // Extract days: "2d" or "2 d" or "2 days"
        if let dayMatch = text.range(of: #"(\d+)\s*d(?:ays?)?"#, options: .regularExpression) {
            let dayStr = String(text[dayMatch])
            if let days = Int(dayStr.filter { $0.isNumber }) {
                totalSeconds += Double(days) * 24 * 3600
            }
        }

        // Extract hours: "2h" or "2 h" or "2 hours"
        if let hourMatch = text.range(of: #"(\d+)\s*h(?:ours?|r)?"#, options: .regularExpression) {
            let hourStr = String(text[hourMatch])
            if let hours = Int(hourStr.filter { $0.isNumber }) {
                totalSeconds += Double(hours) * 3600
            }
        }

        // Extract minutes: "15m" or "15 m" or "15 min" or "15 minutes"
        if let minMatch = text.range(of: #"(\d+)\s*m(?:in(?:utes?)?)?"#, options: .regularExpression) {
            let minStr = String(text[minMatch])
            if let minutes = Int(minStr.filter { $0.isNumber }) {
                totalSeconds += Double(minutes) * 60
            }
        }

        if totalSeconds > 0 {
            return Date().addingTimeInterval(totalSeconds)
        }

        return nil
    }

    /// Parses absolute date/time strings from Claude CLI output.
    ///
    /// Handles these formats (all optionally followed by a timezone in parentheses):
    /// - Time-only: "4:59pm", "3pm", "9pm"
    /// - Month + day: "Dec 28"
    /// - Month + day + time: "Jan 15, 3:30pm" or "Dec 25 at 4:59am"
    /// - Month + day + year + time: "Jan 1, 2026 (America/New_York)"
    func parseAbsoluteDate(_ text: String) -> Date? {
        // Extract timezone identifier from parentheses, e.g., "(America/New_York)"
        let timeZone = extractTimeZone(from: text)

        // Strip everything up to and including the last "Resets" token (case-insensitive),
        // then remove any trailing timezone in parentheses.
        // Using the *last* occurrence handles both start-of-line "Resets Jan 1, 2026"
        // and mid-line "$5.41 ... · Resets Jan 1, 2026 (America/New_York)".
        var cleaned = text

        // Strip trailing "NN% used" or "NN% left" — in newer CLI formats the reset text
        // and percentage share the same line (e.g., "Resets 3pm (Europe/Amsterdam)  27% used")
        cleaned = cleaned
            .replacingOccurrences(of: #"\s+\d{1,3}%\s*(?:used|left)\s*$"#, with: "", options: .regularExpression)

        if let lastResets = cleaned.range(of: "resets", options: [.caseInsensitive, .backwards]) {
            cleaned = String(cleaned[lastResets.upperBound...])
        }
        cleaned = cleaned
            .replacingOccurrences(of: #"\s*\([^)]+\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // Normalize "at" separator: "Dec 25 at 4:59am" -> "Dec 25, 4:59am"
        cleaned = cleaned.replacingOccurrences(of: #"\s+at\s+"#, with: ", ", options: .regularExpression)

        // Try date formats from most specific to least specific
        let formats: [String] = [
            "MMM d, yyyy, h:mma",   // "Jan 1, 2026, 3:30pm" (with year and minutes)
            "MMM d, yyyy, ha",      // "Jan 1, 2026, 3pm" (with year, no minutes)
            "MMM d, yyyy",          // "Jan 1, 2026" (date with year only)
            "MMM d, h:mma",         // "Jan 15, 3:30pm" (date with minutes)
            "MMM d, ha",            // "Jan 15, 4pm" (date without minutes)
            "h:mma",               // "4:59pm" (time-only with minutes)
            "ha",                  // "3pm" (time-only, no minutes)
            "MMM d",               // "Dec 28" (date only)
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? .current

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return resolveToFutureDate(date, format: format, timeZone: formatter.timeZone)
            }
        }

        return nil
    }

    /// Extracts a timezone identifier from parenthesized text, e.g., "(America/New_York)"
    func extractTimeZone(from text: String) -> TimeZone? {
        guard let match = text.range(of: #"\(([^)]+)\)"#, options: [.regularExpression, .backwards]) else {
            return nil
        }
        let content = String(text[match])
            .dropFirst() // remove "("
            .dropLast()  // remove ")"
        let identifier = String(content).trimmingCharacters(in: .whitespaces)
        return TimeZone(identifier: identifier)
    }

    /// Resolves a parsed date to the next future occurrence.
    ///
    /// DateFormatter gives us a date with components that may be in the past
    /// (e.g., "3pm" today but it's already 5pm, or "Dec 25" but it's Dec 26).
    /// This method adjusts to the next occurrence.
    func resolveToFutureDate(_ parsedDate: Date, format: String, timeZone: TimeZone) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let now = Date()

        let hasYear = format.contains("yyyy")
        let hasMonth = format.contains("MMM")
        let hasTime = format.contains("h") || format.contains("H")

        if hasYear {
            // Explicit year provided — use as-is (e.g., "Jan 1, 2026")
            return parsedDate
        }

        if hasMonth && hasTime {
            // Has month, day, and time (e.g., "Jan 15, 3:30pm")
            // Set the year to current or next year
            var components = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: parsedDate)
            components.year = calendar.component(.year, from: now)
            if let candidate = calendar.date(from: components), candidate > now {
                return candidate
            }
            // Already past this year — try next year
            components.year = calendar.component(.year, from: now) + 1
            return calendar.date(from: components) ?? parsedDate
        }

        if hasMonth {
            // Date only, no time (e.g., "Dec 28") — assume start of day
            var components = calendar.dateComponents([.month, .day], from: parsedDate)
            components.hour = 0
            components.minute = 0
            components.second = 0
            components.year = calendar.component(.year, from: now)
            if let candidate = calendar.date(from: components), candidate > now {
                return candidate
            }
            components.year = calendar.component(.year, from: now) + 1
            return calendar.date(from: components) ?? parsedDate
        }

        if hasTime {
            // Time-only (e.g., "3pm", "4:59pm") — resolve to today or tomorrow
            let parsedComponents = calendar.dateComponents([.hour, .minute, .second], from: parsedDate)
            var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
            todayComponents.hour = parsedComponents.hour
            todayComponents.minute = parsedComponents.minute
            todayComponents.second = parsedComponents.second
            if let candidate = calendar.date(from: todayComponents), candidate > now {
                return candidate
            }
            // Already past today — use tomorrow
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                todayComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
                todayComponents.hour = parsedComponents.hour
                todayComponents.minute = parsedComponents.minute
                todayComponents.second = parsedComponents.second
                return calendar.date(from: todayComponents) ?? parsedDate
            }
        }

        return parsedDate
    }

}
