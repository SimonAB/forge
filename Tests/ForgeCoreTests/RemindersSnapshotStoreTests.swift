import Foundation
import Testing

@testable import ForgeCore

@Suite("Reminders snapshot store")
struct RemindersSnapshotStoreTests {
    @Test("loadIfEligible rejects when snapshot is older than maxAge")
    func rejectsStale() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-reminders-snap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let old = Date().addingTimeInterval(-3600)
        let inventory = RemindersInventory(
            generatedAt: old,
            lists: [],
            reminders: [],
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
        try RemindersSnapshotStore.write(forgeDir: tmp.path, inventory: inventory)
        let eligible = try RemindersSnapshotStore.loadIfEligible(
            forgeDir: tmp.path,
            maxAge: 900
        )
        #expect(eligible == nil)
    }

    @Test("fresh snapshot round-trips inventory JSON")
    func roundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-reminders-snap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let due = Date(timeIntervalSince1970: 1_775_664_000)
        let inventory = RemindersInventory(
            generatedAt: Date(),
            lists: [
                RemindersListRecord(
                    id: "list-1",
                    title: "Lepto",
                    matchedProject: "Lepto",
                    incompleteCount: 1,
                    completedCount: 0
                ),
            ],
            reminders: [
                ReminderRecord(
                    id: "rem-1",
                    title: "Draft methods",
                    listTitle: "Lepto",
                    listId: "list-1",
                    isCompleted: false,
                    dueDate: due,
                    priority: 5,
                    notes: "Intro",
                    matchedProject: "Lepto"
                ),
            ],
            unmatchedListTitles: ["Forge"],
            unmatchedProjectNames: ["Other"],
            writer: "test"
        )
        try RemindersSnapshotStore.write(forgeDir: tmp.path, inventory: inventory)
        let loaded = try RemindersSnapshotStore.loadIfEligible(
            forgeDir: tmp.path,
            maxAge: 900
        )
        let snap = try #require(loaded)
        #expect(snap.lists == inventory.lists)
        #expect(snap.reminders == inventory.reminders)
        #expect(snap.unmatchedListTitles == ["Forge"])
        #expect(snap.unmatchedProjectNames == ["Other"])
        #expect(snap.writer == "test")
    }

    @Test("missing snapshot returns nil")
    func missingIsNil() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-reminders-missing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(try RemindersSnapshotStore.read(forgeDir: tmp.path) == nil)
        #expect(try RemindersSnapshotStore.loadIfEligible(forgeDir: tmp.path, maxAge: 900) == nil)
    }

    @Test("corrupt snapshot JSON is ineligible")
    func corruptIsIneligible() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-reminders-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cache = tmp.appendingPathComponent(".cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(
            to: cache.appendingPathComponent(RemindersSnapshotStore.fileName)
        )
        #expect(try RemindersSnapshotStore.loadIfEligible(forgeDir: tmp.path, maxAge: 900) == nil)
        #expect(RemindersSnapshotStore.statusSummary(forgeDir: tmp.path) == "Snapshot: none")
    }
}
