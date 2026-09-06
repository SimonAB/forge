import Foundation

#if canImport(AppKit)
import AppKit

/// Opens project folders and the configured task manager for **Open TASKS**.
public enum ProjectOpenActions {

    /// Reveal a project folder in Finder (selects the folder in its parent).
    public static func revealInFinder(projectDirectory: String) {
        NSWorkspace.shared.selectFile(projectDirectory, inFileViewerRootedAtPath: "")
    }

    /// Open tasks for a project in the preferred task manager (or `TASKS.toml`).
    ///
    /// - Parameters:
    ///   - projectDirectory: Absolute path to the project folder.
    ///   - config: Forge config (backends + SP project ids).
    ///   - forgeDir: Forge home (directory containing ``scripts/``); needed for SP focus.
    ///   - preferredEditor: Stored editor preference for the toml backend.
    ///   - preferredTaskManager: Stored task-manager preference.
    public static func openTasksOrRevealFolder(
        projectDirectory: String,
        config: ForgeConfig?,
        forgeDir: String? = nil,
        preferredEditor: String? = EditorPreferences.loadPreferredEditor(),
        preferredTaskManager: TaskManagerPreferences.Kind? = TaskManagerPreferences.loadPreferredTaskManager()
    ) {
        guard let config else {
            // No config: fall back to toml / Finder.
            switch ProjectOpenResolver.primaryOpenTarget(projectDirectory: projectDirectory) {
            case .tasksFile(let url):
                EditorLauncher.openFile(
                    fileURL: url,
                    preferredEditor: preferredEditor,
                    config: nil,
                    openURL: { NSWorkspace.shared.open($0) }
                )
            case .projectFolder(let url):
                revealInFinder(projectDirectory: url.path)
            default:
                revealInFinder(projectDirectory: projectDirectory)
            }
            return
        }

        let target = ProjectOpenResolver.tasksOpenTarget(
            projectDirectory: projectDirectory,
            config: config,
            preferredTaskManager: preferredTaskManager
        )
        open(target: target, config: config, forgeDir: forgeDir, preferredEditor: preferredEditor)
    }

    /// Resolve a project by name and open tasks in the preferred task manager.
    ///
    /// - Returns: `true` when a project directory was found and an open was attempted.
    @discardableResult
    public static func openTasksOrRevealFolder(
        projectName: String,
        config: ForgeConfig,
        forgeDir: String? = nil,
        preferredEditor: String? = EditorPreferences.loadPreferredEditor(),
        preferredTaskManager: TaskManagerPreferences.Kind? = TaskManagerPreferences.loadPreferredTaskManager()
    ) -> Bool {
        guard let directory = ProjectOpenResolver.resolveProjectDirectory(
            named: projectName,
            projectRoots: config.resolvedProjectRoots
        ) else {
            return false
        }
        let target = ProjectOpenResolver.tasksOpenTarget(
            projectDirectory: directory,
            projectName: projectName,
            config: config,
            preferredTaskManager: preferredTaskManager
        )
        open(target: target, config: config, forgeDir: forgeDir, preferredEditor: preferredEditor)
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

    // MARK: - Private

    private static func open(
        target: ProjectTasksOpenTarget,
        config: ForgeConfig,
        forgeDir: String?,
        preferredEditor: String?
    ) {
        switch target {
        case .superProductivity(let projectId):
            openSuperProductivity(projectId: projectId, forgeDir: forgeDir)
        case .omnifocus(let projectName):
            openOmniFocus(projectName: projectName)
        case .reminders(let listTitle):
            openReminders(listTitle: listTitle)
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

    private static func openSuperProductivity(projectId: String?, forgeDir: String?) {
        let spBundleIds = ["com.super-productivity.app"]
        guard let projectId, !projectId.isEmpty else {
            // No project_ids map for this folder — open SP without a project focus.
            launchApplication(named: "Super Productivity", bundleIdentifiers: spBundleIds)
            return
        }
        // Focus the project view via CDP (may briefly relaunch SP with debugging),
        // then bring SP to the front. Do not re-activate Forge afterward.
        DispatchQueue.global(qos: .userInitiated).async {
            let failure = SuperProductivityFocus.focusProject(projectId: projectId, forgeDir: forgeDir)
            DispatchQueue.main.async {
                launchApplication(named: "Super Productivity", bundleIdentifiers: spBundleIds)
                if failure != nil {
                    NSSound.beep()
                }
            }
        }
    }

    private static func openOmniFocus(projectName: String) {
        _ = projectName
        if let url = URL(string: "omnifocus://"), NSWorkspace.shared.open(url) {
            return
        }
        launchApplication(named: "OmniFocus", bundleIdentifiers: [
            "com.omnigroup.OmniFocus4",
            "com.omnigroup.OmniFocus3",
            "com.omnigroup.OmniFocus2",
        ])
    }

    private static func openReminders(listTitle: String) {
        // Reminders has no stable public deep link for list titles; open the app.
        _ = listTitle
        if let url = URL(string: "x-apple-reminderkit://"), NSWorkspace.shared.open(url) {
            return
        }
        launchApplication(named: "Reminders", bundleIdentifiers: [
            "com.apple.reminders",
        ])
    }

    private static func launchApplication(named name: String, bundleIdentifiers: [String]) {
        for bundleId in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config)
                return
            }
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return
        }
        // Last resort: ask Launch Services by display name via `open`.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", name]
        try? process.run()
    }
}
#endif
