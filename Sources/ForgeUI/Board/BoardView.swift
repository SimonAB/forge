import SwiftUI
import ForgeCore

/// Main Kanban board view: horizontal scroll of columns, each with header and project cards. Supports drag-and-drop between columns.
public struct BoardView: View {
    @Bindable var viewModel: BoardViewModel
    @Environment(\.runForgeInTerminal) private var runForgeInTerminal

    public init(viewModel: BoardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.projects.isEmpty {
                ProgressView("Loading projects…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.projects.isEmpty {
                VStack(spacing: 12) {
                    Text("Could not load projects")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        viewModel.refresh()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    let columnCount = max(1, viewModel.groupedColumns.count)
                    let padding: CGFloat = 12
                    let spacing: CGFloat = 12
                    let totalGaps = padding * 2 + spacing * CGFloat(columnCount - 1)
                    let columnWidth = min(320, max(180, (geometry.size.width - totalGaps) / CGFloat(columnCount)))
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: spacing) {
                            ForEach(Array(viewModel.groupedColumns.enumerated()), id: \.offset) { _, group in
                                ColumnView(
                                    column: group.column,
                                    projects: group.projects,
                                    viewModel: viewModel,
                                    columnWidth: columnWidth
                                )
                            }
                        }
                        .frame(minWidth: geometry.size.width)
                        .padding(padding)
                    }
                }
            }
        }
        .toolbar {
            // MARK: - Filters (leading)
            ToolbarItemGroup(placement: .automatic) {
                Picker("Column", selection: Binding(
                    get: { viewModel.columnFilter ?? "" },
                    set: { viewModel.columnFilter = $0.isEmpty ? nil : $0 }
                )) {
                    Text("All columns").tag("")
                    ForEach(viewModel.config.board.columns, id: \.name) { col in
                        Text(col.name).tag(col.name)
                    }
                    Text("Untagged").tag("Untagged")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 120)

                Picker("Delegation", selection: Binding(
                    get: { viewModel.metaTagFilter ?? "" },
                    set: { viewModel.metaTagFilter = $0.isEmpty ? nil : $0 }
                )) {
                    Text("All").tag("")
                    ForEach(viewModel.metaTagsForFilter, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 100)

                Picker("Domain", selection: Binding(
                    get: { viewModel.pathSegmentFilter ?? "" },
                    set: { viewModel.pathSegmentFilter = $0.isEmpty ? nil : $0 }
                )) {
                    Text("All domains").tag("")
                    Text("Work").tag("Work")
                    Text("Home").tag("Home")
                    Text("Sanctum").tag("Sanctum")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 110)
            }

            // MARK: - Search (centre)
            ToolbarItem(placement: .principal) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11, weight: .medium))
                    TextField("Search", text: Binding(
                        get: { viewModel.searchFilter ?? "" },
                        set: { viewModel.searchFilter = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.plain)
                    .frame(minWidth: 140, maxWidth: 220)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }

            // MARK: - Actions (trailing)
            ToolbarItemGroup(placement: .primaryAction) {
                if runForgeInTerminal != nil {
                    Menu {
                        Section("Workflow") {
                            Button("Inbox (process)") {
                                runForgeInTerminal?("forge process", viewModel.config.resolvedWorkspacePath)
                            }
                            Button("Weekly review") {
                                runForgeInTerminal?("forge review", viewModel.config.resolvedWorkspacePath)
                            }
                            Button("Due today") {
                                runForgeInTerminal?("forge due", viewModel.config.resolvedWorkspacePath)
                            }
                            Button("Next actions") {
                                runForgeInTerminal?("forge next", viewModel.config.resolvedWorkspacePath)
                            }
                        }
                        Section("Terminal") {
                            Button("Sync") {
                                runForgeInTerminal?("forge sync", viewModel.config.resolvedWorkspacePath)
                            }
                            Button("Board") {
                                runForgeInTerminal?("forge board", viewModel.config.resolvedWorkspacePath)
                            }
                        }
                    } label: {
                        Label("GTD", systemImage: "checklist")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary, lineWidth: 0.5))
                    }
                }

                Button {
                    viewModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .task {
            viewModel.load()
        }
    }
}
