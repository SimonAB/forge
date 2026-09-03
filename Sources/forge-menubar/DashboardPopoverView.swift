import ForgeCore
import SwiftUI

/// Menubar popover: schedule, due tasks, and board hot spots from the dashboard snapshot.
struct DashboardPopoverView: View {
    let snapshot: DashboardSnapshotJSON?
    let errorMessage: String?
    let isLoading: Bool
    let onRefresh: () -> Void
    let onOpenBoard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else if let errorMessage {
                ContentUnavailableView(
                    "Dashboard unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .frame(minWidth: 320, minHeight: 160)
            } else if let snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summary(snapshot)
                        if let calendarError = snapshot.calendarError {
                            noteRow(calendarError)
                        }
                        if let worldError = snapshot.world.error {
                            noteRow(worldError)
                        }
                        dashboardSection("Schedule today", isEmpty: snapshot.calendarToday.isEmpty, empty: "No events") {
                            ForEach(snapshot.calendarToday) { event in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(event.time)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 88, alignment: .leading)
                                    Text(event.title)
                                        .lineLimit(2)
                                }
                            }
                        }
                        dashboardSection(
                            "Inbox (\(snapshot.inboxCount))",
                            isEmpty: snapshot.inbox.isEmpty,
                            empty: "Empty"
                        ) {
                            ForEach(snapshot.inbox) { item in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.title)
                                        .lineLimit(2)
                                    Spacer()
                                    if let source = item.source, !source.isEmpty {
                                        Text(source)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        dashboardSection(
                            "Overdue (\(snapshot.dueCounts.overdue))",
                            isEmpty: snapshot.dueOverdue.isEmpty,
                            empty: "None"
                        ) {
                            ForEach(snapshot.dueOverdue) { task in dueRow(task) }
                        }
                        dashboardSection(
                            "Due today (\(snapshot.dueCounts.today))",
                            isEmpty: snapshot.dueToday.isEmpty,
                            empty: "None"
                        ) {
                            ForEach(snapshot.dueToday) { task in dueRow(task) }
                        }
                        dashboardSection("URGENT", isEmpty: snapshot.urgent.isEmpty, empty: "None") {
                            ForEach(snapshot.urgent) { project in projectRow(project) }
                        }
                        dashboardSection("Stuck in-flight", isEmpty: snapshot.stuck.isEmpty, empty: "None") {
                            ForEach(snapshot.stuck) { project in projectRow(project) }
                        }
                    }
                    .padding(12)
                }
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 480)
    }

    private var header: some View {
        HStack {
            Label("Forge Dashboard", systemImage: "hammer.fill")
                .font(.headline)
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh dashboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button("Board…", action: onOpenBoard)
            Spacer()
            if let snapshot {
                Text(snapshot.generatedAt.prefix(16).replacingOccurrences(of: "T", with: " "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private func summary(_ snapshot: DashboardSnapshotJSON) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(columnSummary(snapshot))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(snapshot.world.openTasks) open tasks · inbox \(snapshot.inboxCount) · \(snapshot.activeCount) active projects")
                .font(.caption)
        }
    }

    @ViewBuilder
    private func dashboardSection<Content: View>(
        _ title: String,
        isEmpty: Bool,
        empty: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if isEmpty {
                Text(empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                content()
            }
        }
    }

    private func dueRow(_ task: DashboardSnapshotJSON.DueTask) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(String(task.due.prefix(10)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if let column = task.column {
                    Text(column)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(task.project)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(task.title + (task.waiting ? " [waiting]" : ""))
                .font(.callout)
                .lineLimit(2)
        }
    }

    private func projectRow(_ project: DashboardSnapshotJSON.ProjectHot) -> some View {
        HStack {
            Text(formatAge(project.daysSinceActivity))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Text(project.column)
                .font(.caption2)
                .frame(width: 52, alignment: .leading)
            Text(project.name)
                .lineLimit(1)
        }
        .font(.callout)
    }

    private func noteRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func columnSummary(_ snapshot: DashboardSnapshotJSON) -> String {
        let order = ["Watch", "Coding", "Write", "Review", "Plan", "Paused", "Shipped"]
        let abbrev: [String: String] = [
            "Watch": "Watch", "Coding": "Cod", "Write": "Write", "Review": "Rev",
            "Plan": "Plan", "Paused": "Pause", "Shipped": "Ship",
        ]
        let parts = order.compactMap { name -> String? in
            guard let count = snapshot.columns[name], count > 0 else { return nil }
            return "\(abbrev[name] ?? name):\(count)"
        }
        return parts.joined(separator: " · ")
    }

    private func formatAge(_ days: Double) -> String {
        if days >= 30 { return "\(Int(days / 30))mo" }
        if days >= 7 { return "\(Int(days))d" }
        return String(format: "%.0fd", days)
    }
}
