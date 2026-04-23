import Foundation

/// Shared path helpers for the Forge directory layout.
public struct ForgePaths {

    private let forgeDir: String

    public init(forgeDir: String) {
        self.forgeDir = forgeDir
    }

    /// Path to the Forge cache directory.
    public var cacheDirectory: String {
        (forgeDir as NSString).appendingPathComponent(".cache")
    }
}
