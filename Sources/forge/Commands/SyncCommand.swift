import ArgumentParser
import Foundation
import ForgeCore

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Two-way sync tasks with Reminders.app and Calendar.app."
    )

    @Flag(name: .long, help: "Show detailed sync actions.")
    var verbose = false

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "Rebuild the task index database before syncing.",
            discussion: """
            Forces a full recursive rescan of all configured project roots, discarding any cached \
            TASKS.md paths in .cache/tasks.db. Use this if new project TASKS.md files under an \
            existing project root are not appearing in sync.
            """
        )
    )
    var rebuildIndex = false

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let taskFilesRoot = ConfigLoader.taskFilesRoot(forgeDir: forgeDir)

        if rebuildIndex {
            let cacheDir = (forgeDir as NSString).appendingPathComponent(".cache")
            let dbPath = (cacheDir as NSString).appendingPathComponent("tasks.db")
            try? FileManager.default.removeItem(atPath: dbPath)
        }

        let db = try TaskFileDatabase(forgeDir: forgeDir)
        let index = DatabaseTaskIndex(database: db, forceFullRescan: rebuildIndex)
        let engine = SyncEngine(
            config: config,
            forgeDir: forgeDir,
            taskFilesRoot: taskFilesRoot,
            options: .full,
            taskIndex: index
        )

        let dim = "\u{1B}[2m"
        let bold = "\u{1B}[1m"
        let green = "\u{1B}[32m"
        let red = "\u{1B}[31m"
        let reset = "\u{1B}[0m"

        print("\(dim)Syncing with Reminders and Calendar...\(reset)")

        let report = try await engine.sync()

        print("\n\(bold)Sync complete\(reset)")

        if report.remindersCreated > 0 {
            print("\(green)  ↑\(reset) \(report.remindersCreated) reminders created")
        }
        if report.remindersCompleted > 0 {
            print("\(green)  ↑\(reset) \(report.remindersCompleted) reminders completed")
        }
        if report.remindersMoved > 0 {
            print("  ↔ \(report.remindersMoved) reminder\(report.remindersMoved == 1 ? "" : "s") moved to context list\(report.remindersMoved == 1 ? "" : "s")")
        }
        if report.remindersDeduplicated > 0 {
            print("  ↓ \(report.remindersDeduplicated) duplicate reminder\(report.remindersDeduplicated == 1 ? "" : "s") removed (same ID)")
        }
        if report.remindersMergedByContent > 0 {
            print("  ↓ \(report.remindersMergedByContent) duplicate reminder\(report.remindersMergedByContent == 1 ? "" : "s") merged by content")
        }
        if report.tasksMergedInMarkdown > 0 {
            print("  ↓ \(report.tasksMergedInMarkdown) duplicate task\(report.tasksMergedInMarkdown == 1 ? "" : "s") removed from markdown")
        }
        if report.eventsCreated > 0 {
            print("\(green)  ↑\(reset) \(report.eventsCreated) calendar events created")
        }
        if report.eventsUpdated > 0 {
            print("  ↔ \(report.eventsUpdated) calendar events updated")
        }
        if report.eventsRemoved > 0 {
            print("  ↓ \(report.eventsRemoved) calendar events removed")
        }
        if report.eventsDeduplicated > 0 {
            print("  ↓ \(report.eventsDeduplicated) duplicate calendar event\(report.eventsDeduplicated == 1 ? "" : "s") removed")
        }
        if report.tasksCompleted > 0 {
            print("\(green)  ↓\(reset) \(report.tasksCompleted) tasks completed from Reminders")
        }
        if report.inboxItemsAdded > 0 {
            print("\(green)  ↓\(reset) \(report.inboxItemsAdded) items added to inbox from Reminders")
        }
        if report.tasksUpdated > 0 {
            print("\(green)  ↓\(reset) \(report.tasksUpdated) task due date\(report.tasksUpdated == 1 ? "" : "s") updated from Calendar")
        }
        if report.rollupAreas > 0 {
            print("  ↔ \(report.rollupAreas) area rollup\(report.rollupAreas == 1 ? "" : "s") updated (\(report.rollupTasks) tasks linked)")
        }

        let totalActions = report.remindersCreated + report.remindersCompleted
            + report.remindersMoved + report.remindersDeduplicated + report.remindersMergedByContent
            + report.tasksMergedInMarkdown
            + report.eventsCreated + report.eventsUpdated + report.eventsRemoved + report.eventsDeduplicated
            + report.tasksCompleted + report.inboxItemsAdded + report.tasksUpdated

        if totalActions == 0 {
            print("  Everything is in sync.")
        }

        if !report.errors.isEmpty {
            print("\n\(red)Errors:\(reset)")
            for error in report.errors {
                print("  \(red)✗\(reset) \(error)")
            }
        }

        print()
    }
}
