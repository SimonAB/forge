import Foundation

/// A single task parsed from a TASKS.md file.
public struct ForgeTask: Sendable, Identifiable {
    /// Unique 6-character identifier, stored as <!-- id:xxxxxx --> in markdown.
    public var id: String

    /// The task description text (without inline tags or the ID comment).
    public var text: String

    /// Whether the task checkbox is checked.
    public var isCompleted: Bool

    /// The section this task belongs to (e.g. "Next Actions", "Waiting For").
    public var section: Section

    /// Due date parsed from @due(YYYY-MM-DD).
    public var dueDate: Date?

    /// Context parsed from @ctx(name).
    public var context: String?

    /// Energy level parsed from @energy(high|medium|low).
    public var energy: String?

    /// Person being waited on, parsed from @waiting(name).
    public var waitingOn: String?

    /// Date the waiting started, parsed from @since(YYYY-MM-DD).
    public var sinceDate: Date?

    /// Completion date, parsed from @done(YYYY-MM-DD).
    public var doneDate: Date?

    /// Source annotation, parsed from @source(name) — used for items captured from Reminders.
    public var source: String?

    /// Defer date parsed from @defer(YYYY-MM-DD) — task is hidden until this date.
    public var deferDate: Date?

    /// Repeat rule parsed from @repeat(...).
    public var repeatRule: RepeatRule?

    /// Optional notes for this task (indented block under the task line in TASKS.md).
    public var notes: String?

    /// The project directory name this task belongs to.
    public var projectName: String?

    /// Assignees for this task, derived from inline person annotations such as @person(#Name).
    /// Each entry is a normalised identifier with the leading # removed and surrounding
    /// whitespace trimmed.
    public var assignees: [String]?

    public enum Section: String, Sendable, CaseIterable {
        case nextActions = "Next Actions"
        case waitingFor = "Waiting For"
        case completed = "Completed"
        case notes = "Notes"
    }

    public init(
        id: String,
        text: String,
        isCompleted: Bool = false,
        section: Section = .nextActions,
        dueDate: Date? = nil,
        context: String? = nil,
        energy: String? = nil,
        waitingOn: String? = nil,
        sinceDate: Date? = nil,
        doneDate: Date? = nil,
        source: String? = nil,
        deferDate: Date? = nil,
        repeatRule: RepeatRule? = nil,
        notes: String? = nil,
        projectName: String? = nil,
        assignees: [String]? = nil
    ) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.section = section
        self.dueDate = dueDate
        self.context = context
        self.energy = energy
        self.waitingOn = waitingOn
        self.sinceDate = sinceDate
        self.doneDate = doneDate
        self.source = source
        self.deferDate = deferDate
        self.repeatRule = repeatRule
        self.notes = notes
        self.projectName = projectName
        self.assignees = assignees
    }

    /// Generate a new random 6-character hex ID.
    public static func newID() -> String {
        let bytes = (0..<3).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Format the due date for display.
    public var dueDateString: String? {
        guard let date = dueDate else { return nil }
        return Self.dateFormatter.string(from: date)
    }

    /// True if the task is overdue.
    public var isOverdue: Bool {
        guard let date = dueDate, !isCompleted else { return false }
        return date < Calendar.current.startOfDay(for: Date())
    }

    /// True if the task is due today.
    public var isDueToday: Bool {
        guard let date = dueDate, !isCompleted else { return false }
        return Calendar.current.isDateInToday(date)
    }

    /// True if the task is deferred (defer date is in the future).
    public var isDeferred: Bool {
        guard let date = deferDate, !isCompleted else { return false }
        return date > Calendar.current.startOfDay(for: Date())
    }

    /// True if the task becomes actionable today (defer date is today).
    public var becomesActionableToday: Bool {
        guard let date = deferDate, !isCompleted else { return false }
        return Calendar.current.isDateInToday(date)
    }

    /// Format the defer date for display.
    public var deferDateString: String? {
        guard let date = deferDate else { return nil }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Normalise a raw person tag (for example a Finder tag such as "#PeggySue")
    /// into an identifier that can be used consistently across projects and tasks.
    /// Returns nil when the string does not look like a person tag.
    public static func normalisedAssigneeIdentifier(fromRawTag raw: String) -> String? {
        guard raw.hasPrefix("#") else {
            return nil
        }
        let name = raw.dropFirst()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// All assignee identifiers associated with this task, combining explicit assignees
    /// and the waiting-on person when present. Useful for CLI filtering.
    public var allAssigneeIdentifiers: [String] {
        var result: [String] = assignees ?? []
        if let waiting = waitingOn?.trimmingCharacters(in: .whitespacesAndNewlines),
           !waiting.isEmpty {
            result.append(waiting)
        }
        return result
    }
}
