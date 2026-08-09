import Foundation

/// Result of matching a query to Forge folder names or Reminders list titles.
public enum RemindersNameMatch: Equatable, Sendable {
    case ok(String)
    case ambiguous([String])
    case none
}

/// Match Apple Reminders lists to Forge project folders.
///
/// Exact title match (case-insensitive), then `folder_aliases`. No substring
/// matching — `Lab` does not match `Lab-notebook`.
public enum RemindersMatching {
    /// Canonical folder name for an exact (case-insensitive) title, if any.
    public static func canonicalProjectName(_ title: String, projectNames: [String]) -> String? {
        let lower = title.lowercased()
        return projectNames.first { $0.lowercased() == lower }
    }

    /// Resolve a Reminders list title to a Forge folder name.
    ///
    /// Alias targets that do not exist as folders are unmatched.
    public static func matchList(
        title: String,
        projectNames: [String],
        folderAliases: [String: String]
    ) -> String? {
        if let exact = canonicalProjectName(title, projectNames: projectNames) {
            return exact
        }
        guard let aliased = aliasTarget(for: title, aliases: folderAliases) else {
            return nil
        }
        return canonicalProjectName(aliased, projectNames: projectNames)
    }

    /// Resolve a project query: exact (case-insensitive), then unique substring.
    public static func resolveProjectName(_ query: String, in names: [String]) -> RemindersNameMatch {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        let lower = trimmed.lowercased()
        if let exact = names.first(where: { $0.lowercased() == lower }) {
            return .ok(exact)
        }
        let matches = names.filter { $0.lowercased().contains(lower) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if matches.count == 1 { return .ok(matches[0]) }
        if matches.count > 1 { return .ambiguous(matches) }
        return .none
    }

    /// Resolve a Reminders list title query: exact, then unique prefix (not a loose substring).
    public static func resolveListTitle(_ query: String, in titles: [String]) -> RemindersNameMatch {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        let lower = trimmed.lowercased()
        if let exact = titles.first(where: { $0.lowercased() == lower }) {
            return .ok(exact)
        }
        let prefixes = titles.filter { $0.lowercased().hasPrefix(lower) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if prefixes.count == 1 { return .ok(prefixes[0]) }
        if prefixes.count > 1 { return .ambiguous(prefixes) }
        return .none
    }

    /// Build a full inventory from list/reminder drafts and Forge folder names.
    public static func buildInventory(
        generatedAt: Date = Date(),
        lists: [(id: String, title: String)],
        reminders: [ReminderDraft],
        projectNames: [String],
        config: RemindersConfig,
        writer: String = "Forge.app"
    ) -> RemindersInventory {
        let listTitleById = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.title) })
        var matchedByListId: [String: String?] = [:]
        var listRecords: [RemindersListRecord] = []

        for list in lists {
            let matched = matchList(
                title: list.title,
                projectNames: projectNames,
                folderAliases: config.folderAliases
            )
            matchedByListId[list.id] = matched
            let items = reminders.filter { $0.listId == list.id }
            listRecords.append(
                RemindersListRecord(
                    id: list.id,
                    title: list.title,
                    matchedProject: matched,
                    incompleteCount: items.filter { !$0.isCompleted }.count,
                    completedCount: items.filter(\.isCompleted).count
                )
            )
        }

        let reminderRecords: [ReminderRecord] = reminders.map { draft in
            let listTitle = listTitleById[draft.listId] ?? ""
            let matched = matchedByListId[draft.listId] ?? nil
            return ReminderRecord(
                id: draft.id,
                title: draft.title,
                listTitle: listTitle,
                listId: draft.listId,
                isCompleted: draft.isCompleted,
                dueDate: draft.dueDate,
                priority: draft.priority,
                notes: draft.notes,
                matchedProject: matched
            )
        }

        let unmatchedListTitles = listRecords
            .filter { $0.matchedProject == nil }
            .map(\.title)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let matchedFolders = Set(listRecords.compactMap(\.matchedProject).map { $0.lowercased() })
        let unmatchedProjectNames = projectNames
            .filter { !matchedFolders.contains($0.lowercased()) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        return RemindersInventory(
            generatedAt: generatedAt,
            lists: listRecords.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            },
            reminders: reminderRecords,
            unmatchedListTitles: unmatchedListTitles,
            unmatchedProjectNames: unmatchedProjectNames,
            writer: writer
        )
    }

    private static func aliasTarget(for listTitle: String, aliases: [String: String]) -> String? {
        if let exact = aliases[listTitle] {
            return exact
        }
        let lower = listTitle.lowercased()
        return aliases.first { $0.key.lowercased() == lower }?.value
    }
}
