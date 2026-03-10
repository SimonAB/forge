import Foundation
import Testing
@testable import ForgeCore

/// Tests for the SQLite-backed TaskFileDatabase used to track task files and cached counts.
struct TaskFileDatabaseTests {

    @Test func canInsertAndQueryProjectFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeCoreTests-TaskDB-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let forgeDir = tempDir.appendingPathComponent("Forge").path
        try FileManager.default.createDirectory(atPath: forgeDir, withIntermediateDirectories: true)

        let db = try TaskFileDatabase(forgeDir: forgeDir)

        let root = "/tmp/Projects"
        let now = Date().timeIntervalSinceReferenceDate

        let records = [
            TaskFileRecord(
                path: "\(root)/ProjectA/TASKS.md",
                kind: .projectTasks,
                label: "ProjectA",
                projectRoot: root,
                mtime: now,
                size: 123,
                lastSeenAt: now,
                lastParsedAt: nil,
                overdueCount: 1,
                dueTodayCount: 2,
                inboxOpenCount: 0,
                isDeleted: false
            ),
            TaskFileRecord(
                path: "\(root)/ProjectB/TASKS.md",
                kind: .projectTasks,
                label: "ProjectB",
                projectRoot: root,
                mtime: now,
                size: 456,
                lastSeenAt: now,
                lastParsedAt: nil,
                overdueCount: 0,
                dueTodayCount: 1,
                inboxOpenCount: 0,
                isDeleted: false
            ),
        ]

        try db.upsertFiles(records)

        let fetched = try db.projectTaskFiles(under: [root])
        #expect(fetched.count == 2)
        let paths = Set(fetched.map(\.path))
        #expect(paths.contains(records[0].path))
        #expect(paths.contains(records[1].path))
    }

    @Test func aggregateCountsSumsOverNonDeletedFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgeCoreTests-TaskDB-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let forgeDir = tempDir.appendingPathComponent("Forge").path
        try FileManager.default.createDirectory(atPath: forgeDir, withIntermediateDirectories: true)

        let db = try TaskFileDatabase(forgeDir: forgeDir)

        let root = "/tmp/Projects"
        let now = Date().timeIntervalSinceReferenceDate

        let records = [
            TaskFileRecord(
                path: "\(root)/ProjectA/TASKS.md",
                kind: .projectTasks,
                label: "ProjectA",
                projectRoot: root,
                mtime: now,
                size: 100,
                lastSeenAt: now,
                lastParsedAt: nil,
                overdueCount: 2,
                dueTodayCount: 1,
                inboxOpenCount: 0,
                isDeleted: false
            ),
            TaskFileRecord(
                path: "\(root)/ProjectB/TASKS.md",
                kind: .projectTasks,
                label: "ProjectB",
                projectRoot: root,
                mtime: now,
                size: 200,
                lastSeenAt: now,
                lastParsedAt: nil,
                overdueCount: 1,
                dueTodayCount: 0,
                inboxOpenCount: 0,
                isDeleted: false
            ),
        ]

        try db.upsertFiles(records)

        let totals = try db.aggregateCounts()
        #expect(totals.overdue == 3)
        #expect(totals.dueToday == 1)
        #expect(totals.inboxOpen == 0)
    }
}
