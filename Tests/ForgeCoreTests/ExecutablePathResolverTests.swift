import Foundation
import Testing

@testable import ForgeCore

@Suite("Executable path resolver")
struct ExecutablePathResolverTests {
    @Test("Augmented PATH prefixes extras and preserves existing order")
    func augmentedPATHPrefixesAndDeduplicates() {
        let path = ExecutablePathResolver.augmentedPATH(
            basePATH: "/usr/bin:/bin:/opt/homebrew/bin",
            extraDirectories: ["/opt/homebrew/bin", "/Users/me/bin", "/usr/local/bin"]
        )
        let parts = path.split(separator: ":").map(String.init)
        #expect(parts.first == "/opt/homebrew/bin")
        #expect(parts.contains("/Users/me/bin"))
        #expect(parts.contains("/usr/bin"))
        #expect(parts.filter { $0 == "/opt/homebrew/bin" }.count == 1)
    }

    @Test("Standard extras include user and Homebrew prefixes")
    func standardExtrasIncludeUserBins() {
        let extras = ExecutablePathResolver.standardExtraDirectories(home: "/Users/me")
        #expect(extras.contains("/Users/me/bin"))
        #expect(extras.contains("/Users/me/.local/bin"))
        #expect(extras.contains("/opt/homebrew/bin"))
        #expect(extras.contains("/usr/local/bin"))
    }

    @Test("Find resolves against augmented directories before missing process PATH")
    func findUsesExtraDirectories() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-path-resolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let tool = temp.appendingPathComponent("hermes")
        FileManager.default.createFile(atPath: tool.path, contents: Data("#!/bin/sh\n".utf8), attributes: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        let found = ExecutablePathResolver.find(
            named: "hermes",
            basePATH: "/usr/bin:/bin",
            extraDirectories: [temp.path]
        )
        #expect(found == tool.path)
    }

    @Test("Find falls back to additional candidates")
    func findUsesAdditionalCandidates() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-embedded-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let embedded = temp.appendingPathComponent("forge")
        FileManager.default.createFile(atPath: embedded.path, contents: Data("#!/bin/sh\n".utf8), attributes: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: embedded.path)

        let found = ExecutablePathResolver.find(
            named: "forge",
            basePATH: "/usr/bin:/bin",
            extraDirectories: [],
            additionalCandidates: [embedded.path]
        )
        #expect(found == embedded.path)
    }
}
