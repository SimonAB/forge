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
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(viewModel.groupedColumns.enumerated()), id: \.offset) { _, group in
                            ColumnView(
                                column: group.column,
                                projects: group.projects,
                                viewModel: viewModel
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .keyboardShortcut("r", modifiers: .command)
            }
            ToolbarItem(placement: .automatic) {
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
            }
            ToolbarItem(placement: .automatic) {
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
            }
            ToolbarItem(placement: .automatic) {
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
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Search (regex)", text: Binding(
                        get: { viewModel.searchFilter ?? "" },
                        set: { viewModel.searchFilter = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.plain)
                    .frame(minWidth: 120, maxWidth: 200)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if runForgeInTerminal != nil {
                ToolbarItem(placement: .automatic) {
                    Menu {
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
                        Divider()
                        Button("Sync") {
                            runForgeInTerminal?("forge sync", viewModel.config.resolvedWorkspacePath)
                        }
                        Button("Board (terminal)") {
                            runForgeInTerminal?("forge board", viewModel.config.resolvedWorkspacePath)
                        }
                    } label: {
                        Label("GTD", systemImage: "checklist")
                    }
                }
            }
        }
        .task {
            viewModel.load()
        }
    }
}
