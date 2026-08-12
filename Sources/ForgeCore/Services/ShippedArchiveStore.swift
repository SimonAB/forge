import Foundation

/// Local map of folder name → time entered **Shipped**, under `<forgeDir>/.cache/shipped-at.json`.
/// Used for the delayed `Completed` meta tag (see ``KanbanArchivePolicy``) and to suppress
/// repeated OmniFocus completed→Shipped overwrites after the user leaves Shipped.
public enum ShippedArchiveStore {
    public static let fileName = "shipped-at.json"
    public static let currentSchemaVersion = 2

    public static func cachePath(forgeDir: String) -> String {
        (forgeDir as NSString).appendingPathComponent(".cache/\(fileName)")
    }

    public struct Payload: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        /// Folder directory names → ISO-8601 ship timestamps.
        public var shippedAt: [String: Date]
        /// Folders where the user left Shipped (or Finder was moved away after a ship);
        /// Refresh must not force completed→Shipped again until they return to Shipped.
        public var suppressCompletedToShipped: [String: Bool]

        enum CodingKeys: String, CodingKey {
            case schemaVersion
            case shippedAt
            case suppressCompletedToShipped
        }

        public init(
            schemaVersion: Int = ShippedArchiveStore.currentSchemaVersion,
            shippedAt: [String: Date] = [:],
            suppressCompletedToShipped: [String: Bool] = [:]
        ) {
            self.schemaVersion = schemaVersion
            self.shippedAt = shippedAt
            self.suppressCompletedToShipped = suppressCompletedToShipped
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            shippedAt = try c.decodeIfPresent([String: Date].self, forKey: .shippedAt) ?? [:]
            suppressCompletedToShipped = try c.decodeIfPresent(
                [String: Bool].self,
                forKey: .suppressCompletedToShipped
            ) ?? [:]
        }
    }

    public static func read(forgeDir: String) throws -> Payload {
        let path = cachePath(forgeDir: forgeDir)
        guard FileManager.default.fileExists(atPath: path) else {
            return Payload()
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var payload = try decoder.decode(Payload.self, from: data)
        // v1 → v2: keep shippedAt; suppress map starts empty.
        if payload.schemaVersion < currentSchemaVersion {
            payload.schemaVersion = currentSchemaVersion
        }
        return payload
    }

    public static func write(forgeDir: String, payload: Payload) throws {
        let cacheDir = (forgeDir as NSString).appendingPathComponent(".cache")
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        var toWrite = payload
        toWrite.schemaVersion = currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(toWrite)
        try data.write(to: URL(fileURLWithPath: cachePath(forgeDir: forgeDir)), options: .atomic)
    }

    /// Record or refresh the ship timestamp for a folder (no-op if already present unless `force`).
    /// Clears completed→Shipped suppression (user returned to Shipped).
    @discardableResult
    public static func recordShipped(
        forgeDir: String,
        folderName: String,
        at date: Date = Date(),
        force: Bool = false
    ) throws -> Date {
        var payload = try read(forgeDir: forgeDir)
        payload.suppressCompletedToShipped[folderName] = nil
        if !force, let existing = payload.shippedAt[folderName] {
            try write(forgeDir: forgeDir, payload: payload)
            return existing
        }
        payload.shippedAt[folderName] = date
        try write(forgeDir: forgeDir, payload: payload)
        return date
    }

    /// Remove the ship timestamp when a folder leaves Shipped, and suppress auto re-ship.
    public static func clearShipped(forgeDir: String, folderName: String) throws {
        var payload = try read(forgeDir: forgeDir)
        payload.shippedAt.removeValue(forKey: folderName)
        payload.suppressCompletedToShipped[folderName] = true
        try write(forgeDir: forgeDir, payload: payload)
    }

    /// Mark a folder so Refresh will not force completed→Shipped (Finder left Shipped).
    public static func suppressCompletedShip(forgeDir: String, folderName: String) throws {
        var payload = try read(forgeDir: forgeDir)
        payload.suppressCompletedToShipped[folderName] = true
        payload.shippedAt.removeValue(forKey: folderName)
        try write(forgeDir: forgeDir, payload: payload)
    }

    public static func isCompletedShipSuppressed(forgeDir: String, folderName: String) throws -> Bool {
        try read(forgeDir: forgeDir).suppressCompletedToShipped[folderName] == true
    }

    public static func shippedAt(forgeDir: String, folderName: String) throws -> Date? {
        try read(forgeDir: forgeDir).shippedAt[folderName]
    }
}
