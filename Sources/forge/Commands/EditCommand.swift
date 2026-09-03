import ArgumentParser
import Foundation
import ForgeCore

/// Open files or directories in the terminal editor (Neovim via `vim` on PATH).
///
/// Honours `config.yaml` `terminal:` (Auto prefers Herdr, then tmux, then a GUI terminal).
struct EditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Open files or directories in the terminal editor (vim/Neovim).",
        discussion: """
        Uses the same launch path as Forge board “open in Vim”: when terminal is Auto \
        (or Herdr/tmux), prefers a live Herdr or tmux session, otherwise Ghostty / kitty / \
        iTerm / Warp / Terminal. Intended for Finder “Open With” via NeoVim launcher.app.
        """
    )

    @Argument(help: "Files or directories to open. Defaults to the home directory when omitted.")
    var paths: [String] = []

    @Option(name: .long, help: "Override terminal preference (auto, herdr, tmux, Ghostty, …).")
    var terminal: String?

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let targets: [EditorOpenTarget]
        do {
            targets = try EditorOpenResolver.resolveTargets(paths: paths)
        } catch let error as EditorOpenError {
            throw ValidationError(error.description)
        }
        let launcher = TerminalLauncher(
            config: config,
            terminalOverride: terminal,
            openURL: Self.openURLWithSystemOpen
        )
        for target in targets {
            launcher.openNeovim(filePath: target.filePath, workingDirectory: target.workingDirectory)
        }
    }

    /// Open a URL via `/usr/bin/open` (Warp launch configurations, etc.).
    private static func openURLWithSystemOpen(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        process.qualityOfService = .userInitiated
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Warp fallback inside TerminalLauncher handles failure.
        }
    }
}
