@preconcurrency import EventKit
import Foundation

/// Two-way bridge between ForgeTask and EKReminder using EventKit.
public final class RemindersBridge: @unchecked Sendable {

    private let store: EKEventStore
    private let listName: String

    public init(store: EKEventStore = EKEventStore(), listName: String = "Forge") {
        self.store = store
        self.listName = listName
    }

    /// Request full access to Reminders. Must be called before any read/write operations.
    public func requestAccess() async throws {
        try await store.requestFullAccessToReminders()
    }

    // MARK: - List Management

    /// List title for a given context. Nil context = base list; otherwise "Forge • context".
    private func listTitle(forContext context: String?) -> String {
        guard let ctx = context, !ctx.isEmpty else { return listName }
        return "\(listName) • \(ctx)"
    }

    /// Find or create the Forge reminders list. Pass a context to use a context-specific list
    /// (e.g. "email" → "Forge • email"), so Reminders shows one list per context.
    public func findOrCreateList(context: String? = nil) throws -> EKCalendar {
        let title = listTitle(forContext: context)
        let calendars = store.calendars(for: .reminder)

        if let existing = calendars.first(where: { $0.title == title }) {
            return existing
        }

        guard let source = store.defaultCalendarForNewReminders()?.source else {
            throw BridgeError.noSource
        }

        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = title
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    /// All reminder calendars that belong to Forge (base list + any "Forge • context" lists).
    public func allForgeListCalendars() -> [EKCalendar] {
        let calendars = store.calendars(for: .reminder)
        let prefix = "\(listName) • "
        return calendars.filter { cal in
            cal.title == listName || cal.title.hasPrefix(prefix)
        }
    }

    // MARK: - Reading

    /// Fetch all reminders from a single list.
    public func fetchReminders(from list: EKCalendar) async throws -> [EKReminder] {
        let predicate = store.predicateForReminders(in: [list])
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let result: [EKReminder] = reminders ?? []
                nonisolated(unsafe) let sendableResult = result
                continuation.resume(returning: sendableResult)
            }
        }
    }

    /// Fetch all reminders from multiple lists (e.g. all Forge context lists).
    public func fetchReminders(from lists: [EKCalendar]) async throws -> [EKReminder] {
        guard !lists.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: lists)
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let result: [EKReminder] = reminders ?? []
                nonisolated(unsafe) let sendableResult = result
                continuation.resume(returning: sendableResult)
            }
        }
    }

    /// Extract the forge task ID from a reminder's notes field.
    /// Expects first line: `forge:<project-name>:<task-id>`
    public func extractForgeID(from reminder: EKReminder) -> (project: String, taskID: String)? {
        guard let notes = reminder.notes else { return nil }
        let firstLine = notes.components(separatedBy: .newlines).first ?? notes
        guard firstLine.hasPrefix("forge:") else { return nil }

        let parts = firstLine.split(separator: ":", maxSplits: 2)
        guard parts.count == 3 else { return nil }
        return (project: String(parts[1]), taskID: String(parts[2]))
    }

    // MARK: - Writing

    /// Create a new EKReminder from a ForgeTask, including area tags and recurrence.
    public func createReminder(
        for task: ForgeTask, projectName: String,
        tags: [String] = [], in list: EKCalendar
    ) throws -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.title = task.text
        reminder.calendar = list
        reminder.notes = formatNotes(project: projectName, taskID: task.id, tags: tags)
        reminder.isCompleted = task.isCompleted

        if let deferDate = task.deferDate {
            reminder.startDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day], from: deferDate
            )
        }

        if let dueDate = task.dueDate {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day], from: dueDate
            )
            reminder.dueDateComponents = components
        }

        if task.section == .waitingFor {
            reminder.priority = 5
        }

        if let rule = task.repeatRule, let ekRule = recurrenceRule(from: rule) {
            reminder.recurrenceRules = [ekRule]
        }

        try store.save(reminder, commit: false)
        return reminder
    }

    /// Update the tags on an existing reminder's notes, preserving the forge ID.
    public func updateTags(on reminder: EKReminder, tags: [String]) {
        guard let notes = reminder.notes, notes.hasPrefix("forge:") else { return }
        guard let ids = extractForgeID(from: reminder) else { return }

        let existingTags = extractTags(from: reminder)
        guard Set(existingTags) != Set(tags) else { return }

        reminder.notes = formatNotes(project: ids.project, taskID: ids.taskID, tags: tags)
        try? store.save(reminder, commit: false)
    }

    /// Complete an existing reminder.
    public func completeReminder(_ reminder: EKReminder) throws {
        reminder.isCompleted = true
        reminder.completionDate = Date()
        try store.save(reminder, commit: false)
    }

    /// Move a reminder to a different list (e.g. from "Forge" to "Forge • email").
    public func moveReminder(_ reminder: EKReminder, to list: EKCalendar) throws {
        reminder.calendar = list
        try store.save(reminder, commit: false)
    }

    /// Update an existing reminder's due date.
    public func updateDueDate(_ reminder: EKReminder, to date: Date?) throws {
        if let date = date {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day], from: date
            )
        } else {
            reminder.dueDateComponents = nil
        }
        try store.save(reminder, commit: false)
    }

    /// Format the notes field with forge ID and tags.
    ///
    /// Format: `forge:Project:taskID\ntags: work, personal`
    public func formatNotes(project: String, taskID: String, tags: [String]) -> String {
        var result = "forge:\(project):\(taskID)"
        if !tags.isEmpty {
            result += "\ntags: \(tags.joined(separator: ", "))"
        }
        return result
    }

    /// Extract area tags from a reminder's notes field.
    public func extractTags(from reminder: EKReminder) -> [String] {
        guard let notes = reminder.notes else { return [] }
        for line in notes.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("tags:") {
                let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                return value.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty }
            }
        }
        return []
    }

    // MARK: - Recurrence

    /// Convert a Forge `RepeatRule` to an `EKRecurrenceRule`.
    public func recurrenceRule(from rule: RepeatRule) -> EKRecurrenceRule? {
        let frequency: EKRecurrenceFrequency
        switch rule.unit {
        case .day:   frequency = .daily
        case .week:  frequency = .weekly
        case .month: frequency = .monthly
        case .year:  frequency = .yearly
        }
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: rule.interval,
            end: nil
        )
    }

    /// Convert an `EKRecurrenceRule` to a Forge `RepeatRule`.
    ///
    /// Fixed-schedule rules map to `.fixedSchedule`, but there is no reliable way to
    /// distinguish "defer again" vs "fixed" from EventKit alone, so we default to
    /// `.fixedSchedule` for rules coming back from Reminders.
    public func repeatRule(from ekRule: EKRecurrenceRule) -> RepeatRule? {
        let unit: RepeatRule.Unit
        switch ekRule.frequency {
        case .daily:   unit = .day
        case .weekly:  unit = .week
        case .monthly: unit = .month
        case .yearly:  unit = .year
        @unknown default: return nil
        }
        return RepeatRule(mode: .fixedSchedule, interval: ekRule.interval, unit: unit)
    }

    /// Commit all pending changes.
    public func commit() throws {
        try store.commit()
    }

    // MARK: - Errors

    public enum BridgeError: Error, CustomStringConvertible {
        case noSource
        case accessDenied

        public var description: String {
            switch self {
            case .noSource:
                return "No iCloud or local source found for Reminders."
            case .accessDenied:
                return "Access to Reminders was denied. Check System Settings > Privacy > Reminders."
            }
        }
    }
}
