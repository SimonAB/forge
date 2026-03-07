import Foundation

/// Renders a kanban board to the terminal using ANSI escape codes.
public struct KanbanRenderer: Sendable {

    /// ANSI colour codes for kanban column headers/cells (index = config column colour).
    /// 1=Grey, 2=Green, 3=Purple, 4=Blue, 5=Yellow, 6=Orange, 7=Red
    private static let finderColourToANSI: [Int: String] = [
        1: "\u{1B}[90m",   // Grey  (Paused)
        2: "\u{1B}[32m",   // Green
        3: "\u{1B}[35m",   // Purple
        4: "\u{1B}[34m",   // Blue
        5: "\u{1B}[33m",   // Yellow
        6: "\u{1B}[38;5;208m", // Orange (256-colour)
        7: "\u{1B}[31m",   // Red
    ]

    private static let reset = "\u{1B}[0m"
    private static let bold = "\u{1B}[1m"
    private static let dim = "\u{1B}[2m"

    public init() {}

    /// Render the full kanban board to stdout.
    public func render(projects: [Project], config: ForgeConfig) {
        let grouped = groupByColumn(projects: projects, config: config)
        let columnWidth = terminalColumnWidth(columnCount: grouped.count)

        printHeader(grouped: grouped, columnWidth: columnWidth, config: config)
        printSeparator(columnCount: grouped.count, columnWidth: columnWidth)
        printRows(grouped: grouped, columnWidth: columnWidth, config: config)
        printSummary(projects: projects, grouped: grouped)
    }

    /// Render a compact single-column list view (for narrow terminals).
    public func renderList(projects: [Project], config: ForgeConfig) {
        let grouped = groupByColumn(projects: projects, config: config)

        for (column, columnProjects) in grouped {
            let colour = ansiColour(for: column, config: config)
            print("\(Self.bold)\(colour)\(column.name) (\(columnProjects.count))\(Self.reset)")

            if columnProjects.isEmpty {
                print("  \(Self.dim)(empty)\(Self.reset)")
            } else {
                for project in columnProjects {
                    let meta = project.metaTags.isEmpty ? "" : " \(Self.dim)\(project.metaTags.joined(separator: " "))\(Self.reset)"
                    print("  • \(project.name)\(meta)")
                }
            }
            print()
        }
    }

    // MARK: - Private Helpers

    private struct ColumnGroup {
        let column: ColumnConfig
        let projects: [Project]
    }

    private func groupByColumn(
        projects: [Project], config: ForgeConfig
    ) -> [(column: ColumnConfig, projects: [Project])] {
        var result: [(column: ColumnConfig, projects: [Project])] = []

        for col in config.board.columns {
            let matching = projects.filter { $0.column == col.name }
            result.append((column: col, projects: matching))
        }

        let untagged = projects.filter { $0.column == nil }
        if !untagged.isEmpty {
            let untaggedCol = ColumnConfig(name: "Untagged", tag: "", colour: 0)
            result.append((column: untaggedCol, projects: untagged))
        }

        return result
    }

    private func terminalColumnWidth(columnCount: Int) -> Int {
        let termWidth = terminalWidth()
        let separators = columnCount + 1
        let available = termWidth - separators
        return max(12, available / max(1, columnCount))
    }

    private func terminalWidth() -> Int {
        var size = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }
        return 120
    }

    private func ansiColour(for column: ColumnConfig, config: ForgeConfig) -> String {
        Self.finderColourToANSI[column.colour] ?? ""
    }

    private func printHeader(
        grouped: [(column: ColumnConfig, projects: [Project])],
        columnWidth: Int,
        config: ForgeConfig
    ) {
        print()
        var header = ""
        for (column, projects) in grouped {
            let colour = ansiColour(for: column, config: config)
            let label = "\(column.name) (\(projects.count))"
            let padded = pad(label, to: columnWidth)
            header += "│\(Self.bold)\(colour)\(padded)\(Self.reset)"
        }
        header += "│"
        print(header)
    }

    private func printSeparator(columnCount: Int, columnWidth: Int) {
        var sep = ""
        for _ in 0..<columnCount {
            sep += "├" + String(repeating: "─", count: columnWidth)
        }
        sep += "┤"
        print(sep)
    }

    private func printRows(
        grouped: [(column: ColumnConfig, projects: [Project])],
        columnWidth: Int,
        config: ForgeConfig
    ) {
        let maxRows = grouped.map(\.projects.count).max() ?? 0

        for row in 0..<maxRows {
            var line = ""
            for (column, projects) in grouped {
                let colour = ansiColour(for: column, config: config)
                if row < projects.count {
                    let project = projects[row]
                    let meta = project.metaTags.isEmpty ? "" : " ⚒"
                    let label = truncate(project.name + meta, to: columnWidth - 2)
                    let padded = pad(" \(label)", to: columnWidth)
                    line += "│\(colour)\(padded)\(Self.reset)"
                } else {
                    line += "│" + String(repeating: " ", count: columnWidth)
                }
            }
            line += "│"
            print(line)
        }
    }

    private func printSummary(
        projects: [Project],
        grouped: [(column: ColumnConfig, projects: [Project])]
    ) {
        print()
        let active = projects.filter { col in
            col.column != nil && col.column != "Shipped" && col.column != "Paused"
        }.count
        print("\(Self.dim)\(projects.count) projects total, \(active) active\(Self.reset)")
        print()
    }

    private func pad(_ string: String, to width: Int) -> String {
        let visibleLength = string.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression
        ).count
        if visibleLength >= width {
            return string
        }
        return string + String(repeating: " ", count: width - visibleLength)
    }

    private func truncate(_ string: String, to maxLength: Int) -> String {
        guard string.count > maxLength, maxLength > 1 else { return string }
        return String(string.prefix(maxLength - 1)) + "…"
    }
}
