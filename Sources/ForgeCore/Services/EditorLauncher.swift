import Foundation

#if canImport(AppKit)
import AppKit

/// Opens files and folders using the configured Forge editor preference.
public enum EditorLauncher {

    /// Open a single file according to the preferred editor.
    ///
    /// - Parameters:
    ///   - fileURL: The file URL to open.
    ///   - preferredEditor: The stored editor preference value.
    ///   - config: The Forge configuration used for terminal-based editors.
    ///   - openURL: A callback used to open URLs with the system.
    public static func openFile(
        fileURL: URL,
        preferredEditor: String?,
        config: ForgeConfig?,
        openURL: @escaping @Sendable (URL) -> Void
    ) {
        let filePath = fileURL.path
        if preferredEditor == nil || preferredEditor == "default" || preferredEditor?.isEmpty == true {
            openURL(fileURL)
            return
        }

        guard let editorIdentifier = preferredEditor else {
            openURL(fileURL)
            return
        }

        if EditorPreferences.isVimInTerminal(editorIdentifier) {
            guard let config else {
                openURL(fileURL)
                return
            }
            let directory = (filePath as NSString).deletingLastPathComponent
            runVimInTerminal(targetPath: filePath, workingDirectory: directory, config: config, openURL: openURL)
            return
        }

        switch editorIdentifier {
        case "Cursor", "Visual Studio Code", "TextEdit", "Sublime Text":
            launchNamedApp(appName: editorIdentifier, path: filePath)
        default:
            openURL(fileURL)
        }
    }

    /// Open a folder according to the preferred editor.
    ///
    /// - Parameters:
    ///   - folderURL: The folder URL to open.
    ///   - preferredEditor: The stored editor preference value.
    ///   - config: The Forge configuration used for terminal-based editors.
    ///   - openURL: A callback used to open URLs with the system.
    public static func openFolder(
        folderURL: URL,
        preferredEditor: String?,
        config: ForgeConfig?,
        openURL: @escaping @Sendable (URL) -> Void
    ) {
        let folderPath = folderURL.path
        if preferredEditor == nil || preferredEditor == "default" || preferredEditor?.isEmpty == true {
            openURL(folderURL)
            return
        }

        guard let editorIdentifier = preferredEditor else {
            openURL(folderURL)
            return
        }

        if EditorPreferences.isVimInTerminal(editorIdentifier) {
            guard let config else {
                openURL(folderURL)
                return
            }
            runVimInTerminal(targetPath: folderPath, workingDirectory: folderPath, config: config, openURL: openURL)
            return
        }

        switch editorIdentifier {
        case "Cursor", "Visual Studio Code", "TextEdit", "Sublime Text":
            launchNamedApp(appName: editorIdentifier, path: folderPath)
        default:
            openURL(folderURL)
        }
    }

    /// Run the terminal editor (`vim` on `PATH`, per `TerminalLauncher`) for a file or folder.
    ///
    /// - Parameters:
    ///   - targetPath: The file or folder path opened in the editor.
    ///   - workingDirectory: The directory to set before launch.
    ///   - config: The Forge configuration containing terminal preference.
    ///   - openURL: A callback used by terminal launchers for URL-based terminals.
    private static func runVimInTerminal(
        targetPath: String,
        workingDirectory: String,
        config: ForgeConfig,
        openURL: @escaping @Sendable (URL) -> Void
    ) {
        let launcher = TerminalLauncher(config: config, terminalOverride: nil, openURL: openURL)
        launcher.openNeovim(filePath: targetPath, workingDirectory: workingDirectory)
    }

    /// Launch a GUI editor app with `open -a`.
    ///
    /// - Parameters:
    ///   - appName: The macOS application name.
    ///   - path: The target file or folder path.
    private static func launchNamedApp(appName: String, path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName, path]
        process.qualityOfService = .userInitiated
        try? process.run()
    }
}
#endif
