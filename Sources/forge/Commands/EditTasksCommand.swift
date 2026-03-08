import ArgumentParser
import Foundation
import ForgeCore

/// Open the task files directory (inbox, area files, someday) in the default application.
struct EditTasksCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit-tasks",
        abstract: "Open the task files directory (inbox.md, area files, someday-maybe.md) in the default application."
    )

    mutating func run() throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let paths = ForgePaths(forgeDir: forgeDir)
        let taskFilesRoot = paths.taskFilesRoot

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [taskFilesRoot]
        process.qualityOfService = .userInitiated
        try process.run()
        process.waitUntilExit()
        #else
        print("Task files root: \(taskFilesRoot)")
        print("Open this directory in your editor to edit inbox, area files, and someday list.")
        #endif
    }
}
