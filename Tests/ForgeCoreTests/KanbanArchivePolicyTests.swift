import Foundation
import Testing
@testable import ForgeCore

@Suite("KanbanArchivePolicy")
struct KanbanArchivePolicyTests {

    private func makeConfig(delay: Int = 7, includeCompleted: Bool = true) -> ForgeConfig {
        var meta = ["URGENT ⚠️", "Student 🎓"]
        if includeCompleted {
            meta.append("Completed ✔️")
        }
        return ForgeConfig(
            projectRoots: ["/tmp"],
            board: BoardConfig(
                columns: [
                    ColumnConfig(name: "Watch", tag: "Watch 👁️", colour: 2),
                    ColumnConfig(name: "Shipped", tag: "Shipped 🚀", colour: 3),
                ],
                metaTags: meta,
                tagAliases: [:],
                archiveAfterShippedDays: delay
            )
        )
    }

    private func project(
        name: String = "Demo",
        column: String? = "Shipped",
        metaTags: [String] = [],
        path: String = "/tmp/Demo"
    ) -> Project {
        Project(
            name: name,
            path: path,
            tags: metaTags,
            workflowTag: column == "Shipped" ? "Shipped 🚀" : nil,
            column: column,
            metaTags: metaTags
        )
    }

    @Test("disabled without Completed meta tag")
    func disabledWithoutTag() {
        let config = makeConfig(includeCompleted: false)
        let status = KanbanArchivePolicy.status(
            project: project(),
            config: config,
            shippedAt: Date()
        )
        #expect(status == .notApplicable)
    }

    @Test("countdown while within delay")
    func countdownWithinDelay() {
        let config = makeConfig(delay: 7)
        let shippedAt = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        let status = KanbanArchivePolicy.status(
            project: project(),
            config: config,
            shippedAt: shippedAt,
            now: Date()
        )
        guard case .countdown(let days) = status else {
            Issue.record("expected countdown, got \(status)")
            return
        }
        #expect(days >= 4 && days <= 5)
    }

    @Test("ready when delay elapsed")
    func readyWhenElapsed() {
        let config = makeConfig(delay: 7)
        let shippedAt = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        let status = KanbanArchivePolicy.status(
            project: project(),
            config: config,
            shippedAt: shippedAt,
            now: Date()
        )
        #expect(status == .readyToComplete)
    }

    @Test("already completed")
    func alreadyCompleted() {
        let config = makeConfig()
        let status = KanbanArchivePolicy.status(
            project: project(metaTags: ["Completed ✔️"]),
            config: config,
            shippedAt: Date().addingTimeInterval(-30 * 24 * 60 * 60)
        )
        #expect(status == .completed)
    }

    @Test("legacy Archived counts as completed")
    func legacyArchivedCountsAsCompleted() {
        let config = makeConfig()
        let status = KanbanArchivePolicy.status(
            project: project(metaTags: ["Archived 🗄️"]),
            config: config,
            shippedAt: Date()
        )
        #expect(status == .completed)
    }

    @Test("countdown label")
    func countdownLabel() {
        #expect(KanbanArchivePolicy.countdownLabel(for: .countdown(daysRemaining: 3)) == "complete in 3d")
        #expect(KanbanArchivePolicy.countdownLabel(for: .readyToComplete) == "complete due")
        #expect(KanbanArchivePolicy.countdownLabel(for: .completed) == nil)
    }

    @Test("shipped-at store round trip")
    func shippedAtStoreRoundTrip() throws {
        let forgeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-archive-test-\(UUID().uuidString)", isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: forgeDir) }
        try FileManager.default.createDirectory(atPath: forgeDir, withIntermediateDirectories: true)

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try ShippedArchiveStore.recordShipped(forgeDir: forgeDir, folderName: "Alpha", at: date)
        #expect(try ShippedArchiveStore.shippedAt(forgeDir: forgeDir, folderName: "Alpha") == date)

        try ShippedArchiveStore.clearShipped(forgeDir: forgeDir, folderName: "Alpha")
        #expect(try ShippedArchiveStore.shippedAt(forgeDir: forgeDir, folderName: "Alpha") == nil)
        #expect(try ShippedArchiveStore.isCompletedShipSuppressed(forgeDir: forgeDir, folderName: "Alpha"))
    }

    @Test("leaving Shipped suppresses completed→Shipped; return clears suppress")
    func suppressCompletedToShipped() throws {
        let forgeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-suppress-test-\(UUID().uuidString)", isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: forgeDir) }
        try FileManager.default.createDirectory(atPath: forgeDir, withIntermediateDirectories: true)

        _ = try ShippedArchiveStore.recordShipped(forgeDir: forgeDir, folderName: "Beta")
        try ShippedArchiveStore.clearShipped(forgeDir: forgeDir, folderName: "Beta")
        #expect(try ShippedArchiveStore.isCompletedShipSuppressed(forgeDir: forgeDir, folderName: "Beta"))

        #expect(
            OmniFocusMoveSync.shouldForceCompletedToShipped(
                finderColumn: "Watch",
                shippedAt: nil,
                suppressed: true
            ) == false
        )
        #expect(
            OmniFocusMoveSync.shouldForceCompletedToShipped(
                finderColumn: "Watch",
                shippedAt: Date(),
                suppressed: false
            ) == false
        )
        #expect(
            OmniFocusMoveSync.shouldForceCompletedToShipped(
                finderColumn: "Coding",
                shippedAt: nil,
                suppressed: false
            ) == true
        )

        _ = try ShippedArchiveStore.recordShipped(forgeDir: forgeDir, folderName: "Beta", force: true)
        #expect(try ShippedArchiveStore.isCompletedShipSuppressed(forgeDir: forgeDir, folderName: "Beta") == false)
    }
}
