import Testing
@testable import ForgeCore

@Test func defaultConfigHasSevenColumns() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    #expect(config.board.columns.count == 7)
}

@Test func defaultProjectScanDepthIsOne() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    #expect(config.projectScanDepth == 1)
    #expect(config.resolvedProjectScanDepth == 1)
}

@Test func columnLookupResolvesAliases() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    let col = config.column(forTag: "active 🚧")
    #expect(col?.name == "Watch")
}

@Test func columnLookupMapsLegacyAnalyseToCoding() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    let col = config.column(forTag: "Analyse 🔍")
    #expect(col?.name == "Coding")
}

@Test func columnLookupFindsWatchTag() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    let col = config.column(forTag: "Watch 👁️")
    #expect(col?.name == "Watch")
}

@Test func columnLookupFindsCanonicalTag() {
    let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp/test"])
    let col = config.column(forTag: "Write ✒️")
    #expect(col?.name == "Write")
}
