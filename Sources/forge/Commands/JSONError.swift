import ArgumentParser
import Foundation
import ForgeCore

/// Structured JSON error envelope for `--json` commands.
///
/// When a command that accepts `--json` encounters a domain error,
/// emit a machine-parseable error object on stdout and exit with code 1
/// (via ``throwDomainFailure``). ArgumentParser-level errors (missing
/// arguments, unknown flags) remain plain-text on stderr.
struct ForgeJSONError: Encodable {
    let error: String
    let command: String
    let candidates: [String]?

    enum CodingKeys: String, CodingKey {
        case error, command, candidates
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(error, forKey: .error)
        try container.encode(command, forKey: .command)
        if let candidates, !candidates.isEmpty {
            try container.encode(candidates, forKey: .candidates)
        }
    }

    /// Encode and print a JSON error object to stdout.
    static func emit(_ message: String, command: String, candidates: [String]? = nil) {
        let payload = ForgeJSONError(error: message, command: command, candidates: candidates)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload),
           let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    }

    /// Emit JSON on stdout when `json` is true, otherwise throw `ValidationError`.
    ///
    /// JSON domain failures use exit code 1 and do not reprint via ArgumentParser.
    /// Always throws (typed as `Never` for control-flow).
    static func throwDomainFailure(
        _ message: String,
        command: String,
        json: Bool,
        candidates: [String]? = nil
    ) throws -> Never {
        if json {
            emit(message, command: command, candidates: candidates)
            throw ExitCode(1)
        }
        throw ValidationError(message)
    }
}

/// Result of resolving a project name or unique substring.
enum ProjectMatch {
    case found(Project)
    case none
    case ambiguous([String])
}

/// Resolve a project by exact name, then unique substring (case-insensitive).
func matchProject(named query: String, in projects: [Project]) -> ProjectMatch {
    let lower = query.lowercased()
    if let exact = projects.first(where: { $0.name.lowercased() == lower }) {
        return .found(exact)
    }
    let matches = projects.filter { $0.name.lowercased().contains(lower) }
    if matches.count == 1, let only = matches.first {
        return .found(only)
    }
    if matches.count > 1 {
        return .ambiguous(matches.map(\.name).sorted())
    }
    return .none
}

/// Print human-readable ambiguous-match lines (not for `--json` mode).
func printAmbiguousProjectMatch(query: String, candidates: [String]) {
    print("Ambiguous match for '\(query)':")
    for name in candidates {
        print("  - \(name)")
    }
}
