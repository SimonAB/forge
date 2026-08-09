import Foundation
import Testing

@testable import ForgeCore

@Suite("Reminders sentinel")
struct RemindersSentinelTests {
    private let columns = ["Plan", "Watch", "Coding", "Write", "Review", "Shipped", "Paused"]

    @Test("title and notes format the column")
    func format() {
        #expect(RemindersSentinel.title(column: "Watch") == "Forge · Watch")
        #expect(RemindersSentinel.notes(column: "Coding") == "forge-kanban: Coding")
    }

    @Test("notes marker parses even when title was renamed")
    func notesWinOverTitle() {
        let column = RemindersSentinel.parse(
            title: "Status",
            notes: "forge-kanban: Write\nKeep this marker.",
            knownColumns: columns
        )
        #expect(column == "Write")
        #expect(
            RemindersSentinel.isSentinel(title: "Status", notes: "forge-kanban: Write")
        )
    }

    @Test("title prefix parses when notes are missing")
    func titlePrefix() {
        #expect(
            RemindersSentinel.parse(
                title: "Forge · Review",
                notes: nil,
                knownColumns: columns
            ) == "Review"
        )
    }

    @Test("ordinary reminders are not sentinels")
    func ordinary() {
        #expect(!RemindersSentinel.isSentinel(title: "Buy milk", notes: "from the shop"))
        #expect(
            RemindersSentinel.parse(
                title: "Buy milk",
                notes: nil,
                knownColumns: columns
            ) == nil
        )
    }

    @Test("unknown column is a sentinel but does not parse")
    func unknownColumn() {
        #expect(
            RemindersSentinel.isSentinel(
                title: "Forge · Mystery",
                notes: "forge-kanban: Mystery"
            )
        )
        #expect(
            RemindersSentinel.parse(
                title: "Forge · Mystery",
                notes: "forge-kanban: Mystery",
                knownColumns: columns
            ) == nil
        )
    }

    @Test("parse is case-insensitive for known columns")
    func caseInsensitive() {
        #expect(
            RemindersSentinel.parse(
                title: "forge · coding",
                notes: nil,
                knownColumns: columns
            ) == "Coding"
        )
    }

    @Test("URGENT Finder tag maps to EventKit high priority")
    func urgentPriority() {
        #expect(RemindersSentinel.priority(isUrgent: true) == 1)
        #expect(RemindersSentinel.priority(isUrgent: false) == 0)
        #expect(RemindersSentinel.urgentPriority == 1)
        #expect(RemindersSentinel.nonePriority == 0)
    }
}
