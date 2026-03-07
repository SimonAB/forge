import ArgumentParser
import Foundation
import ForgeCore

/// Regenerate read-only project task summaries in area files.
struct RollupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rollup",
        abstract: "Update area files with linked project task summaries."
    )

    @Flag(name: .shortAndLong, help: "Show detailed output.")
    var verbose = false

    mutating func run() throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)

        let dim = "\u{1B}[2m"
        let green = "\u{1B}[32m"
        let reset = "\u{1B}[0m"

        if config.projectAreas.isEmpty {
            print("No project_areas configured in config.yaml.")
            print("\(dim)Add a mapping to enable rollups:")
            print("  project_areas:")
            print("    research:")
            print("    - ProjectName\(reset)")
            return
        }

        let generator = RollupGenerator(config: config, forgeDir: forgeDir)
        let report = try generator.generateAll()

        if report.areasUpdated == 0 {
            print("No areas needed updating \(dim)(no mapped projects with pending tasks).\(reset)")
        } else {
            print("\(green)✓\(reset) Updated \(report.areasUpdated) area file\(report.areasUpdated == 1 ? "" : "s")")
            print("  \(report.projectsLinked) project\(report.projectsLinked == 1 ? "" : "s") linked, \(report.tasksLinked) task\(report.tasksLinked == 1 ? "" : "s") surfaced")
        }

        if verbose {
            print()
            for (area, projects) in config.projectAreas.sorted(by: { $0.key < $1.key }) {
                guard !projects.isEmpty else { continue }
                print("\(dim)\(area).md ← \(projects.count) project\(projects.count == 1 ? "" : "s")\(reset)")
            }
        }
    }
}
