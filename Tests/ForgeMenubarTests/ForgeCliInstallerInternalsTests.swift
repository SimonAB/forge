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
}

