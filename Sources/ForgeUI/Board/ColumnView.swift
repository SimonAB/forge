import SwiftUI
import ForgeCore

/// Maps config column colour index (1–7) to SwiftUI Color for column headers/cards.
/// 1=Grey, 2=Green, 3=Purple, 4=Blue, 5=Yellow, 6=Orange, 7=Red.
func columnColor(for colourIndex: Int) -> Color {
    switch colourIndex {
    case 1: return .gray
    case 2: return .green
    case 3: return .purple
    case 4: return .blue
    case 5: return .yellow
    case 6: return .orange
    case 7: return .red
    default: return .secondary
    }
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
                    ProjectCardView(project: project)
                }
            }
        }
        .frame(minHeight: 120)
    }
}
