import SwiftUI
import Foundation
import ForgeCore
#if canImport(AppKit)
import AppKit
#endif

/// Main Kanban board view: horizontal scroll of columns, each with header and project cards. Supports drag-and-drop between columns.
/// When the window is narrower than `narrowWindowThreshold`, shows a list view instead.
public struct BoardView: View {
    @Bindable var viewModel: BoardViewModel
    @Environment(\.runForgeInTerminal) private var runForgeInTerminal
    @Environment(\.openTaskFilesFolder) private var openTaskFilesFolder
    #if canImport(AppKit)
    @State private var appKitSearchFieldShouldFocus = false
    #else
    @FocusState private var focusedField: FocusField?
    #endif
    @State private var keyDownMonitor: Any?

    /// Window width below which the list layout is shown instead of the board.
    private static let narrowWindowThreshold: CGFloat = 520

    private enum FocusField {
        case search
    }

    public init(viewModel: BoardViewModel) {
        self.viewModel = viewModel
    }

    /// Two-way binding for the toolbar search text that maps empty text to a nil filter.
    private var searchTextBinding: Binding<String> {
        Binding(
            get: { viewModel.searchFilter ?? "" },
            set: { viewModel.searchFilter = $0.isEmpty ? nil : $0 }
        )
    }

    /// True when the board search currently has a non-empty query.
    private var hasActiveSearchQuery: Bool {
        !(viewModel.searchFilter ?? "").isEmpty
    }

    /// Clear the active board search query.
    private func clearSearchQuery() {
        viewModel.searchFilter = nil
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
                    if geometry.size.width < Self.narrowWindowThreshold {
                        BoardListView(viewModel: viewModel)
                    } else {
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

                Picker("Radar", selection: Binding(
                    get: { viewModel.radarFilterKey ?? "" },
                    set: { viewModel.radarFilterKey = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Radar (all)").tag("")
                    Text("Calm").tag("calm")
                    Text("Watch").tag("watch")
                    Text("Heat").tag("heat")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 110)

                Picker("Assignee", selection: Binding(
                    get: { viewModel.assigneeFilter ?? "" },
                    set: { viewModel.assigneeFilter = $0.isEmpty ? nil : $0 }
                )) {
                    Text("All").tag("")
                    ForEach(viewModel.assigneesForFilter, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 110)

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
                    #if canImport(AppKit)
                    ToolbarSearchField(text: searchTextBinding, shouldFocus: $appKitSearchFieldShouldFocus, placeholder: "Search")
                    .frame(minWidth: 140, maxWidth: 220)
                    #else
                    TextField("Search", text: searchTextBinding)
                    .focused($focusedField, equals: .search)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 140, maxWidth: 220)
                    #endif
                    if hasActiveSearchQuery {
                        Button {
                            clearSearchQuery()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }

            // MARK: - Actions (trailing)
            ToolbarItemGroup(placement: .primaryAction) {
                if runForgeInTerminal != nil || openTaskFilesFolder != nil {
                    Menu {
                        Section("Workflow") {
                            if let openTaskFilesFolder = openTaskFilesFolder {
                                Button("Edit task files…") {
                                    openTaskFilesFolder()
                                }
                            }
                            if runForgeInTerminal != nil {
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
                        }
                        if runForgeInTerminal != nil {
                            Section("Terminal") {
                                Button("Sync") {
                                    runForgeInTerminal?("forge sync", viewModel.config.resolvedWorkspacePath)
                                }
                                Button("Board") {
                                    runForgeInTerminal?("forge board", viewModel.config.resolvedWorkspacePath)
                                }
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
                    viewModel.syncAndRefresh()
                } label: {
                    Label("Sync", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .onAppear {
            #if canImport(AppKit)
            guard keyDownMonitor == nil else { return }
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                // macOS handles Cmd+F as "Find…". We intercept it so we can focus the board search field instead.
                let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
                // On macOS, keyCode 3 is typically the "f" physical key.
                let isFKey = chars == "f" || event.keyCode == 3
                let isCmdF = event.modifierFlags.contains(.command) && isFKey
                if isCmdF {
                    NotificationCenter.default.post(name: .forgeBoardFocusSearch, object: nil)
                    return nil // Swallow so macOS doesn't take over with Find…
                }
                // Press Esc to clear the active board search.
                let isEscape = event.keyCode == 53
                let hasNoModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
                if isEscape && hasNoModifiers && hasActiveSearchQuery {
                    clearSearchQuery()
                    return nil
                }
                return event
            }
            #endif
        }
        .onDisappear {
            #if canImport(AppKit)
            if let keyDownMonitor {
                NSEvent.removeMonitor(keyDownMonitor)
                self.keyDownMonitor = nil
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeBoardFocusSearch)) { _ in
            // Toolbars sometimes need a "refocus" to update first-responder correctly.
            Task { @MainActor in
                #if canImport(AppKit)
                appKitSearchFieldShouldFocus = false
                appKitSearchFieldShouldFocus = true
                #else
                focusedField = nil
                focusedField = .search
                #endif
            }
        }
        .task {
            viewModel.load()
        }
    }
}

public extension Notification.Name {
    static let forgeBoardFocusSearch = Notification.Name("forge.board.focus.search")
}

#if canImport(AppKit)
/// SwiftUI toolbar-friendly search field that can be reliably focused via AppKit.
private struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var shouldFocus: Bool
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.placeholderString = placeholder
        field.isBordered = false
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.font = NSFont.systemFont(ofSize: 13)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        // Make it first responder when requested.
        if shouldFocus {
            if nsView.window?.firstResponder as? NSTextField !== nsView {
                _ = nsView.becomeFirstResponder()
            }
            // Avoid repeated refocusing on every state update, which resets selection/caret.
            shouldFocus = false
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
#endif

// MARK: - List layout (narrow window)

/// Vertical list of projects grouped by column, shown when the window is too narrow for the board.
private struct BoardListView: View {
    @Bindable var viewModel: BoardViewModel

    var body: some View {
        List {
            ForEach(Array(viewModel.groupedColumns.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group.projects, id: \.path) { project in
                        ProjectCardView(project: project)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowBackground(EmptyView())
                            .listRowSeparator(.hidden)
                            .dropDestination(for: String.self) { paths, _ in
                                guard let path = paths.first,
                                      let droppedProject = viewModel.projects.first(where: { $0.path == path }),
                                      droppedProject.column != group.column.name else { return false }
                                viewModel.move(project: droppedProject, toColumn: group.column)
                                return true
                            }
                    }
                } header: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(columnColor(for: group.column.colour))
                            .frame(width: 4, height: 14)
                        Text(group.column.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .dropDestination(for: String.self) { paths, _ in
                        guard let path = paths.first,
                              let droppedProject = viewModel.projects.first(where: { $0.path == path }),
                              droppedProject.column != group.column.name else { return false }
                        viewModel.move(project: droppedProject, toColumn: group.column)
                        return true
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}
