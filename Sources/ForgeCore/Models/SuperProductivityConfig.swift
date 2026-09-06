import Foundation

/// Optional Super Productivity local REST settings (`superproductivity:` in config.yaml).
public struct SuperProductivityConfig: Codable, Sendable, Equatable {
    /// When true, SP is available for capture / Open TASKS (with Auto).
    public var enabled: Bool
    /// When true with ``enabled``, SP is the day-to-day task store; OmniFocus stays
    /// for kanban join / rollback only (see docs/of-frozen-sp-primary.md).
    public var primary: Bool
    /// Local REST base URL (default loopback).
    public var endpoint: String
    /// Request timeout in seconds.
    public var timeout: Double
    /// Forge folder name → SP project id (exact title match).
    public var projectIds: [String: String]

    enum CodingKeys: String, CodingKey {
        case enabled
        case primary
        case endpoint
        case timeout
        case projectIds = "project_ids"
    }

    public init(
        enabled: Bool = false,
        primary: Bool = false,
        endpoint: String = "http://127.0.0.1:3876",
        timeout: Double = 5,
        projectIds: [String: String] = [:]
    ) {
        self.enabled = enabled
        self.primary = primary
        self.endpoint = endpoint
        self.timeout = timeout
        self.projectIds = projectIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        primary = try container.decodeIfPresent(Bool.self, forKey: .primary) ?? false
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? "http://127.0.0.1:3876"
        timeout = try container.decodeIfPresent(Double.self, forKey: .timeout) ?? 5
        projectIds = try container.decodeIfPresent([String: String].self, forKey: .projectIds) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(primary, forKey: .primary)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(timeout, forKey: .timeout)
        if !projectIds.isEmpty {
            try container.encode(projectIds, forKey: .projectIds)
        }
    }

    /// True when SP is enabled and marked primary for day-to-day tasks.
    public var isPrimaryTaskStore: Bool { enabled && primary }
}
