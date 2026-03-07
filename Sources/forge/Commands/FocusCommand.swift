import ArgumentParser
import Foundation
import ForgeCore

/// Enter, check, or clear a focus session.
///
/// A focus session filters all task-listing commands (next, contexts, waiting)
/// to only show areas matching the given tag — e.g. `work`, `personal`, or
/// `spiritual`.  The session persists until explicitly cleared.
struct FocusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Enter or clear a focus session."
    )

    @Argument(help: "Tag to focus on (e.g. work, personal). Omit to show current focus.")
    var tag: String?

    @Flag(name: .long, help: "Clear the active focus session.")
    var clear = false

    mutating func run() throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)

        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let green = "\u{1B}[32m"
        let yellow = "\u{1B}[33m"
        let reset = "\u{1B}[0m"

        let focusPath = ConfigLoader.focusFilePath(forgeDir: forgeDir)

        if clear {
            try? FileManager.default.removeItem(atPath: focusPath)
            print("\(green)✓\(reset) Focus cleared — showing all areas.")
            return
        }

        guard let newTag = tag else {
            if let current = ConfigLoader.currentFocus(forgeDir: forgeDir) {
                let areas = ConfigLoader.areaFiles(forgeDir: forgeDir, focusTag: current)
                let includesProjects = ConfigLoader.includesProjects(focusTag: current, config: config)
                print("\(bold)Focus:\(reset) \(yellow)\(current)\(reset)")
                print("\(dim)Areas:\(reset) \(areas.map(\.name).joined(separator: ", "))")
                if includesProjects {
                    print("\(dim)Workspace projects are included.\(reset)")
                }
            } else {
                print("No active focus. Use \(dim)forge focus <tag>\(reset) to enter one.")
                let allAreas = ConfigLoader.scanAreaFiles(forgeDir: forgeDir)
                let allTags = Set(allAreas.flatMap { $0.frontmatter?.tags ?? [] }).sorted()
                if !allTags.isEmpty {
                    print("\(dim)Available tags: \(allTags.joined(separator: ", "))\(reset)")
                }
            }
            return
        }

        let matching = ConfigLoader.areaFiles(forgeDir: forgeDir, focusTag: newTag)
        if matching.isEmpty {
            let allAreas = ConfigLoader.scanAreaFiles(forgeDir: forgeDir)
            let allTags = Set(allAreas.flatMap { $0.frontmatter?.tags ?? [] }).sorted()
            print("No areas tagged '\(newTag)'.")
            if !allTags.isEmpty {
                print("\(dim)Available tags: \(allTags.joined(separator: ", "))\(reset)")
            }
            return
        }

        try newTag.write(toFile: focusPath, atomically: true, encoding: .utf8)

        let includesProjects = ConfigLoader.includesProjects(focusTag: newTag, config: config)
        print("\(green)✓\(reset) Focus set to \(bold)\(newTag)\(reset)")
        print("\(dim)Areas:\(reset) \(matching.map(\.name).joined(separator: ", "))")
        if includesProjects {
            print("\(dim)Workspace projects are included.\(reset)")
        } else {
            print("\(dim)Workspace projects are excluded.\(reset)")
        }
        print("\(dim)All task commands now filter to this focus. Clear with: forge focus --clear\(reset)")
    }
}
