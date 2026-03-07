import ArgumentParser
import Foundation
import ForgeCore

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show a summary dashboard of all projects."
    )

    mutating func run() throws {
        let config = try ConfigLoader.load()
        let scanner = WorkspaceScanner(config: config)
        let projects = try scanner.scanProjects()

        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let reset = "\u{1B}[0m"

        print("\n\(bold)Forge Status\(reset)")
        print(String(repeating: "─", count: 40))

        for col in config.board.columns {
            let count = projects.filter { $0.column == col.name }.count
            let bar = String(repeating: "█", count: count)
            let colour = ansiColour(for: col.colour)
            print("\(colour)\(pad(col.name, to: 10)) \(bar) \(count)\(reset)")
        }

        let untagged = projects.filter { $0.column == nil }
        if !untagged.isEmpty {
            print("\(dim)\(pad("Untagged", to: 10)) \(String(repeating: "░", count: untagged.count)) \(untagged.count)\(reset)")
        }

        print(String(repeating: "─", count: 40))

        let activeCount = projects.filter { p in
            let col = p.column
            return col != nil && col != "Shipped" && col != "Paused"
        }.count

        print("\(bold)\(projects.count)\(reset) projects total, \(bold)\(activeCount)\(reset) active")

        let mineCount = projects.filter { $0.metaTags.contains("Mine ⚒️") }.count
        if mineCount > 0 {
            print("\(mineCount) led by you (Mine ⚒️)")
        }
        print()
    }

    private func pad(_ s: String, to width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    private func ansiColour(for finderColour: Int) -> String {
        let map: [Int: String] = [
            1: "\u{1B}[90m", 2: "\u{1B}[32m", 3: "\u{1B}[35m",
            4: "\u{1B}[34m", 5: "\u{1B}[33m", 6: "\u{1B}[38;5;208m",
            7: "\u{1B}[31m",
        ]
        return map[finderColour] ?? ""
    }
}
