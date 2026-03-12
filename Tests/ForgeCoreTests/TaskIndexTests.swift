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
        let initialFiles = index.projectTaskFiles(for: config)

        // Assert: both TASKS.md files are present with the expected labels.
        #expect(initialFiles.count == 2)
        let paths = Set(initialFiles.map { $0.path })
        #expect(paths.contains(tasksA.path))
        #expect(paths.contains(tasksB.path))

        let labelsByPath = Dictionary(uniqueKeysWithValues: initialFiles.map { ($0.path, $0.projectName) })
        #expect(labelsByPath[tasksA.path] == "ProjectA")
        #expect(labelsByPath[tasksB.path] == "ProjectB")

        // Act: add a third project under the same root after the initial refresh.
        let projectC = projectRoot.appendingPathComponent("Later/ProjectC")
        try FileManager.default.createDirectory(at: projectC, withIntermediateDirectories: true)
        let tasksC = projectC.appendingPathComponent("TASKS.md")
        try "## Next Actions\n".write(to: tasksC, atomically: true, encoding: .utf8)

        let rescanIndex = DatabaseTaskIndex(database: db, forceFullRescan: true)
        try rescanIndex.refreshIfNeeded(config: config, forgeDir: forgeDir)
        let updatedFiles = rescanIndex.projectTaskFiles(for: config)

        // Assert: the new TASKS.md is discovered on the subsequent refresh.
        #expect(updatedFiles.count == 3)
        let updatedPaths = Set(updatedFiles.map { $0.path })
        #expect(updatedPaths.contains(tasksC.path))
    }
}
