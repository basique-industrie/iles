import Foundation

/// Applies a conservative privacy boundary before diagnostics leave process memory.
/// Provider responses and command output must still be logged at debug level only;
/// this redactor is the final safeguard for operational file logs.
enum LogRedactor {
  private static let maximumLength = 1_000

  static func redact(_ message: String) -> String {
    var value = firstLineOnly(message)

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if !home.isEmpty {
      value = value.replacingOccurrences(of: home, with: "~")
    }

    let replacements: [(pattern: String, template: String)] = [
      (#"(?i)(authorization\s*[:=]\s*(?:bearer\s+)?)[^\s,;]+"#, "$1<redacted>"),
      (
        #"(?i)((?:access|refresh|id)?_?token|api[_-]?key|password|secret)\s*[:=]\s*[^\s,;]+"#,
        "$1=<redacted>"
      ),
      (#"(?i)([?&](?:token|key|secret|password)=)[^&\s]+"#, "$1<redacted>"),
      (#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "<redacted-email>"),
      (
        #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b"#,
        "<redacted-id>"
      ),
      (#"\beyJ[A-Za-z0-9_-]{20,}(?:\.[A-Za-z0-9_-]+){1,2}\b"#, "<redacted-token>"),
    ]

    for replacement in replacements {
      value = value.replacingOccurrences(
        of: replacement.pattern,
        with: replacement.template,
        options: [.regularExpression, .caseInsensitive]
      )
    }

    if value.count > maximumLength {
      value = String(value.prefix(maximumLength)) + "… [truncated]"
    }
    return value
  }

  private static func firstLineOnly(_ message: String) -> String {
    guard let newline = message.firstIndex(where: { $0.isNewline }) else {
      return message
    }
    let firstLine = message[..<newline]
    return "\(firstLine) [multiline details omitted]"
  }
}
