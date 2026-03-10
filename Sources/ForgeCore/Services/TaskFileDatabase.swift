import Foundation
import SQLite3

/// Represents a single row in the `files` table of the task file database.
///
/// This record mirrors the schema stored in `<ForgeDir>/.cache/tasks.db` and is used as the
/// in-memory representation for queries and updates.
public struct TaskFileRecord {

    public enum Kind: String {
        case projectTasks
        case area
        case inbox
    }

    /// Absolute path to the markdown file.
    public var path: String

    /// Kind of file (project TASKS.md, area, or inbox).
    public var kind: Kind

    /// Human-readable label (usually project or area name).
    public var label: String

    /// Resolved project root this file belongs to (for projectTasks).
    public var projectRoot: String

    /// Last modification time on disk (seconds since reference date).
    public var mtime: TimeInterval

    /// Last known size in bytes.
    public var size: Int64

    /// When this file was last observed by any scan or watcher.
    public var lastSeenAt: TimeInterval

    /// When this file was last parsed to compute counts, or nil if never.
    public var lastParsedAt: TimeInterval?

    /// Cached count of overdue tasks in this file.
    public var overdueCount: Int

    /// Cached count of tasks due today in this file.
    public var dueTodayCount: Int

    /// Cached count of open inbox items (only meaningful for inbox).
    public var inboxOpenCount: Int

    /// Whether this file has been logically deleted from the index.
    public var isDeleted: Bool

    /// Creates a new task file record.
    ///
    /// - Parameters:
    ///   - path: Absolute path to the markdown file.
    ///   - kind: Kind of file (project tasks, area, or inbox).
    ///   - label: Human-readable label.
    ///   - projectRoot: Resolved project root, if applicable.
    ///   - mtime: Last modification time on disk.
    ///   - size: Last known size in bytes.
    ///   - lastSeenAt: Time when this file was last observed.
    ///   - lastParsedAt: Time when this file was last parsed, or nil.
    ///   - overdueCount: Cached overdue count.
    ///   - dueTodayCount: Cached due-today count.
    ///   - inboxOpenCount: Cached open inbox count.
    ///   - isDeleted: Logical deletion flag.
    public init(
        path: String,
        kind: Kind,
        label: String,
        projectRoot: String,
        mtime: TimeInterval,
        size: Int64,
        lastSeenAt: TimeInterval,
        lastParsedAt: TimeInterval?,
        overdueCount: Int,
        dueTodayCount: Int,
        inboxOpenCount: Int,
        isDeleted: Bool
    ) {
        self.path = path
        self.kind = kind
        self.label = label
        self.projectRoot = projectRoot
        self.mtime = mtime
        self.size = size
        self.lastSeenAt = lastSeenAt
        self.lastParsedAt = lastParsedAt
        self.overdueCount = overdueCount
        self.dueTodayCount = dueTodayCount
        self.inboxOpenCount = inboxOpenCount
        self.isDeleted = isDeleted
    }
}

/// Represents a batch update to per-file counts and metadata.
public struct TaskFileCountsUpdate {

    /// Absolute path to the markdown file.
    public var path: String

    /// Cached overdue count.
    public var overdueCount: Int

    /// Cached due-today count.
    public var dueTodayCount: Int

    /// Cached inbox open count.
    public var inboxOpenCount: Int

    /// Latest modification time on disk.
    public var mtime: TimeInterval

    /// Latest size on disk.
    public var size: Int64

    /// Time when parsing completed.
    public var parsedAt: TimeInterval

    /// Creates a new counts update.
    ///
    /// - Parameters:
    ///   - path: Absolute path to the markdown file.
    ///   - overdueCount: Cached overdue count.
    ///   - dueTodayCount: Cached due-today count.
    ///   - inboxOpenCount: Cached inbox open count.
    ///   - mtime: Latest modification time.
    ///   - size: Latest size.
    ///   - parsedAt: Time when parsing completed.
    public init(
        path: String,
        overdueCount: Int,
        dueTodayCount: Int,
        inboxOpenCount: Int,
        mtime: TimeInterval,
        size: Int64,
        parsedAt: TimeInterval
    ) {
        self.path = path
        self.overdueCount = overdueCount
        self.dueTodayCount = dueTodayCount
        self.inboxOpenCount = inboxOpenCount
        self.mtime = mtime
        self.size = size
        self.parsedAt = parsedAt
    }
}

/// Lightweight wrapper around a SQLite database that tracks Forge task files and their cached
/// counts. The database lives under `<ForgeDir>/.cache/tasks.db` and is used as a shared source
/// of truth for project TASKS.md discovery and per-file counts.
public final class TaskFileDatabase {

    private enum Constants {
        static let schemaVersion: Int32 = 1
    }

    private let dbPath: String
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "TaskFileDatabase", qos: .utility)

    /// Initialise the task file database for a given Forge directory.
    ///
    /// - Parameter forgeDir: Absolute path to the Forge directory containing `config.yaml`.
    public init(forgeDir: String) throws {
        let cacheDir = (forgeDir as NSString).appendingPathComponent(".cache")
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        self.dbPath = (cacheDir as NSString).appendingPathComponent("tasks.db")
        try openAndMigrateIfNeeded()
    }

    deinit {
        if let db = handle {
            sqlite3_close(db)
        }
    }

    /// Insert or update a batch of file records.
    ///
    /// - Parameter files: Records to upsert into the `files` table.
    public func upsertFiles(_ files: [TaskFileRecord]) throws {
        guard !files.isEmpty else { return }
        try queue.sync {
            guard let db = handle else { return }
            let sql = """
            INSERT INTO files (
                path, kind, label, projectRoot,
                mtime, size, lastSeenAt, lastParsedAt,
                overdueCount, dueTodayCount, inboxOpenCount, isDeleted
            ) VALUES (
                ?, ?, ?, ?,
                ?, ?, ?, ?,
                ?, ?, ?, ?
            )
            ON CONFLICT(path) DO UPDATE SET
                kind = excluded.kind,
                label = excluded.label,
                projectRoot = excluded.projectRoot,
                mtime = excluded.mtime,
                size = excluded.size,
                lastSeenAt = excluded.lastSeenAt,
                lastParsedAt = COALESCE(excluded.lastParsedAt, files.lastParsedAt),
                overdueCount = excluded.overdueCount,
                dueTodayCount = excluded.dueTodayCount,
                inboxOpenCount = excluded.inboxOpenCount,
                isDeleted = excluded.isDeleted;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw databaseError()
            }
            defer { sqlite3_finalize(stmt) }

            for file in files {
                sqlite3_reset(stmt)
                bindString(file.path, index: 1, in: stmt)
                bindString(file.kind.rawValue, index: 2, in: stmt)
                bindString(file.label, index: 3, in: stmt)
                bindString(file.projectRoot, index: 4, in: stmt)
                sqlite3_bind_double(stmt, 5, file.mtime)
                sqlite3_bind_int64(stmt, 6, file.size)
                sqlite3_bind_double(stmt, 7, file.lastSeenAt)
                if let parsed = file.lastParsedAt {
                    sqlite3_bind_double(stmt, 8, parsed)
                } else {
                    sqlite3_bind_null(stmt, 8)
                }
                sqlite3_bind_int(stmt, 9, Int32(file.overdueCount))
                sqlite3_bind_int(stmt, 10, Int32(file.dueTodayCount))
                sqlite3_bind_int(stmt, 11, Int32(file.inboxOpenCount))
                sqlite3_bind_int(stmt, 12, file.isDeleted ? 1 : 0)

                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw databaseError()
                }
            }
        }
    }

    /// Mark the given paths as logically deleted.
    ///
    /// - Parameter paths: Absolute paths to mark as deleted.
    public func markDeleted(paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try queue.sync {
            guard let db = handle else { return }
            let now = Date().timeIntervalSinceReferenceDate
            let sql = "UPDATE files SET isDeleted = 1, lastSeenAt = ? WHERE path = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw databaseError()
            }
            defer { sqlite3_finalize(stmt) }

            for path in paths {
                sqlite3_reset(stmt)
                sqlite3_bind_double(stmt, 1, now)
                bindString(path, index: 2, in: stmt)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw databaseError()
                }
            }
        }
    }

    /// Apply a batch of per-file count updates.
    ///
    /// - Parameter updates: Count updates to persist.
    public func updateCounts(_ updates: [TaskFileCountsUpdate]) throws {
        guard !updates.isEmpty else { return }
        try queue.sync {
            guard let db = handle else { return }
            let sql = """
            UPDATE files SET
                overdueCount = ?,
                dueTodayCount = ?,
                inboxOpenCount = ?,
                mtime = ?,
                size = ?,
                lastParsedAt = ?
            WHERE path = ?;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw databaseError()
            }
            defer { sqlite3_finalize(stmt) }

            for update in updates {
                sqlite3_reset(stmt)
                sqlite3_bind_int(stmt, 1, Int32(update.overdueCount))
                sqlite3_bind_int(stmt, 2, Int32(update.dueTodayCount))
                sqlite3_bind_int(stmt, 3, Int32(update.inboxOpenCount))
                sqlite3_bind_double(stmt, 4, update.mtime)
                sqlite3_bind_int64(stmt, 5, update.size)
                sqlite3_bind_double(stmt, 6, update.parsedAt)
                bindString(update.path, index: 7, in: stmt)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw databaseError()
                }
            }
        }
    }

    /// Return all project task files under any of the given project roots.
    ///
    /// - Parameter roots: Resolved project roots.
    /// - Returns: Records for matching project task files.
    public func projectTaskFiles(under roots: [String]) throws -> [TaskFileRecord] {
        guard !roots.isEmpty else { return [] }
        return try queue.sync {
            guard let db = handle else { return [] }
            let placeholders = Array(repeating: "?", count: roots.count).joined(separator: ",")
            let sql = """
            SELECT path, kind, label, projectRoot, mtime, size,
                   lastSeenAt, lastParsedAt, overdueCount, dueTodayCount,
                   inboxOpenCount, isDeleted
            FROM files
            WHERE kind = 'projectTasks'
              AND isDeleted = 0
              AND projectRoot IN (\(placeholders));
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw databaseError()
            }
            defer { sqlite3_finalize(stmt) }

            for (i, root) in roots.enumerated() {
                bindString(root, index: Int32(i + 1), in: stmt)
            }

            var results: [TaskFileRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let record = readRecord(from: stmt) {
                    results.append(record)
                }
            }
            return results
        }
    }

    /// Compute aggregate overdue and due-today counts across all non-deleted files.
    ///
    /// - Returns: Tuple of (overdue, dueToday, inboxOpen).
    public func aggregateCounts() throws -> (overdue: Int, dueToday: Int, inboxOpen: Int) {
        return try queue.sync {
            guard let db = handle else { return (0, 0, 0) }
            let sql = """
            SELECT
                SUM(overdueCount),
                SUM(dueTodayCount),
                SUM(inboxOpenCount)
            FROM files
            WHERE isDeleted = 0;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw databaseError()
            }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW else {
                return (0, 0, 0)
            }
            let overdue = Int(sqlite3_column_int(stmt, 0))
            let dueToday = Int(sqlite3_column_int(stmt, 1))
            let inbox = Int(sqlite3_column_int(stmt, 2))
            return (overdue, dueToday, inbox)
        }
    }

    /// Return files that appear to need parsing based on timestamps.
    ///
    /// - Returns: Records where `lastParsedAt` is nil or older than `mtime`.
    public func filesNeedingParse() throws -> [TaskFileRecord] {
        return try queue.sync {
            guard let db = handle else { return [] }
            let sql = """
            SELECT path, kind, label, projectRoot, mtime, size,
                   lastSeenAt, lastParsedAt, overdueCount, dueTodayCount,
                   inboxOpenCount, isDeleted
            FROM files
            WHERE isDeleted = 0
              AND (lastParsedAt IS NULL OR lastParsedAt < mtime);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw databaseError()
            }
            defer { sqlite3_finalize(stmt) }

            var results: [TaskFileRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let record = readRecord(from: stmt) {
                    results.append(record)
                }
            }
            return results
        }
    }

    // MARK: - Private

    private func openAndMigrateIfNeeded() throws {
        var db: OpaquePointer?
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw databaseError()
        }
        handle = db
        try createSchemaIfNeeded()
    }

    private func createSchemaIfNeeded() throws {
        try queue.sync {
            guard let db = handle else { return }
            let createSQL = """
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;

            CREATE TABLE IF NOT EXISTS files (
                path TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                label TEXT NOT NULL,
                projectRoot TEXT NOT NULL,
                mtime REAL NOT NULL,
                size INTEGER NOT NULL,
                lastSeenAt REAL NOT NULL,
                lastParsedAt REAL,
                overdueCount INTEGER NOT NULL DEFAULT 0,
                dueTodayCount INTEGER NOT NULL DEFAULT 0,
                inboxOpenCount INTEGER NOT NULL DEFAULT 0,
                isDeleted INTEGER NOT NULL DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_files_projectRoot_kind
                ON files(projectRoot, kind, isDeleted);

            CREATE INDEX IF NOT EXISTS idx_files_kind
                ON files(kind, isDeleted);

            CREATE INDEX IF NOT EXISTS idx_files_lastParsedAt
                ON files(lastParsedAt);

            PRAGMA user_version = \(Constants.schemaVersion);
            """
            if sqlite3_exec(db, createSQL, nil, nil, nil) != SQLITE_OK {
                throw databaseError()
            }
        }
    }

    private func databaseError() -> NSError {
        let message: String
        if let db = handle, let cString = sqlite3_errmsg(db) {
            message = String(cString: cString)
        } else {
            message = "Unknown SQLite error"
        }
        return NSError(domain: "TaskFileDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func bindString(_ value: String, index: Int32, in statement: OpaquePointer?) {
        _ = value.withCString { cStr in
            sqlite3_bind_text(
                statement,
                index,
                cStr,
                -1,
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
        }
    }

    private func readRecord(from stmt: OpaquePointer?) -> TaskFileRecord? {
        guard let stmt else { return nil }

        guard
            let pathCStr = sqlite3_column_text(stmt, 0),
            let kindCStr = sqlite3_column_text(stmt, 1),
            let labelCStr = sqlite3_column_text(stmt, 2),
            let rootCStr = sqlite3_column_text(stmt, 3)
        else {
            return nil
        }

        let path = String(cString: pathCStr)
        let kindRaw = String(cString: kindCStr)
        guard let kind = TaskFileRecord.Kind(rawValue: kindRaw) else {
            return nil
        }
        let label = String(cString: labelCStr)
        let projectRoot = String(cString: rootCStr)

        let mtime = sqlite3_column_double(stmt, 4)
        let size = sqlite3_column_int64(stmt, 5)
        let lastSeenAt = sqlite3_column_double(stmt, 6)
        let lastParsedAtValue = sqlite3_column_double(stmt, 7)
        let lastParsedAt: TimeInterval?
        if sqlite3_column_type(stmt, 7) == SQLITE_NULL {
            lastParsedAt = nil
        } else {
            lastParsedAt = lastParsedAtValue
        }
        let overdueCount = Int(sqlite3_column_int(stmt, 8))
        let dueTodayCount = Int(sqlite3_column_int(stmt, 9))
        let inboxOpenCount = Int(sqlite3_column_int(stmt, 10))
        let isDeleted = sqlite3_column_int(stmt, 11) != 0

        return TaskFileRecord(
            path: path,
            kind: kind,
            label: label,
            projectRoot: projectRoot,
            mtime: mtime,
            size: size,
            lastSeenAt: lastSeenAt,
            lastParsedAt: lastParsedAt,
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            inboxOpenCount: inboxOpenCount,
            isDeleted: isDeleted
        )
    }
}
