import Foundation
import Testing

@testable import ForgeCore

@Suite("Reminders EventKit display helpers")
struct RemindersReaderHelpersTests {
    @Test("displayTitle substitutes a placeholder for empty titles")
    func emptyTitle() {
        #expect(RemindersReader.displayTitle(nil) == "(No title)")
        #expect(RemindersReader.displayTitle("") == "(No title)")
        #expect(RemindersReader.displayTitle("Draft methods") == "Draft methods")
    }

    @Test("truncate trims, drops empty notes, and caps length")
    func noteTruncate() {
        #expect(RemindersReader.truncate(nil, limit: 10) == nil)
        #expect(RemindersReader.truncate("   ", limit: 10) == nil)
        #expect(RemindersReader.truncate("  hello  ", limit: 10) == "hello")
        let long = String(repeating: "a", count: 12)
        let truncated = RemindersReader.truncate(long, limit: 8)
        #expect(truncated == "aaaaaaaa…")
        #expect(truncated?.count == 9)
    }
}
