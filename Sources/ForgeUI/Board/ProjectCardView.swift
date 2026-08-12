import SwiftUI
import ForgeCore

/// A single project card on the board: name, meta tags (context/people from native folder tags), draggable,
/// optional clickable folder icon to reveal in Finder, and optional context menu from environment.
struct ProjectCardView: View {
    let project: Project
    /// Optional Shipped→Completed countdown label (e.g. `complete in 3d`).
    var archiveCountdownLabel: String? = nil
    @Environment(\.projectContextMenuActions) private var contextMenuActions
    @Environment(\.projectRevealAction) private var revealAction
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !project.metaTags.isEmpty || !project.assignees.isEmpty {
                    let meta = project.metaTags.joined(separator: " ")
                    let people = project.assignees.map { "@\($0)" }.joined(separator: " ")
                    let combined = [meta, people].filter { !$0.isEmpty }.joined(separator: " ")
                    Text(combined)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let archiveCountdownLabel, !archiveCountdownLabel.isEmpty {
                    Text(archiveCountdownLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help("Days remaining before the Completed Finder tag is applied")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Intentionally no task-file shortcuts (Forge is kanban-only).

            if let revealAction = revealAction {
                Button {
                    revealAction(project)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isHovering ? Color.primary.opacity(0.12) : .clear, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .draggable(project.path)
        .contentShape(Rectangle())
        .contextMenu {
            if let actions = contextMenuActions?(project), !actions.isEmpty {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.title) {
                        action.action(project)
                    }
                }
            }
        }
    }
}
