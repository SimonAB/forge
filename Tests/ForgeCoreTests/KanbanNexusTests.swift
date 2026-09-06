import Foundation
import Testing
import Yams
@testable import ForgeCore

@Test func kanbanSidecarRoundTrip() throws {
    let original = KanbanSidecar(
        column: "Coding",
        workflowTag: "Coding 🤖",
        meta: ["URGENT ⚠️"],
        assignees: ["#Alice"],
        source: "migrate"
    )
    let text = KanbanSidecarStore.encode(original)
    let decoded = try KanbanSidecarStore.decode(text)
    #expect(decoded.column == "Coding")
    #expect(decoded.workflowTag == "Coding 🤖")
    #expect(decoded.meta == ["URGENT ⚠️"])
    #expect(decoded.assignees == ["#Alice"])
    #expect(decoded.source == "migrate")
    #expect(decoded.schema == 1)
}

@Test func kanbanNexusWritesSidecarAndTags() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-nexus-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = InMemoryTagStore()
    var config = ForgeConfig.defaultConfig(projectRoots: [dir.path])
    config = ForgeConfig(
        projectRoots: config.projectRoots,
        board: config.board,
        nexus: NexusConfig(sidecarEnabled: true),
        projectTag: nil
    )

    try KanbanNexus.setWorkflowColumn(
        path: dir.path,
        column: "Watch",
        config: config,
        tagStore: store,
        source: KanbanNexus.Source.migrate
    )

    #expect(store.tags(at: dir.path).contains("Watch 👁️"))
    let sidecar = try KanbanSidecarStore.load(projectPath: dir.path)
    #expect(sidecar?.column == "Watch")
    #expect(sidecar?.workflowTag == "Watch 👁️")
}

@Test func kanbanFsSyncSidecarToTags() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-fs-\(UUID().uuidString)", isDirectory: true)
    let project = root.appendingPathComponent("Demo", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = InMemoryTagStore()
    store.setTags(["Coding 🤖"], at: project.path)
    let config = ForgeConfig(
        projectRoots: [root.path],
        board: ForgeConfig.defaultConfig(projectRoots: [root.path]).board,
        nexus: NexusConfig(sidecarEnabled: true),
        projectTag: nil
    )
    try KanbanSidecarStore.save(
        KanbanSidecarStore.make(
            column: "Plan",
            workflowTag: "Plan 📐",
            meta: [],
            assignees: [],
            source: "migrate"
        ),
        projectPath: project.path
    )

    let projects = [
        Project(
            name: "Demo",
            path: project.path,
            tags: ["Coding 🤖"],
            workflowTag: "Coding 🤖",
            column: "Coding",
            metaTags: [],
            assignees: []
        ),
    ]
    let changes = try KanbanFsSync.sync(
        projects: projects,
        config: config,
        prefer: .sidecar,
        apply: true,
        tagStore: store
    )
    #expect(changes.count == 1)
    #expect(store.tags(at: project.path).contains("Plan 📐"))
    #expect(!store.tags(at: project.path).contains("Coding 🤖"))
}

@Test func nexusConfigDefaultsOff() throws {
    let config = try decodeNexusYAML("""
    project_roots:
      - /tmp
    board:
      columns:
        - name: Plan
          tag: "Plan"
          colour: 4
      meta_tags: []
      tag_aliases: {}
    """)
    #expect(config.nexus.sidecarEnabled == false)
    #expect(config.nexus.preferSidecar == true)
    #expect(config.nexus.spColumnMirror == false)
}

@Test func nexusConfigParsesFlags() throws {
    let config = try decodeNexusYAML("""
    project_roots:
      - /tmp
    board:
      columns:
        - name: Plan
          tag: "Plan"
          colour: 4
      meta_tags: []
      tag_aliases: {}
    nexus:
      sidecar_enabled: true
      prefer_sidecar: false
      sync_sidecar_on_refresh: true
      sp_column_mirror: true
    """)
    #expect(config.nexus.sidecarEnabled == true)
    #expect(config.nexus.preferSidecar == false)
    #expect(config.nexus.syncSidecarOnRefresh == true)
    #expect(config.nexus.spColumnMirror == true)
}

private func decodeNexusYAML(_ yaml: String) throws -> ForgeConfig {
    let decoder = YAMLDecoder()
    return try decoder.decode(ForgeConfig.self, from: yaml)
}

@Test(arguments: ["sidecar", "finder", "refresh"])
func kanbanMetadataSyncWithoutColumnChange(direction: String) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("forge-meta-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let config = ForgeConfig.defaultConfig(projectRoots: [root.path])
    let store = InMemoryTagStore()
    store.setTags(["Coding 🤖", "#Bob", "Unrelated"], at: root.path)
    try KanbanSidecarStore.save(KanbanSidecar(
        column: "Coding", workflowTag: "Coding 🤖", meta: ["URGENT ⚠️"],
        assignees: ["#Alice"]
    ), projectPath: root.path)
    let projects = [Project(name: "Demo", path: root.path, tags: store.tags(at: root.path),
                            workflowTag: "Coding 🤖", column: "Coding", metaTags: [], assignees: ["#Bob"])]
    let drift = try KanbanFsSync.doctor(projects: projects, config: config, tagStore: store)
    #expect(drift.map(\.issue) == ["metadata-drift"])
    let preview = try KanbanFsSync.sync(projects: projects, config: config, apply: false, tagStore: store)
    #expect(preview.count == 1)
    #expect(store.tags(at: root.path) == ["Coding 🤖", "#Bob", "Unrelated"])
    if direction == "refresh" {
        let changes = try KanbanFsSync.paintAllFromSidecar(projects: projects, config: config, tagStore: store)
        #expect(changes.count == 1)
    } else {
        let changes = try KanbanFsSync.sync(projects: projects, config: config,
            prefer: direction == "finder" ? .finder : .sidecar, apply: true, tagStore: store)
        #expect(changes.count == 1)
    }
    if direction == "finder" {
        let sidecar = try KanbanSidecarStore.load(projectPath: root.path)
        #expect(sidecar?.meta == [])
        #expect(sidecar?.assignees == ["#Bob"])
    } else {
        #expect(Set(store.tags(at: root.path)) == Set(["Coding 🤖", "URGENT ⚠️", "#Alice", "Unrelated"]))
    }
    #expect(try KanbanFsSync.doctor(projects: projects, config: config, tagStore: store).isEmpty)
    #expect(try KanbanFsSync.sync(projects: projects, config: config, apply: true, tagStore: store).isEmpty)
}
