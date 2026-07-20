import Foundation

/// JSON cache under `<forgeDir>/.cache/omnifocus-snapshot.json`.
public enum OmniFocusSnapshotStore {
    public static let fileName = "omnifocus-snapshot.json"
    public static let currentSchemaVersion = 1

    public static func cachePath(forgeDir: String) -> String {
        (forgeDir as NSString).appendingPathComponent(".cache/\(fileName)")
    }

    public struct Payload: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let inventory: OmniFocusInventory

        public init(schemaVersion: Int = OmniFocusSnapshotStore.currentSchemaVersion, inventory: OmniFocusInventory) {
            self.schemaVersion = schemaVersion
            self.inventory = inventory
        }
    }

    public static func write(forgeDir: String, inventory: OmniFocusInventory) throws {
        let cacheDir = (forgeDir as NSString).appendingPathComponent(".cache")
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let payload = Payload(inventory: inventory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: URL(fileURLWithPath: cachePath(forgeDir: forgeDir)), options: .atomic)
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
    ) throws -> OmniFocusInventory? {
        guard let payload = try read(forgeDir: forgeDir) else { return nil }
        guard payload.schemaVersion == currentSchemaVersion else { return nil }
        let age = now.timeIntervalSince(payload.inventory.generatedAt)
        guard age >= 0, age <= maxAge else { return nil }
        return payload.inventory
    }
}
