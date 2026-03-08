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
    private let viewModel: BoardViewModel

    init(config: ForgeConfig) {
        let scanner = WorkspaceScanner(config: config)
        let tagStore = FinderTagStore()

        let fetchProjects: @Sendable () async throws -> [Project] = {
            try scanner.scanProjects()
        }

        let moveProject: @Sendable (Project, ColumnConfig) throws -> Void = { project, column in
            if let existing = project.workflowTag {
                try tagStore.removeTag(existing, at: project.path)
            }
            try tagStore.addTag(column.tag, at: project.path)
        }

        self.viewModel = BoardViewModel(
            config: config,
            fetchProjects: fetchProjects,
            moveProject: moveProject,
            filterMetaTags: BoardFilterPreferences.loadEnabledMetaTags()
        )
    }

    func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contextMenuActions: (Project) -> [ProjectContextMenuAction] = { [weak self] project in
            guard let self = self else { return [] }
            let config = self.viewModel.config
            return [
                ProjectContextMenuAction(title: "Reveal in Finder") { p in
                    NSWorkspace.shared.selectFile(p.path, inFileViewerRootedAtPath: "")
                },
                ProjectContextMenuAction(title: "Open in Terminal") { p in
                    let launcher = TerminalLauncher(config: config)
                    launcher.run("exec /opt/homebrew/bin/zsh -i", workingDirectory: p.path)
                },
            ]
        }

        let rootView = BoardView(viewModel: viewModel)
            .environment(\.projectContextMenuActions, contextMenuActions)
            .environment(\.projectRevealAction) { project in
                NSWorkspace.shared.selectFile(project.path, inFileViewerRootedAtPath: "")
            }

        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
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

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    }
}
