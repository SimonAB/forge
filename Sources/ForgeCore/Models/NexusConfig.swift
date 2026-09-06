import Foundation

/// Nexus / portable kanban flags (`nexus:` in config.yaml).
///
/// Defaults preserve Finder-only behaviour until `sidecar_enabled` is turned on.
public struct NexusConfig: Codable, Sendable, Equatable {
    /// Write `<project>/.forge/kanban.toml` on move / project-tag / migrate.
    public var sidecarEnabled: Bool
    /// When classifying projects, prefer sidecar column/meta over local tags when both exist.
    public var preferSidecar: Bool
    /// On board / OF Refresh, paint sidecar → local tags before OF → Finder.
    public var syncSidecarOnRefresh: Bool
    /// On move, mirror `Forge/<Column>` tags onto Super Productivity tasks for mapped projects.
    public var spColumnMirror: Bool

    enum CodingKeys: String, CodingKey {
        case sidecarEnabled = "sidecar_enabled"
        case preferSidecar = "prefer_sidecar"
        case syncSidecarOnRefresh = "sync_sidecar_on_refresh"
        case spColumnMirror = "sp_column_mirror"
    }

    public init(
        sidecarEnabled: Bool = false,
        preferSidecar: Bool = true,
        syncSidecarOnRefresh: Bool = false,
        spColumnMirror: Bool = false
    ) {
        self.sidecarEnabled = sidecarEnabled
        self.preferSidecar = preferSidecar
        self.syncSidecarOnRefresh = syncSidecarOnRefresh
        self.spColumnMirror = spColumnMirror
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sidecarEnabled = try container.decodeIfPresent(Bool.self, forKey: .sidecarEnabled) ?? false
        preferSidecar = try container.decodeIfPresent(Bool.self, forKey: .preferSidecar) ?? true
        syncSidecarOnRefresh = try container.decodeIfPresent(Bool.self, forKey: .syncSidecarOnRefresh) ?? false
        spColumnMirror = try container.decodeIfPresent(Bool.self, forKey: .spColumnMirror) ?? false
    }
}
