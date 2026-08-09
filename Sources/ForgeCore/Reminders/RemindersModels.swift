import Foundation

/// One Apple Reminders list (`EKCalendar` of type reminder).
public struct RemindersListRecord: Codable, Sendable, Equatable {
    /// EventKit calendar identifier (opaque).
    public let id: String
    public let title: String
    /// Matching Forge project folder name, when linked.
    public let matchedProject: String?
    public let incompleteCount: Int
    public let completedCount: Int

    public init(
        id: String,
        title: String,
        matchedProject: String?,
        incompleteCount: Int,
        completedCount: Int
    ) {
        self.id = id
        self.title = title
        self.matchedProject = matchedProject
        self.incompleteCount = incompleteCount
        self.completedCount = completedCount
    }
}

/// One reminder item. `id` is EventKit `calendarItemIdentifier` (opaque).
public struct ReminderRecord: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let listTitle: String
    public let listId: String
    public let isCompleted: Bool
    public let dueDate: Date?
    /// EventKit priority (0 = none; typically 1 high, 5 medium, 9 low).
    public let priority: Int
    public let notes: String?
    public let matchedProject: String?

    public init(
        id: String,
        title: String,
        listTitle: String,
        listId: String,
        isCompleted: Bool,
        dueDate: Date?,
        priority: Int,
        notes: String?,
        matchedProject: String?
    ) {
        self.id = id
        self.title = title
        self.listTitle = listTitle
        self.listId = listId
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.priority = priority
        self.notes = notes
        self.matchedProject = matchedProject
    }
}

/// Snapshot of Reminders lists and items, matched to Forge folders.
public struct RemindersInventory: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let lists: [RemindersListRecord]
    public let reminders: [ReminderRecord]
    public let unmatchedListTitles: [String]
    public let unmatchedProjectNames: [String]
    public let writer: String

    public init(
        generatedAt: Date,
        lists: [RemindersListRecord],
        reminders: [ReminderRecord],
        unmatchedListTitles: [String],
        unmatchedProjectNames: [String],
        writer: String = "Forge.app"
    ) {
        self.generatedAt = generatedAt
        self.lists = lists
        self.reminders = reminders
        self.unmatchedListTitles = unmatchedListTitles
        self.unmatchedProjectNames = unmatchedProjectNames
        self.writer = writer
    }

    /// Incomplete reminder counts per matched Forge folder (snapshot-only enrichment).
    public func enrichmentByFolder(now: Date = Date()) -> [String: RemindersBoardEnrichment] {
        let age = now.timeIntervalSince(generatedAt)
        var result: [String: RemindersBoardEnrichment] = [:]
        let grouped = Dictionary(grouping: reminders.filter { !$0.isCompleted && $0.matchedProject != nil }) {
            $0.matchedProject!
        }
        for (folder, items) in grouped {
            let sorted = items.sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?):
                    if l != r { return l < r }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
            result[folder] = RemindersBoardEnrichment(
                incompleteCount: items.count,
                nextReminder: sorted.first?.title,
                due: sorted.first?.dueDate,
                snapshotAgeSeconds: age
            )
        }
        return result
    }

    /// Filter reminder rows (list counts stay unchanged).
    public func filteringReminders(includeCompleted: Bool) -> RemindersInventory {
        guard !includeCompleted else { return self }
        return RemindersInventory(
            generatedAt: generatedAt,
            lists: lists,
            reminders: reminders.filter { !$0.isCompleted },
            unmatchedListTitles: unmatchedListTitles,
            unmatchedProjectNames: unmatchedProjectNames,
            writer: writer
        )
    }
}

/// Per-project enrichment embedded in `forge board --json`.
public struct RemindersBoardEnrichment: Codable, Sendable, Equatable {
    public let incompleteCount: Int
    public let nextReminder: String?
    public let due: Date?
    public let snapshotAgeSeconds: TimeInterval?

    public init(
        incompleteCount: Int,
        nextReminder: String?,
        due: Date?,
        snapshotAgeSeconds: TimeInterval?
    ) {
        self.incompleteCount = incompleteCount
        self.nextReminder = nextReminder
        self.due = due
        self.snapshotAgeSeconds = snapshotAgeSeconds
    }
}

/// Reminder fields used to build an inventory without EventKit (tests).
public struct ReminderDraft: Sendable, Equatable {
    public let id: String
    public let title: String
    public let listId: String
    public let isCompleted: Bool
    public let dueDate: Date?
    public let priority: Int
    public let notes: String?

    public init(
        id: String,
        title: String,
        listId: String,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        priority: Int = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.listId = listId
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.priority = priority
        self.notes = notes
    }
}
