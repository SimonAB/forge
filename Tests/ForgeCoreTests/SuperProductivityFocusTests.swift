import Foundation
import Testing
@testable import ForgeCore

@Test func superProductivityUsesDurablePython() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let binary = root.appendingPathComponent(".venv/bin/python")
    try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("#!/bin/sh\n".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    #expect(SuperProductivityFocus.preferredPython(forgeDir: root.path) == binary.path)
}
