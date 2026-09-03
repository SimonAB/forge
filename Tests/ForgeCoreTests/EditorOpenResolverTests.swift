import Foundation
import Testing

@testable import ForgeCore

@Suite("Editor open resolver")
struct EditorOpenResolverTests {

    @Test("Empty paths fall back to home directory")
    func emptyPathsUseHome() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-edit-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let targets = try EditorOpenResolver.resolveTargets(
            paths: [],
            homeDirectory: home.path
        )
        #expect(targets == [EditorOpenTarget(filePath: home.path, workingDirectory: home.path)])
    }

    @Test("File target uses parent as working directory")
    func fileUsesParentWorkingDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-edit-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("notes.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        let targets = try EditorOpenResolver.resolveTargets(paths: [file.path])
        #expect(targets == [EditorOpenTarget(filePath: file.path, workingDirectory: dir.path)])
    }

    @Test("Directory target uses itself as working directory")
    func directoryUsesSelf() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-edit-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let targets = try EditorOpenResolver.resolveTargets(paths: [dir.path])
        #expect(targets == [EditorOpenTarget(filePath: dir.path, workingDirectory: dir.path)])
    }

    @Test("Missing path throws")
    func missingPathThrows() {
        #expect(throws: EditorOpenError.pathNotFound("/no/such/forge-edit-path")) {
            try EditorOpenResolver.resolveTargets(paths: ["/no/such/forge-edit-path"])
        }
    }
}
