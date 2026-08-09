import Foundation
import Testing

@testable import ForgeCore

@Suite("Reminders doctor and align")
struct RemindersAlignmentTests {
    private func project(_ name: String, column: String? = "Watch") -> Project {
        Project(
            name: name,
            path: "/tmp/\(name)",
            tags: column.map { ["\($0)"] } ?? [],
            workflowTag: column,
            column: column,
            metaTags: []
        )
    }

    private func list(
        id: String,
        title: String,
        matched: String?,
        incomplete: Int = 1,
        completed: Int = 0
    ) -> RemindersListRecord {
        RemindersListRecord(
            id: id,
            title: title,
            matchedProject: matched,
            incompleteCount: incomplete,
            completedCount: completed
        )
    }

    private func reminder(
        id: String,
        title: String,
        listId: String,
        listTitle: String,
        matched: String?,
        completed: Bool = false,
        notes: String? = nil
    ) -> ReminderRecord {
        ReminderRecord(
            id: id,
            title: title,
            listTitle: listTitle,
            listId: listId,
            isCompleted: completed,
            dueDate: nil,
            priority: 0,
            notes: notes,
            matchedProject: matched
        )
    }

    private func config(
        sync: Bool = false,
        inbox: String = "Forge"
    ) -> ForgeConfig {
        let base = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        return ForgeConfig(
            projectRoots: base.projectRoots,
            board: base.board,
            calendar: base.calendar,
            omnifocus: base.omnifocus,
            reminders: RemindersConfig(
                enabled: true,
                list: inbox,
                syncOnMove: sync,
                syncFromReminders: sync
            ),
            gtd: base.gtd,
            workspaceTags: base.workspaceTags,
            projectAreas: base.projectAreas,
            terminal: base.terminal,
            projectTag: base.projectTag,
            projectScanDepth: base.projectScanDepth,
            dueConflictPolicy: base.dueConflictPolicy
        )
    }

    @Test("folder without list is forge_only")
    func forgeOnly() {
        let inv = RemindersInventory(
            generatedAt: Date(),
            lists: [list(id: "inbox", title: "Forge", matched: nil, incomplete: 0)],
            reminders: [],
            unmatchedListTitles: ["Forge"],
            unmatchedProjectNames: ["Lepto"],
            writer: "test"
        )
        let report = RemindersAlignment.doctor(
            projects: [project("Lepto")],
            inventory: inv,
            config: config()
        )
        #expect(report.items.contains { $0.bucket == .forgeOnly && $0.folderName == "Lepto" })
        #expect(report.items.contains { $0.bucket == .hygiene && $0.listTitle == "Forge" })
        #expect(!report.items.contains { $0.bucket == .remindersOnly })
        #expect(!report.isClean)
    }

    @Test("unmatched non-inbox list is reminders_only")
    func remindersOnly() {
        let inv = RemindersInventory(
            generatedAt: Date(),
            lists: [list(id: "s", title: "Shopping", matched: nil, incomplete: 2)],
            reminders: [],
            unmatchedListTitles: ["Shopping"],
            unmatchedProjectNames: [],
            writer: "test"
        )
        let report = RemindersAlignment.doctor(
            projects: [],
            inventory: inv,
            config: config()
        )
        #expect(report.items.contains { $0.bucket == .remindersOnly && $0.listTitle == "Shopping" })
        #expect(!report.isClean)
    }

    @Test("two lists matching one folder are ambiguous")
    func ambiguousLists() {
        let inv = RemindersInventory(
            generatedAt: Date(),
            lists: [
                list(id: "a", title: "Lepto", matched: "Lepto"),
                list(id: "b", title: "Lepto lab", matched: "Lepto"),
            ],
            reminders: [],
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
        let report = RemindersAlignment.doctor(
            projects: [project("Lepto")],
            inventory: inv,
            config: config()
        )
        #expect(report.items.contains { $0.bucket == .ambiguous && $0.folderName == "Lepto" })
        #expect(!report.isClean)
    }

    @Test("sentinel missing and drift when column sync is on")
    func sentinelBuckets() {
        let invMissing = RemindersInventory(
            generatedAt: Date(),
            lists: [list(id: "l1", title: "Lepto", matched: "Lepto")],
            reminders: [
                reminder(id: "t", title: "Draft", listId: "l1", listTitle: "Lepto", matched: "Lepto"),
            ],
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
        let missing = RemindersAlignment.doctor(
            projects: [project("Lepto", column: "Watch")],
            inventory: invMissing,
            config: config(sync: true)
        )
        #expect(missing.items.contains { $0.bucket == .sentinelMissing })

        let invDrift = RemindersInventory(
            generatedAt: Date(),
            lists: [list(id: "l1", title: "Lepto", matched: "Lepto")],
            reminders: [
                reminder(
                    id: "s",
                    title: "Forge · Coding",
                    listId: "l1",
                    listTitle: "Lepto",
                    matched: "Lepto",
                    notes: "forge-kanban: Coding"
                ),
            ],
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
        let drift = RemindersAlignment.doctor(
            projects: [project("Lepto", column: "Watch")],
            inventory: invDrift,
            config: config(sync: true)
        )
        #expect(drift.items.contains { $0.bucket == .sentinelDrift && $0.sentinelColumn == "Coding" })
    }

    @Test("two sentinels are sentinel_extra")
    func sentinelExtra() {
        let inv = RemindersInventory(
            generatedAt: Date(),
            lists: [list(id: "l1", title: "Lepto", matched: "Lepto")],
            reminders: [
                reminder(
                    id: "s1",
                    title: "Forge · Watch",
                    listId: "l1",
                    listTitle: "Lepto",
                    matched: "Lepto",
                    notes: "forge-kanban: Watch"
                ),
                reminder(
                    id: "s2",
                    title: "Forge · Coding",
                    listId: "l1",
                    listTitle: "Lepto",
                    matched: "Lepto",
                    notes: "forge-kanban: Coding"
                ),
            ],
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
        let report = RemindersAlignment.doctor(
            projects: [project("Lepto")],
            inventory: inv,
            config: config(sync: true)
        )
        #expect(report.items.contains { $0.bucket == .sentinelExtra })
        #expect(report.isClean)
    }

    @Test("align proposes create_list for unmatched folders")
    func alignCreateList() {
        let inv = RemindersInventory(
            generatedAt: Date(),
            lists: [],
            reminders: [],
            unmatchedListTitles: [],
            unmatchedProjectNames: ["Lepto", "VHP2_manuscript", "Lab"],
            writer: "test"
        )
        let plan = RemindersAlignment.alignPlan(
            projects: [project("Lepto"), project("VHP2_manuscript"), project("Lab")],
            inventory: inv,
            config: config(sync: false)
        )
        #expect(plan.dryRun)
        #expect(plan.proposals.map(\.kind) == [.createList, .createList, .createList])
        #expect(Set(plan.proposals.compactMap(\.folderName)) == ["Lab", "Lepto", "VHP2_manuscript"])
        #expect(plan.proposals.allSatisfy { $0.kind != .ensureSentinel })
    }

    @Test("align proposes ensure_sentinel only when sync flags are on")
    func alignSentinelWhenSyncOn() {
        let inv = RemindersInventory(
            generatedAt: Date(),
            lists: [list(id: "l1", title: "Lepto", matched: "Lepto")],
            reminders: [],
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
        let off = RemindersAlignment.alignPlan(
            projects: [project("Lepto", column: "Coding")],
            inventory: inv,
            config: config(sync: false)
        )
        #expect(off.proposals.isEmpty)

        let on = RemindersAlignment.alignPlan(
            projects: [project("Lepto", column: "Coding")],
            inventory: inv,
            config: config(sync: true)
        )
        #expect(on.proposals.contains { $0.kind == .ensureSentinel && $0.column == "Coding" })
    }

    @Test("all-complete ordinary reminders propose Finder Shipped")
    func proposeShipped() {
        let inv = RemindersInventory(
            generatedAt: Date(),
            lists: [list(id: "l1", title: "Lepto", matched: "Lepto", incomplete: 0, completed: 1)],
            reminders: [
                reminder(
                    id: "t",
                    title: "Old note",
                    listId: "l1",
                    listTitle: "Lepto",
                    matched: "Lepto",
                    completed: true
                ),
                reminder(
                    id: "s",
                    title: "Forge · Watch",
                    listId: "l1",
                    listTitle: "Lepto",
                    matched: "Lepto",
                    notes: "forge-kanban: Watch"
                ),
            ],
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
        let plan = RemindersAlignment.alignPlan(
            projects: [project("Lepto", column: "Watch")],
            inventory: inv,
            config: config(sync: true)
        )
        #expect(plan.proposals.contains { $0.kind == .proposeFinderShipped && $0.folderName == "Lepto" })
    }
}
