import Foundation
import ForgeCore

/// Shared helper to locate and load the forge configuration.
enum ConfigLoader {

    /// The resolved path to the Forge directory, set after config is loaded.
    nonisolated(unsafe) private(set) static var resolvedForgeDir: String?

    /// Files that are not treated as GTD area files.
    private static let excludedFiles: Set<String> = [
        "config.yaml", "someday-maybe.md",
    ]

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

    /// Metadata about an area file, including its parsed frontmatter.
    struct AreaFile {
        let path: String
        let name: String
        let frontmatter: Frontmatter?
    }

    /// Discover area markdown files dynamically by scanning the Forge directory.
    ///
    /// Any `.md` file in the directory is treated as an area file, except for
    /// those listed in `excludedFiles`.
    static func areaTaskFiles(forgeDir: String) -> [(path: String, name: String)] {
        return scanAreaFiles(forgeDir: forgeDir).map { ($0.path, $0.name) }
    }

    /// Scan area files and parse their frontmatter.
    static func scanAreaFiles(forgeDir: String) -> [AreaFile] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: forgeDir) else { return [] }
        var result: [AreaFile] = []
        for entry in entries.sorted() where entry.hasSuffix(".md") {
            guard !excludedFiles.contains(entry) else { continue }
            let filePath = (forgeDir as NSString).appendingPathComponent(entry)
            let name = (entry as NSString).deletingPathExtension.capitalized
            let content = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            let (frontmatter, _) = Frontmatter.parse(from: content)
            result.append(AreaFile(path: filePath, name: name, frontmatter: frontmatter))
        }
        return result
    }

    /// Filter area files to those matching a focus tag.
    static func areaFiles(forgeDir: String, focusTag: String?) -> [AreaFile] {
        let all = scanAreaFiles(forgeDir: forgeDir)
        guard let tag = focusTag?.lowercased() else { return all }
        return all.filter { area in
            guard let fm = area.frontmatter else { return false }
            return fm.tags.contains { $0.lowercased() == tag }
        }
    }

    /// Whether workspace projects should be included for a given focus tag.
    static func includesProjects(focusTag: String?, config: ForgeConfig) -> Bool {
        guard let tag = focusTag?.lowercased() else { return true }
        return config.workspaceTags.contains { $0.lowercased() == tag }
    }

    /// Path to the persistent focus file.
    static func focusFilePath(forgeDir: String) -> String {
        (forgeDir as NSString).appendingPathComponent(".focus")
    }

    /// Read the current persistent focus tag, if any.
    static func currentFocus(forgeDir: String) -> String? {
        let path = focusFilePath(forgeDir: forgeDir)
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
