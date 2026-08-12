import AppKit
import SwiftUI
import ForgeCore
import ForgeUI

/// Creates and owns the Kanban board window, hosting the SwiftUI BoardView with macOS-specific
/// fetch/move (WorkspaceScanner + FinderTagStore) and context menu actions (Reveal in Finder, Open in Terminal).
/// Persists window frame to UserDefaults and restores it on next open.
@MainActor
final class BoardWindowController: NSObject, NSWindowDelegate {

    private static let frameKey = "ForgeBoardWindowFrame"

    private var window: NSWindow?
    private var viewModel: BoardViewModel
    private var forgeDir: String?

    var isWindowVisible: Bool { window?.isVisible == true }

    init(config: ForgeConfig, forgeDir: String? = nil) {
        self.forgeDir = forgeDir
        self.viewModel = Self.makeViewModel(config: config, forgeDir: forgeDir)
        super.init()
    }

    /// Rebuild fetch/move/sync closures from a newly saved config without closing the window.
    func reload(config: ForgeConfig, forgeDir: String?) {
        self.forgeDir = forgeDir
        self.viewModel = Self.makeViewModel(config: config, forgeDir: forgeDir)
        if let window {
            installRootView(in: window)
        }
        viewModel.refresh()
    }

    func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: NSViewController())
        window.title = "Forge — Board"
        window.minSize = NSSize(width: 600, height: 300)
        window.delegate = self
        if let saved = UserDefaults.standard.string(forKey: Self.frameKey) {
            let rect = NSRectFromString(saved)
            if rect.width >= 600, rect.height >= 300 {
                window.setFrame(rect, display: false)
            } else {
                window.setContentSize(NSSize(width: 900, height: 500))
                window.center()
            }
        } else {
            window.setContentSize(NSSize(width: 900, height: 500))
            window.center()
        }

        installRootView(in: window)
        self.window = window
        window.makeKeyAndOrderFront(nil as Any?)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Refreshes the board's project list (e.g. after a sync so new tags/columns appear).
    func refreshBoardIfNeeded() {
        viewModel.refresh()
    }

    /// Close the board window (user dismisses it, or config becomes unavailable).
    func closeWindow() {
        saveWindowFrame()
        window?.close()
        window = nil
    }

    private func installRootView(in window: NSWindow) {
        let contextMenuActions: (Project) -> [ProjectContextMenuAction] = { [weak self] project in
            guard let self = self else { return [] }
            let config = self.viewModel.config
            return [
                ProjectContextMenuAction(title: "Reveal in Finder") { p in
                    NSWorkspace.shared.selectFile(p.path, inFileViewerRootedAtPath: "")
                },
                ProjectContextMenuAction(title: "Open in Terminal") { p in
                    let launcher = TerminalLauncher(config: config, terminalOverride: nil, openURL: { NSWorkspace.shared.open($0) })
                    launcher.run("exec /opt/homebrew/bin/zsh -i", workingDirectory: p.path)
                },
            ]
        }

        let config = viewModel.config
        let runForgeInTerminal: @Sendable (String, String?) -> Void = { command, workingDir in
            let launcher = TerminalLauncher(config: config, terminalOverride: nil, openURL: { NSWorkspace.shared.open($0) })
            launcher.run(command, workingDirectory: workingDir)
        }

        let rootView = BoardView(viewModel: viewModel)
            .environment(\.projectContextMenuActions, contextMenuActions)
            .environment(\.projectRevealAction) { project in
                NSWorkspace.shared.selectFile(project.path, inFileViewerRootedAtPath: "")
            }
            .environment(\.runForgeInTerminal, runForgeInTerminal)

        window.contentViewController = NSHostingController(rootView: rootView)
        window.delegate = self
    }

    private static func makeViewModel(config: ForgeConfig, forgeDir: String?) -> BoardViewModel {
        let scanner = WorkspaceScanner(config: config)
        let tagStore = FinderTagStore()

        let fetchProjects: @Sendable () async throws -> [Project] = {
            try await scanner.scanProjects()
        }

        let moveProject: @Sendable (Project, ColumnConfig) async throws -> Void = { project, column in
            try OmniFocusMoveSync.setFinderWorkflowColumn(
                path: project.path,
                column: column.name,
                config: config,
                tagStore: tagStore,
                forgeDir: forgeDir,
                folderName: project.name,
                previousColumn: project.column
            )

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
                    "Forge directory unknown; cannot sync. Open Preferences and select config.yaml."
                )
            }
            let configPath = (resolvedForgeDir as NSString).appendingPathComponent("config.yaml")
            let activeConfig = (try? ForgeConfig.load(from: configPath)) ?? config
            let ofRefresh = activeConfig.omnifocus.enabled && (
                activeConfig.omnifocus.syncOnMove
                    || activeConfig.omnifocus.syncFromOmnifocus
                    || activeConfig.omnifocus.syncCompletedProjectToShipped
            )
            let archiveEnabled = KanbanArchivePolicy.isEnabled(config: activeConfig)
            guard ofRefresh || activeConfig.reminders.enabled || archiveEnabled else { return }

            let freshScanner = WorkspaceScanner(config: activeConfig)
            var projects = try await freshScanner.scanProjects()
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
                if !outcome.pulledFolders.isEmpty {
                    projects = try await freshScanner.scanProjects()
                }
            }

            if activeConfig.reminders.enabled {
                let remOut = try await RemindersMoveSync.refreshAndPull(
                    config: activeConfig,
                    forgeDir: resolvedForgeDir,
                    projects: projects,
                    skipFolderNames: skipFolders,
                    writerName: "forge-menubar",
                    setColumn: { project, column in
                        try OmniFocusMoveSync.setFinderWorkflowColumn(
                            path: project.path,
                            column: column,
                            config: activeConfig,
                            tagStore: FinderTagStore(),
                            forgeDir: resolvedForgeDir,
                            folderName: project.name,
                            previousColumn: project.column
                        )
                    }
                )
                errors.append(contentsOf: remOut.errors)
                if !remOut.updatedFolders.isEmpty {
                    projects = try await freshScanner.scanProjects()
                }
            }

            if archiveEnabled {
                let sweep = try KanbanArchivePolicy.applyDueArchives(
                    projects: projects,
                    config: activeConfig,
                    forgeDir: resolvedForgeDir
                )
                errors.append(contentsOf: sweep.errors)
            }

            if !errors.isEmpty {
                throw OmniJSBridgeError.evaluationFailed(
                    "Refresh: \(errors.joined(separator: "; "))"
                )
            }
        }

        return BoardViewModel(
            config: config,
            fetchProjects: fetchProjects,
            moveProject: moveProject,
            forgeDir: forgeDir,
            filterMetaTags: BoardFilterPreferences.loadEnabledMetaTags(),
            performSync: performSync
        )
    }

    private func saveWindowFrame() {
        guard let window = window, window.isVisible else { return }
        let rect = window.frame
        UserDefaults.standard.set(NSStringFromRect(rect), forKey: Self.frameKey)
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowFrame()
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
        window = nil
    }

    /// Opens a file with the user's default editor preference (EditorPreferences). Used for project files on cards.
    private static func openFileWithEditor(url: URL, config: ForgeConfig?) {
        let editor = EditorPreferences.loadPreferredEditor()
        EditorLauncher.openFile(
            fileURL: url,
            preferredEditor: editor,
            config: config,
            openURL: { NSWorkspace.shared.open($0) }
        )
    }
}
