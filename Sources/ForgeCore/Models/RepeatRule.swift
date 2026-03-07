import Foundation

/// Defines how a task recurs after completion or on a fixed schedule.
///
/// Inline syntax:
/// - `@repeat(2w)`       — 2 weeks after completion (deferred)
/// - `@repeat(every 2w)` — every 2 weeks from the due date (fixed)
///
/// Supported units: `d` (days), `w` (weeks), `m` (months), `y` (years).
/// The interval number defaults to 1 if omitted (e.g. `@repeat(w)` = weekly).
public struct RepeatRule: Sendable, Equatable {

    public enum Mode: String, Sendable, Equatable {
        /// Next due date = completion date + interval.
        case fromCompletion
        /// Next due date = previous due date + interval (fixed schedule).
        case fixedSchedule
    }

    public enum Unit: String, Sendable, Equatable, CaseIterable {
        case day = "d"
        case week = "w"
        case month = "m"
        case year = "y"

        /// Human-readable plural label.
        var label: String {
            switch self {
            case .day: "day"
            case .week: "week"
            case .month: "month"
            case .year: "year"
            }
        }
    }

    public let mode: Mode
    public let interval: Int
    public let unit: Unit

    public init(mode: Mode, interval: Int = 1, unit: Unit) {
        self.mode = mode
        self.interval = max(1, interval)
        self.unit = unit
    }

    // MARK: - Parsing

    /// Parse a repeat rule from the value inside `@repeat(...)`.
    ///
    /// Examples: `"2w"`, `"every 2w"`, `"m"`, `"every 1d"`.
    public static func parse(_ raw: String) -> RepeatRule? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        var mode: Mode = .fromCompletion
        var body = trimmed

        if body.hasPrefix("every ") || body.hasPrefix("every\u{00A0}") {
            mode = .fixedSchedule
            body = String(body.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }

        guard !body.isEmpty else { return nil }

        let lastChar = body.last!
        guard let unit = Unit(rawValue: String(lastChar)) else { return nil }

        let numberPart = String(body.dropLast())
        let interval: Int
        if numberPart.isEmpty {
            interval = 1
        } else {
            guard let n = Int(numberPart), n > 0 else { return nil }
            interval = n
        }

        return RepeatRule(mode: mode, interval: interval, unit: unit)
    }

    // MARK: - Serialisation

    /// Serialise to the inline tag value (without the `@repeat()` wrapper).
    public func serialise() -> String {
        let prefix = mode == .fixedSchedule ? "every " : ""
        let number = interval == 1 ? "" : "\(interval)"
        return "\(prefix)\(number)\(unit.rawValue)"
    }

    // MARK: - Date Calculation

    /// Calculate the next due date based on the repeat rule.
    ///
    /// - Parameters:
    ///   - previousDue: The original due date of the completed task.
    ///   - completionDate: The date the task was completed.
    /// - Returns: The next due date.
    public func nextDueDate(previousDue: Date?, completionDate: Date) -> Date {
        let anchor: Date
        switch mode {
        case .fromCompletion:
            anchor = completionDate
        case .fixedSchedule:
            anchor = previousDue ?? completionDate
        }

        let calendar = Calendar.current
        var nextDate: Date

        switch unit {
        case .day:
            nextDate = calendar.date(byAdding: .day, value: interval, to: anchor)!
        case .week:
            nextDate = calendar.date(byAdding: .weekOfYear, value: interval, to: anchor)!
        case .month:
            nextDate = calendar.date(byAdding: .month, value: interval, to: anchor)!
        case .year:
            nextDate = calendar.date(byAdding: .year, value: interval, to: anchor)!
        }

        if mode == .fixedSchedule, previousDue != nil {
            while nextDate <= completionDate {
                switch unit {
                case .day:
                    nextDate = calendar.date(byAdding: .day, value: interval, to: nextDate)!
                case .week:
                    nextDate = calendar.date(byAdding: .weekOfYear, value: interval, to: nextDate)!
                case .month:
                    nextDate = calendar.date(byAdding: .month, value: interval, to: nextDate)!
                case .year:
                    nextDate = calendar.date(byAdding: .year, value: interval, to: nextDate)!
                }
            }
        }

        return nextDate
    }
}
