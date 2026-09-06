import Foundation
import Testing

@testable import ForgeCore

@Suite("Project open resolver")
struct ProjectOpenResolverTests {

    @Test("Resolves exact folder name under project roots")
    func resolvesExactFolderName() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("Apodemus luxury", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let found = ProjectOpenResolver.resolveProjectDirectory(
            named: "Apodemus luxury",
            projectRoots: [root.path]
        )
        #expect(found == project.path)
    }

    @Test("Returns nil for unknown project name")
    func unknownProjectReturnsNil() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let found = ProjectOpenResolver.resolveProjectDirectory(
            named: "Missing Project",
            projectRoots: [root.path]
        )
        #expect(found == nil)
    }

    @Test("Legacy primary target prefers TASKS.toml when present")
    func primaryPrefersTasksFile() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("Forge", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let tasks = project.appendingPathComponent("TASKS.toml")
        try "[[task]]\ntitle = \"x\"\n".write(to: tasks, atomically: true, encoding: .utf8)

        let target = ProjectOpenResolver.primaryOpenTarget(projectDirectory: project.path)
        #expect(target == .tasksFile(tasks))
    }

    @Test("Legacy primary target falls back to folder when TASKS.toml is missing")
    func primaryFallsBackToFolder() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("No Tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let target = ProjectOpenResolver.primaryOpenTarget(projectDirectory: project.path)
        #expect(target == .projectFolder(project))
    }

    @Test("Auto prefers Super Productivity when enabled")
    func autoPrefersSuperProductivity() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("Forge", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let config = ForgeConfig(
            projectRoots: [root.path],
            board: BoardConfig(columns: [], metaTags: [], tagAliases: [:]),
            superproductivity: SuperProductivityConfig(
                enabled: true,
                projectIds: ["Forge": "sp-forge-id"]
            )
        )
        let target = ProjectOpenResolver.tasksOpenTarget(
            projectDirectory: project.path,
            projectName: "Forge",
            config: config,
            preferredTaskManager: .auto
        )
        #expect(target == .superProductivity(projectId: "sp-forge-id"))
    }

    @Test("Explicit OmniFocus preference overrides Auto")
    func explicitOmniFocusOverride() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("Forge", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let config = ForgeConfig(
            projectRoots: [root.path],
            board: BoardConfig(columns: [], metaTags: [], tagAliases: [:]),
            superproductivity: SuperProductivityConfig(enabled: true)
        )
        let target = ProjectOpenResolver.tasksOpenTarget(
            projectDirectory: project.path,
            projectName: "Forge",
            config: config,
            preferredTaskManager: .omnifocus
        )
        #expect(target == .omnifocus(projectName: "Forge"))
    }

    @Test("TASKS.toml backend opens the file when present")
    func tasksTomlBackend() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("Forge", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let tasks = project.appendingPathComponent(ProjectOpenResolver.tasksFileName)
        FileManager.default.createFile(atPath: tasks.path, contents: Data(), attributes: nil)

        let config = ForgeConfig(
            projectRoots: [root.path],
            board: BoardConfig(columns: [], metaTags: [], tagAliases: [:])
        )
        let target = ProjectOpenResolver.tasksOpenTarget(
            projectDirectory: project.path,
            config: config,
            preferredTaskManager: .tasksToml
        )
        #expect(target == .tasksFile(tasks))
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-project-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
