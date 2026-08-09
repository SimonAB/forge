import Foundation
import Testing

@testable import ForgeCore

@Suite("Reminders inventory helpers")
struct RemindersInventoryTests {
    private func sampleInventory(generatedAt: Date = Date()) -> RemindersInventory {
        RemindersInventory(
            generatedAt: generatedAt,
            lists: [
                RemindersListRecord(
                    id: "l1",
                    title: "Lepto",
                    matchedProject: "Lepto",
                    incompleteCount: 2,
                    completedCount: 1
                ),
            ],
            reminders: [
                ReminderRecord(
                    id: "r1",
                    title: "Draft methods",
                    listTitle: "Lepto",
                    listId: "l1",
                    isCompleted: false,
                    dueDate: Date(timeIntervalSince1970: 1_800_000_000),
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
            ],
            unmatchedListTitles: ["Forge"],
            unmatchedProjectNames: ["Other"],
            writer: "test"
        )
    }

    @Test("filteringReminders hides completed rows but keeps list counts")
    func filteringHidesCompleted() {
        let inventory = sampleInventory()
        let filtered = inventory.filteringReminders(includeCompleted: false)
        #expect(filtered.reminders.map(\.id) == ["r1", "r2"])
        #expect(filtered.lists.first?.incompleteCount == 2)
        #expect(filtered.lists.first?.completedCount == 1)
        #expect(inventory.filteringReminders(includeCompleted: true) == inventory)
    }

    @Test("enrichment prefers the earliest due incomplete reminder")
    func enrichmentNextDue() {
        let generated = Date(timeIntervalSince1970: 1_700_000_000)
        let now = Date(timeIntervalSince1970: 1_700_000_090)
        let enrichment = sampleInventory(generatedAt: generated).enrichmentByFolder(now: now)
        let row = enrichment["Lepto"]
        #expect(row?.incompleteCount == 2)
        #expect(row?.nextReminder == "Draft methods")
        #expect(row?.due == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(row?.snapshotAgeSeconds == 90)
    }

    @Test("RemindersConfig.updating changes includeCompleted")
    func configUpdatingIncludeCompleted() {
        let updated = RemindersConfig().updating(enabled: true, includeCompleted: true)
        #expect(updated.enabled)
        #expect(updated.includeCompleted)
        #expect(updated.list == "Forge")
    }

    @Test("requireEnabled throws when disabled")
    func requireEnabledThrows() throws {
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        #expect(config.reminders.enabled == false)
        do {
            try RemindersService(config: config).requireEnabled()
            Issue.record("expected RemindersReaderError.disabled")
        } catch RemindersReaderError.disabled {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("updating trims empty inbox list to the default")
    func updatingEmptyList() {
        let updated = RemindersConfig(list: "Inbox").updating(list: "   ")
        #expect(updated.list == RemindersConfig.defaultListName)
    }

    @Test("enrichment skips folders with only completed reminders")
    func enrichmentSkipsCompletedOnly() {
        let inventory = RemindersInventory(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lists: [
                RemindersListRecord(
                    id: "l1",
                    title: "Lepto",
                    matchedProject: "Lepto",
                    incompleteCount: 0,
                    completedCount: 1
                ),
            ],
            reminders: [
                ReminderRecord(
                    id: "r1",
                    title: "Old note",
                    listTitle: "Lepto",
                    listId: "l1",
                    isCompleted: true,
                    dueDate: nil,
                    priority: 0,
                    notes: nil,
                    matchedProject: "Lepto"
                ),
            ],
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
        #expect(inventory.enrichmentByFolder().isEmpty)
    }

    @Test("enrichment ignores unmatched inbox reminders")
    func enrichmentIgnoresUnmatched() {
        let inventory = RemindersInventory(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lists: [
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
            unmatchedProjectNames: [],
            writer: "test"
        )
        #expect(inventory.enrichmentByFolder().isEmpty)
    }
}
