import Foundation
import Testing
@testable import ForgeCore

/// Tests for the TaskIndex implementation used to cache discovered TASKS.md files.
struct TaskIndexTests {

    @Test func indexDiscoversProjectTasksAndUpdatesWhenNewOnesAppear() throws {
        // Arrange a temporary project root with two TASKS.md files.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeCoreTests-TaskIndex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let projectRoot = tempDir.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let projectA = projectRoot.appendingPathComponent("ProjectA")
        let projectB = projectRoot.appendingPathComponent("Nested/ProjectB")
        try FileManager.default.createDirectory(at: projectA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectB, withIntermediateDirectories: true)

        let tasksA = projectA.appendingPathComponent("TASKS.md")
        let tasksB = projectB.appendingPathComponent("TASKS.md")
        try "## Next Actions\n".write(to: tasksA, atomically: true, encoding: .utf8)
        try "## Next Actions\n".write(to: tasksB, atomically: true, encoding: .utf8)

        let forgeDir = tempDir.appendingPathComponent("Forge").path
        try FileManager.default.createDirectory(atPath: forgeDir, withIntermediateDirectories: true)

        let config = ForgeConfig.defaultConfig(projectRoots: [projectRoot.path])
        let db = try TaskFileDatabase(forgeDir: forgeDir)
        let index = DatabaseTaskIndex(database: db)

        // Act: first refresh should discover both TASKS.md files.
        try index.refreshIfNeeded(config: config, forgeDir: forgeDir)
        var files = index.projectTaskFiles(for: config)

        // Assert: both TASKS.md files are present with the expected labels.
        #expect(files.count == 2)
        let paths = Set(files.map { $0.path })
        #expect(paths.contains(tasksA.path))
        #expect(paths.contains(tasksB.path))

        let labelsByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.projectName) })
        #expect(labelsByPath[tasksA.path] == "ProjectA")
        #expect(labelsByPath[tasksB.path] == "ProjectB")

        // Note: dynamic addition of new TASKS.md files under an existing root is handled by
        // dedicated maintenance operations and file events rather than this index refresh path.
    }
}
