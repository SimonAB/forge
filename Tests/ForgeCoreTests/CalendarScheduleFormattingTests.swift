import Foundation
import Testing

import ForgeCore

@Suite("Calendar schedule formatting")
struct CalendarScheduleFormattingTests {
    @Test("dateWindow spans N days from start of anchor day")
    func dateWindowLength() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = Date(timeIntervalSince1970: 1_717_209_600) // 2024-06-01 00:00 UTC
        let (start, end) = CalendarScheduleFormatting.dateWindow(anchor: anchor, days: 7, calendar: cal)
        let diff = cal.dateComponents([.day], from: start, to: end).day ?? 0
        #expect(diff == 7)
        #expect(cal.isDate(start, inSameDayAs: anchor))
    }

    @Test("groupByDay sorts days and events")
    func groupByDayOrder() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let d1 = cal.date(from: DateComponents(year: 2026, month: 4, day: 10))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 4, day: 11))!
        let e1 = CalendarEventSummary(
            title: "B",
            calendarTitle: "C",
            isAllDay: false,
            startDate: d1.addingTimeInterval(36_000),
            endDate: d1.addingTimeInterval(37_200),
            location: nil
        )
        let e2 = CalendarEventSummary(
            title: "A",
            calendarTitle: "C",
            isAllDay: false,
            startDate: d2.addingTimeInterval(10_800),
            endDate: d2.addingTimeInterval(12_000),
            location: nil
        )
        let grouped = CalendarScheduleFormatting.groupByDay([e2, e1], calendar: cal)
        #expect(grouped.count == 2)
        #expect(grouped[0].events.first?.title == "B")
        #expect(grouped[1].events.first?.title == "A")
    }

    @Test("compactLine shows time range for timed events")
    func compactLineTimed() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 9, minute: 0))!
        let end = cal.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 10, minute: 0))!
        let ev = CalendarEventSummary(
            title: "Meet",
            calendarTitle: "Work",
            isAllDay: false,
            startDate: start,
            endDate: end,
            location: "Room 1"
        )
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "en_GB")
        tf.timeZone = cal.timeZone
        tf.dateFormat = "HH:mm"
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_GB")
        df.timeZone = cal.timeZone
        df.dateFormat = "EEE d MMM"
        let line = CalendarScheduleFormatting.compactLine(ev, timeFormatter: tf, dateFormatter: df)
        #expect(line.contains("Meet"))
        #expect(line.contains("Work"))
        #expect(line.contains("Room 1"))
    }
}
