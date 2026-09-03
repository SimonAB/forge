import Foundation
import Testing

@testable import ForgeCore

@Suite("Terminal multiplexer support")
struct TerminalMultiplexerSupportTests {

    @Test("Detects running herdr server from status output")
    func detectsRunningHerdrServer() {
        let output = """
        client:
          version: 0.8.2

        server:
          status: running
          version: 0.8.2

        update:
          restart_needed: no
        """
        #expect(TerminalMultiplexerSupport.isHerdrServerRunning(statusOutput: output))
    }

    @Test("Rejects stopped herdr server")
    func rejectsStoppedHerdrServer() {
        let output = """
        server:
          status: stopped
          version: 0.8.2
        """
        #expect(!TerminalMultiplexerSupport.isHerdrServerRunning(statusOutput: output))
    }

    @Test("Parses pane id from herdr tab create JSON")
    func parsesTabCreatePaneID() {
        let json = """
        {"id":"cli:tab:create","result":{"root_pane":{"pane_id":"w8:pC","tab_id":"w8:t2","workspace_id":"w8"},"tab":{"tab_id":"w8:t2"},"type":"tab_created"}}
        """
        #expect(TerminalMultiplexerSupport.parseHerdrTabCreatePaneID(from: json) == "w8:pC")
    }

    @Test("Returns nil for malformed herdr JSON")
    func malformedJSONReturnsNil() {
        #expect(TerminalMultiplexerSupport.parseHerdrTabCreatePaneID(from: "{not json") == nil)
        #expect(TerminalMultiplexerSupport.parseHerdrTabCreatePaneID(from: "{\"result\":{}}") == nil)
    }

    @Test("Label uses last path component")
    func labelFromWorkingDirectory() {
        #expect(
            TerminalMultiplexerSupport.label(forWorkingDirectory: "/Users/me/Projects/Apodemus luxury")
                == "Apodemus luxury"
        )
        #expect(TerminalMultiplexerSupport.label(forWorkingDirectory: nil) == "Forge")
    }
}
