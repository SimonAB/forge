import Foundation

/// Represents a project task file discovered under one of the configured project roots.
///
/// The index stores these records so that Forge does not need to recursively walk the entire
/// directory tree on every sync or due run. Each record corresponds to a single `TASKS.md`
/// file and the project label inferred from its parent directory.
public struct TaskIndexProjectFile: Codable, Equatable {

    /// Absolute path to the `TASKS.md` file.
    public var path: String

    /// Human-readable project name, usually the name of the directory containing the file.
    public var projectName: String

    public init(path: String, projectName: String) {
        self.path = path
        self.projectName = projectName
    }
}

/// Snapshot of the indexed project task files for all configured project roots.
///
/// The snapshot is persisted to disk in JSON form so that subsequent Forge runs can reuse the
/// previously discovered `TASKS.md` files without repeating a full recursive directory walk.
private struct TaskIndexSnapshot: Codable {

    /// Mapping from normalised project root path to the list of project task files under it.
    var projectFilesByRoot: [String: [TaskIndexProjectFile]]

    init(projectFilesByRoot: [String: [TaskIndexProjectFile]] = [:]) {
        self.projectFilesByRoot = projectFilesByRoot
    }
}

/// Abstraction for accessing cached knowledge of project `TASKS.md` files.
///
/// Implementations are responsible for loading and persisting a snapshot, and for discovering
/// `TASKS.md` files when no cached data exists for a given project root.
public protocol TaskIndex {

    /// Ensure the in-memory snapshot is loaded from disk and that project roots present in the
    /// configuration have corresponding entries in the snapshot.
    ///
    /// This method may perform a full recursive walk for roots that have never been seen before,
    /// but subsequent calls will reuse the cached paths instead of walking the filesystem again.
    ///
    /// - Parameters:
    ///   - config: The loaded Forge configuration.
    ///   - forgeDir: Absolute path to the Forge directory containing `config.yaml`.
    func refreshIfNeeded(config: ForgeConfig, forgeDir: String) throws

    /// Return all known project task files for the given configuration.
    ///
    /// The result contains a unique entry for each `TASKS.md` path across all project roots.
    ///
    /// - Parameter config: The loaded Forge configuration.
    func projectTaskFiles(for config: ForgeConfig) -> [(path: String, projectName: String)]
}

/// Database-backed implementation of `TaskIndex` that uses `TaskFileDatabase` and
/// `TaskDiscoveryService` for discovery.
public final class DatabaseTaskIndex: TaskIndex {

    private let database: TaskFileDatabase
    private let discovery: TaskDiscoveryService
    private let forceFullRescan: Bool

    /// Create a new database-backed task index.
    ///
    /// - Parameters:
    ///   - database: Task file database used as the source of truth.
    ///   - discovery: Service responsible for initial discovery of project task files.
    ///   - forceFullRescan: When true, force a full recursive rescan of all project roots on the
    ///     next refresh, regardless of existing records.
    public init(
        database: TaskFileDatabase,
        discovery: TaskDiscoveryService = TaskDiscoveryService(),
        forceFullRescan: Bool = false
    ) {
        self.database = database
        self.discovery = discovery
        self.forceFullRescan = forceFullRescan
    }

    public func refreshIfNeeded(config: ForgeConfig, forgeDir: String) throws {
        try discovery.ensureProjectTasksIndexed(
            config: config,
            forgeDir: forgeDir,
            database: database,
            forceFullRescan: forceFullRescan
        )
    }

    public func projectTaskFiles(for config: ForgeConfig) -> [(path: String, projectName: String)] {
        let roots = config.resolvedProjectRoots.map { ($0 as NSString).standardizingPath }
        guard !roots.isEmpty else { return [] }
        let results: [TaskFileRecord]
        do {
            results = try database.projectTaskFiles(under: roots)
        } catch {
            return []
        }
        return results.map { ($0.path, $0.label) }
    }
}
