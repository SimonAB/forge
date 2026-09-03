import Foundation

/// Where a primary click on a project/task entry should land.
public enum ProjectPrimaryOpenTarget: Equatable, Sendable {
    /// Open `<project>/TASKS.toml` in the preferred editor.
    case tasksFile(URL)
    /// `TASKS.toml` is missing — reveal the project folder instead.
    case projectFolder(URL)
}

/// Resolves Forge project folders and primary-click targets for dashboard / board opens.
public enum ProjectOpenResolver {

    /// Canonical per-project tasks filename.
    public static let tasksFileName = "TASKS.toml"

    /// Locate a project directory by exact folder name under the configured roots.
    ///
    /// - Parameters:
    ///   - name: Finder folder name (exact match).
    ///   - projectRoots: Absolute project root directories from `config.yaml`.
    ///   - fileManager: File manager used for existence checks.
    /// - Returns: Absolute path to the project folder, or `nil` if not found.
    public static func resolveProjectDirectory(
        named name: String,
        projectRoots: [String],
        fileManager: FileManager = .default
    ) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for root in projectRoots {
            let expanded = (root as NSString).expandingTildeInPath
            let candidate = (expanded as NSString).appendingPathComponent(trimmed)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    /// Absolute URL for `TASKS.toml` inside a project directory.
    public static func tasksFileURL(projectDirectory: String) -> URL {
        URL(fileURLWithPath: projectDirectory).appendingPathComponent(tasksFileName)
    }

    /// Choose the primary-click target: `TASKS.toml` when present, else the project folder.
    ///
    /// - Parameters:
    ///   - projectDirectory: Absolute path to the project folder.
    ///   - fileExists: Injected existence check (defaults to `FileManager`).
    /// - Returns: Editor target or folder fallback.
    public static func primaryOpenTarget(
        projectDirectory: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> ProjectPrimaryOpenTarget {
        let tasksURL = tasksFileURL(projectDirectory: projectDirectory)
        if fileExists(tasksURL.path) {
            return .tasksFile(tasksURL)
        }
        return .projectFolder(URL(fileURLWithPath: projectDirectory))
    }

    /// Resolve a project name to a primary-click target, or `nil` when the folder is unknown.
    public static func primaryOpenTarget(
        projectName: String,
        projectRoots: [String],
        fileManager: FileManager = .default
    ) -> ProjectPrimaryOpenTarget? {
        guard let directory = resolveProjectDirectory(
            named: projectName,
            projectRoots: projectRoots,
            fileManager: fileManager
        ) else {
            return nil
        }
        return primaryOpenTarget(
            projectDirectory: directory,
            fileExists: { fileManager.fileExists(atPath: $0) }
        )
    }
}
