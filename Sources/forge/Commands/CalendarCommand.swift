import ArgumentParser
import Foundation
import ForgeCore

/// List upcoming macOS Calendar events (read-only). Default: next `ForgeCalendarDefaults.horizonDays` days from the anchor day.
struct CalendarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendar",
        abstract: "List Apple Calendar events for the next week (read-only; default \(ForgeCalendarDefaults.horizonDays) days).",
        aliases: ["events"]
    )

    @Option(name: .long, help: "Number of days in the window starting at the anchor day’s midnight (default: \(ForgeCalendarDefaults.horizonDays)).")
    var days: Int = ForgeCalendarDefaults.horizonDays

    @Option(
        name: .long,
        help: "Anchor day for the window (YYYY-MM-DD). Default: today (local timezone). Forces live Calendar access (Forge.app snapshot is not used)."
    )
    var start: String?

    @Flag(name: .long, help: "Emit JSON (for scripts or pasting into an assistant).")
    var json: Bool = false

    mutating func run() async throws {
        guard days >= 1 else {
            throw ValidationError("--days must be at least 1.")
        }
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let allowlist = config.gtd.calendarInclude

        let gregorian = Calendar.current
        let customStart: Date?
        if let raw = start?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let fmt = DateFormatter()
            fmt.calendar = gregorian
            fmt.locale = Locale(identifier: "en_GB_POSIX")
            fmt.timeZone = gregorian.timeZone
            fmt.dateFormat = "yyyy-MM-dd"
            guard let d = fmt.date(from: raw) else {
                throw ValidationError("Could not parse --start as YYYY-MM-DD: \(raw)")
            }
            customStart = d
        } else {
            customStart = nil
        }

        let resolution: CalendarEventsResolution.Result
        do {
            resolution = try await CalendarEventsResolution.resolve(
                forgeDir: forgeDir,
                config: config,
                days: days,
                customStart: customStart
            )
        } catch {
            if let e = error as? CalendarReaderError {
                throw ValidationError(e.description)
            }
            throw error
        }

        let windowStart = resolution.windowStart
        let windowEnd = resolution.windowEnd
        let events = resolution.events

        if json {
            let snapshotAt: Date? = {
                if case .forgeAppSnapshot(let at) = resolution.source { return at }
                return nil
            }()
            let sourceLabel: String = {
                switch resolution.source {
                case .forgeAppSnapshot: return "forge_app_snapshot"
                case .liveEventKit: return "live_eventkit"
                }
            }()
            let payload = CalendarJSONPayload(
                windowStart: windowStart,
                windowEnd: windowEnd,
                days: days,
                calendarInclude: allowlist,
                events: events,
                source: sourceLabel,
                snapshotGeneratedAt: snapshotAt
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            if let s = String(data: data, encoding: .utf8) {
                print(s)
            }
            return
        }

        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let reset = "\u{1B}[0m"

        let dayHeaderFormatter = Self.makeDayHeaderFormatter()
        let timeFormatter = Self.makeTimeFormatter()
        let dayLineFormatter = Self.makeDayLineFormatter()

        print("\n\(bold)Calendar\(reset) \(dim)(read-only, next \(days) day(s))\(reset)")
        switch resolution.source {
        case .forgeAppSnapshot(let generatedAt):
            let rel = Self.formatSnapshotRelativeAge(generatedAt)
            print("\(dim)Source:\(reset) Forge.app snapshot · updated \(rel)")
        case .liveEventKit:
            break
        }
        print("\(dim)Window:\(reset) \(dayHeaderFormatter.string(from: windowStart)) \(dim)–\(reset) \(dayHeaderFormatter.string(from: windowEnd))")
        if !allowlist.isEmpty {
            print("\(dim)Calendars:\(reset) \(allowlist.joined(separator: ", "))")
        } else {
            print("\(dim)Calendars:\(reset) all event calendars")
        }
        print()

        if events.isEmpty {
            print("  \(dim)No events in this window.\(reset)\n")
            return
        }

        let grouped = CalendarScheduleFormatting.groupByDay(events, calendar: gregorian)
        for bucket in grouped {
            print("\(bold)\(dayHeaderFormatter.string(from: bucket.dayStart))\(reset)")
            for ev in bucket.events {
                let line = CalendarScheduleFormatting.compactLine(ev, timeFormatter: timeFormatter, dateFormatter: dayLineFormatter)
                print("  • \(line)")
            }
            print()
        }
    }

    private struct CalendarJSONPayload: Encodable {
        let windowStart: Date
        let windowEnd: Date
        let days: Int
        let calendarInclude: [String]
        let events: [CalendarEventSummary]
        let source: String
        let snapshotGeneratedAt: Date?
    }

    private static func formatSnapshotRelativeAge(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private static func makeDayHeaderFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE d MMM yyyy"
        return f
    }

    private static func makeTimeFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "HH:mm"
        return f
    }

    private static func makeDayLineFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }
}
