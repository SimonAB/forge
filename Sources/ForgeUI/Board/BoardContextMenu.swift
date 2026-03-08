import SwiftUI
import ForgeCore

/// A single action shown in the project card context menu (e.g. "Reveal in Finder", "Open in Terminal").
/// Supplied by the host app so ForgeUI stays free of AppKit/UIKit.
public struct ProjectContextMenuAction: Sendable {
    public let title: String
    public let action: @Sendable (Project) -> Void

    public init(title: String, action: @escaping @Sendable (Project) -> Void) {
        self.title = title
        self.action = action
    }
}

// MARK: - Environment

private enum ProjectContextMenuActionsKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ((Project) -> [ProjectContextMenuAction])? = nil
}

public extension EnvironmentValues {
    /// Optional list of context menu actions for project cards (e.g. "Reveal in Finder", "Open in Terminal").
    /// The host app supplies these so ForgeUI does not depend on AppKit/UIKit.
    var projectContextMenuActions: ((Project) -> [ProjectContextMenuAction])? {
        get { self[ProjectContextMenuActionsKey.self] }
        set { self[ProjectContextMenuActionsKey.self] = newValue }
    }
}

// MARK: - Reveal action (clickable folder icon)

private enum ProjectRevealActionKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ((Project) -> Void)? = nil
}

public extension EnvironmentValues {
    /// Optional action invoked when the user taps the folder icon on a project card (e.g. Reveal in Finder).
    /// When set, a small folder icon is shown on each card.
    var projectRevealAction: ((Project) -> Void)? {
        get { self[ProjectRevealActionKey.self] }
        set { self[ProjectRevealActionKey.self] = newValue }
    }
}

// MARK: - Run forge command in terminal (GTD toolbar)

private enum RunForgeInTerminalKey: EnvironmentKey {
    static let defaultValue: (@Sendable (String, String?) -> Void)? = nil
}

public extension EnvironmentValues {
    /// When set, board toolbar GTD buttons (Inbox, Review, etc.) run the given forge command in the user's terminal.
    /// Closure receives (command, workingDirectory). Working directory is typically the forge workspace path.
    var runForgeInTerminal: (@Sendable (String, String?) -> Void)? {
        get { self[RunForgeInTerminalKey.self] }
        set { self[RunForgeInTerminalKey.self] = newValue }
    }
}

// MARK: - Open file with default editor (e.g. TASKS.md on card)

private enum OpenFileWithDefaultEditorKey: EnvironmentKey {
    static let defaultValue: (@Sendable (URL) -> Void)? = nil
}

public extension EnvironmentValues {
    /// When set (e.g. on macOS), project cards show a button to open TASKS.md with the user's default editor.
    var openFileWithDefaultEditor: (@Sendable (URL) -> Void)? {
        get { self[OpenFileWithDefaultEditorKey.self] }
        set { self[OpenFileWithDefaultEditorKey.self] = newValue }
    }
}
