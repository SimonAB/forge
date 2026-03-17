import Foundation

/// Discovers Forge task files on disk and ensures they are represented in the task file database.
///
/// This service is the only place that performs deep recursive scans using `TaskFileFinder`.
/// Callers should use it sparingly (for initial bootstrap and explicit rescans) and rely on the
/// database for steady-state queries.
public struct TaskDiscoveryService {

    /// Create a new discovery service.
    public init() {}

    /// True if `tasksPath` is in the "direct child project" form `root/<child>/TASKS.md`.
    private func isDirectChildProjectTasksPath(_ tasksPath: String, under root: String) -> Bool {
        let normalisedRoot = (root as NSString).standardizingPath
        let path = (tasksPath as NSString).standardizingPath
        guard path.hasPrefix(normalisedRoot + "/") else { return false }
        guard (path as NSString).lastPathComponent == "TASKS.md" else { return false }
        let parentDir = (path as NSString).deletingLastPathComponent
        let parentParent = (parentDir as NSString).deletingLastPathComponent
        return (parentParent as NSString).standardizingPath == normalisedRoot
    }

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
        let tagStore = FinderTagStore()
        let now = Date().timeIntervalSinceReferenceDate
        let roots = config.resolvedProjectRoots.map { ($0 as NSString).standardizingPath }

        let existing = try database.projectTaskFiles(under: roots)
        let existingByRoot = Dictionary(grouping: existing, by: \.projectRoot)

        var toUpsert: [TaskFileRecord] = []

        for root in roots {
            let normalisedRoot = (root as NSString).standardizingPath
            let existingForRoot = existingByRoot[normalisedRoot] ?? []
            let existingPaths = Set(existingForRoot.map(\.path))

            // Fast path: always scan direct child project folders (same semantics as the board).
            // When `project_tag` is configured, only tagged children are considered projects.
            //
            // This ensures newly added projects (e.g. a new direct child folder with `🔥 Forge`)
            // are picked up without requiring an expensive recursive rescan.
            do {
                guard let children = try? fileManager.contentsOfDirectory(atPath: normalisedRoot) else { throw NSError() }
                var foundFastPaths = Set<String>()

                for child in children.sorted() {
                    guard !child.hasPrefix(".") else { continue }
                    let projectDir = (normalisedRoot as NSString).appendingPathComponent(child)
                    var isDir: ObjCBool = false
                    guard fileManager.fileExists(atPath: projectDir, isDirectory: &isDir), isDir.boolValue else { continue }

                    if let requiredTag = config.projectTag {
                        let tags = tagStore.readTagsIfAvailable(at: projectDir) ?? []
                        if !tags.contains(requiredTag) { continue }
                    }

                    let tasksPath = (projectDir as NSString).appendingPathComponent("TASKS.md")
                    guard fileManager.fileExists(atPath: tasksPath) else { continue }

                    let attrs = (try? fileManager.attributesOfItem(atPath: tasksPath)) ?? [:]
                    let mtimeDate = (attrs[.modificationDate] as? Date) ?? .distantPast
                    let sizeValue = (attrs[.size] as? NSNumber)?.int64Value ?? 0

                    foundFastPaths.insert(tasksPath)
                    toUpsert.append(TaskFileRecord(
                        path: tasksPath,
                        kind: .projectTasks,
                        label: child,
                        projectRoot: normalisedRoot,
                        mtime: mtimeDate.timeIntervalSinceReferenceDate,
                        size: sizeValue,
                        lastSeenAt: now,
                        lastParsedAt: nil,
                        overdueCount: 0,
                        dueTodayCount: 0,
                        inboxOpenCount: 0,
                        isDeleted: false
                    ))
                }

                // For direct-child projects, mark removals (project deleted, tag removed, or TASKS.md removed).
                let existingDirectChildPaths = existingPaths.filter { isDirectChildProjectTasksPath($0, under: normalisedRoot) }
                let removedDirectChildPaths = Set(existingDirectChildPaths).subtracting(foundFastPaths)
                for path in removedDirectChildPaths {
                    let dirPath = (path as NSString).deletingLastPathComponent
                    let label = (dirPath as NSString).lastPathComponent
                    toUpsert.append(TaskFileRecord(
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
                    ))
                }
            } catch {
                // If the root can't be read, fall through to no-op for fast scan.
            }

            // Default behaviour: once we have at least one record for a root, avoid repeated
            // full rescans on every run. A deep rescan is only performed when explicitly
            // requested via `forceFullRescan`, or when the root has never been seen before.
            if !forceFullRescan, !existingForRoot.isEmpty {
                continue
            }

            // Slow path: deep recursive scan (used for initial bootstrap and explicit rebuilds).
            // When `project_tag` is configured, only treat directories with that tag as projects.
            let taskFiles: [TaskFileFinder.TaskFile] = TaskFileFinder.findAll(under: normalisedRoot).filter { tf in
                guard let requiredTag = config.projectTag else { return true }
                let parentDir = (tf.path as NSString).deletingLastPathComponent
                let tags = tagStore.readTagsIfAvailable(at: parentDir) ?? []
                return tags.contains(requiredTag)
            }
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
