import Foundation
import Testing

@testable import ForgeCore

@Suite("Reminders list matching")
struct RemindersMatchingTests {
    private let projects = ["Lepto", "VHP2_manuscript", "Lab-notebook"]

    @Test("exact folder title matches case-insensitively")
    func exactTitleMatch() {
        #expect(
            RemindersMatching.matchList(
                title: "Lepto",
                projectNames: projects,
                folderAliases: [:]
            ) == "Lepto"
        )
        #expect(
            RemindersMatching.matchList(
                title: "lepto",
                projectNames: projects,
                folderAliases: [:]
            ) == "Lepto"
        )
    }

    @Test("folder alias maps list title to folder")
    func aliasMatch() {
        #expect(
            RemindersMatching.matchList(
                title: "VHP2 ms",
                projectNames: projects,
                folderAliases: ["VHP2 ms": "VHP2_manuscript"]
            ) == "VHP2_manuscript"
        )
        #expect(
            RemindersMatching.matchList(
                title: "vhp2 ms",
                projectNames: projects,
                folderAliases: ["VHP2 ms": "VHP2_manuscript"]
            ) == "VHP2_manuscript"
        )
    }

    @Test("alias to an unknown folder is unmatched")
    func aliasWithoutFolderIsUnmatched() {
        #expect(
            RemindersMatching.matchList(
                title: "VHP2 ms",
                projectNames: ["Lepto"],
                folderAliases: ["VHP2 ms": "VHP2_manuscript"]
            ) == nil
        )
    }

    @Test("inbox list Forge is unmatched when no such folder")
    func inboxUnmatched() {
        #expect(
            RemindersMatching.matchList(
                title: "Forge",
                projectNames: projects,
                folderAliases: [:]
            ) == nil
        )
    }

    @Test("inbox list named like a folder matches that folder")
    func inboxNamedLikeFolderMatches() {
        #expect(
            RemindersMatching.matchList(
                title: "Forge",
                projectNames: ["Forge", "Lepto"],
                folderAliases: [:]
            ) == "Forge"
        )
    }

    @Test("substring titles do not match")
    func noSubstringMatch() {
        #expect(
            RemindersMatching.matchList(
                title: "Lab",
                projectNames: projects,
                folderAliases: [:]
            ) == nil
        )
    }

    @Test("inventory groups unmatched lists and folders")
    func inventoryUnmatched() {
        let config = RemindersConfig(list: "Forge")
        let inventory = RemindersMatching.buildInventory(
            lists: [
                (id: "l1", title: "Lepto"),
                (id: "l2", title: "Forge"),
            ],
            reminders: [
                ReminderDraft(id: "r1", title: "Draft methods", listId: "l1"),
                ReminderDraft(id: "r2", title: "Buy milk", listId: "l2"),
                ReminderDraft(id: "r3", title: "Done note", listId: "l1", isCompleted: true),
            ],
            projectNames: projects,
            config: config
        )
        #expect(inventory.lists.first { $0.title == "Lepto" }?.matchedProject == "Lepto")
        #expect(inventory.lists.first { $0.title == "Lepto" }?.incompleteCount == 1)
        #expect(inventory.lists.first { $0.title == "Lepto" }?.completedCount == 1)
        #expect(inventory.unmatchedListTitles == ["Forge"])
        #expect(inventory.unmatchedProjectNames == ["Lab-notebook", "VHP2_manuscript"])
        #expect(inventory.reminders.first { $0.id == "r1" }?.matchedProject == "Lepto")
        #expect(inventory.reminders.first { $0.id == "r2" }?.matchedProject == nil)
    }

    @Test("list title query is exact or unique prefix, not a loose substring")
    func listTitleQuery() {
        let titles = ["Lab", "Lab-notebook", "Lepto"]
        #expect(RemindersMatching.resolveListTitle("Lab", in: titles) == .ok("Lab"))
        #expect(RemindersMatching.resolveListTitle("lab-", in: titles) == .ok("Lab-notebook"))
        #expect(RemindersMatching.resolveListTitle("L", in: titles) == .ambiguous(["Lab", "Lab-notebook", "Lepto"]))
        #expect(RemindersMatching.resolveListTitle("Missing", in: titles) == .none)
        #expect(RemindersMatching.resolveListTitle("  ", in: titles) == .none)
    }

    @Test("project query resolves exact then unique substring")
    func projectQueryResolve() {
        let names = ["Lepto", "Lab-notebook", "Lab"]
        #expect(RemindersMatching.resolveProjectName("Lepto", in: names) == .ok("Lepto"))
        #expect(RemindersMatching.resolveProjectName("lepto", in: names) == .ok("Lepto"))
        #expect(RemindersMatching.resolveProjectName("notebook", in: names) == .ok("Lab-notebook"))
        #expect(RemindersMatching.resolveProjectName("Lab", in: names) == .ok("Lab"))
        #expect(RemindersMatching.resolveProjectName("La", in: names) == .ambiguous(["Lab", "Lab-notebook"]))
        #expect(RemindersMatching.resolveProjectName("Nope", in: names) == .none)
        #expect(RemindersMatching.resolveProjectName("  ", in: names) == .none)
    }

    @Test("buildInventory applies folder aliases")
    func inventoryAlias() {
        let config = RemindersConfig(
            folderAliases: ["VHP2 ms": "VHP2_manuscript"]
        )
        let inventory = RemindersMatching.buildInventory(
            lists: [(id: "l1", title: "VHP2 ms")],
            reminders: [
                ReminderDraft(id: "r1", title: "Revise intro", listId: "l1"),
            ],
            projectNames: projects,
            config: config
        )
        #expect(inventory.lists.first?.matchedProject == "VHP2_manuscript")
        #expect(inventory.reminders.first?.matchedProject == "VHP2_manuscript")
        #expect(inventory.unmatchedProjectNames == ["Lab-notebook", "Lepto"])
    }
}
