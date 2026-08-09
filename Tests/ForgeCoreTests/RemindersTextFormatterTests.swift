import Foundation
import Testing

@testable import ForgeCore

@Suite("Reminders text formatter")
struct RemindersTextFormatterTests {
    private let generated = Date(timeIntervalSince1970: 1_700_000_000)
    private let now = Date(timeIntervalSince1970: 1_700_000_045)
    private let due = Date(timeIntervalSince1970: 1_800_000_000)

    private func sampleInventory() -> RemindersInventory {
        RemindersInventory(
            generatedAt: generated,
            lists: [
                RemindersListRecord(
                    id: "l1",
                    title: "Lepto",
                    matchedProject: "Lepto",
                    incompleteCount: 2,
                    completedCount: 1
                ),
                RemindersListRecord(
                    id: "l2",
                    title: "Forge",
                    matchedProject: nil,
                    incompleteCount: 1,
                    completedCount: 0
                ),
            ],
            reminders: [
                ReminderRecord(
                    id: "r1",
                    title: "Draft methods",
                    listTitle: "Lepto",
                    listId: "l1",
                    isCompleted: false,
                    dueDate: due,
                    priority: 1,
                    notes: nil,
                    matchedProject: "Lepto"
                ),
                ReminderRecord(
                    id: "r2",
                    title: "Check figures",
                    listTitle: "Lepto",
                    listId: "l1",
                    isCompleted: false,
                    dueDate: nil,
                    priority: 0,
                    notes: nil,
                    matchedProject: "Lepto"
                ),
                ReminderRecord(
                    id: "r3",
                    title: "Old note",
                    listTitle: "Lepto",
                    listId: "l1",
                    isCompleted: true,
                    dueDate: nil,
                    priority: 0,
                    notes: nil,
                    matchedProject: "Lepto"
                ),
                ReminderRecord(
                    id: "r4",
                    title: "Buy milk",
                    listTitle: "Forge",
                    listId: "l2",
                    isCompleted: false,
                    dueDate: nil,
                    priority: 0,
                    notes: nil,
                    matchedProject: nil
                ),
            ],
            unmatchedListTitles: ["Forge"],
            unmatchedProjectNames: ["Lab-notebook", "VHP2_manuscript"],
            writer: "test"
        )
    }

    @Test("sourceLabel reports snapshot age and live EventKit")
    func sourceLabels() {
        #expect(
            RemindersTextFormatter.sourceLabel(
                .forgeAppSnapshot(generatedAt: generated),
                now: now
            ) == "snapshot 45s ago"
        )
        #expect(RemindersTextFormatter.sourceLabel(.liveEventKit, now: now) == "live EventKit")
    }

    @Test("formatDue uses en_GB medium date or empty")
    func dueFormatting() {
        #expect(RemindersTextFormatter.formatDue(nil) == "")
        let text = RemindersTextFormatter.formatDue(due)
        #expect(text.contains("due"))
        #expect(text.contains("2027") || text.contains("Jan"))
    }

    @Test("sortedReminders puts incomplete and earliest due first")
    func sortOrder() {
        let sorted = RemindersTextFormatter.sortedReminders(sampleInventory().reminders.filter {
            $0.listId == "l1"
        })
        #expect(sorted.map(\.id) == ["r1", "r2", "r3"])
    }

    @Test("inventoryText groups matched projects, inbox, and unmatched folders")
    func fullListing() {
        let text = RemindersTextFormatter.inventoryText(
            sampleInventory(),
            source: .forgeAppSnapshot(generatedAt: generated),
            now: now
        )
        #expect(text.contains("Reminders (snapshot 45s ago)"))
        #expect(text.contains("Matched projects"))
        #expect(text.contains("  Lepto (2 incomplete)"))
        #expect(text.contains("Draft methods"))
        #expect(text.contains("due"))
        #expect(text.contains("Old note ✓"))
        #expect(text.contains("Inbox / unmatched lists"))
        #expect(text.contains("  Forge (1 incomplete)"))
        #expect(text.contains("Buy milk"))
        #expect(text.contains("Unmatched folders (no Reminders list)"))
        #expect(text.contains("Lab-notebook"))
        #expect(text.contains("VHP2_manuscript"))
    }

    @Test("list filter keeps one list and hides unmatched folders")
    func listFilter() {
        let text = RemindersTextFormatter.inventoryText(
            sampleInventory(),
            source: .liveEventKit,
            listFilter: "Lepto",
            now: now
        )
        #expect(text.contains("Lepto"))
        #expect(!text.contains("Buy milk"))
        #expect(!text.contains("Unmatched folders"))
        #expect(!text.contains("Inbox / unmatched lists"))
    }

    @Test("unknown list filter reports no match")
    func unknownListFilter() {
        let text = RemindersTextFormatter.inventoryText(
            sampleInventory(),
            source: .liveEventKit,
            listFilter: "Missing"
        )
        #expect(text.contains("No Reminders list matching 'Missing'."))
        #expect(text.contains("No Reminders lists."))
    }

    @Test("ambiguous list filter names the candidates")
    func ambiguousListFilter() {
        let inventory = RemindersInventory(
            generatedAt: generated,
            lists: [
                RemindersListRecord(
                    id: "a",
                    title: "Lab",
                    matchedProject: "Lab",
                    incompleteCount: 0,
                    completedCount: 0
                ),
                RemindersListRecord(
                    id: "b",
                    title: "Lab-notebook",
                    matchedProject: "Lab-notebook",
                    incompleteCount: 0,
                    completedCount: 0
                ),
            ],
            reminders: [],
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
        let text = RemindersTextFormatter.inventoryText(
            inventory,
            source: .liveEventKit,
            listFilter: "L"
        )
        #expect(text.contains("Ambiguous Reminders list 'L':"))
        #expect(text.contains("Lab"))
        #expect(text.contains("Lab-notebook"))
    }

    @Test("project filter shows only that folder")
    func projectFilter() {
        let text = RemindersTextFormatter.inventoryText(
            sampleInventory(),
            source: .liveEventKit,
            projectFilter: "Lepto",
            now: now
        )
        #expect(text.contains("Lepto"))
        #expect(!text.contains("Buy milk"))
        #expect(!text.contains("Lab-notebook"))
    }

    @Test("itemLimit appends an ellipsis remainder")
    func itemLimit() {
        let many = (1...5).map { i in
            ReminderRecord(
                id: "r\(i)",
                title: "Item \(i)",
                listTitle: "Lepto",
                listId: "l1",
                isCompleted: false,
                dueDate: nil,
                priority: 0,
                notes: nil,
                matchedProject: "Lepto"
            )
        }
        let inventory = RemindersInventory(
            generatedAt: generated,
            lists: [
                RemindersListRecord(
                    id: "l1",
                    title: "Lepto",
                    matchedProject: "Lepto",
                    incompleteCount: 5,
                    completedCount: 0
                ),
            ],
            reminders: many,
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
        let text = RemindersTextFormatter.inventoryText(
            inventory,
            source: .liveEventKit,
            itemLimit: 2
        )
        #expect(text.contains("Item 1"))
        #expect(text.contains("Item 2"))
        #expect(text.contains("… 3 more"))
        #expect(!text.contains("Item 5"))
    }
}
