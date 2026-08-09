import Foundation

/// Chooses an EventKit account for a new reminder list (pure; no EventKit types).
public enum RemindersSourcePicker {
    public enum Kind: Sendable, Equatable {
        case calDAV
        case local
        case exchange
        case other
    }

    public struct Candidate: Sendable, Equatable {
        public let title: String
        public let kind: Kind
        public let hasReminderLists: Bool

        public init(title: String, kind: Kind, hasReminderLists: Bool) {
            self.title = title
            self.kind = kind
            self.hasReminderLists = hasReminderLists
        }

        public var isPreferredAccountKind: Bool {
            kind == .calDAV || kind == .local || kind == .exchange
        }
    }

    public enum Choice: Sendable, Equatable {
        case source(String)
        case requestedNotFound(String)
        case noneAvailable
    }

    /// Pick a source title: explicit name, else an account that already has lists, else local, else first preferred.
    public static func choose(named requested: String?, among candidates: [Candidate]) -> Choice {
        let trimmed = requested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            let lower = trimmed.lowercased()
            if let match = candidates.first(where: { $0.title.lowercased() == lower }) {
                return .source(match.title)
            }
            return .requestedNotFound(trimmed)
        }

        let preferred = candidates.filter(\.isPreferredAccountKind)
        let pool = preferred.isEmpty ? candidates : preferred
        if pool.isEmpty { return .noneAvailable }

        if let withLists = pool.first(where: \.hasReminderLists) {
            return .source(withLists.title)
        }
        if let local = pool.first(where: { $0.kind == .local }) {
            return .source(local.title)
        }
        return .source(pool[0].title)
    }
}
