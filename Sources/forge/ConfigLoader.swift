import Foundation
import ForgeCore

/// Shared helper to locate and load the forge configuration.
enum ConfigLoader {

    /// Subfolder under the Forge directory where task files (inbox, area files, someday) live.
    static let tasksSubfolderName = ForgePaths.tasksSubfolderName

    /// The resolved path to the Forge directory, set after config is loaded.
    nonisolated(unsafe) private(set) static var resolvedForgeDir: String?

    /// Path to the task files directory (Forge/tasks). This is always the root for task files.
    static func tasksDirectory(forgeDir: String) -> String {
        ForgePaths(forgeDir: forgeDir).tasksDirectory
    }

    /// Root directory for task files: always Forge/tasks.
    static func taskFilesRoot(forgeDir: String) -> String {
        ForgePaths(forgeDir: forgeDir).taskFilesRoot
    }

    /// Path to inbox.md (in task files root).
    static func inboxPath(forgeDir: String) -> String {
        ForgePaths(forgeDir: forgeDir).inboxPath
    }

    /// Path to someday-maybe.md (in task files root).
    static func somedayPath(forgeDir: String) -> String {
        ForgePaths(forgeDir: forgeDir).somedayPath
    }

    /// Files that are not treated as GTD area files (inbox, someday, config when in root, generated summaries).
    private static let excludedFiles: Set<String> = [
        "config.yaml", "someday-maybe.md", "inbox.md", "due.md",
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

    /// Discover area markdown files dynamically by scanning the task files directory.
    ///
    /// Uses `taskFilesRoot(forgeDir:)` (Forge/tasks). Any `.md` file is treated as an area file except those in `excludedFiles`.
    static func areaTaskFiles(forgeDir: String) -> [(path: String, name: String)] {
        let root = taskFilesRoot(forgeDir: forgeDir)
        return scanAreaFiles(in: root).map { ($0.path, $0.name) }
    }

    /// All markdown files in the task files directory (Forge/tasks), including inbox and someday-maybe.
    /// Use when completing or searching for tasks by ID so every task file is considered.
    static func allTaskFilesInTaskRoot(forgeDir: String) -> [(path: String, name: String)] {
        let root = taskFilesRoot(forgeDir: forgeDir)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        return entries
            .filter { $0.hasSuffix(".md") }
            .sorted()
            .map { entry in
                let path = (root as NSString).appendingPathComponent(entry)
                let name = (entry as NSString).deletingPathExtension.capitalized
                return (path, name)
            }
    }

    /// Scan area files in the given directory and parse their frontmatter.
    /// - Parameter dir: Directory containing area .md files (e.g. Forge/tasks or Forge).
    static func scanAreaFiles(in dir: String) -> [AreaFile] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var result: [AreaFile] = []
        for entry in entries.sorted() where entry.hasSuffix(".md") {
            guard !excludedFiles.contains(entry) else { continue }
            let filePath = (dir as NSString).appendingPathComponent(entry)
            let name = (entry as NSString).deletingPathExtension.capitalized
            let content = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            let (frontmatter, _) = Frontmatter.parse(from: content)
            result.append(AreaFile(path: filePath, name: name, frontmatter: frontmatter))
        }
        return result
    }

    /// Convenience: scan area files in the task files root (Forge/tasks) for the given Forge directory.
    static func scanAreaFiles(forgeDir: String) -> [AreaFile] {
        scanAreaFiles(in: taskFilesRoot(forgeDir: forgeDir))
    }

    /// Filter area files to those matching a focus tag.
    static func areaFiles(forgeDir: String, focusTag: String?) -> [AreaFile] {
        let root = taskFilesRoot(forgeDir: forgeDir)
        let all = scanAreaFiles(in: root)
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
