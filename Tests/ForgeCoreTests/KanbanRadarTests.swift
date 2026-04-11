import Foundation
import Testing

import ForgeCore

@Suite("Kanban radar")
struct KanbanRadarTests {

    private func makeProject(path: String, metaTags: [String] = []) -> Project {
        Project(
            name: (path as NSString).lastPathComponent,
            path: path,
            tags: [],
            workflowTag: nil,
            column: nil,
            metaTags: metaTags,
            assignees: []
        )
    }

    @Test("URGENT meta tag yields heat regardless of age")
    func urgentIsHeat() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-kanban-radar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let tasks = tmp.appendingPathComponent("TASKS.md")
        try "x".write(to: tasks, atomically: true, encoding: .utf8)
        let old = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: tasks.path)

        let project = makeProject(path: tmp.path, metaTags: ["URGENT ⚠️"])
        let now = Date()
        #expect(KanbanRadar.bucket(for: project, now: now) == .heat)
    }

    @Test("Stale TASKS.md (21+ days) is heat")
    func staleTasksIsHeat() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-kanban-radar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let tasks = tmp.appendingPathComponent("TASKS.md")
        try "x".write(to: tasks, atomically: true, encoding: .utf8)
        let old = Date().addingTimeInterval(-22 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: tasks.path)

        let project = makeProject(path: tmp.path)
        let now = Date()
        #expect(KanbanRadar.bucket(for: project, now: now) == .heat)
    }

    @Test("TASKS.md 7–20 days old is watch when not urgent")
    func weekOldIsWatch() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-kanban-radar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let tasks = tmp.appendingPathComponent("TASKS.md")
        try "x".write(to: tasks, atomically: true, encoding: .utf8)
        let old = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: tasks.path)

        let project = makeProject(path: tmp.path)
        let now = Date()
        #expect(KanbanRadar.bucket(for: project, now: now) == .watch)
    }

    @Test("Recently touched TASKS.md is calm")
    func recentIsCalm() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-kanban-radar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let tasks = tmp.appendingPathComponent("TASKS.md")
        try "x".write(to: tasks, atomically: true, encoding: .utf8)

        let project = makeProject(path: tmp.path)
        let now = Date()
        #expect(KanbanRadar.bucket(for: project, now: now) == .calm)
    }
}
