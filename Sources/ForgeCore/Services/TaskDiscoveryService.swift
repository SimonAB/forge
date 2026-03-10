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
    /// database. For each root, if the database already contains at least one project task file,
    /// no further work is done for that root.
    ///
    /// - Parameters:
    ///   - config: Loaded Forge configuration.
    ///   - forgeDir: Absolute path to the Forge directory.
    ///   - database: Task file database to populate.
    public func ensureProjectTasksIndexed(
        config: ForgeConfig,
        forgeDir: String,
        database: TaskFileDatabase
    ) throws {
        let fileManager = FileManager.default
        let now = Date().timeIntervalSinceReferenceDate
        let roots = config.resolvedProjectRoots.map { ($0 as NSString).standardizingPath }

        // Query existing records once to avoid repeated round-trips.
        let existing = try database.projectTaskFiles(under: roots)
        let existingByRoot = Dictionary(grouping: existing, by: \.projectRoot)

        var toInsert: [TaskFileRecord] = []

        for root in roots {
            if let records = existingByRoot[root], !records.isEmpty {
                continue
            }

            let taskFiles = TaskFileFinder.findAll(under: root)
            for tf in taskFiles {
                let attrs = (try? fileManager.attributesOfItem(atPath: tf.path)) ?? [:]
                let mtimeDate = (attrs[.modificationDate] as? Date) ?? .distantPast
                let sizeValue = (attrs[.size] as? NSNumber)?.int64Value ?? 0

                let record = TaskFileRecord(
                    path: tf.path,
                    kind: .projectTasks,
                    label: tf.label,
                    projectRoot: root,
                    mtime: mtimeDate.timeIntervalSinceReferenceDate,
                    size: sizeValue,
                    lastSeenAt: now,
                    lastParsedAt: nil,
                    overdueCount: 0,
                    dueTodayCount: 0,
                    inboxOpenCount: 0,
                    isDeleted: false
                )
                toInsert.append(record)
            }
        }

        if !toInsert.isEmpty {
            try database.upsertFiles(toInsert)
        }
    }
}
