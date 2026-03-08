import SwiftUI
import ForgeCore
import ForgeUI

#if canImport(AppKit)
import AppKit
#endif

@main
struct ForgeBoardApp: App {
    @State private var config: ForgeConfig?
    @State private var configLoaded = false

    init() {
        _config = State(initialValue: nil)
        _configLoaded = State(initialValue: false)
    }

    var body: some Scene {
        WindowGroup("Forge — Board") {
            Group {
                if !configLoaded {
                    LoadingConfigView()
                } else if let config = config {
                    BoardRootView(config: config)
                } else {
                    NoConfigView()
                }
            }
            .task {
                guard !configLoaded else { return }
                config = await Self.loadConfig()
                configLoaded = true
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 500)
    }

    private static func loadConfig() async -> ForgeConfig? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            (home as NSString).appendingPathComponent("Documents/Forge/config.yaml"),
            (home as NSString).appendingPathComponent("Documents/Work/Projects/Forge/config.yaml"),
        ]
        return await Task.detached(priority: .userInitiated) {
            for path in candidates {
                if FileManager.default.fileExists(atPath: path), let config = try? ForgeConfig.load(from: path) {
                    return config
                }
            }
            return nil
        }.value
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
        let config = viewModel.config
        let runForge: @Sendable (String, String?) -> Void = { command, workingDir in
            let launcher = TerminalLauncher(config: config, terminalOverride: nil, openURL: { NSWorkspace.shared.open($0) })
            launcher.run(command, workingDirectory: workingDir)
        }
        #if canImport(AppKit)
        let openWithEditor: @Sendable (URL) -> Void = { url in
            Task { @MainActor in
                Self.openFileWithEditor(url: url, config: config)
            }
        }
        #endif
        return BoardView(viewModel: viewModel)
            .environment(\.projectContextMenuActions, contextMenuActions(for: viewModel))
            .environment(\.projectRevealAction, revealAction)
            .environment(\.runForgeInTerminal, runForge)
            #if canImport(AppKit)
            .environment(\.openFileWithDefaultEditor, openWithEditor)
            #endif
    }

    #if canImport(AppKit)
    private static func openFileWithEditor(url: URL, config: ForgeConfig) {
        let path = url.path
        // Create TASKS.md from template if missing (same structure as MarkdownIO.createEmptyTasksFile).
        if url.lastPathComponent == "TASKS.md", !FileManager.default.fileExists(atPath: path) {
            try? MarkdownIO().createEmptyTasksFile(at: path)
        }
        let editor = EditorPreferences.loadPreferredEditor()
        if editor == nil || editor == "default" || editor?.isEmpty == true {
            NSWorkspace.shared.open(url)
            return
        }
        switch editor! {
        case "Vim (in default terminal)":
            let dir = (path as NSString).deletingLastPathComponent
            let launcher = TerminalLauncher(config: config, terminalOverride: nil, openURL: { NSWorkspace.shared.open($0) })
            let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
            launcher.run("zsh -i -c 'vim \"\(escaped)\"'", workingDirectory: dir)
        case "Cursor", "Visual Studio Code", "TextEdit", "Sublime Text":
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", editor!, path]
            process.qualityOfService = .userInitiated
            try? process.run()
        default:
            NSWorkspace.shared.open(url)
        }
    }
    #endif

    private static func makeViewModel(_ config: ForgeConfig) -> BoardViewModel {
        let scanner = WorkspaceScanner(config: config)
        let tagStore = FinderTagStore()
        let fetch: @Sendable () async throws -> [Project] = { try await scanner.scanProjects() }
        let move: @Sendable (Project, ColumnConfig) throws -> Void = { project, column in
            if let existing = project.workflowTag {
                try tagStore.removeTag(existing, at: project.path)
            }
            try tagStore.addTag(column.tag, at: project.path)
        }
        return BoardViewModel(
            config: config,
            fetchProjects: fetch,
            moveProject: move,
            filterMetaTags: BoardFilterPreferences.loadEnabledMetaTags()
        )
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
                    let launcher = TerminalLauncher(config: config, terminalOverride: nil, openURL: { NSWorkspace.shared.open($0) })
                    launcher.run("exec /opt/homebrew/bin/zsh -i", workingDirectory: p.path)
                },
            ]
        }
    }
}

// MARK: - No config state

private struct LoadingConfigView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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
