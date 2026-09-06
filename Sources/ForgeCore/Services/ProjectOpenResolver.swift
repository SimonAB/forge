import Foundation

/// Where **Open TASKS** should land for a project.
public enum ProjectTasksOpenTarget: Equatable, Sendable {
    /// Launch Super Productivity (optionally with a mapped project id).
    case superProductivity(projectId: String?)
    /// Activate OmniFocus (project matched by folder name when possible).
    case omnifocus(projectName: String)
    /// Open Reminders (list title = folder name).
    case reminders(listTitle: String)
    /// Open `<project>/TASKS.toml` in the preferred editor.
    case tasksFile(URL)
    /// Fallback when no tasks file exists for the toml backend.
    case projectFolder(URL)
}

/// Resolves Forge project folders and Open TASKS targets for dashboard / board.
public enum ProjectOpenResolver {

    /// Canonical per-project tasks filename (legacy toml backend).
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

    /// Choose the Open TASKS target from config + task-manager preference.
    ///
    /// - Parameters:
    ///   - projectDirectory: Absolute path to the project folder.
    ///   - projectName: Folder name (for SP / OF / Reminders matching).
    ///   - config: Forge configuration.
    ///   - preferredTaskManager: Stored preference; defaults to UserDefaults.
    ///   - fileExists: Injected existence check (defaults to `FileManager`).
    public static func tasksOpenTarget(
        projectDirectory: String,
        projectName: String? = nil,
        config: ForgeConfig,
        preferredTaskManager: TaskManagerPreferences.Kind? = TaskManagerPreferences.loadPreferredTaskManager(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> ProjectTasksOpenTarget {
        let name = projectName
            ?? URL(fileURLWithPath: projectDirectory).lastPathComponent
        let manager = TaskManagerPreferences.resolve(config: config, preferred: preferredTaskManager)
        switch manager {
        case .auto:
            // resolve() never returns auto
            return .projectFolder(URL(fileURLWithPath: projectDirectory))
        case .superproductivity:
            let id = config.superproductivity.projectIds[name]
            return .superProductivity(projectId: id)
        case .omnifocus:
            return .omnifocus(projectName: name)
        case .reminders:
            return .reminders(listTitle: name)
        case .tasksToml:
            let tasksURL = tasksFileURL(projectDirectory: projectDirectory)
            if fileExists(tasksURL.path) {
                return .tasksFile(tasksURL)
            }
            return .projectFolder(URL(fileURLWithPath: projectDirectory))
        }
    }

    /// Legacy primary-click helper: `TASKS.toml` when present, else the project folder.
    public static func primaryOpenTarget(
        projectDirectory: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> ProjectTasksOpenTarget {
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
    ) -> ProjectTasksOpenTarget? {
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
