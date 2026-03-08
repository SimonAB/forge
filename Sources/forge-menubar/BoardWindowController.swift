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

        let openFileWithDefaultEditor: @Sendable (URL) -> Void = { url in
            Task { @MainActor in
                Self.openFileWithEditor(url: url, config: config)
            }
        }

        let rootView = BoardView(viewModel: viewModel)
            .environment(\.projectContextMenuActions, contextMenuActions)
            .environment(\.projectRevealAction) { project in
                NSWorkspace.shared.selectFile(project.path, inFileViewerRootedAtPath: "")
            }
            .environment(\.runForgeInTerminal, runForgeInTerminal)
            .environment(\.openFileWithDefaultEditor, openFileWithDefaultEditor)

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

    /// Opens a file with the user's default editor preference (EditorPreferences). Used for TASKS.md on cards.
    private static func openFileWithEditor(url: URL, config: ForgeConfig?) {
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
            guard let config = config else {
                NSWorkspace.shared.open(url)
                return
            }
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
}
