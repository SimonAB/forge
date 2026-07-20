import ArgumentParser
import Foundation
import ForgeCore

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show a summary dashboard of all projects."
    )

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()

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

        let urgentCount = projects.filter { KanbanRadar.isUrgent(metaTags: $0.metaTags) }.count
        if urgentCount > 0 {
            print("\(urgentCount) urgent")
        }
        print()
    }

    private func pad(_ s: String, to width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    private func ansiColour(for finderColour: Int) -> String {
        // Catppuccin Mocha palette (truecolour), aligned with `KanbanRenderer`.
        let map: [Int: String] = [
            1: "\u{1B}[38;2;108;112;134m", // Overlay0  #6C7086
            2: "\u{1B}[38;2;166;227;161m", // Green     #A6E3A1
            3: "\u{1B}[38;2;203;166;247m", // Mauve     #CBA6F7
            4: "\u{1B}[38;2;137;180;250m", // Blue      #89B4FA
            5: "\u{1B}[38;2;249;226;175m", // Yellow    #F9E2AF
            6: "\u{1B}[38;2;250;179;135m", // Peach     #FAB387
            7: "\u{1B}[38;2;243;139;168m", // Red       #F38BA8
        ]
        return map[finderColour] ?? ""
    }
}
