import EventKit
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Errors from EventKit writes (create list / sentinel).
public enum RemindersWriterError: Error, CustomStringConvertible, LocalizedError, Sendable {
    case accessDenied
    case noReminderSource(String?)
    case listNotFound(String)
    case reminderNotFound(String)

    public var description: String {
        switch self {
        case .accessDenied:
            return RemindersReaderError.accessDenied.description
        case .noReminderSource(let name):
            if let name, !name.isEmpty {
                return "No Reminders account named '\(name)'. Check reminders.source in config.yaml."
            }
            return "No Reminders account available to create a list. Set reminders.source, or create one list in Reminders.app first."
        case .listNotFound(let id):
            return "Reminders list not found (\(id))."
        case .reminderNotFound(let id):
            return "Reminder not found (\(id))."
        }
    }

    public var errorDescription: String? { description }
}

/// Create Reminders lists and update kanban sentinels (EventKit or test doubles).
public protocol RemindersMutating: Sendable {
    /// Create a reminder list; returns the EventKit calendar identifier.
    func createList(title: String, sourceTitle: String?, colourIndex: Int?) async throws -> String
    /// Create the sentinel reminder; returns its calendar item identifier.
    func saveSentinel(listId: String, column: String, prefix: String) async throws -> String
    /// Update an existing sentinel’s title and notes.
    func updateSentinel(reminderId: String, column: String, prefix: String) async throws
    /// Paint a list’s colour from a Finder tag index (1–7). Icons cannot be set via EventKit.
    func updateListColour(listId: String, colourIndex: Int) async throws
    /// Set EventKit priority on a reminder (0 none, 1 high). Used for Finder URGENT → sentinel.
    func updateReminderPriority(reminderId: String, priority: Int) async throws
}

/// EventKit writer for Phase 2 align / sync_on_move.
public final class RemindersWriter: RemindersMutating, @unchecked Sendable {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public func createList(title: String, sourceTitle: String?, colourIndex: Int?) async throws -> String {
        try await requestAccess()
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = title
        calendar.source = try resolveSource(named: sourceTitle)
        if let colourIndex, let colour = FinderTagColour.cgColor(for: colourIndex) {
            calendar.cgColor = colour
        }
        try store.saveCalendar(calendar, commit: true)
        return calendar.calendarIdentifier
    }

    public func updateListColour(listId: String, colourIndex: Int) async throws {
        try await requestAccess()
        guard let calendar = store.calendar(withIdentifier: listId) else {
            throw RemindersWriterError.listNotFound(listId)
        }
        guard let colour = FinderTagColour.cgColor(for: colourIndex) else { return }
        calendar.cgColor = colour
        try store.saveCalendar(calendar, commit: true)
    }

    public func saveSentinel(listId: String, column: String, prefix: String) async throws -> String {
        try await requestAccess()
        guard let calendar = store.calendar(withIdentifier: listId) else {
            throw RemindersWriterError.listNotFound(listId)
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = RemindersSentinel.title(column: column, prefix: prefix)
        reminder.notes = RemindersSentinel.notes(column: column)
        reminder.isCompleted = false
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    public func updateSentinel(reminderId: String, column: String, prefix: String) async throws {
        try await requestAccess()
        guard let reminder = store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            throw RemindersWriterError.reminderNotFound(reminderId)
        }
        reminder.title = RemindersSentinel.title(column: column, prefix: prefix)
        reminder.notes = RemindersSentinel.notes(column: column)
        reminder.isCompleted = false
        try store.save(reminder, commit: true)
    }

    public func updateReminderPriority(reminderId: String, priority: Int) async throws {
        try await requestAccess()
        guard let reminder = store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            throw RemindersWriterError.reminderNotFound(reminderId)
        }
        let clamped: Int = (1...9).contains(priority) ? priority : 0
        reminder.priority = clamped
        try store.save(reminder, commit: true)
    }

    private func requestAccess() async throws {
        let granted = try await store.requestFullAccessToReminders()
        if !granted {
            throw RemindersWriterError.accessDenied
        }
    }

    private func resolveSource(named title: String?) throws -> EKSource {
        let candidates = store.sources.map { source in
            RemindersSourcePicker.Candidate(
                title: source.title,
                kind: Self.kind(of: source),
                hasReminderLists: !source.calendars(for: .reminder).isEmpty
            )
        }
        switch RemindersSourcePicker.choose(named: title, among: candidates) {
        case .source(let chosenTitle):
            let lower = chosenTitle.lowercased()
            if let match = store.sources.first(where: { $0.title.lowercased() == lower }) {
                return match
            }
            throw RemindersWriterError.noReminderSource(chosenTitle)
        case .requestedNotFound(let name):
            throw RemindersWriterError.noReminderSource(name)
        case .noneAvailable:
            throw RemindersWriterError.noReminderSource(nil)
        }
    }

    private static func kind(of source: EKSource) -> RemindersSourcePicker.Kind {
        switch source.sourceType {
        case .calDAV: return .calDAV
        case .local: return .local
        case .exchange: return .exchange
        default: return .other
        }
    }
}

/// Result of applying a Reminders align plan.
public struct RemindersAlignApplyResult: Sendable, Equatable {
    public let createdLists: [String]
    public let sentinelsWritten: Int
    public let skipped: [String]

    public init(createdLists: [String], sentinelsWritten: Int, skipped: [String]) {
        self.createdLists = createdLists
        self.sentinelsWritten = sentinelsWritten
        self.skipped = skipped
    }
}

extension RemindersService {
    /// Execute align proposals (create lists / sentinels). Skips `propose_finder_shipped`.
    public func apply(
        plan: RemindersAlignPlan,
        writer: any RemindersMutating,
        projects: [Project] = []
    ) async throws -> RemindersAlignApplyResult {
        var created: [String] = []
        var sentinels = 0
        var skipped: [String] = []
        var listIdByFolder: [String: String] = [:]
        let prefix = remindersConfig.sentinelPrefix
        let sourceTitle = remindersConfig.source
        let urgentByFolder = Dictionary(
            uniqueKeysWithValues: projects.map {
                ($0.name.lowercased(), KanbanRadar.isUrgent(metaTags: $0.metaTags))
            }
        )

        for proposal in plan.proposals {
            switch proposal.kind {
            case .proposeFinderShipped:
                skipped.append(proposal.summary)
            case .createList:
                guard let title = proposal.listTitle ?? proposal.folderName else {
                    skipped.append(proposal.summary)
                    continue
                }
                let colourIndex = proposal.column.flatMap { config.board.colourIndex(forColumn: $0) }
                let id = try await writer.createList(
                    title: title,
                    sourceTitle: sourceTitle,
                    colourIndex: colourIndex
                )
                created.append(title)
                if let folder = proposal.folderName {
                    listIdByFolder[folder] = id
                }
            case .ensureSentinel:
                guard let column = proposal.column else {
                    skipped.append(proposal.summary)
                    continue
                }
                let listId = proposal.listId
                    ?? proposal.folderName.flatMap { listIdByFolder[$0] }
                guard let listId else {
                    skipped.append(proposal.summary)
                    continue
                }
                let reminderId = try await writer.saveSentinel(
                    listId: listId,
                    column: column,
                    prefix: prefix
                )
                try await writer.updateReminderPriority(
                    reminderId: reminderId,
                    priority: RemindersSentinel.priority(
                        isUrgent: urgentByFolder[proposal.folderName?.lowercased() ?? ""] ?? false
                    )
                )
                sentinels += 1
            case .updateSentinel:
                guard let reminderId = proposal.reminderId, let column = proposal.column else {
                    skipped.append(proposal.summary)
                    continue
                }
                try await writer.updateSentinel(
                    reminderId: reminderId,
                    column: column,
                    prefix: prefix
                )
                try await writer.updateReminderPriority(
                    reminderId: reminderId,
                    priority: RemindersSentinel.priority(
                        isUrgent: urgentByFolder[proposal.folderName?.lowercased() ?? ""] ?? false
                    )
                )
                sentinels += 1
            }
        }

        return RemindersAlignApplyResult(
            createdLists: created,
            sentinelsWritten: sentinels,
            skipped: skipped
        )
    }

    /// Create Reminders lists for Forge folders that have none. Does not delete unmatched lists or write sentinels.
    public func ensureMissingLists(
        projects: [Project],
        inventory: RemindersInventory,
        writer: any RemindersMutating
    ) async throws -> RemindersAlignApplyResult {
        let full = RemindersAlignment.alignPlan(
            projects: projects,
            inventory: inventory,
            config: config,
            dryRun: false
        )
        let creates = full.proposals.filter { $0.kind == .createList }
        let plan = RemindersAlignPlan(
            generatedAt: full.generatedAt,
            proposals: creates,
            dryRun: false
        )
        return try await apply(plan: plan, writer: writer)
    }
}
