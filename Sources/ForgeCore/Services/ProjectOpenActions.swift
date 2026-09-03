import Foundation

#if canImport(AppKit)
import AppKit

/// Opens project folders and `TASKS.toml` using Finder / the preferred editor.
public enum ProjectOpenActions {

    /// Reveal a project folder in Finder (selects the folder in its parent).
    public static func revealInFinder(projectDirectory: String) {
        NSWorkspace.shared.selectFile(projectDirectory, inFileViewerRootedAtPath: "")
    }

    /// Open `TASKS.toml` in the preferred editor, or reveal the folder when the file is missing.
    ///
    /// - Parameters:
    ///   - projectDirectory: Absolute path to the project folder.
    ///   - config: Forge config (needed for Vim-in-terminal).
    ///   - preferredEditor: Stored editor preference; defaults to `EditorPreferences`.
    public static func openTasksOrRevealFolder(
        projectDirectory: String,
        config: ForgeConfig?,
        preferredEditor: String? = EditorPreferences.loadPreferredEditor()
    ) {
        switch ProjectOpenResolver.primaryOpenTarget(projectDirectory: projectDirectory) {
        case .tasksFile(let url):
            EditorLauncher.openFile(
                fileURL: url,
                preferredEditor: preferredEditor,
                config: config,
                openURL: { NSWorkspace.shared.open($0) }
            )
        case .projectFolder(let url):
            revealInFinder(projectDirectory: url.path)
        }
    }

    /// Resolve a project by name and open `TASKS.toml` (or reveal the folder if missing).
    ///
    /// - Returns: `true` when a project directory was found and an open was attempted.
    @discardableResult
    public static func openTasksOrRevealFolder(
        projectName: String,
        config: ForgeConfig,
        preferredEditor: String? = EditorPreferences.loadPreferredEditor()
    ) -> Bool {
        guard let directory = ProjectOpenResolver.resolveProjectDirectory(
            named: projectName,
            projectRoots: config.resolvedProjectRoots
        ) else {
            return false
        }
        openTasksOrRevealFolder(
            projectDirectory: directory,
            config: config,
            preferredEditor: preferredEditor
        )
        return true
    }

    /// Resolve a project by name and reveal it in Finder.
    ///
    /// - Returns: `true` when a project directory was found.
    @discardableResult
    public static func revealInFinder(projectName: String, config: ForgeConfig) -> Bool {
        guard let directory = ProjectOpenResolver.resolveProjectDirectory(
            named: projectName,
            projectRoots: config.resolvedProjectRoots
        ) else {
            return false
        }
        revealInFinder(projectDirectory: directory)
        return true
    }
}
#endif
