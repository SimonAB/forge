import Foundation
import Testing

import ForgeCore

@Suite("Calendar snapshot store")
struct CalendarSnapshotStoreTests {
    @Test("loadIfEligible rejects when snapshot is older than maxAge")
    func rejectsStale() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-snapshot-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let forgeDir = tmp.path
        let old = Date().addingTimeInterval(-3600)
        let cal = Calendar.current
        let start = cal.startOfDay(for: old)
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        let payload = CalendarSnapshotStore.Payload(
            generatedAt: old,
            windowStart: start,
            windowEnd: end,
            horizonDays: 7,
            calendarInclude: [],
            events: []
        )
        try CalendarSnapshotStore.write(forgeDir: forgeDir, payload: payload)
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let eligible = try CalendarSnapshotStore.loadIfEligible(
            forgeDir: forgeDir,
            config: config,
            requestedDays: 7,
            hasCustomStart: false,
            maxAge: 900
        )
        #expect(eligible == nil)
    }

    @Test("filterEvents keeps overlapping events only")
    func filterOverlap() {
        let cal = Calendar.current
        let ws = cal.date(from: DateComponents(year: 2026, month: 4, day: 10))!
        let we = cal.date(from: DateComponents(year: 2026, month: 4, day: 13))!
        let e1 = CalendarEventSummary(
            title: "A",
            calendarTitle: "W",
            isAllDay: false,
            startDate: ws.addingTimeInterval(10_800),
            endDate: ws.addingTimeInterval(11_000),
            location: nil
        )
        let e2 = CalendarEventSummary(
            title: "B",
            calendarTitle: "W",
            isAllDay: false,
            startDate: we.addingTimeInterval(100),
            endDate: we.addingTimeInterval(200),
            location: nil
        )
        let out = CalendarSnapshotStore.filterEvents([e1, e2], windowStart: ws, windowEnd: we)
        #expect(out.count == 1)
        #expect(out.first?.title == "A")
    }

    @Test("Payload decodes legacy JSON without schemaVersion or groupedByDay")
    func decodesLegacySnapshotJSON() throws {
        let json = """
        {
          "calendarInclude" : [],
          "events" : [
            {
              "calendarTitle" : "Work",
              "endDate" : "2026-04-10T10:00:00Z",
              "isAllDay" : false,
              "location" : "Room A",
              "startDate" : "2026-04-10T09:00:00Z",
              "title" : "Stand-up"
            }
          ],
          "generatedAt" : "2026-04-10T08:00:00Z",
          "horizonDays" : 7,
          "windowEnd" : "2026-04-17T00:00:00Z",
          "windowStart" : "2026-04-10T00:00:00Z",
          "writer" : "Forge.app"
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(CalendarSnapshotStore.Payload.self, from: data)
        #expect(payload.schemaVersion == 1)
        #expect(payload.events.count == 1)
        #expect(payload.events.first?.title == "Stand-up")
        #expect(payload.events.first?.notes == nil)
        #expect(!payload.groupedByDay.isEmpty)
    }

    @Test("Payload round-trip encodes schema version and groupedByDay")
    func roundTripPayload() throws {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 4, day: 10))!
        let end = cal.date(from: DateComponents(year: 2026, month: 4, day: 11))!
        let ev = CalendarEventSummary(
            title: "A",
            calendarTitle: "C",
            isAllDay: false,
            startDate: start.addingTimeInterval(3600),
            endDate: start.addingTimeInterval(7200),
            location: nil,
            notes: "Hello",
            eventIdentifier: "id1"
        )
        let payload = CalendarSnapshotStore.Payload(
            generatedAt: start,
            windowStart: start,
            windowEnd: end,
            horizonDays: 1,
            calendarInclude: [],
            events: [ev],
            calendarForGrouping: cal
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(CalendarSnapshotStore.Payload.self, from: data)
        #expect(back.schemaVersion == CalendarSnapshotStore.currentSchemaVersion)
        #expect(back.groupedByDay.count == 1)
        #expect(back.events.first?.notes == "Hello")
        #expect(back.events.first?.eventIdentifier == "id1")
    }
}
