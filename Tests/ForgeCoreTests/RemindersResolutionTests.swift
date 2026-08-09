import Foundation
import Testing

@testable import ForgeCore

@Suite("Reminders snapshot resolution")
struct RemindersResolutionTests {
    private func makeForgeDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-rem-res-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func inventory(generatedAt: Date, completed: Bool = false) -> RemindersInventory {
        RemindersInventory(
            generatedAt: generatedAt,
            lists: [
                RemindersListRecord(
                    id: "l1",
                    title: "Lepto",
                    matchedProject: "Lepto",
                    incompleteCount: completed ? 0 : 1,
                    completedCount: completed ? 1 : 0
                ),
            ],
            reminders: [
                ReminderRecord(
                    id: "r1",
                    title: completed ? "Done" : "Open",
                    listTitle: "Lepto",
                    listId: "l1",
                    isCompleted: completed,
                    dueDate: nil,
                    priority: 0,
                    notes: nil,
                    matchedProject: "Lepto"
                ),
            ],
            unmatchedListTitles: [],
            unmatchedProjectNames: [],
            writer: "test"
        )
    }

    private func enabledConfig() -> ForgeConfig {
        let base = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        return ForgeConfig(
            projectRoots: base.projectRoots,
            board: base.board,
            calendar: base.calendar,
            omnifocus: base.omnifocus,
            reminders: RemindersConfig(enabled: true, snapshotMaxAgeSeconds: 900),
            gtd: base.gtd,
            workspaceTags: base.workspaceTags,
            projectAreas: base.projectAreas,
            terminal: base.terminal,
            projectTag: base.projectTag,
            projectScanDepth: base.projectScanDepth,
            dueConflictPolicy: base.dueConflictPolicy
        )
    }

    @Test("eligible snapshot is used and stub fetcher is not called")
    func usesEligibleSnapshot() async throws {
        let dir = try makeForgeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let snap = inventory(generatedAt: Date())
        try RemindersSnapshotStore.write(forgeDir: dir.path, inventory: snap)
        let stub = StubRemindersFetcher(inventory: inventory(generatedAt: Date(), completed: true))
        let result = try await RemindersInventoryResolution.resolve(
            forgeDir: dir.path,
            config: enabledConfig(),
            projectNames: ["Lepto"],
            live: false,
            includeCompleted: false,
            reader: stub
        )
        #expect(stub.fetchCount == 0)
        guard case .forgeAppSnapshot = result.source else {
            Issue.record("expected snapshot source")
            return
        }
        #expect(result.inventory.reminders.map(\.title) == ["Open"])
    }

    @Test("live flag skips snapshot and calls fetcher")
    func liveSkipsSnapshot() async throws {
        let dir = try makeForgeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try RemindersSnapshotStore.write(forgeDir: dir.path, inventory: inventory(generatedAt: Date()))
        let liveInv = inventory(generatedAt: Date(), completed: false)
        let stub = StubRemindersFetcher(inventory: liveInv)
        let result = try await RemindersInventoryResolution.resolve(
            forgeDir: dir.path,
            config: enabledConfig(),
            projectNames: ["Lepto"],
            live: true,
            includeCompleted: true,
            reader: stub
        )
        #expect(stub.fetchCount == 1)
        #expect(result.source == .liveEventKit)
        #expect(result.inventory.reminders.count == 1)
    }

    @Test("stale snapshot falls through to fetcher")
    func staleFallsThrough() async throws {
        let dir = try makeForgeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = inventory(generatedAt: Date().addingTimeInterval(-3600))
        try RemindersSnapshotStore.write(forgeDir: dir.path, inventory: old)
        let stub = StubRemindersFetcher(inventory: inventory(generatedAt: Date()))
        let result = try await RemindersInventoryResolution.resolve(
            forgeDir: dir.path,
            config: enabledConfig(),
            projectNames: ["Lepto"],
            live: false,
            includeCompleted: false,
            reader: stub
        )
        #expect(stub.fetchCount == 1)
        #expect(result.source == .liveEventKit)
    }

    @Test("wrong schema version is ineligible")
    func wrongSchemaRejected() throws {
        let dir = try makeForgeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let inv = inventory(generatedAt: Date())
        let payload = RemindersSnapshotStore.Payload(schemaVersion: 99, inventory: inv)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let cacheDir = dir.appendingPathComponent(".cache")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try data.write(to: cacheDir.appendingPathComponent(RemindersSnapshotStore.fileName))
        let eligible = try RemindersSnapshotStore.loadIfEligible(forgeDir: dir.path, maxAge: 900)
        #expect(eligible == nil)
    }

    @Test("statusSummary reports none and populated snapshots")
    func statusSummary() throws {
        let dir = try makeForgeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(RemindersSnapshotStore.statusSummary(forgeDir: dir.path) == "Snapshot: none")
        let generated = Date(timeIntervalSince1970: 1_700_000_000)
        try RemindersSnapshotStore.write(
            forgeDir: dir.path,
            inventory: inventory(generatedAt: generated)
        )
        let summary = RemindersSnapshotStore.statusSummary(
            forgeDir: dir.path,
            now: Date(timeIntervalSince1970: 1_700_000_030)
        )
        #expect(summary.contains("30s ago"))
        #expect(summary.contains("1 list"))
        #expect(summary.contains("1 incomplete"))
    }

    @Test("snapshot includeCompleted false drops completed rows")
    func snapshotFiltersCompleted() async throws {
        let dir = try makeForgeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try RemindersSnapshotStore.write(
            forgeDir: dir.path,
            inventory: inventory(generatedAt: Date(), completed: true)
        )
        let stub = StubRemindersFetcher(inventory: inventory(generatedAt: Date()))
        let hidden = try await RemindersInventoryResolution.resolve(
            forgeDir: dir.path,
            config: enabledConfig(),
            projectNames: ["Lepto"],
            live: false,
            includeCompleted: false,
            reader: stub
        )
        #expect(stub.fetchCount == 0)
        #expect(hidden.inventory.reminders.isEmpty)
        let shown = try await RemindersInventoryResolution.resolve(
            forgeDir: dir.path,
            config: enabledConfig(),
            projectNames: ["Lepto"],
            live: false,
            includeCompleted: true,
            reader: stub
        )
        #expect(shown.inventory.reminders.map(\.title) == ["Done"])
    }

    @Test("refreshSnapshot writes cache via stub fetcher")
    func refreshWritesSnapshot() async throws {
        let dir = try makeForgeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let liveInv = inventory(generatedAt: Date())
        let stub = StubRemindersFetcher(inventory: liveInv)
        let service = RemindersService(config: enabledConfig())
        let written = try await service.refreshSnapshot(
            forgeDir: dir.path,
            projectNames: ["Lepto"],
            writer: "test",
            reader: stub
        )
        #expect(stub.fetchCount == 1)
        #expect(written.reminders.map(\.title) == ["Open"])
        let loaded = try RemindersSnapshotStore.loadIfEligible(forgeDir: dir.path, maxAge: 900)
        #expect(loaded?.reminders.map(\.title) == ["Open"])
        #expect(RemindersSnapshotStore.statusSummary(forgeDir: dir.path).contains("1 incomplete"))
    }
}

/// Test double: records fetch count without touching EventKit.
final class StubRemindersFetcher: RemindersFetching, @unchecked Sendable {
    let inventory: RemindersInventory
    private(set) var fetchCount = 0

    init(inventory: RemindersInventory) {
        self.inventory = inventory
    }

    func fetchInventory(
        projectNames: [String],
        config: RemindersConfig,
        writer: String
    ) async throws -> RemindersInventory {
        fetchCount += 1
        return inventory
    }
}
