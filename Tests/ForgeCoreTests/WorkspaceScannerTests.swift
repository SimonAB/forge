import Foundation
import Testing
@testable import ForgeCore

@Suite("WorkspaceScanner")
struct WorkspaceScannerTests {

    @Test func depthOneSkipsNestedTaggedProjects() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let container = (root as NSString).appendingPathComponent("Group")
        try FileManager.default.createDirectory(atPath: container, withIntermediateDirectories: true)
        let nested = (container as NSString).appendingPathComponent("NestedProject")
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)

        let tagStore = FinderTagStore()
        try tagStore.writeTags(["🔥 Forge", "Watch 👁️"], at: nested)

        let config = ForgeConfig.defaultConfig(projectRoots: [root])
        let projects = try WorkspaceScanner(config: config, tagStore: tagStore).scanProjects()

        #expect(projects.map(\.name) == [])
    }

    @Test func depthTwoFindsNestedTaggedProjects() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let container = (root as NSString).appendingPathComponent("Group")
        try FileManager.default.createDirectory(atPath: container, withIntermediateDirectories: true)
        let nested = (container as NSString).appendingPathComponent("NestedProject")
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)

        let tagStore = FinderTagStore()
        try tagStore.writeTags(["🔥 Forge", "Write ✒️"], at: nested)

        let config = ForgeConfig(
            projectRoots: [root],
            board: ForgeConfig.defaultConfig(projectRoots: [root]).board,
            projectTag: "🔥 Forge",
            projectScanDepth: 2
        )
        let projects = try WorkspaceScanner(config: config, tagStore: tagStore).scanProjects()

        #expect(projects.count == 1)
        #expect(projects[0].name == "NestedProject")
        #expect(projects[0].column == "Write")
        #expect(projects[0].path == nested)
    }

    @Test func depthTwoStillIncludesTopLevelProjects() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let top = (root as NSString).appendingPathComponent("TopLevel")
        try FileManager.default.createDirectory(atPath: top, withIntermediateDirectories: true)

        let tagStore = FinderTagStore()
        try tagStore.writeTags(["🔥 Forge", "Plan 📐"], at: top)

        let config = ForgeConfig(
            projectRoots: [root],
            board: ForgeConfig.defaultConfig(projectRoots: [root]).board,
            projectTag: "🔥 Forge",
            projectScanDepth: 2
        )
        let projects = try WorkspaceScanner(config: config, tagStore: tagStore).scanProjects()

        #expect(projects.count == 1)
        #expect(projects[0].name == "TopLevel")
    }

    @Test func taggedContainerDoesNotRecurseIntoChildren() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let container = (root as NSString).appendingPathComponent("TaggedGroup")
        try FileManager.default.createDirectory(atPath: container, withIntermediateDirectories: true)
        let nested = (container as NSString).appendingPathComponent("Child")
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)

        let tagStore = FinderTagStore()
        try tagStore.writeTags(["🔥 Forge", "Watch 👁️"], at: container)
        try tagStore.writeTags(["🔥 Forge", "Coding 🤖"], at: nested)

        let config = ForgeConfig(
            projectRoots: [root],
            board: ForgeConfig.defaultConfig(projectRoots: [root]).board,
            projectTag: "🔥 Forge",
            projectScanDepth: 2
        )
        let projects = try WorkspaceScanner(config: config, tagStore: tagStore).scanProjects()

        #expect(projects.map(\.name) == ["TaggedGroup"])
    }

    private func makeTempWorkspace() throws -> String {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("forge-scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }
}
