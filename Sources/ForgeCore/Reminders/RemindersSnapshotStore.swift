import Foundation

/// JSON cache under `<forgeDir>/.cache/reminders-snapshot.json`, written by **Forge.app**
/// so the `forge` CLI can show Reminders without terminal Reminders TCC.
public enum RemindersSnapshotStore {
    public static let fileName = "reminders-snapshot.json"
    public static let currentSchemaVersion = 1

    public static func cachePath(forgeDir: String) -> String {
        (forgeDir as NSString).appendingPathComponent(".cache/\(fileName)")
    }

    public struct Payload: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let inventory: RemindersInventory

        public init(
            schemaVersion: Int = RemindersSnapshotStore.currentSchemaVersion,
            inventory: RemindersInventory
        ) {
            self.schemaVersion = schemaVersion
            self.inventory = inventory
        }
    }

    public static func write(forgeDir: String, inventory: RemindersInventory) throws {
        let cacheDir = (forgeDir as NSString).appendingPathComponent(".cache")
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let payload = Payload(inventory: inventory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let path = cachePath(forgeDir: forgeDir)
        let tmp = path + ".tmp"
        try data.write(to: URL(fileURLWithPath: tmp), options: .atomic)
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
        try FileManager.default.moveItem(atPath: tmp, toPath: path)
    }

    public static func read(forgeDir: String) throws -> Payload? {
        let path = cachePath(forgeDir: forgeDir)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Payload.self, from: data)
    }

    public static func loadIfEligible(
        forgeDir: String,
        maxAge: TimeInterval,
        now: Date = Date()
    ) throws -> RemindersInventory? {
        let payload: Payload?
        do {
            payload = try read(forgeDir: forgeDir)
        } catch {
            return nil
        }
        guard let payload else { return nil }
        guard payload.schemaVersion == currentSchemaVersion else { return nil }
        let age = now.timeIntervalSince(payload.inventory.generatedAt)
        guard age >= 0, age <= maxAge else { return nil }
        return payload.inventory
    }

    /// One-line snapshot summary for Preferences and `forge reminders status`.
    public static func statusSummary(forgeDir: String, now: Date = Date()) -> String {
        guard let payload = try? read(forgeDir: forgeDir) else {
            return "Snapshot: none"
        }
        let age = max(0, Int(now.timeIntervalSince(payload.inventory.generatedAt)))
        let incomplete = payload.inventory.reminders.filter { !$0.isCompleted }.count
        return "Snapshot: \(age)s ago · \(payload.inventory.lists.count) list(s) · \(incomplete) incomplete"
    }

}

// MARK: - CLI resolution (snapshot first, then EventKit)

public enum RemindersInventoryResolution {
    public struct Result: Sendable {
        public let inventory: RemindersInventory
        public let source: Source
    }

    public enum Source: Equatable, Sendable {
        case forgeAppSnapshot(generatedAt: Date)
        case liveEventKit
    }

    /// Resolves inventory: Forge.app snapshot when eligible, otherwise live EventKit.
    public static func resolve(
        forgeDir: String,
        config: ForgeConfig,
        projectNames: [String],
        live: Bool,
        includeCompleted: Bool,
        reader: any RemindersFetching = RemindersReader()
    ) async throws -> Result {
        let maxAge = config.reminders.snapshotMaxAgeSeconds
        if !live, let snap = try RemindersSnapshotStore.loadIfEligible(forgeDir: forgeDir, maxAge: maxAge) {
            return Result(
                inventory: snap.filteringReminders(includeCompleted: includeCompleted),
                source: .forgeAppSnapshot(generatedAt: snap.generatedAt)
            )
        }

        let inventory = try await reader.fetchInventory(
            projectNames: projectNames,
            config: config.reminders,
            writer: "forge"
        )
        return Result(
            inventory: inventory.filteringReminders(includeCompleted: includeCompleted),
            source: .liveEventKit
        )
    }
}
