import Foundation

/// Represents a project task file discovered under one of the configured project roots.
///
/// The index stores these records so that Forge does not need to recursively walk the entire
/// directory tree on every sync or due run. Each record corresponds to a single `TASKS.md`
/// file and the project label inferred from its parent directory.
public struct TaskIndexProjectFile: Codable {

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

/// JSON-backed implementation of `TaskIndex` that stores its snapshot under `Forge/.cache`.
///
/// This implementation is intentionally simple: it discovers project `TASKS.md` files the first
/// time it sees a project root, and then reuses those paths on subsequent runs. This removes
/// the dominant cost seen in profiling, which came from repeatedly walking large directory
/// trees with `FileManager` enumerators.
public final class FileTaskIndex: TaskIndex {

    /// Shared singleton used by default in callers that do not need custom instances.
    nonisolated(unsafe) public static let shared = FileTaskIndex()

    private let fileManager: FileManager
    private var snapshot: TaskIndexSnapshot
    private var loadedForForgeDir: String?
    private let queue = DispatchQueue(label: "TaskIndex.FileTaskIndex", qos: .utility)

    /// Create a new file-backed task index.
    ///
    /// - Parameter fileManager: File manager used for filesystem access.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.snapshot = TaskIndexSnapshot()
    }

    /// Ensure the snapshot has been loaded from disk for the given Forge directory.
    ///
    /// - Parameter forgeDir: Absolute path to the Forge directory.
    private func loadSnapshotIfNeeded(forgeDir: String) {
        if let loaded = loadedForForgeDir, loaded == forgeDir {
            return
        }

        let cacheDir = (forgeDir as NSString).appendingPathComponent(".cache")
        let indexPath = (cacheDir as NSString).appendingPathComponent("task-index.json")
        var loadedSnapshot = TaskIndexSnapshot()

        if fileManager.fileExists(atPath: indexPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: indexPath)) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(TaskIndexSnapshot.self, from: data) {
                loadedSnapshot = decoded
            }
        }

        snapshot = loadedSnapshot
        loadedForForgeDir = forgeDir
    }

    /// Persist the current snapshot to disk for the given Forge directory.
    ///
    /// - Parameter forgeDir: Absolute path to the Forge directory.
    private func saveSnapshot(forgeDir: String) {
        let cacheDir = (forgeDir as NSString).appendingPathComponent(".cache")
        let indexPath = (cacheDir as NSString).appendingPathComponent("task-index.json")
        do {
            try fileManager.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: URL(fileURLWithPath: indexPath), options: .atomic)
        } catch {
            // The index is an optimisation. If persisting fails, ignore the error so that sync
            // and CLI commands continue to work.
        }
    }

    public func refreshIfNeeded(config: ForgeConfig, forgeDir: String) throws {
        queue.sync {
            loadSnapshotIfNeeded(forgeDir: forgeDir)

            var didChange = false
            var projectFilesByRoot = snapshot.projectFilesByRoot

            for root in config.resolvedProjectRoots {
                let normalisedRoot = (root as NSString).standardizingPath
                if projectFilesByRoot[normalisedRoot] != nil {
                    continue
                }
                let discovered = TaskFileFinder.findAll(under: normalisedRoot)
                let mapped = discovered.map { file in
                    TaskIndexProjectFile(path: file.path, projectName: file.label)
                }
                projectFilesByRoot[normalisedRoot] = mapped
                didChange = true
            }

            if didChange {
                snapshot.projectFilesByRoot = projectFilesByRoot
                saveSnapshot(forgeDir: forgeDir)
            }
        }
    }

    public func projectTaskFiles(for config: ForgeConfig) -> [(path: String, projectName: String)] {
        var results: [(path: String, projectName: String)] = []
        var seenPaths = Set<String>()

        queue.sync {
            for root in config.resolvedProjectRoots {
                let normalisedRoot = (root as NSString).standardizingPath
                guard let files = snapshot.projectFilesByRoot[normalisedRoot] else {
                    continue
                }
                for file in files where seenPaths.insert(file.path).inserted {
                    results.append((path: file.path, projectName: file.projectName))
                }
            }
        }

        return results
    }
}

