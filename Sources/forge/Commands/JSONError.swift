import Foundation

/// Structured JSON error envelope for `--json` commands.
///
/// When a command that accepts `--json` encounters a domain error,
/// it can emit a machine-parseable error object on stdout before
/// exiting. ArgumentParser-level errors (missing arguments, unknown
/// flags) are outside this scope and remain plain-text on stderr.
struct ForgeJSONError: Encodable {
    let error: String
    let command: String

    /// Encode and print a JSON error object to stdout.
    static func emit(_ message: String, command: String) {
        let payload = ForgeJSONError(error: message, command: command)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload),
           let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    }
}
