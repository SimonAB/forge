import Foundation
import ForgeCore

/// Shared helper to locate and load the forge configuration.
enum ConfigLoader {

    /// The resolved path to the Forge directory, set after config is loaded.
    nonisolated(unsafe) private(set) static var resolvedForgeDir: String?


    /// Search upward from the current directory for a Forge/config.yaml file.
    /// Falls back to ~/Documents/Forge/ if not found.
    static func load() throws -> ForgeConfig {
        if let path = findConfigPath() {
            resolvedForgeDir = (path as NSString).deletingLastPathComponent
            return try ForgeConfig.load(from: path)
        }

        let fallback = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Documents/Forge/config.yaml")
        if FileManager.default.fileExists(atPath: fallback) {
            resolvedForgeDir = (fallback as NSString).deletingLastPathComponent
            return try ForgeConfig.load(from: fallback)
        }

        throw ConfigError.notFound
    }

    /// Resolve the Forge directory path from the loaded config location.
    static func forgeDirectory(for config: ForgeConfig) -> String {
        resolvedForgeDir ?? (config.resolvedWorkspacePath as NSString).appendingPathComponent("Forge")
    }


    private static func findConfigPath() -> String? {
        var dir = FileManager.default.currentDirectoryPath

        while true {
            let candidate = (dir as NSString)
                .appendingPathComponent("Forge/config.yaml")
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }

            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        return nil
    }

    enum ConfigError: Error, CustomStringConvertible {
        case notFound

        var description: String {
            """
            No Forge/config.yaml found. Run 'forge init' in your workspace \
            or 'forge init --workspace <path>' to set up.
            """
        }
    }
}
