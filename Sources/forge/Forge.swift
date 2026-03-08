import ArgumentParser
import ForgeCore

@main
struct Forge: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forge",
        abstract: "Local kanban + GTD project manager with iCloud integration.",
        version: ForgeVersion.version,
        subcommands: [
            InitCommand.self,
            BoardCommand.self,
            ProjectsCommand.self,
            MoveCommand.self,
            StatusCommand.self,
            AddCommand.self,
            DoneCommand.self,
            DueCommand.self,
            NextCommand.self,
            InboxCommand.self,
            SyncCommand.self,
            ProcessCommand.self,
            WaitingCommand.self,
            ContextsCommand.self,
            ReviewCommand.self,
            RollupCommand.self,
            SomedayCommand.self,
            FocusCommand.self,
            EditTasksCommand.self,
        ]
    )
}
