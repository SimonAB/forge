import Foundation

/// Delayed **Completed** meta tag for projects in the Shipped column.
///
/// Clock: preferred ship date from ``ShippedArchiveStore``; for legacy Shipped folders
/// without a cache entry, folder activity modification time (see ``KanbanRadar``).
/// When activity is already older than `board.archive_after_shipped_days`, apply immediately.
public enum KanbanArchivePolicy {

    /// Status of a Shipped project relative to the Completed meta tag.
    public enum Status: Sendable, Equatable {
        /// Not in Shipped, or feature disabled (no Completed meta tag in config).
        case notApplicable
        /// Already carries the Completed meta tag (or legacy Archived).
        case completed
        /// Delay elapsed; sweep should add Completed.
        case readyToComplete
        /// Still within the delay; `daysRemaining` is whole days until eligible (at least 1 while waiting).
        case countdown(daysRemaining: Int)
    }

    /// Outcome of applying due Completed tags.
    public struct SweepResult: Sendable, Equatable {
        public let completedFolders: [String]
        public let migratedFromLegacyArchived: [String]
        public let recordedShipDates: [String]
        public let errors: [String]

        public init(
            completedFolders: [String],
            migratedFromLegacyArchived: [String] = [],
            recordedShipDates: [String],
            errors: [String]
        ) {
            self.completedFolders = completedFolders
            self.migratedFromLegacyArchived = migratedFromLegacyArchived
            self.recordedShipDates = recordedShipDates
            self.errors = errors
        }

        /// Backwards-compatible alias for callers expecting `archivedFolders`.
        public var archivedFolders: [String] { completedFolders }
    }

    /// First configured meta tag whose name starts with `Completed` (case-insensitive).
    public static func completedTag(in board: BoardConfig) -> String? {
        board.metaTags.first {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
                .hasPrefix("COMPLETED")
        }
    }

    /// Deprecated alias — use ``completedTag(in:)``.
    public static func archivedTag(in board: BoardConfig) -> String? {
        completedTag(in: board)
    }

    public static func isEnabled(config: ForgeConfig) -> Bool {
        completedTag(in: config.board) != nil
    }

    /// True when the project carries the configured Completed tag.
    public static func hasCompletedTag(project: Project, config: ForgeConfig) -> Bool {
        guard let tag = completedTag(in: config.board) else { return false }
        return project.metaTags.contains(tag) || project.tags.contains(tag)
    }

    /// Legacy `Archived…` tags on a project (exact Finder strings).
    public static func legacyArchivedTags(on project: Project) -> [String] {
        project.tags.filter {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
                .hasPrefix("ARCHIVED")
        }
    }

    /// Compact board label, e.g. `complete in 3d`, or nil when not shown.
    public static func countdownLabel(for status: Status) -> String? {
        switch status {
        case .countdown(let days):
            return "complete in \(days)d"
        case .readyToComplete:
            return "complete due"
        case .completed, .notApplicable:
            return nil
        }
    }

    /// Resolve status for display or sweep decisions.
    public static func status(
        project: Project,
        config: ForgeConfig,
        shippedAt: Date?,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> Status {
        guard completedTag(in: config.board) != nil else { return .notApplicable }
        guard project.column == "Shipped" else { return .notApplicable }
        if hasCompletedTag(project: project, config: config) || !legacyArchivedTags(on: project).isEmpty {
            return .completed
        }

        let delayDays = config.board.resolvedArchiveAfterShippedDays
        let activity = KanbanRadar.activityModificationDate(for: project, fileManager: fileManager)
        let clockStart = shippedAt ?? activity
        let elapsedDays = now.timeIntervalSince(clockStart) / (60 * 60 * 24)

        if delayDays == 0 || elapsedDays >= Double(delayDays) {
            return .readyToComplete
        }

        let remaining = Int(ceil(Double(delayDays) - elapsedDays))
        return .countdown(daysRemaining: max(1, remaining))
    }

    /// After a Finder column change: record or clear ship dates and strip Completed when leaving Shipped.
    public static func noteColumnTransition(
        folderName: String,
        path: String,
        previousColumn: String?,
        newColumn: String,
        config: ForgeConfig,
        forgeDir: String,
        tagStore: any TagWriting = PlatformTagStore.makeDefault(),
        now: Date = Date()
    ) throws {
        guard isEnabled(config: config) else { return }

        let enteringShipped = newColumn == "Shipped" && previousColumn != "Shipped"
        let leavingShipped = previousColumn == "Shipped" && newColumn != "Shipped"

        if enteringShipped {
            try ShippedArchiveStore.recordShipped(
                forgeDir: forgeDir,
                folderName: folderName,
                at: now,
                force: false
            )
        }

        if leavingShipped {
            try ShippedArchiveStore.clearShipped(forgeDir: forgeDir, folderName: folderName)
            if let tag = completedTag(in: config.board) {
                try tagStore.removeTag(tag, at: path)
            }
            for legacy in tagStore.tags(at: path).filter({
                $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("ARCHIVED")
            }) {
                try tagStore.removeTag(legacy, at: path)
            }
        }
    }

    /// Swap legacy `Archived…` Finder tags for `Completed…` on Shipped folders.
    @discardableResult
    public static func migrateLegacyArchivedTags(
        projects: [Project],
        config: ForgeConfig,
        tagStore: FinderTagStore = FinderTagStore(),
        dryRun: Bool = false
    ) throws -> [String] {
        guard let completed = completedTag(in: config.board) else { return [] }
        var migrated: [String] = []
        for project in projects where project.column == "Shipped" {
            let legacy = legacyArchivedTags(on: project)
            guard !legacy.isEmpty else { continue }
            if dryRun {
                migrated.append(project.name)
                continue
            }
            for tag in legacy {
                try tagStore.removeTag(tag, at: project.path)
            }
            try tagStore.addTag(completed, at: project.path)
            migrated.append(project.name)
        }
        return migrated
    }

    /// Add `Completed` where due; seed ship dates for legacy Shipped folders.
    public static func applyDueArchives(
        projects: [Project],
        config: ForgeConfig,
        forgeDir: String,
        tagStore: FinderTagStore = FinderTagStore(),
        now: Date = Date(),
        fileManager: FileManager = .default,
        dryRun: Bool = false
    ) throws -> SweepResult {
        guard let completedTag = completedTag(in: config.board) else {
            return SweepResult(completedFolders: [], recordedShipDates: [], errors: [])
        }

        let migrated = try migrateLegacyArchivedTags(
            projects: projects,
            config: config,
            tagStore: tagStore,
            dryRun: dryRun
        )

        var payload = try ShippedArchiveStore.read(forgeDir: forgeDir)
        var completed: [String] = []
        var recorded: [String] = []
        var errors: [String] = []
        var payloadDirty = false

        for project in projects where project.column == "Shipped" {
            if hasCompletedTag(project: project, config: config) {
                continue
            }
            if !legacyArchivedTags(on: project).isEmpty {
                continue
            }

            let activity = KanbanRadar.activityModificationDate(for: project, fileManager: fileManager)
            if payload.shippedAt[project.name] == nil {
                if !dryRun {
                    payload.shippedAt[project.name] = activity
                    payloadDirty = true
                }
                recorded.append(project.name)
            }

            let shippedAt = payload.shippedAt[project.name] ?? activity
            let decision = status(
                project: project,
                config: config,
                shippedAt: shippedAt,
                now: now,
                fileManager: fileManager
            )
            guard decision == .readyToComplete else { continue }

            if dryRun {
                completed.append(project.name)
                continue
            }

            do {
                try tagStore.addTag(completedTag, at: project.path)
                completed.append(project.name)
            } catch {
                errors.append("\(project.name): \(error.localizedDescription)")
            }
        }

        if payloadDirty, !dryRun {
            try ShippedArchiveStore.write(forgeDir: forgeDir, payload: payload)
        }

        return SweepResult(
            completedFolders: completed,
            migratedFromLegacyArchived: migrated,
            recordedShipDates: recorded,
            errors: errors
        )
    }
}
