import Testing
import EventKit
@testable import ForgeCore

struct SyncEngineTests {

    @Test func preferCompletedSources_prefersCompletedButKeepsFirstIDOrder() throws {
        let t1Incomplete = ForgeTask(
            id: "t1",
            text: "Task 1",
            isCompleted: false
        )
        let t1Complete = ForgeTask(
            id: "t1",
            text: "Task 1",
            isCompleted: true
        )
        let t2Incomplete = ForgeTask(
            id: "t2",
            text: "Task 2",
            isCompleted: false
        )

        let sourced: [SyncEngine.SourcedTask] = [
            .init(task: t1Incomplete, filePath: "A.md", areaTags: [], isAreaTask: false),
            .init(task: t2Incomplete, filePath: "C.md", areaTags: [], isAreaTask: false),
            .init(task: t1Complete, filePath: "B.md", areaTags: [], isAreaTask: false),
        ]

        let chosen = SyncEngine.preferCompletedSources(for: sourced)

        // "t1" first appeared before "t2", so it must remain first even though we switch the
        // representative source to the completed variant.
        #expect(chosen.count == 2)
        #expect(chosen[0].task.id == "t1")
        #expect(chosen[0].filePath == "B.md")
        #expect(chosen[0].task.isCompleted)
        #expect(chosen[1].task.id == "t2")
        #expect(chosen[1].filePath == "C.md")
    }

    @Test func preferCompletedSources_doesNotReplaceCompletedWithIncomplete() throws {
        let t1Complete = ForgeTask(
            id: "t1",
            text: "Task 1",
            isCompleted: true
        )
        let t1Incomplete = ForgeTask(
            id: "t1",
            text: "Task 1",
            isCompleted: false
        )

        let sourced: [SyncEngine.SourcedTask] = [
            .init(task: t1Complete, filePath: "A.md", areaTags: [], isAreaTask: false),
            .init(task: t1Incomplete, filePath: "B.md", areaTags: [], isAreaTask: false),
        ]

        let chosen = SyncEngine.preferCompletedSources(for: sourced)

        #expect(chosen.count == 1)
        #expect(chosen[0].filePath == "A.md")
        #expect(chosen[0].task.isCompleted)
    }

    @Test func preferCompletedSources_keepsFirstCompletedVariant() throws {
        let t1Incomplete = ForgeTask(
            id: "t1",
            text: "Task 1",
            isCompleted: false
        )
        let t1Complete1 = ForgeTask(
            id: "t1",
            text: "Task 1",
            isCompleted: true
        )
        let t1Complete2 = ForgeTask(
            id: "t1",
            text: "Task 1",
            isCompleted: true
        )

        let sourced: [SyncEngine.SourcedTask] = [
            .init(task: t1Incomplete, filePath: "A.md", areaTags: [], isAreaTask: false),
            .init(task: t1Complete1, filePath: "B.md", areaTags: [], isAreaTask: false),
            .init(task: t1Complete2, filePath: "C.md", areaTags: [], isAreaTask: false),
        ]

        let chosen = SyncEngine.preferCompletedSources(for: sourced)

        #expect(chosen.count == 1)
        #expect(chosen[0].filePath == "B.md")
        #expect(chosen[0].task.isCompleted)
    }

    @Test func shouldIncludeTaskMarkdownFile_exclusionRules() throws {
        #expect(SyncEngine.shouldIncludeTaskMarkdownFile("inbox.md") == true)
        #expect(SyncEngine.shouldIncludeTaskMarkdownFile("home.md") == true)
        #expect(SyncEngine.shouldIncludeTaskMarkdownFile("due.md") == false)
        #expect(SyncEngine.shouldIncludeTaskMarkdownFile("config.yaml") == false)
        #expect(SyncEngine.shouldIncludeTaskMarkdownFile("not-a-markdown.txt") == false)
    }

    @Test func pickUnambiguousSingleElement_onlyWhenCountIsOne() throws {
        #expect(SyncEngine.pickUnambiguousSingleElement([] as [Int]) == nil)
        #expect(SyncEngine.pickUnambiguousSingleElement([1]) == 1)
        #expect(SyncEngine.pickUnambiguousSingleElement([1, 2]) == nil)
    }

    @Test func reminderLooseSignature_matchesTaskLooseSignature() throws {
        let cal = Calendar.current
        let dueComponents = DateComponents(year: 2026, month: 3, day: 18)
        let deferComponents = DateComponents(year: 2026, month: 3, day: 20)
        let dueDate = cal.date(from: dueComponents)!
        let deferDate = cal.date(from: deferComponents)!

        let task = ForgeTask(
            id: "t1",
            text: "  My  Title  ",
            isCompleted: false,
            dueDate: dueDate,
            dueHasTime: false,
            deferDate: deferDate
        )

        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "My  Title"
        reminder.dueDateComponents = dueComponents
        reminder.startDateComponents = deferComponents

        let taskSig = SyncEngine.taskLooseSignature(for: task)
        let reminderSig = SyncEngine.reminderLooseSignature(for: reminder)

        #expect(taskSig == reminderSig)
    }
}

