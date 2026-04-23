import Foundation

/// Board Radar bucket labels (matches Forge Board filter tags and CLI JSON).
public enum KanbanRadarBucket: String, Codable, Sendable, Equatable {
    case calm
    case watch
    case heat
}

/// Urgency and staleness scoring for kanban projects, shared by the board UI and CLI.
public enum KanbanRadar {

    /// Where the activity timestamp was taken from (`missing` uses `Date.distantPast` for age math).
    public static func activityResolution(for project: Project, fileManager: FileManager = .default) -> (
        modificationDate: Date,
        source: String
    ) {
        if let attrs = try? fileManager.attributesOfItem(atPath: project.path),
           let mtime = attrs[.modificationDate] as? Date {
            return (mtime, "project_directory")
        }
        return (.distantPast, "missing")
    }

    /// Modification time used for activity: project directory, else distant past.
    public static func activityModificationDate(for project: Project, fileManager: FileManager = .default) -> Date {
        activityResolution(for: project, fileManager: fileManager).modificationDate
    }

    /// Whole days since the activity modification date, relative to `now`.
    public static func daysSinceActivity(for project: Project, now: Date, fileManager: FileManager = .default) -> Double {
        let modificationDate = activityModificationDate(for: project, fileManager: fileManager)
        return now.timeIntervalSince(modificationDate) / (60 * 60 * 24)
    }

    /// Combines URGENT-prefixed meta tags with folder age (same thresholds as the board Radar filter).
    public static func bucket(for project: Project, now: Date, fileManager: FileManager = .default) -> KanbanRadarBucket {
        let hasUrgentTag = project.metaTags.contains { tag in
            tag.uppercased().hasPrefix("URGENT")
        }
        let modificationDate = activityModificationDate(for: project, fileManager: fileManager)
        let daysSinceChange = now.timeIntervalSince(modificationDate) / (60 * 60 * 24)

        if hasUrgentTag || daysSinceChange >= 21 {
            return .heat
        }
        if daysSinceChange >= 7 {
            return .watch
        }
        return .calm
    }
}
