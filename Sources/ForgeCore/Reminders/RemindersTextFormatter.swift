import Foundation

/// Human-readable Reminders listing used by `forge reminders` and tests.
public enum RemindersTextFormatter {
    /// Label for snapshot vs live EventKit.
    public static func sourceLabel(
        _ source: RemindersInventoryResolution.Source,
        now: Date = Date()
    ) -> String {
        switch source {
        case .forgeAppSnapshot(let generatedAt):
            let age = max(0, Int(now.timeIntervalSince(generatedAt)))
            return "snapshot \(age)s ago"
        case .liveEventKit:
            return "live EventKit"
        }
    }

    /// British medium date, or empty when there is no due date.
    public static func formatDue(
        _ date: Date?,
        locale: Locale = Locale(identifier: "en_GB")
    ) -> String {
        guard let date else { return "" }
        let fmt = DateFormatter()
        fmt.locale = locale
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return "  due \(fmt.string(from: date))"
    }

    /// Incomplete first, then earliest due date, then title.
    public static func sortedReminders(_ items: [ReminderRecord]) -> [ReminderRecord] {
        items.sorted(by: reminderSort)
    }

    /// Full listing text: matched projects, unmatched lists, unmatched folders.
    public static func inventoryText(
        _ inventory: RemindersInventory,
        source: RemindersInventoryResolution.Source,
        listFilter: String? = nil,
        projectFilter: String? = nil,
        now: Date = Date(),
        locale: Locale = Locale(identifier: "en_GB"),
        itemLimit: Int = 40
    ) -> String {
        var lines: [String] = []
        lines.append("Reminders (\(sourceLabel(source, now: now)))")
        lines.append(String(repeating: "─", count: 48))

        var lists = inventory.lists
        var reminders = inventory.reminders
        if let listFilter {
            switch RemindersMatching.resolveListTitle(listFilter, in: lists.map(\.title)) {
            case .ok(let title):
                lists = lists.filter { $0.title == title }
                let ids = Set(lists.map(\.id))
                reminders = reminders.filter { ids.contains($0.listId) }
            case .ambiguous(let matches):
                lines.append(
                    "Ambiguous Reminders list '\(listFilter)': \(matches.joined(separator: ", "))."
                )
                lists = []
                reminders = []
            case .none:
                lines.append("No Reminders list matching '\(listFilter)'.")
                lists = []
                reminders = []
            }
        }
        if let projectFilter {
            lists = lists.filter { $0.matchedProject?.lowercased() == projectFilter.lowercased() }
            reminders = reminders.filter { $0.matchedProject?.lowercased() == projectFilter.lowercased() }
        }

        let matched = lists.filter { $0.matchedProject != nil }
        let unmatched = lists.filter { $0.matchedProject == nil }
        let remindersByList = Dictionary(grouping: reminders, by: \.listId)

        if !matched.isEmpty {
            lines.append("Matched projects")
            for list in matched {
                let project = list.matchedProject ?? list.title
                lines.append("  \(project) (\(list.incompleteCount) incomplete)")
                let items = sortedReminders(remindersByList[list.id] ?? [])
                appendReminderLines(
                    items,
                    to: &lines,
                    locale: locale,
                    itemLimit: itemLimit
                )
            }
            lines.append("")
        }

        if !unmatched.isEmpty {
            lines.append("Inbox / unmatched lists")
            for list in unmatched {
                lines.append("  \(list.title) (\(list.incompleteCount) incomplete)")
                let items = sortedReminders(remindersByList[list.id] ?? [])
                appendReminderLines(
                    items,
                    to: &lines,
                    locale: locale,
                    itemLimit: itemLimit
                )
            }
            lines.append("")
        }

        let unmatchedFolders = inventory.unmatchedProjectNames.filter { name in
            if let projectFilter {
                return name.lowercased() == projectFilter.lowercased()
            }
            return true
        }
        if !unmatchedFolders.isEmpty, listFilter == nil {
            lines.append("Unmatched folders (no Reminders list)")
            for name in unmatchedFolders.prefix(itemLimit) {
                lines.append("  • \(name)")
            }
        }

        if matched.isEmpty, unmatched.isEmpty {
            lines.append("No Reminders lists.")
        }

        while lines.last == "" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func appendReminderLines(
        _ items: [ReminderRecord],
        to lines: inout [String],
        locale: Locale,
        itemLimit: Int
    ) {
        for item in items.prefix(itemLimit) {
            let done = item.isCompleted ? " ✓" : ""
            lines.append("    • \(item.title)\(formatDue(item.dueDate, locale: locale))\(done)")
        }
        if items.count > itemLimit {
            lines.append("    … \(items.count - itemLimit) more")
        }
    }

    private static func reminderSort(_ lhs: ReminderRecord, _ rhs: ReminderRecord) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        switch (lhs.dueDate, rhs.dueDate) {
        case let (l?, r?):
            if l != r { return l < r }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
