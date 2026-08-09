import Testing

@testable import ForgeCore

@Suite("Finder tag colour palette")
struct FinderTagColourTests {
    @Test("indices 1 through 7 have sRGB")
    func knownIndexes() {
        for index in 1...7 {
            #expect(FinderTagColour.sRGB(for: index) != nil)
            #expect(FinderTagColour.ansiTrueColour(for: index) != nil)
        }
    }

    @Test("unknown index is nil")
    func unknown() {
        #expect(FinderTagColour.sRGB(for: 0) == nil)
        #expect(FinderTagColour.sRGB(for: 8) == nil)
        #expect(FinderTagColour.ansiTrueColour(for: 0) == nil)
    }

    @Test("Watch is green and Coding is yellow")
    func defaultBoardIndexes() {
        let board = ForgeConfig.defaultConfig(projectRoots: ["/tmp"]).board
        #expect(board.colourIndex(forColumn: "Watch") == 2)
        #expect(board.colourIndex(forColumn: "Coding") == 5)
        #expect(board.colourIndex(forColumn: "watch") == 2)
        #expect(board.colourIndex(forColumn: "Unknown") == nil)
        let watch = FinderTagColour.sRGB(for: 2)!
        #expect(Int((watch.green * 255).rounded()) == 227)
    }
}
