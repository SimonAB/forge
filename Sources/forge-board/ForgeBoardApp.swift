import SwiftUI
import ForgeCore
import ForgeUI

#if canImport(AppKit)
import AppKit
#endif

@main
struct ForgeBoardApp: App {
    private let config = Self.loadConfig()

    var body: some Scene {
        WindowGroup("Forge — Board") {
            if let config = config {
                BoardRootView(config: config)
            } else {
                NoConfigView()
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 500)
    }

    private static func loadConfig() -> ForgeConfig? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            (home as NSString).appendingPathComponent("Documents/Forge/config.yaml"),
            (home as NSString).appendingPathComponent("Documents/Work/Projects/Forge/config.yaml"),
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path), let config = try? ForgeConfig.load(from: path) {
                return config
            }
        }
        return nil
    }
}

// MARK: - Board root (view model + environment)

private struct BoardRootView: View {
    let config: ForgeConfig
    @State private var viewModel: BoardViewModel

    init(config: ForgeConfig) {
        self.config = config
        _viewModel = State(initialValue: Self.makeViewModel(config))
    }

    var body: some View {
        BoardView(viewModel: viewModel)
            .environment(\.projectContextMenuActions, contextMenuActions(for: viewModel))
            .environment(\.projectRevealAction, revealAction)
    }

    private static func makeViewModel(_ config: ForgeConfig) -> BoardViewModel {
        let scanner = WorkspaceScanner(config: config)
        let tagStore = FinderTagStore()
        let fetch: @Sendable () async throws -> [Project] = { try scanner.scanProjects() }
        let move: @Sendable (Project, ColumnConfig) throws -> Void = { project, column in
            if let existing = project.workflowTag {
                try tagStore.removeTag(existing, at: project.path)
            }
            try tagStore.addTag(column.tag, at: project.path)
        }
        return BoardViewModel(config: config, fetchProjects: fetch, moveProject: move)
    }

    private var revealAction: (Project) -> Void {
        { project in
            #if canImport(AppKit)
            NSWorkspace.shared.selectFile(project.path, inFileViewerRootedAtPath: "")
            #endif
        }
    }

    private func contextMenuActions(for viewModel: BoardViewModel) -> (Project) -> [ProjectContextMenuAction] {
        let config = viewModel.config
        return { project in
            [
                ProjectContextMenuAction(title: "Reveal in Finder") { p in
                    #if canImport(AppKit)
                    NSWorkspace.shared.selectFile(p.path, inFileViewerRootedAtPath: "")
                    #endif
                },
                ProjectContextMenuAction(title: "Open in Terminal") { p in
                    let launcher = TerminalLauncher(config: config)
                    launcher.run("exec /opt/homebrew/bin/zsh -i", workingDirectory: p.path)
                },
            ]
        }
    }
}

// MARK: - No config state

private struct NoConfigView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Forge config found")
                .font(.title2)
            Text("Place config.yaml at one of these locations:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("• ~/Documents/Forge/config.yaml")
                Text("• ~/Documents/Work/Projects/Forge/config.yaml")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
