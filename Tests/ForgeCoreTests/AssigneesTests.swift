import Foundation
import Testing
@testable import ForgeCore

struct AssigneesTests {

    @Test func normalisesPersonTagFromFinder() {
        #expect(ForgeTask.normalisedAssigneeIdentifier(fromRawTag: "#PeggySue") == "PeggySue")
        #expect(ForgeTask.normalisedAssigneeIdentifier(fromRawTag: "#  Alice  ") == "Alice")
        #expect(ForgeTask.normalisedAssigneeIdentifier(fromRawTag: "NoHash") == nil)
        #expect(ForgeTask.normalisedAssigneeIdentifier(fromRawTag: "# ") == nil)
    }

    @Test func markdownParsesPersonAssigneeTag() {
        let markdown = """
        ## Next Actions
        - [ ] Delegated task @person(#PeggySue) <!-- id:abc123 -->
        """
        let io = MarkdownIO()
        let tasks = io.parseTasks(from: markdown, projectName: "Demo")
        #expect(tasks.count == 1)
        let task = tasks[0]
        #expect(task.assignees == ["PeggySue"])
    }
}
