import EventKit
import Foundation

/// Errors from the read-only Reminders EventKit reader.
public enum RemindersReaderError: Error, CustomStringConvertible, LocalizedError, Sendable {
    case accessDenied
    case disabled

    public var description: String {
        switch self {
        case .accessDenied:
            return "Access to Reminders was denied for this terminal. Either allow Reminders for your terminal app in System Settings → Privacy & Security → Reminders, or rely on Forge.app: keep Forge running so it can refresh \(RemindersSnapshotStore.fileName) under your Forge directory’s .cache."
        case .disabled:
            return "Reminders integration is disabled. Set reminders.enabled: true in config.yaml, or enable it in Forge → Preferences → Reminders."
        }
    }

    public var errorDescription: String? { description }
}

/// Fetch Reminders inventories (EventKit or test doubles).
public protocol RemindersFetching: Sendable {
    func fetchInventory(
        projectNames: [String],
        config: RemindersConfig,
        writer: String
    ) async throws -> RemindersInventory
}

/// Read-only access to Apple Reminders via EventKit (no writes).
public final class RemindersReader: RemindersFetching, @unchecked Sendable {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    /// Request full Reminders access (macOS 14+). Must succeed before fetching.
    public func requestAccess() async throws {
        let granted = try await store.requestFullAccessToReminders()
        if !granted {
            throw RemindersReaderError.accessDenied
        }
    }

    /// Fetch reminder lists and items, matched to Forge folder names.
    public func fetchInventory(
        projectNames: [String],
        config: RemindersConfig,
        writer: String
    ) async throws -> RemindersInventory {
        try await requestAccess()
        let calendars = store.calendars(for: .reminder)
        let lists = calendars.map { (id: $0.calendarIdentifier, title: $0.title) }
        let drafts = await fetchReminderDrafts(in: calendars)
        return RemindersMatching.buildInventory(
            generatedAt: Date(),
            lists: lists,
            reminders: drafts,
            projectNames: projectNames,
            config: config,
            writer: writer
        )
    }

    private func fetchReminderDrafts(in calendars: [EKCalendar]) async -> [ReminderDraft] {
        await withCheckedContinuation { continuation in
            let predicateCalendars: [EKCalendar]? = calendars.isEmpty ? nil : calendars
            let predicate = store.predicateForReminders(in: predicateCalendars)
            store.fetchReminders(matching: predicate) { reminders in
                let drafts = (reminders ?? []).map { rem in
                    ReminderDraft(
                        id: rem.calendarItemIdentifier,
                        title: Self.displayTitle(rem.title),
                        listId: rem.calendar?.calendarIdentifier ?? "",
                        isCompleted: rem.isCompleted,
                        dueDate: rem.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                        priority: rem.priority,
                        notes: Self.truncate(rem.notes, limit: 4000)
                    )
                }
                continuation.resume(returning: drafts)
            }
        }
    }

    static func displayTitle(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return "(No title)" }
        return title
    }

    static func truncate(_ text: String?, limit: Int) -> String? {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.count > limit {
            let end = text.index(text.startIndex, offsetBy: limit)
            text = String(text[..<end]) + "…"
        }
        return text
    }
}

/// High-level Reminders operations used by the CLI and Forge.app.
public struct RemindersService: Sendable {
    public let config: ForgeConfig

    public init(config: ForgeConfig) {
        self.config = config
    }

    public var remindersConfig: RemindersConfig { config.reminders }

    public func requireEnabled() throws {
        guard remindersConfig.enabled else { throw RemindersReaderError.disabled }
    }

    public func loadEligibleSnapshot(forgeDir: String, now: Date = Date()) throws -> RemindersInventory? {
        try RemindersSnapshotStore.loadIfEligible(
            forgeDir: forgeDir,
            maxAge: remindersConfig.snapshotMaxAgeSeconds,
            now: now
        )
    }

    /// Live EventKit fetch and write `.cache/reminders-snapshot.json`.
    public func refreshSnapshot(
        forgeDir: String,
        projectNames: [String],
        writer: String = "Forge.app",
        reader: any RemindersFetching = RemindersReader()
    ) async throws -> RemindersInventory {
        let inventory = try await reader.fetchInventory(
            projectNames: projectNames,
            config: remindersConfig,
            writer: writer
        )
        try RemindersSnapshotStore.write(forgeDir: forgeDir, inventory: inventory)
        return inventory
    }
}
