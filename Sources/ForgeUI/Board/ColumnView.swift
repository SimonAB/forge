import SwiftUI
import ForgeCore

/// Maps config column colour index (1–7) to SwiftUI Color for column headers/cards.
func columnColor(for colourIndex: Int) -> Color {
    guard let rgb = FinderTagColour.sRGB(for: colourIndex) else { return .secondary }
    return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
}

/// A single kanban column: header (name + count, colour) and a list of project cards. Accepts drops to move projects into this column.
struct ColumnView: View {
    let column: ColumnConfig
    let projects: [Project]
    @Bindable var viewModel: BoardViewModel
    var columnWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            columnHeader
            projectList
        }
        .frame(width: columnWidth)
        .padding(10)
        .background(columnColor(for: column.colour).opacity(0.12))
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(columnColor(for: column.colour).opacity(0.22), lineWidth: 1)
        )
        .dropDestination(for: String.self) { paths, _ in
            guard let path = paths.first,
                  let project = viewModel.projects.first(where: { $0.path == path }),
                  project.column != column.name else { return false }
            viewModel.move(project: project, toColumn: column)
            return true
        }
    }

    private var columnHeader: some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(columnColor(for: column.colour))
                .frame(width: 4, height: 20)
            Text(column.name)
                .font(.headline)
            Spacer()
            Text("\(projects.count)")
                .foregroundStyle(.secondary)
        }
    }

    private var projectList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(projects, id: \.path) { project in
                    ProjectCardView(
                        project: project,
                        archiveCountdownLabel: viewModel.archiveCountdownLabel(for: project)
                    )
                }
            }
        }
        .frame(minHeight: 120)
    }
}
