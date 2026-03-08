import Foundation
import Testing
@testable import ForgeCore

/// Tests for MarkdownIO.completeTask, including completion when the checkbox is already [x]
/// (e.g. after the user or forge-neovim toggled it before running `forge done`).
struct MarkdownIOTests {

    @Test func completeTaskWithUncheckedBoxMovesToCompletedAndAddsDone() throws {
        let content = """
        ## Next Actions
        - [ ] First task <!-- id:abc123 -->
        - [ ] Other task <!-- id:other1 -->

        ## Completed
        """
        let path = try writeTempTasks(content)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let markdownIO = MarkdownIO()
        let didComplete = try markdownIO.completeTask(withID: "abc123", inFileAt: path)

        #expect(didComplete == true)
        let result = try String(contentsOfFile: path, encoding: .utf8)
        #expect(result.contains("- [x] First task"))
        #expect(result.contains("@done("))
        #expect(result.contains("<!-- id:abc123 -->"))
        #expect(result.contains("## Completed"))
        // Task should appear under Completed section
        let completedRange = result.range(of: "## Completed")!
        let afterCompleted = result[completedRange.upperBound...]
        #expect(afterCompleted.contains("First task"))
        #expect(!afterCompleted.contains("## Next Actions") || afterCompleted.contains("- [ ] Other task"))
    }

    @Test func completeTaskWithAlreadyCheckedBoxStillMovesToCompletedAndAddsDone() throws {
        // Simulates editor (e.g. forge-neovim) having toggled [ ] to [x] before forge done runs.
        let content = """
        ## Next Actions
        - [x] Already checked task <!-- id:xyz789 -->
        - [ ] Another task <!-- id:another1 -->

        ## Completed
        """
        let path = try writeTempTasks(content)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let markdownIO = MarkdownIO()
        let didComplete = try markdownIO.completeTask(withID: "xyz789", inFileAt: path)

        #expect(didComplete == true)
        let result = try String(contentsOfFile: path, encoding: .utf8)
        #expect(result.contains("- [x] Already checked task"))
        #expect(result.contains("@done("))
        #expect(result.contains("<!-- id:xyz789 -->"))
        // Task should have been moved to Completed (not left in Next Actions)
        let nextActionsRange = result.range(of: "## Next Actions")!
        let afterNext = result[nextActionsRange.upperBound...]
        let completedSectionStart = afterNext.range(of: "## Completed")!.lowerBound
        let nextActionsBody = afterNext[..<completedSectionStart]
        #expect(!nextActionsBody.contains("xyz789"))
        let completedRange = result.range(of: "## Completed")!
        let afterCompleted = result[completedRange.upperBound...]
        #expect(afterCompleted.contains("Already checked task"))
    }

    @Test func completeTaskReturnsFalseWhenTaskIdNotFound() throws {
        let content = """
        ## Next Actions
        - [ ] Some task <!-- id:missing -->

        ## Completed
        """
        let path = try writeTempTasks(content)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let markdownIO = MarkdownIO()
        let didComplete = try markdownIO.completeTask(withID: "nonexistent", inFileAt: path)

        #expect(didComplete == false)
        let result = try String(contentsOfFile: path, encoding: .utf8)
        #expect(result == content)
    }

    private func writeTempTasks(_ content: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("TASKS.md").path
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
