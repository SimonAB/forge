import Testing
@testable import ForgeCore

@Test func defaultConfigHasSevenColumns() {
    let config = ForgeConfig.defaultConfig(workspace: "/tmp/test")
    #expect(config.board.columns.count == 7)
}

@Test func columnLookupResolvesAliases() {
    let config = ForgeConfig.defaultConfig(workspace: "/tmp/test")
    let col = config.column(forTag: "active 🚧")
    #expect(col?.name == "Active")
}

@Test func columnLookupFindsCanonicalTag() {
    let config = ForgeConfig.defaultConfig(workspace: "/tmp/test")
    let col = config.column(forTag: "Write ✒️")
    #expect(col?.name == "Write")
}
