import Foundation

/// Thin SP column mirror: apply the same kanban tag strings as Finder onto mapped SP projects.
public enum SuperProductivityColumnMirror {
    /// Best-effort mirror; returns a user-facing note, or nil when disabled / no-op.
    public static func mirrorColumn(
        projectName: String,
        column: ColumnConfig,
        config: ForgeConfig,
        forgeDir: String
    ) -> String? {
        guard config.nexus.spColumnMirror else { return nil }
        let script = (forgeDir as NSString).appendingPathComponent("scripts/forge-superproductivity.py")
        guard FileManager.default.fileExists(atPath: script) else {
            return "SP column mirror skipped: forge-superproductivity.py not found."
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", script,
            "--forge-home", forgeDir,
            "mirror-column", projectName, column.name,
            "--tag", column.tag,
        ] + config.board.columns.flatMap { ["--kanban-tag", $0.tag] }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 0 {
                return text.isEmpty ? "SP column mirror: \(column.tag)" : text
            }
            return "SP column mirror skipped: \(text.isEmpty ? "exit \(process.terminationStatus)" : text)"
        } catch {
            return "SP column mirror skipped: \(error.localizedDescription)"
        }
    }

    /// Convenience when only the column name is known.
    public static func mirrorColumn(
        projectName: String,
        columnName: String,
        config: ForgeConfig,
        forgeDir: String
    ) -> String? {
        guard let column = config.board.columns.first(where: { $0.name == columnName }) else {
            return "SP column mirror skipped: unknown column \(columnName)"
        }
        return mirrorColumn(projectName: projectName, column: column, config: config, forgeDir: forgeDir)
    }
}
