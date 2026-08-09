import Foundation
import Testing

@testable import ForgeCore

@Suite("Reminders align apply + stub writer")
struct RemindersWriterTests {
    @Test("apply create_list then ensure_sentinel uses new list id")
    func applyCreateThenSentinel() async throws {
        let stub = StubRemindersMutator()
        let plan = RemindersAlignPlan(
            generatedAt: Date(),
            proposals: [
                RemindersAlignProposal(
                    kind: .createList,
                    folderName: "Lepto",
                    listTitle: "Lepto",
                    summary: "Create Reminders list 'Lepto'."
                ),
                RemindersAlignProposal(
                    kind: .ensureSentinel,
                    folderName: "Lepto",
                    column: "Watch",
                    summary: "Add sentinel."
                ),
                RemindersAlignProposal(
                    kind: .proposeFinderShipped,
                    folderName: "Other",
                    summary: "Propose Finder Shipped for 'Other'."
                ),
            ],
            dryRun: false
        )
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let enabled = ForgeConfig(
            projectRoots: config.projectRoots,
            board: config.board,
            calendar: config.calendar,
            omnifocus: config.omnifocus,
            reminders: RemindersConfig(enabled: true, syncOnMove: true),
            gtd: config.gtd,
            workspaceTags: config.workspaceTags,
            projectAreas: config.projectAreas,
            terminal: config.terminal,
            projectTag: config.projectTag,
            projectScanDepth: config.projectScanDepth,
            dueConflictPolicy: config.dueConflictPolicy
        )
        let result = try await RemindersService(config: enabled).apply(plan: plan, writer: stub)
        #expect(stub.createdLists == ["Lepto"])
        #expect(stub.savedSentinels.count == 1)
        #expect(stub.savedSentinels.first?.column == "Watch")
        #expect(stub.savedSentinels.first?.listId == stub.createdIds["Lepto"])
        #expect(result.createdLists == ["Lepto"])
        #expect(result.sentinelsWritten == 1)
        #expect(result.skipped.count == 1)
        #expect(stub.updatedPriorities.count == 1)
        #expect(stub.updatedPriorities[0].1 == 0)
    }

    @Test("apply ensure_sentinel sets high priority for URGENT folders")
    func applySentinelUrgentPriority() async throws {
        let stub = StubRemindersMutator()
        let plan = RemindersAlignPlan(
            generatedAt: Date(),
            proposals: [
                RemindersAlignProposal(
                    kind: .ensureSentinel,
                    folderName: "Lepto",
                    listId: "list-existing",
                    column: "Review",
                    summary: "Add sentinel."
                ),
            ],
            dryRun: false
        )
        let base = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let config = ForgeConfig(
            projectRoots: base.projectRoots,
            board: base.board,
            calendar: base.calendar,
            omnifocus: base.omnifocus,
            reminders: RemindersConfig(enabled: true, syncOnMove: true),
            gtd: base.gtd,
            workspaceTags: base.workspaceTags,
            projectAreas: base.projectAreas,
            terminal: base.terminal,
            projectTag: base.projectTag,
            projectScanDepth: base.projectScanDepth,
            dueConflictPolicy: base.dueConflictPolicy
        )
        let urgent = Project(
            name: "Lepto",
            path: "/tmp/Lepto",
            tags: ["Review", "URGENT ⚠️"],
            workflowTag: "Review",
            column: "Review",
            metaTags: ["URGENT ⚠️"]
        )
        let result = try await RemindersService(config: config).apply(
            plan: plan,
            writer: stub,
            projects: [urgent]
        )
        #expect(result.sentinelsWritten == 1)
        #expect(stub.savedSentinels.count == 1)
        #expect(stub.updatedPriorities.count == 1)
        #expect(stub.updatedPriorities[0].1 == 1)
    }

    @Test("apply update_sentinel calls writer")
    func applyUpdate() async throws {
        let stub = StubRemindersMutator()
        let plan = RemindersAlignPlan(
            generatedAt: Date(),
            proposals: [
                RemindersAlignProposal(
                    kind: .updateSentinel,
                    folderName: "Lepto",
                    reminderId: "rem-1",
                    column: "Coding",
                    summary: "Update sentinel."
                ),
            ],
            dryRun: false
        )
        let base = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let config = ForgeConfig(
            projectRoots: base.projectRoots,
            board: base.board,
            calendar: base.calendar,
            omnifocus: base.omnifocus,
            reminders: RemindersConfig(enabled: true, syncOnMove: true),
            gtd: base.gtd,
            workspaceTags: base.workspaceTags,
            projectAreas: base.projectAreas,
            terminal: base.terminal,
            projectTag: base.projectTag,
            projectScanDepth: base.projectScanDepth,
            dueConflictPolicy: base.dueConflictPolicy
        )
        let result = try await RemindersService(config: config).apply(plan: plan, writer: stub)
        #expect(stub.updatedSentinels.count == 1)
        #expect(stub.updatedSentinels[0].0 == "rem-1")
        #expect(stub.updatedSentinels[0].1 == "Coding")
        #expect(stub.updatedPriorities.count == 1)
        #expect(stub.updatedPriorities[0].0 == "rem-1")
        #expect(stub.updatedPriorities[0].1 == 0)
        #expect(result.sentinelsWritten == 1)
    }

    @Test("ensureMissingLists creates forge_only lists only")
    func ensureMissingListsOnlyCreates() async throws {
        let stub = StubRemindersMutator()
        let inv = RemindersInventory(
            generatedAt: Date(),
            lists: [
                RemindersListRecord(
                    id: "shop",
                    title: "Shopping",
                    matchedProject: nil,
                    incompleteCount: 1,
                    completedCount: 0
                ),
                RemindersListRecord(
                    id: "l1",
                    title: "Lepto",
                    matchedProject: "Lepto",
                    incompleteCount: 1,
                    completedCount: 0
                ),
            ],
            reminders: [],
            unmatchedListTitles: ["Shopping"],
            unmatchedProjectNames: ["VHP2_manuscript"],
            writer: "test"
        )
        let lepto = Project(
            name: "Lepto",
            path: "/tmp/Lepto",
            tags: ["Watch"],
            workflowTag: "Watch",
            column: "Watch",
            metaTags: []
        )
        let vhp = Project(
            name: "VHP2_manuscript",
            path: "/tmp/VHP2_manuscript",
            tags: ["Watch"],
            workflowTag: "Watch",
            column: "Watch",
            metaTags: []
        )
        let base = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let config = ForgeConfig(
            projectRoots: base.projectRoots,
            board: base.board,
            calendar: base.calendar,
            omnifocus: base.omnifocus,
            reminders: RemindersConfig(enabled: true),
            gtd: base.gtd,
            workspaceTags: base.workspaceTags,
            projectAreas: base.projectAreas,
            terminal: base.terminal,
            projectTag: base.projectTag,
            projectScanDepth: base.projectScanDepth,
            dueConflictPolicy: base.dueConflictPolicy
        )
        let result = try await RemindersService(config: config).ensureMissingLists(
            projects: [lepto, vhp],
            inventory: inv,
            writer: stub
        )
        #expect(stub.createdLists == ["VHP2_manuscript"])
        #expect(stub.createdColourIndexes["VHP2_manuscript"] == 2)
        #expect(stub.savedSentinels.isEmpty)
        #expect(result.createdLists == ["VHP2_manuscript"])
        #expect(result.sentinelsWritten == 0)
    }
}

final class StubRemindersMutator: RemindersMutating, @unchecked Sendable {
    private(set) var createdLists: [String] = []
    private(set) var createdIds: [String: String] = [:]
    private(set) var createdColourIndexes: [String: Int?] = [:]
    private(set) var savedSentinels: [(listId: String, column: String)] = []
    private(set) var updatedSentinels: [(String, String)] = []
    private(set) var updatedColours: [(listId: String, colourIndex: Int)] = []
    private(set) var updatedPriorities: [(String, Int)] = []

    func createList(title: String, sourceTitle: String?, colourIndex: Int?) async throws -> String {
        let id = "list-\(createdLists.count + 1)"
        createdLists.append(title)
        createdIds[title] = id
        createdColourIndexes[title] = colourIndex
        return id
    }

    func saveSentinel(listId: String, column: String, prefix: String) async throws -> String {
        savedSentinels.append((listId, column))
        return "sentinel-\(savedSentinels.count)"
    }

    func updateSentinel(reminderId: String, column: String, prefix: String) async throws {
        updatedSentinels.append((reminderId, column))
    }

    func updateListColour(listId: String, colourIndex: Int) async throws {
        updatedColours.append((listId, colourIndex))
    }

    func updateReminderPriority(reminderId: String, priority: Int) async throws {
        updatedPriorities.append((reminderId, priority))
    }
}
