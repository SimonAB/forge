import ArgumentParser

@main
struct Forge: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forge",
        abstract: "Local kanban + GTD project manager with iCloud integration.",
        version: "0.4.0",
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
        ]
    )
}
