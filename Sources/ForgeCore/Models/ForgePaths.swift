import Foundation

/// Shared path helpers for the Forge directory layout (inbox, someday, task files root).
/// Used by CLI, menubar app, and board app so task files can live in Forge/tasks when present.
public struct ForgePaths {

    /// Subfolder under the Forge directory where task files (inbox, area files, someday) live.
    public static let tasksSubfolderName = "tasks"

    private let forgeDir: String

    public init(forgeDir: String) {
        self.forgeDir = forgeDir
    }

    /// Path to the tasks directory (Forge/tasks). This is the single location for all task files.
    public var tasksDirectory: String {
        (forgeDir as NSString).appendingPathComponent(Self.tasksSubfolderName)
    }

    /// Root directory for task files: always Forge/tasks. New task files are created here.
    public var taskFilesRoot: String {
        tasksDirectory
    }

    /// Creates the tasks directory if it does not exist. Call before writing inbox, someday, or area files.
    public func ensureTaskFilesDirectoryExists(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(atPath: tasksDirectory, withIntermediateDirectories: true)
    }

    /// Path to inbox.md (in task files root).
    public var inboxPath: String {
        (taskFilesRoot as NSString).appendingPathComponent("inbox.md")
    }

    /// Path to someday-maybe.md (in task files root).
    public var somedayPath: String {
        (taskFilesRoot as NSString).appendingPathComponent("someday-maybe.md")
    }
}
