import Foundation

/// Helpers for working with assignee Finder tags (e.g. `#Alice`) on project folders.
public enum AssigneeTag {
    /// Normalise a raw Finder tag into a canonical assignee identifier.
    ///
    /// - Returns: The assignee name without the leading `#`, or nil if the tag is not an assignee tag.
    public static func normalisedIdentifier(fromRawTag tag: String) -> String? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let raw = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }
}

