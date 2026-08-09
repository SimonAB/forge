import Foundation

/// Doctor buckets for Reminders ↔ Forge folder alignment.
public enum RemindersDoctorBucket: String, Codable, Sendable {
    case aligned
    case forgeOnly = "forge_only"
    case remindersOnly = "reminders_only"
    case ambiguous
    case sentinelMissing = "sentinel_missing"
    case sentinelExtra = "sentinel_extra"
    case sentinelDrift = "sentinel_drift"
    case hygiene
}

public struct RemindersDoctorItem: Codable, Sendable, Equatable {
    public let bucket: RemindersDoctorBucket
    public let folderName: String?
    public let listId: String?
    public let listTitle: String?
    public let finderColumn: String?
    public let sentinelColumn: String?
    public let detail: String

    public init(
        bucket: RemindersDoctorBucket,
        folderName: String? = nil,
        listId: String? = nil,
        listTitle: String? = nil,
        finderColumn: String? = nil,
        sentinelColumn: String? = nil,
        detail: String
    ) {
        self.bucket = bucket
        self.folderName = folderName
        self.listId = listId
        self.listTitle = listTitle
        self.finderColumn = finderColumn
        self.sentinelColumn = sentinelColumn
        self.detail = detail
    }
}

public struct RemindersDoctorReport: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let items: [RemindersDoctorItem]
    public let isClean: Bool

    public init(generatedAt: Date, items: [RemindersDoctorItem]) {
        self.generatedAt = generatedAt
        self.items = items
        let blocking: Set<RemindersDoctorBucket> = [.forgeOnly, .remindersOnly, .ambiguous]
        self.isClean = !items.contains { blocking.contains($0.bucket) }
    }
}

public enum RemindersAlignKind: String, Codable, Sendable {
    case createList = "create_list"
    case ensureSentinel = "ensure_sentinel"
    case updateSentinel = "update_sentinel"
    case proposeFinderShipped = "propose_finder_shipped"
}

public struct RemindersAlignProposal: Codable, Sendable, Equatable {
    public let id: String
    public let kind: RemindersAlignKind
    public let folderName: String?
    public let listId: String?
    public let listTitle: String?
    public let reminderId: String?
    public let column: String?
    public let summary: String

    public init(
        id: String = UUID().uuidString,
        kind: RemindersAlignKind,
        folderName: String? = nil,
        listId: String? = nil,
        listTitle: String? = nil,
        reminderId: String? = nil,
        column: String? = nil,
        summary: String
    ) {
        self.id = id
        self.kind = kind
        self.folderName = folderName
        self.listId = listId
        self.listTitle = listTitle
        self.reminderId = reminderId
        self.column = column
        self.summary = summary
    }
}

public struct RemindersAlignPlan: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let proposals: [RemindersAlignProposal]
    public let dryRun: Bool

    public init(generatedAt: Date, proposals: [RemindersAlignProposal], dryRun: Bool) {
        self.generatedAt = generatedAt
        self.proposals = proposals
        self.dryRun = dryRun
    }
}

/// Compares Forge-tagged folders with a Reminders inventory (doctor + align).
public enum RemindersAlignment {
    public static let blockingBuckets: Set<RemindersDoctorBucket> = [
        .forgeOnly, .remindersOnly, .ambiguous,
    ]

    public static let syncOnMoveBlockingBuckets: Set<RemindersDoctorBucket> = [
        .forgeOnly, .ambiguous,
    ]

    public static func shouldBlockSyncOnMove(
        folderName: String,
        report: RemindersDoctorReport,
        force: Bool
    ) -> Bool {
        if force { return false }
        return report.items.contains {
            $0.folderName == folderName && syncOnMoveBlockingBuckets.contains($0.bucket)
        }
    }

    /// Build a doctor report from scanned projects and a Reminders inventory.
    public static func doctor(
        projects: [Project],
        inventory: RemindersInventory,
        config: ForgeConfig,
        now: Date = Date()
    ) -> RemindersDoctorReport {
        let rem = config.reminders
        let knownColumns = config.board.columns.map(\.name)
        let inboxLower = rem.inboxListTitle?.lowercased()
        var items: [RemindersDoctorItem] = []

        var listsByFolder: [String: [RemindersListRecord]] = [:]
        var titleCounts: [String: Int] = [:]
        for list in inventory.lists {
            let titleKey = list.title.lowercased()
            titleCounts[titleKey, default: 0] += 1
            if let folder = list.matchedProject {
                listsByFolder[folder.lowercased(), default: []].append(list)
            }
        }

        for list in inventory.lists where titleCounts[list.title.lowercased(), default: 0] > 1 {
            items.append(RemindersDoctorItem(
                bucket: .ambiguous,
                folderName: list.matchedProject,
                listId: list.id,
                listTitle: list.title,
                detail: "Duplicate Reminders list title '\(list.title)'."
            ))
        }

        let projectByLower = Dictionary(uniqueKeysWithValues: projects.map { ($0.name.lowercased(), $0) })

        for project in projects.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let lists = listsByFolder[project.name.lowercased()] ?? []
            if lists.isEmpty {
                items.append(RemindersDoctorItem(
                    bucket: .forgeOnly,
                    folderName: project.name,
                    finderColumn: project.column,
                    detail: "Forge project has no matching Reminders list."
                ))
                continue
            }
            if lists.count > 1 {
                let titles = lists.map(\.title).joined(separator: ", ")
                items.append(RemindersDoctorItem(
                    bucket: .ambiguous,
                    folderName: project.name,
                    finderColumn: project.column,
                    detail: "Multiple Reminders lists match this folder: \(titles)."
                ))
                continue
            }

            let list = lists[0]
            let sentinels = inventory.reminders.filter {
                $0.listId == list.id
                    && RemindersSentinel.isSentinel(
                        title: $0.title,
                        notes: $0.notes,
                        prefix: rem.sentinelPrefix
                    )
            }

            if rem.columnSyncEnabled {
                appendSentinelItems(
                    project: project,
                    list: list,
                    sentinels: sentinels,
                    knownColumns: knownColumns,
                    prefix: rem.sentinelPrefix,
                    into: &items
                )
            }

            if isAllCompleteExceptSentinel(
                list: list,
                reminders: inventory.reminders,
                prefix: rem.sentinelPrefix
            ), project.column != "Shipped" {
                items.append(RemindersDoctorItem(
                    bucket: .hygiene,
                    folderName: project.name,
                    listId: list.id,
                    listTitle: list.title,
                    finderColumn: project.column,
                    detail: "Reminders list has no incomplete tasks (except sentinel). Consider moving Finder to Shipped."
                ))
            }

            if lists.count == 1, !rem.columnSyncEnabled || sentinels.count == 1 {
                let sentinelCol = sentinels.first.flatMap {
                    RemindersSentinel.parse(
                        title: $0.title,
                        notes: $0.notes,
                        prefix: rem.sentinelPrefix,
                        knownColumns: knownColumns
                    )
                }
                if !rem.columnSyncEnabled
                    || (sentinels.count == 1 && sentinelCol == project.column) {
                    items.append(RemindersDoctorItem(
                        bucket: .aligned,
                        folderName: project.name,
                        listId: list.id,
                        listTitle: list.title,
                        finderColumn: project.column,
                        sentinelColumn: sentinelCol,
                        detail: "List '\(list.title)' matches folder."
                    ))
                }
            }
        }

        for list in inventory.lists where list.matchedProject == nil {
            let isInbox = inboxLower != nil && list.title.lowercased() == inboxLower
            if isInbox {
                items.append(RemindersDoctorItem(
                    bucket: .hygiene,
                    listId: list.id,
                    listTitle: list.title,
                    detail: "Inbox list '\(list.title)' is unmatched (no Forge folder with this name)."
                ))
            } else {
                items.append(RemindersDoctorItem(
                    bucket: .remindersOnly,
                    listId: list.id,
                    listTitle: list.title,
                    detail: "Reminders list '\(list.title)' has no matching Forge folder."
                ))
            }
        }

        _ = projectByLower
        _ = now
        return RemindersDoctorReport(generatedAt: now, items: items)
    }

    /// Dry-run align plan. Sentinel proposals only when column sync flags are on.
    public static func alignPlan(
        projects: [Project],
        inventory: RemindersInventory,
        config: ForgeConfig,
        report: RemindersDoctorReport? = nil,
        now: Date = Date(),
        dryRun: Bool = true
    ) -> RemindersAlignPlan {
        let rem = config.reminders
        let doctorReport = report ?? doctor(projects: projects, inventory: inventory, config: config, now: now)
        var proposals: [RemindersAlignProposal] = []

        for item in doctorReport.items {
            switch item.bucket {
            case .forgeOnly:
                guard let folder = item.folderName else { continue }
                proposals.append(RemindersAlignProposal(
                    kind: .createList,
                    folderName: folder,
                    listTitle: folder,
                    column: item.finderColumn,
                    summary: "Create Reminders list '\(folder)'."
                ))
            case .sentinelMissing:
                guard rem.columnSyncEnabled,
                      let folder = item.folderName,
                      let listId = item.listId else { continue }
                let column = item.finderColumn ?? "Watch"
                proposals.append(RemindersAlignProposal(
                    kind: .ensureSentinel,
                    folderName: folder,
                    listId: listId,
                    listTitle: item.listTitle,
                    column: column,
                    summary: "Add sentinel \(RemindersSentinel.title(column: column, prefix: rem.sentinelPrefix)) on '\(item.listTitle ?? folder)'."
                ))
            case .sentinelDrift:
                guard rem.columnSyncEnabled,
                      let folder = item.folderName,
                      let reminderId = sentinelReminderId(
                        listId: item.listId,
                        inventory: inventory,
                        prefix: rem.sentinelPrefix
                      ),
                      let column = item.finderColumn else { continue }
                proposals.append(RemindersAlignProposal(
                    kind: .updateSentinel,
                    folderName: folder,
                    listId: item.listId,
                    listTitle: item.listTitle,
                    reminderId: reminderId,
                    column: column,
                    summary: "Update sentinel on '\(item.listTitle ?? folder)' to \(column)."
                ))
            case .hygiene:
                if item.detail.contains("Shipped"), let folder = item.folderName {
                    proposals.append(RemindersAlignProposal(
                        kind: .proposeFinderShipped,
                        folderName: folder,
                        listId: item.listId,
                        listTitle: item.listTitle,
                        column: "Shipped",
                        summary: "Propose Finder Shipped for '\(folder)' (not applied automatically)."
                    ))
                }
            default:
                break
            }
        }

        return RemindersAlignPlan(generatedAt: now, proposals: proposals, dryRun: dryRun)
    }

    private static func appendSentinelItems(
        project: Project,
        list: RemindersListRecord,
        sentinels: [ReminderRecord],
        knownColumns: [String],
        prefix: String,
        into items: inout [RemindersDoctorItem]
    ) {
        if sentinels.isEmpty {
            items.append(RemindersDoctorItem(
                bucket: .sentinelMissing,
                folderName: project.name,
                listId: list.id,
                listTitle: list.title,
                finderColumn: project.column,
                detail: "Matched list has no kanban sentinel reminder."
            ))
            return
        }
        if sentinels.count > 1 {
            items.append(RemindersDoctorItem(
                bucket: .sentinelExtra,
                folderName: project.name,
                listId: list.id,
                listTitle: list.title,
                finderColumn: project.column,
                detail: "Matched list has \(sentinels.count) sentinel reminders."
            ))
            return
        }
        let sentinel = sentinels[0]
        let parsed = RemindersSentinel.parse(
            title: sentinel.title,
            notes: sentinel.notes,
            prefix: prefix,
            knownColumns: knownColumns
        )
        if sentinel.isCompleted {
            items.append(RemindersDoctorItem(
                bucket: .sentinelDrift,
                folderName: project.name,
                listId: list.id,
                listTitle: list.title,
                finderColumn: project.column,
                sentinelColumn: parsed,
                detail: "Sentinel reminder is completed."
            ))
            return
        }
        if let parsed, let finder = project.column, parsed != finder {
            items.append(RemindersDoctorItem(
                bucket: .sentinelDrift,
                folderName: project.name,
                listId: list.id,
                listTitle: list.title,
                finderColumn: finder,
                sentinelColumn: parsed,
                detail: "Sentinel column \(parsed) differs from Finder \(finder)."
            ))
        }
    }

    private static func isAllCompleteExceptSentinel(
        list: RemindersListRecord,
        reminders: [ReminderRecord],
        prefix: String
    ) -> Bool {
        let items = reminders.filter { $0.listId == list.id }
        let ordinary = items.filter {
            !RemindersSentinel.isSentinel(title: $0.title, notes: $0.notes, prefix: prefix)
        }
        guard !ordinary.isEmpty else { return false }
        return ordinary.allSatisfy(\.isCompleted)
    }

    private static func sentinelReminderId(
        listId: String?,
        inventory: RemindersInventory,
        prefix: String
    ) -> String? {
        guard let listId else { return nil }
        let sentinels = inventory.reminders.filter {
            $0.listId == listId
                && RemindersSentinel.isSentinel(title: $0.title, notes: $0.notes, prefix: prefix)
        }
        return sentinels.count == 1 ? sentinels[0].id : nil
    }
}
