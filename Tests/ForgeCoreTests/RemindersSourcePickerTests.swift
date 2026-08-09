import Testing

@testable import ForgeCore

@Suite("Reminders source picker")
struct RemindersSourcePickerTests {
    private let iCloud = RemindersSourcePicker.Candidate(
        title: "iCloud",
        kind: .calDAV,
        hasReminderLists: true
    )
    private let onMyMac = RemindersSourcePicker.Candidate(
        title: "On My Mac",
        kind: .local,
        hasReminderLists: false
    )
    private let exchange = RemindersSourcePicker.Candidate(
        title: "Work",
        kind: .exchange,
        hasReminderLists: false
    )
    private let subscribed = RemindersSourcePicker.Candidate(
        title: "Holidays",
        kind: .other,
        hasReminderLists: false
    )

    @Test("explicit title matches case-insensitively")
    func explicitTitle() {
        let choice = RemindersSourcePicker.choose(
            named: "icloud",
            among: [onMyMac, iCloud, exchange]
        )
        #expect(choice == .source("iCloud"))
    }

    @Test("unknown explicit title is requestedNotFound")
    func unknownTitle() {
        let choice = RemindersSourcePicker.choose(
            named: "Google",
            among: [iCloud, onMyMac]
        )
        #expect(choice == .requestedNotFound("Google"))
    }

    @Test("empty request prefers a source that already has reminder lists")
    func preferExistingLists() {
        let choice = RemindersSourcePicker.choose(
            named: nil,
            among: [exchange, onMyMac, iCloud]
        )
        #expect(choice == .source("iCloud"))
    }

    @Test("with no existing lists, prefer local over exchange")
    func preferLocalWhenNoLists() {
        let choice = RemindersSourcePicker.choose(
            named: nil,
            among: [exchange, onMyMac]
        )
        #expect(choice == .source("On My Mac"))
    }

    @Test("subscribed calendars are ignored when preferred kinds exist")
    func ignoreOtherWhenPreferredExist() {
        let choice = RemindersSourcePicker.choose(
            named: nil,
            among: [subscribed, exchange]
        )
        #expect(choice == .source("Work"))
    }

    @Test("no candidates yields noneAvailable")
    func empty() {
        #expect(RemindersSourcePicker.choose(named: nil, among: []) == .noneAvailable)
    }
}
