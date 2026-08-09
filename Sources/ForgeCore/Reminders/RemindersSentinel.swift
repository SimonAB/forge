import Foundation

/// Kanban sentinel reminder: one incomplete item per matched Reminders list.
///
/// Title `Forge · Watch`, notes first line `forge-kanban: Watch`. Ordinary tasks
/// are never treated as sentinels.
public enum RemindersSentinel {
    public static let notesMarker = "forge-kanban:"
    /// EventKit high priority (Reminders.app exclamation). Finder `URGENT` has no Flagged API.
    public static let urgentPriority = 1
    /// EventKit “none” priority.
    public static let nonePriority = 0

    /// Priority written on the kanban sentinel when Finder does or does not carry URGENT.
    public static func priority(isUrgent: Bool) -> Int {
        isUrgent ? urgentPriority : nonePriority
    }

    /// Human-readable sentinel title.
    public static func title(
        column: String,
        prefix: String = RemindersConfig.defaultSentinelPrefix
    ) -> String {
        prefix + column
    }

    /// Notes body whose first line is the parseable marker.
    public static func notes(column: String) -> String {
        "\(notesMarker) \(column)"
    }

    /// True when title or notes look like a Forge sentinel (column may be unknown).
    public static func isSentinel(
        title: String,
        notes: String?,
        prefix: String = RemindersConfig.defaultSentinelPrefix
    ) -> Bool {
        if notesColumn(notes) != nil { return true }
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrefix.isEmpty else { return false }
        return title.lowercased().hasPrefix(trimmedPrefix.lowercased())
    }

    /// Canonical board column name, if this reminder is a sentinel for a known column.
    ///
    /// Notes marker wins over title when both are present.
    public static func parse(
        title: String,
        notes: String?,
        prefix: String = RemindersConfig.defaultSentinelPrefix,
        knownColumns: [String]
    ) -> String? {
        if let fromNotes = notesColumn(notes),
           let canonical = canonicalColumn(fromNotes, known: knownColumns) {
            return canonical
        }
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrefix.isEmpty,
              title.lowercased().hasPrefix(trimmedPrefix.lowercased()) else {
            return nil
        }
        let remainder = String(title.dropFirst(trimmedPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return canonicalColumn(remainder, known: knownColumns)
    }

    private static func notesColumn(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let first = notes.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lower = first.lowercased()
        let marker = notesMarker.lowercased()
        guard lower.hasPrefix(marker) else { return nil }
        let rest = String(first.dropFirst(notesMarker.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    private static func canonicalColumn(_ raw: String, known: [String]) -> String? {
        let lower = raw.lowercased()
        return known.first { $0.lowercased() == lower }
    }
}
