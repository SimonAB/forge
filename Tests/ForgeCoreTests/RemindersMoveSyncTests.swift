import Foundation
import Testing

@testable import ForgeCore

@Suite("Reminders move sync")
struct RemindersMoveSyncTests {
    private func project(_ name: String, column: String?, metaTags: [String] = []) -> Project {
        Project(
            name: name,
            path: "/tmp/\(name)",
            tags: (column.map { [$0] } ?? []) + metaTags,
            workflowTag: column,
            column: column,
            metaTags: metaTags
        )
    }

    private func inventory(
        matched: Bool,
        sentinelColumn: String? = nil,
        extraSentinel: Bool = false
    ) -> RemindersInventory {
        let list = RemindersListRecord(
            id: "l1",
            title: "Lepto",
            matchedProject: matched ? "Lepto" : nil,
            incompleteCount: 1,
            completedCount: 0
        )
        var reminders: [ReminderRecord] = []
        if let column = sentinelColumn {
            reminders.append(
                ReminderRecord(
                    id: "s1",
                    title: RemindersSentinel.title(column: column),
                    listTitle: "Lepto",
                    listId: "l1",
                    isCompleted: false,
                    dueDate: nil,
                    priority: 0,
                    notes: RemindersSentinel.notes(column: column),
                    matchedProject: matched ? "Lepto" : nil
                )
            )
        }
        if extraSentinel {
            reminders.append(
                ReminderRecord(
                    id: "s2",
                    title: RemindersSentinel.title(column: "Write"),
                    listTitle: "Lepto",
                    listId: "l1",
                    isCompleted: false,
                    dueDate: nil,
                    priority: 0,
                    notes: RemindersSentinel.notes(column: "Write"),
                    matchedProject: matched ? "Lepto" : nil
                )
            )
        }
        return RemindersInventory(
            generatedAt: Date(),
            lists: [list],
            reminders: reminders,
            unmatchedListTitles: matched ? [] : ["Lepto"],
            unmatchedProjectNames: matched ? [] : ["Lepto"],
            writer: "test"
        )
    }

    private func config(syncOnMove: Bool = true, syncFrom: Bool = false) -> ForgeConfig {
        let base = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        return ForgeConfig(
            projectRoots: base.projectRoots,
            board: base.board,
            calendar: base.calendar,
            omnifocus: base.omnifocus,
            reminders: RemindersConfig(
                enabled: true,
                syncOnMove: syncOnMove,
                syncFromReminders: syncFrom
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

    @Test("disabled flag skips writer")
    func disabled() async {
        let stub = StubRemindersMutator()
        let outcome = await RemindersMoveSync.mirrorFinderColumn(
            config: config(syncOnMove: false),
            project: project("Lepto", column: "Watch"),
            column: "Coding",
            inventory: inventory(matched: true, sentinelColumn: "Watch"),
            writer: stub
        )
        #expect(outcome == .disabled)
        #expect(stub.updatedSentinels.isEmpty)
        #expect(stub.savedSentinels.isEmpty)
    }

    @Test("paintListColour updates colour when Reminders is enabled without sentinel sync")
    func paintColourWithoutSentinel() async {
        let stub = StubRemindersMutator()
        let outcome = await RemindersMoveSync.paintListColour(
            config: config(syncOnMove: false),
            project: project("Lepto", column: "Watch"),
            column: "Coding",
            inventory: inventory(matched: true, sentinelColumn: "Watch"),
            writer: stub
        )
        #expect(outcome == .synced(listTitle: "Lepto", column: "Coding"))
        #expect(stub.updatedColours.count == 1)
        #expect(stub.updatedColours[0].listId == "l1")
        #expect(stub.updatedColours[0].colourIndex == 5)
        #expect(stub.updatedSentinels.isEmpty)
    }

    @Test("paintAllMatchedListColours paints each unique list")
    func paintAllMatched() async {
        let stub = StubRemindersMutator()
        let inv = inventory(matched: true, sentinelColumn: "Watch")
        let result = await RemindersMoveSync.paintAllMatchedListColours(
            config: config(syncOnMove: false),
            projects: [
                project("Lepto", column: "Watch"),
                project("Other", column: "Plan"),
            ],
            inventory: inv,
            writer: stub
        )
        #expect(result.painted == ["Lepto → Watch"])
        #expect(result.skipped.contains { $0.contains("Other") })
        #expect(stub.updatedColours.count == 1)
        #expect(stub.updatedColours[0].colourIndex == 2)
    }

    @Test("afterFinderColumnChange paints colour and updates sentinel when sync_on_move")
    func afterMoveBoth() async {
        let stub = StubRemindersMutator()
        let rem = await RemindersMoveSync.afterFinderColumnChange(
            config: config(),
            project: project("Lepto", column: "Watch"),
            column: "Coding",
            inventory: inventory(matched: true, sentinelColumn: "Watch"),
            writer: stub
        )
        #expect(rem.colour == .synced(listTitle: "Lepto", column: "Coding"))
        #expect(rem.sentinel == .synced(listTitle: "Lepto", column: "Coding"))
        #expect(stub.updatedColours.count == 1)
        #expect(stub.updatedSentinels.count == 1)
    }

    @Test("Watch to Coding updates sentinel")
    func updateOnMove() async {
        let stub = StubRemindersMutator()
        let outcome = await RemindersMoveSync.mirrorFinderColumn(
            config: config(),
            project: project("Lepto", column: "Watch"),
            column: "Coding",
            inventory: inventory(matched: true, sentinelColumn: "Watch"),
            writer: stub
        )
        #expect(outcome == .synced(listTitle: "Lepto", column: "Coding"))
        #expect(stub.updatedSentinels.count == 1)
        #expect(stub.updatedSentinels[0].0 == "s1")
        #expect(stub.updatedSentinels[0].1 == "Coding")
    }

    @Test("missing list is skipped")
    func missingList() async {
        let stub = StubRemindersMutator()
        let outcome = await RemindersMoveSync.mirrorFinderColumn(
            config: config(),
            project: project("Lepto", column: "Watch"),
            column: "Coding",
            inventory: inventory(matched: false),
            writer: stub
        )
        guard case .skipped(let reason) = outcome else {
            Issue.record("expected skipped")
            return
        }
        #expect(reason.contains("doctor drift") || reason.contains("no unique"))
        #expect(stub.savedSentinels.isEmpty)
    }

    @Test("single-column pull Watch to Coding")
    func pullAdjacent() {
        var moved: [String] = []
        let outcome = RemindersMoveSync.applySentinelsToFinder(
            config: config(syncOnMove: false, syncFrom: true),
            projects: [project("Lepto", column: "Watch")],
            inventory: inventory(matched: true, sentinelColumn: "Coding"),
            setColumn: { project, column in
                moved.append("\(project.name):\(column)")
            }
        )
        #expect(outcome.updatedFolders == ["Lepto"])
        #expect(moved == ["Lepto:Coding"])
        #expect(outcome.errors.isEmpty)
    }

    @Test("multi-column pull Plan to Shipped is refused")
    func pullJumpRefused() {
        var moved: [String] = []
        let outcome = RemindersMoveSync.applySentinelsToFinder(
            config: config(syncOnMove: false, syncFrom: true),
            projects: [project("Lepto", column: "Plan")],
            inventory: inventory(matched: true, sentinelColumn: "Shipped"),
            setColumn: { project, column in
                moved.append("\(project.name):\(column)")
            }
        )
        #expect(moved.isEmpty)
        #expect(outcome.updatedFolders.isEmpty)
        #expect(outcome.errors.contains { $0.contains("more than one column") })
    }

    @Test("OmniFocus skip set is honoured")
    func skipFolders() {
        var moved: [String] = []
        let outcome = RemindersMoveSync.applySentinelsToFinder(
            config: config(syncOnMove: false, syncFrom: true),
            projects: [project("Lepto", column: "Watch")],
            inventory: inventory(matched: true, sentinelColumn: "Coding"),
            skipFolderNames: ["Lepto"],
            setColumn: { project, column in
                moved.append("\(project.name):\(column)")
            }
        )
        #expect(moved.isEmpty)
        #expect(outcome.updatedFolders.isEmpty)
    }

    @Test("isSingleColumnStep")
    func stepHelper() {
        #expect(RemindersMoveSync.isSingleColumnStep(from: "Watch", to: "Coding"))
        #expect(!RemindersMoveSync.isSingleColumnStep(from: "Plan", to: "Coding"))
        #expect(RemindersMoveSync.isSingleColumnStep(from: "Watch", to: "Paused"))
        #expect(RemindersMoveSync.isSingleColumnStep(from: nil, to: "Watch"))
    }

    @Test("paintSentinelPriority sets high priority when Finder has URGENT")
    func paintPriorityUrgent() async {
        let stub = StubRemindersMutator()
        let outcome = await RemindersMoveSync.paintSentinelPriority(
            config: config(syncOnMove: false),
            project: project("Lepto", column: "Watch", metaTags: ["URGENT ⚠️"]),
            inventory: inventory(matched: true, sentinelColumn: "Watch"),
            writer: stub
        )
        #expect(outcome == .synced(listTitle: "Lepto", column: "URGENT"))
        #expect(stub.updatedPriorities.count == 1)
        #expect(stub.updatedPriorities[0].0 == "s1")
        #expect(stub.updatedPriorities[0].1 == 1)
        #expect(stub.updatedSentinels.isEmpty)
        #expect(stub.savedSentinels.isEmpty)
    }

    @Test("paintSentinelPriority clears priority when URGENT is absent")
    func paintPriorityClear() async {
        let stub = StubRemindersMutator()
        let inv = RemindersInventory(
            generatedAt: Date(),
            lists: inventory(matched: true, sentinelColumn: "Watch").lists,
            reminders: [
                ReminderRecord(
                    id: "s1",
                    title: RemindersSentinel.title(column: "Watch"),
                    listTitle: "Lepto",
                    listId: "l1",
                    isCompleted: false,
                    dueDate: nil,
                    priority: 1,
                    notes: RemindersSentinel.notes(column: "Watch"),
                    matchedProject: "Lepto"
                ),
            ],
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
        let outcome = await RemindersMoveSync.paintSentinelPriority(
            config: config(syncOnMove: false),
            project: project("Lepto", column: "Watch"),
            inventory: inv,
            writer: stub
        )
        #expect(outcome == .synced(listTitle: "Lepto", column: "clear"))
        #expect(stub.updatedPriorities.count == 1)
        #expect(stub.updatedPriorities[0].0 == "s1")
        #expect(stub.updatedPriorities[0].1 == 0)
    }

    @Test("paintSentinelPriority skips when there is no sentinel")
    func paintPriorityNoSentinel() async {
        let stub = StubRemindersMutator()
        let outcome = await RemindersMoveSync.paintSentinelPriority(
            config: config(syncOnMove: false),
            project: project("Lepto", column: "Watch", metaTags: ["URGENT ⚠️"]),
            inventory: inventory(matched: true),
            writer: stub
        )
        guard case .skipped(let reason) = outcome else {
            Issue.record("expected skipped")
            return
        }
        #expect(reason.contains("sentinel"))
        #expect(stub.updatedPriorities.isEmpty)
        #expect(stub.savedSentinels.isEmpty)
    }

    @Test("paintAllMatchedSentinelPriorities paints unique sentinels")
    func paintAllPriorities() async {
        let stub = StubRemindersMutator()
        let result = await RemindersMoveSync.paintAllMatchedSentinelPriorities(
            config: config(syncOnMove: false),
            projects: [
                project("Lepto", column: "Watch", metaTags: ["URGENT ⚠️"]),
                project("Other", column: "Plan"),
            ],
            inventory: inventory(matched: true, sentinelColumn: "Watch"),
            writer: stub
        )
        #expect(result.painted == ["Lepto → URGENT"])
        #expect(result.skipped.contains { $0.contains("Other") })
        #expect(stub.updatedPriorities.count == 1)
        #expect(stub.updatedPriorities[0].0 == "s1")
        #expect(stub.updatedPriorities[0].1 == 1)
    }

    @Test("applyRefreshAppearance paints colour and URGENT priority without creating lists")
    func refreshAppearancePaints() async {
        let stub = StubRemindersMutator()
        let outcome = await RemindersMoveSync.applyRefreshAppearance(
            config: config(syncOnMove: false, syncFrom: false),
            projects: [project("Lepto", column: "Watch", metaTags: ["URGENT ⚠️"])],
            inventory: inventory(matched: true, sentinelColumn: "Watch"),
            writer: stub,
            pullSentinels: false,
            setColumn: { _, _ in Issue.record("should not pull Finder") }
        )
        #expect(outcome.updatedFolders.isEmpty)
        #expect(outcome.createdLists.isEmpty)
        #expect(outcome.paintedColours == ["Lepto → Watch"])
        #expect(outcome.paintedPriorities == ["Lepto → URGENT"])
        #expect(stub.createdLists.isEmpty)
        #expect(stub.savedSentinels.isEmpty)
        #expect(stub.updatedColours.count == 1)
        #expect(stub.updatedColours[0].colourIndex == 2)
        #expect(stub.updatedPriorities.count == 1)
        #expect(stub.updatedPriorities[0].1 == 1)
        #expect(outcome.errors.isEmpty)
    }

    @Test("applyRefreshAppearance paints colour from pulled sentinel column")
    func refreshAppearanceUsesPulledColumn() async {
        let stub = StubRemindersMutator()
        var moved: [String] = []
        let outcome = await RemindersMoveSync.applyRefreshAppearance(
            config: config(syncOnMove: false, syncFrom: true),
            projects: [project("Lepto", column: "Watch")],
            inventory: inventory(matched: true, sentinelColumn: "Coding"),
            writer: stub,
            pullSentinels: true,
            setColumn: { project, column in
                moved.append("\(project.name):\(column)")
            }
        )
        #expect(moved == ["Lepto:Coding"])
        #expect(outcome.updatedFolders == ["Lepto"])
        #expect(outcome.paintedColours == ["Lepto → Coding"])
        #expect(stub.updatedColours.count == 1)
        #expect(stub.updatedColours[0].colourIndex == 5)
    }

    @Test("mirrorFinderColumn writes sentinel priority from URGENT meta tag")
    func moveWritesUrgentPriority() async {
        let stub = StubRemindersMutator()
        let outcome = await RemindersMoveSync.mirrorFinderColumn(
            config: config(),
            project: project("Lepto", column: "Watch", metaTags: ["URGENT ⚠️"]),
            column: "Coding",
            inventory: inventory(matched: true, sentinelColumn: "Watch"),
            writer: stub
        )
        #expect(outcome == .synced(listTitle: "Lepto", column: "Coding"))
        #expect(stub.updatedSentinels.count == 1)
        #expect(stub.updatedPriorities.count == 1)
        #expect(stub.updatedPriorities[0].0 == "s1")
        #expect(stub.updatedPriorities[0].1 == 1)
    }
}
