import Foundation

/// Discovers Forge task files on disk and ensures they are represented in the task file database.
///
/// This service is the only place that performs deep recursive scans using `TaskFileFinder`.
/// Callers should use it sparingly (for initial bootstrap and explicit rescans) and rely on the
/// database for steady-state queries.
public struct TaskDiscoveryService {

    /// Create a new discovery service.
    public init() {}

    /// Ensure that all configured project roots have their `TASKS.md` files recorded in the
    /// database.
    ///
    /// This method reconciles the database with the filesystem for each configured project root.
    ///
    /// For each root it will, when needed:
    /// - Perform a recursive scan for `TASKS.md` files.
    /// - Insert new task files.
    /// - Update existing task files with latest metadata.
    /// - Mark files that have been removed from disk as deleted.
    ///
    /// - Parameters:
    ///   - config: Loaded Forge configuration.
    ///   - forgeDir: Absolute path to the Forge directory.
    ///   - database: Task file database to populate.
    public func ensureProjectTasksIndexed(
        config: ForgeConfig,
        forgeDir: String,
        database: TaskFileDatabase,
        forceFullRescan: Bool = false
    ) throws {
        let fileManager = FileManager.default
        let now = Date().timeIntervalSinceReferenceDate
        let roots = config.resolvedProjectRoots.map { ($0 as NSString).standardizingPath }

        let existing = try database.projectTaskFiles(under: roots)
        let existingByRoot = Dictionary(grouping: existing, by: \.projectRoot)

        var toUpsert: [TaskFileRecord] = []

        for root in roots {
            let normalisedRoot = (root as NSString).standardizingPath
            let existingForRoot = existingByRoot[normalisedRoot] ?? []

            // Default behaviour: once we have at least one record for a root, avoid repeated
            // full rescans on every run. A deep rescan is only performed when explicitly
            // requested via `forceFullRescan`, or when the root has never been seen before.
            if !forceFullRescan, !existingForRoot.isEmpty {
                continue
            }

            let existingPaths = Set(existingForRoot.map(\.path))

            let taskFiles = TaskFileFinder.findAll(under: normalisedRoot)
            let foundPaths = Set(taskFiles.map(\.path))

            for tf in taskFiles {
                let attrs = (try? fileManager.attributesOfItem(atPath: tf.path)) ?? [:]
                let mtimeDate = (attrs[.modificationDate] as? Date) ?? .distantPast
                let sizeValue = (attrs[.size] as? NSNumber)?.int64Value ?? 0

                let record = TaskFileRecord(
                    path: tf.path,
                    kind: .projectTasks,
                    label: tf.label,
                    projectRoot: normalisedRoot,
                    mtime: mtimeDate.timeIntervalSinceReferenceDate,
                    size: sizeValue,
                    lastSeenAt: now,
                    lastParsedAt: nil,
                    overdueCount: 0,
                    dueTodayCount: 0,
                    inboxOpenCount: 0,
                    isDeleted: false
                )
                toUpsert.append(record)
            }

            let removedPaths = existingPaths.subtracting(foundPaths)
            if !removedPaths.isEmpty {
                for path in removedPaths {
                    let dirPath = (path as NSString).deletingLastPathComponent
                    let label = (dirPath as NSString).lastPathComponent
                    let record = TaskFileRecord(
                        path: path,
                        kind: .projectTasks,
                        label: label,
                        projectRoot: normalisedRoot,
                        mtime: 0,
                        size: 0,
                        lastSeenAt: now,
                        lastParsedAt: nil,
                        overdueCount: 0,
                        dueTodayCount: 0,
                        inboxOpenCount: 0,
                        isDeleted: true
                    )
                    toUpsert.append(record)
                }
            }
        }

        if !toUpsert.isEmpty {
            try database.upsertFiles(toUpsert)
        }
    }
}
