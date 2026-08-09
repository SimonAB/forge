import Foundation

/// Shared path helpers for the Forge directory layout.
public struct ForgePaths {

    /// Primary Forge home when not resolved from config or the environment.
    public static let defaultHomeDirectory: String = {
        (NSHomeDirectory() as NSString).appendingPathComponent("Documents/Software/Forge")
    }()

    /// Ordered `config.yaml` candidates for GUI apps and the CLI fallback search.
    public static func configCandidatePaths(home: String = NSHomeDirectory()) -> [String] {
        let homeNS = home as NSString
        return [
            homeNS.appendingPathComponent("Documents/Software/Forge/config.yaml"),
            homeNS.appendingPathComponent("Documents/Forge/config.yaml"),
            homeNS.appendingPathComponent("Documents/Work/Projects/Forge/config.yaml"),
        ]
    }

    /// Default `config.yaml` path under the primary Forge home.
    public static func defaultConfigPath(home: String = NSHomeDirectory()) -> String {
        (home as NSString).appendingPathComponent("Documents/Software/Forge/config.yaml")
    }

    private let forgeDir: String

    public init(forgeDir: String) {
        self.forgeDir = forgeDir
    }

    /// Path to the Forge cache directory.
    public var cacheDirectory: String {
        (forgeDir as NSString).appendingPathComponent(".cache")
    }
}
