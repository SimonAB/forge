import ArgumentParser
import ForgeCore

@main
struct Forge: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forge",
        abstract: "Local kanban project manager driven by Finder tags.",
        version: ForgeVersion.version,
        subcommands: [
            InitCommand.self,
            BoardCommand.self,
            MoveCommand.self,
            ProjectTagCommand.self,
            ArchiveCommand.self,
            StatusCommand.self,
            CalendarCommand.self,
            CaptureCommand.self,
            TasksCommand.self,
            DashboardCommand.self,
            EditCommand.self,
            OmniFocusCommand.self,
            RemindersCommand.self,
        ]
    )
}
