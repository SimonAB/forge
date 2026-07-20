import Foundation

/// Resolves OmniFocus kanban column tags when a task (or project) carries more than one.
///
/// Default policy (`resolveTask` / `resolveProject`):
/// 1. Prefer a column that matches the current Finder column, if present among the candidates.
/// 2. Otherwise prefer the furthest-right column on the main flow
///    (`Plan → Watch → Coding → Write → Review → Shipped`).
/// 3. `Paused` wins only when it is the sole distinct candidate (or every candidate is Paused).
/// 4. Across linked tasks, use a majority of per-task resolutions; ties fall back to (1) then (2).
///
/// Pull policy (`resolveForPull` / `resolveProjectForPull`):
/// Prefer a column that **differs** from Finder when several tags are stacked (typical when the
/// user adds Watch without clearing Review), then furthest among those differing tags.
public enum OmniFocusColumnResolution {

    public struct TaskResolution: Sendable, Equatable {
        /// All distinct Forge columns detected on the task.
        public let columns: [String]
        /// Single column chosen by policy, if any.
        public let resolved: String?
        public var isAmbiguous: Bool { columns.count > 1 }

        public init(columns: [String], resolved: String?) {
            self.columns = columns
            self.resolved = resolved
        }
    }

    /// Resolve a single task's set of column tags.
    public static func resolveTask(
        columns: [String],
        boardOrder: [String] = KanbanTransitionPolicy.mainFlowOrder,
        preferFinder: String? = nil
    ) -> TaskResolution {
        let unique = uniquePreservingOrder(columns)
        let resolved = pick(from: unique, boardOrder: boardOrder, preferFinder: preferFinder)
        return TaskResolution(columns: unique, resolved: resolved)
    }

    /// Resolve columns when pulling OmniFocus → Finder.
    ///
    /// If several kanban tags are present, prefer one that **differs** from the current
    /// Finder column (the usual case: user added a new OF tag without clearing the old).
    /// Among differing tags, prefer furthest on the main flow. If every OF tag matches
    /// Finder (or Finder is unset), fall back to the normal pick policy.
    public static func resolveForPull(
        columns: [String],
        finderColumn: String?,
        boardOrder: [String] = KanbanTransitionPolicy.mainFlowOrder
    ) -> String? {
        let unique = uniquePreservingOrder(columns)
        guard !unique.isEmpty else { return nil }
        if unique.count == 1 { return unique[0] }

        let differing = unique.filter { $0 != finderColumn }
        if differing.count == 1 {
            return differing[0]
        }
        if !differing.isEmpty {
            return pick(from: differing, boardOrder: boardOrder, preferFinder: nil)
        }
        return pick(from: unique, boardOrder: boardOrder, preferFinder: finderColumn)
    }

    /// Resolve a project's linked tasks for an OF → Finder pull.
    public static func resolveProjectForPull(
        tasks: [OmniFocusTaskRecord],
        finderColumn: String?,
        boardOrder: [String] = KanbanTransitionPolicy.mainFlowOrder
    ) -> String? {
        let perTask: [String] = tasks.compactMap { task in
            let cols = task.forgeColumns.isEmpty
                ? (task.forgeColumn.map { [$0] } ?? [])
                : task.forgeColumns
            return resolveForPull(columns: cols, finderColumn: finderColumn, boardOrder: boardOrder)
        }
        guard !perTask.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        for column in perTask {
            counts[column, default: 0] += 1
        }
        let maxCount = counts.values.max() ?? 0
        let leaders = counts.filter { $0.value == maxCount }.map(\.key)
        // Prefer a leader that differs from Finder when tied.
        if let finderColumn {
            let differingLeaders = leaders.filter { $0 != finderColumn }
            if differingLeaders.count == 1 { return differingLeaders[0] }
            if !differingLeaders.isEmpty {
                return pick(from: differingLeaders, boardOrder: boardOrder, preferFinder: nil)
            }
        }
        return pick(from: leaders, boardOrder: boardOrder, preferFinder: finderColumn)
    }

    /// Resolve a project's linked tasks to one Finder-facing column.
    public static func resolveProject(
        tasks: [OmniFocusTaskRecord],
        boardOrder: [String] = KanbanTransitionPolicy.mainFlowOrder,
        preferFinder: String? = nil
    ) -> String? {
        let resolved = tasks.compactMap { task -> String? in
            if !task.forgeColumns.isEmpty {
                return resolveTask(
                    columns: task.forgeColumns,
                    boardOrder: boardOrder,
                    preferFinder: preferFinder
                ).resolved
            }
            return task.forgeColumn
        }
        guard !resolved.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        for column in resolved {
            counts[column, default: 0] += 1
        }
        let maxCount = counts.values.max() ?? 0
        let leaders = counts.filter { $0.value == maxCount }.map(\.key)
        return pick(from: leaders, boardOrder: boardOrder, preferFinder: preferFinder)
    }

    /// Pick one column from candidates using Finder preference then board order.
    public static func pick(
        from candidates: [String],
        boardOrder: [String] = KanbanTransitionPolicy.mainFlowOrder,
        preferFinder: String? = nil
    ) -> String? {
        let unique = uniquePreservingOrder(candidates)
        guard !unique.isEmpty else { return nil }
        if unique.count == 1 { return unique[0] }

        if let preferFinder, unique.contains(preferFinder) {
            return preferFinder
        }

        let pausedOnly = unique.allSatisfy { $0 == "Paused" }
        if pausedOnly { return "Paused" }

        let main = unique.filter { $0 != "Paused" }
        if main.isEmpty { return "Paused" }

        var best: String?
        var bestIndex = -1
        for column in main {
            let index = boardOrder.firstIndex(of: column) ?? boardOrder.count
            if index >= bestIndex {
                bestIndex = index
                best = column
            }
        }
        return best ?? main.last
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                out.append(value)
            }
        }
        return out
    }
}
