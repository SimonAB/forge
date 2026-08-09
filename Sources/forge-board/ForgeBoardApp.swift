import SwiftUI
import Foundation
import ForgeCore
import ForgeUI

#if canImport(AppKit)
import AppKit
#endif

@main
struct ForgeBoardApp: App {
    @State private var config: ForgeConfig?
    @State private var forgeDir: String?
    @State private var configLoaded = false

    init() {
        _config = State(initialValue: nil)
        _forgeDir = State(initialValue: nil)
        _configLoaded = State(initialValue: false)
    }

    var body: some Scene {
        WindowGroup("Forge — Board") {
            Group {
                if !configLoaded {
                    LoadingConfigView()
                } else if let config = config {
                    BoardRootView(config: config, forgeDir: forgeDir)
                } else {
                    NoConfigView()
                }
            }
            .task {
                guard !configLoaded else { return }
                let loaded = await Self.loadConfig()
                config = loaded?.config
                forgeDir = loaded?.forgeDir
                configLoaded = true
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 500)
        #if canImport(AppKit)
        .commands {
            CommandGroup(after: .windowArrangement) {
                EmptyView()
            }

            // Cmd+F is also used by macOS for system "Find…". We replace the `.textEditing`
            // command group so our Cmd+F handler runs and focuses the board search field.
            CommandGroup(replacing: .textEditing) {
                Button("Find") {
                    NotificationCenter.default.post(name: .forgeBoardFocusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        #endif
    }

    private static func loadConfig() async -> (config: ForgeConfig, forgeDir: String)? {
        return await Task.detached(priority: .userInitiated) {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let candidates = ForgePaths.configCandidatePaths(home: home)
            for path in candidates {
                if FileManager.default.fileExists(atPath: path), let config = try? ForgeConfig.load(from: path) {
                    let forgeDir = (path as NSString).deletingLastPathComponent
                    return (config, forgeDir)
                }
            }
            return nil
        }.value
    }
}

// MARK: - Board root (view model + environment)

private struct BoardRootView: View {
    let config: ForgeConfig
    var forgeDir: String?
    @State private var viewModel: BoardViewModel

    init(config: ForgeConfig, forgeDir: String? = nil) {
        self.config = config
        self.forgeDir = forgeDir
        _viewModel = State(initialValue: Self.makeViewModel(config, forgeDir: forgeDir))
    }

    var body: some View {
        let config = viewModel.config
        let runForge: @Sendable (String, String?) -> Void = { command, workingDir in
            let launcher = TerminalLauncher(config: config, terminalOverride: nil, openURL: { NSWorkspace.shared.open($0) })
            launcher.run(command, workingDirectory: workingDir)
        }
        #if canImport(AppKit)
        // No editor/task-file integration in the kanban-only build.
        #endif
        return BoardView(viewModel: viewModel)
            .environment(\.projectContextMenuActions, contextMenuActions(for: viewModel))
            .environment(\.projectRevealAction, revealAction)
            .environment(\.runForgeInTerminal, runForge)
    }

    private static func makeViewModel(_ config: ForgeConfig, forgeDir: String?) -> BoardViewModel {
        let scanner = WorkspaceScanner(config: config)
        let tagStore = FinderTagStore()
        let fetch: @Sendable () async throws -> [Project] = { try await scanner.scanProjects() }
        let move: @Sendable (Project, ColumnConfig) async throws -> Void = { project, column in
            if let existing = project.workflowTag {
                try tagStore.removeTag(existing, at: project.path)
            }
            try tagStore.addTag(column.tag, at: project.path)

            guard let resolvedForgeDir = forgeDir else { return }

            if config.omnifocus.enabled, config.omnifocus.syncOnMove {
                let projects = try await scanner.scanProjects()
                let outcome = OmniFocusMoveSync.mirrorFinderColumn(
                    config: config,
                    forgeDir: resolvedForgeDir,
                    projects: projects,
                    project: project,
                    column: column.name
                )
                if case .skipped(let reason) = outcome, reason.contains("ambiguous") {
                    throw OmniJSBridgeError.evaluationFailed("OmniFocus sync skipped: \(reason)")
                }
            }

            if config.reminders.enabled {
                guard let inv = try RemindersService(config: config).loadEligibleSnapshot(forgeDir: resolvedForgeDir) else {
                    return
                }
                _ = await RemindersMoveSync.afterFinderColumnChange(
                    config: config,
                    project: project,
                    column: column.name,
                    inventory: inv,
                    writer: RemindersWriter()
                )
            }
        }
        let performSync: (@Sendable () async throws -> Void)? = {
            guard let resolvedForgeDir = forgeDir else {
                throw OmniJSBridgeError.evaluationFailed(
                    "Forge directory unknown; cannot sync."
                )
            }
            let configPath = (resolvedForgeDir as NSString).appendingPathComponent("config.yaml")
            let activeConfig = (try? ForgeConfig.load(from: configPath)) ?? config
            let ofRefresh = activeConfig.omnifocus.enabled && (
                activeConfig.omnifocus.syncOnMove
                    || activeConfig.omnifocus.syncFromOmnifocus
                    || activeConfig.omnifocus.syncCompletedProjectToShipped
            )
            guard ofRefresh || activeConfig.reminders.enabled else { return }

            let freshScanner = WorkspaceScanner(config: activeConfig)
            let projects = try await freshScanner.scanProjects()
            var skipFolders: Set<String> = []
            var errors: [String] = []

            if ofRefresh {
                let outcome = try OmniFocusMoveSync.syncBidirectionalOnRefresh(
                    config: activeConfig,
                    forgeDir: resolvedForgeDir,
                    projects: projects
                )
                skipFolders = Set(outcome.pulledFolders)
                errors.append(contentsOf: outcome.errors)
            }

            if activeConfig.reminders.enabled {
                let remOut = try await RemindersMoveSync.refreshAndPull(
                    config: activeConfig,
                    forgeDir: resolvedForgeDir,
                    projects: projects,
                    skipFolderNames: skipFolders,
                    writerName: "forge-board",
                    setColumn: { project, column in
                        try OmniFocusMoveSync.setFinderWorkflowColumn(
                            path: project.path,
                            column: column,
                            config: activeConfig,
                            tagStore: FinderTagStore()
                        )
                    }
                )
                errors.append(contentsOf: remOut.errors)
            }

            if !errors.isEmpty {
                throw OmniJSBridgeError.evaluationFailed(
                    "Refresh: \(errors.joined(separator: "; "))"
                )
            }
        }
        return BoardViewModel(
            config: config,
            fetchProjects: fetch,
            moveProject: move,
            filterMetaTags: BoardFilterPreferences.loadEnabledMetaTags(),
            performSync: performSync
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
                Text("• ~/Documents/Software/Forge/config.yaml")
                Text("• ~/Documents/Forge/config.yaml")
                Text("• ~/Documents/Work/Projects/Forge/config.yaml")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
