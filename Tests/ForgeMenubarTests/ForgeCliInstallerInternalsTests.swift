import Foundation
import Testing

@_spi(Testing) @testable import forge_menubar

@Suite("Forge CLI installer internals")
struct ForgeCliInstallerInternalsTests {

    @Test("shellEscape uses single quotes and escapes embedded quotes")
    func shellEscapeEscapesSingleQuotes() {
        let input = "/Applications/Forge's App/Contents/Resources/bin/forge"
        let escaped = ForgeCliInstallerInternals.shellEscape(input)
        #expect(escaped.hasPrefix("'"))
        #expect(escaped.hasSuffix("'"))
        #expect(escaped.contains("'\\''"))
    }

    @Test("appleScriptStringLiteral escapes backslashes and quotes")
    func appleScriptStringLiteralEscapes() {
        let input = #"say "hi" \ world"#
        let lit = ForgeCliInstallerInternals.appleScriptStringLiteral(input)
        #expect(lit.hasPrefix("\"") && lit.hasSuffix("\""))
        // Inner characters should not include raw quotes/backslashes.
        #expect(lit.contains("\\\""))
        #expect(lit.contains("\\\\"))
    }

    @Test("isIdenticalFile accepts identical regular files")
    func identicalFilesMatch() throws {
        let dir = try makeTemporaryDirectory()
        let a = dir.appendingPathComponent("a")
        let b = dir.appendingPathComponent("b")
        try Data("same content".utf8).write(to: a)
        try Data("same content".utf8).write(to: b)

        #expect(ForgeCliInstallerInternals.isIdenticalFile(destination: a, embedded: b))
    }

    @Test("isIdenticalFile rejects same-size different files")
    func sameSizeDifferentFilesDoNotMatch() throws {
        let dir = try makeTemporaryDirectory()
        let a = dir.appendingPathComponent("a")
        let b = dir.appendingPathComponent("b")
        try Data("abc123".utf8).write(to: a)
        try Data("xyz789".utf8).write(to: b)

        #expect(!ForgeCliInstallerInternals.isIdenticalFile(destination: a, embedded: b))
    }

    @Test("isIdenticalFile rejects non-regular files")
    func nonRegularFilesDoNotMatch() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("forge")
        let subdir = dir.appendingPathComponent("folder")
        try Data("content".utf8).write(to: file)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        #expect(!ForgeCliInstallerInternals.isIdenticalFile(destination: subdir, embedded: file))
    }

    @Test("sha256 hashes identical file content consistently")
    func sha256HashesContent() throws {
        let dir = try makeTemporaryDirectory()
        let a = dir.appendingPathComponent("a")
        let b = dir.appendingPathComponent("b")
        try Data("hash me".utf8).write(to: a)
        try Data("hash me".utf8).write(to: b)

        let hashA = ForgeCliInstallerInternals.sha256(url: a)
        let hashB = ForgeCliInstallerInternals.sha256(url: b)

        guard let hashA, let hashB else {
            Issue.record("Expected sha256(url:) to return a hash for both files")
            return
        }

        #expect(hashA == hashB)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
