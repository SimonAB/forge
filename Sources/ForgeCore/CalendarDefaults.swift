import Foundation

/// Defaults shared by `forge calendar` / `forge brief` Schedule (read-only Calendar).
public enum ForgeCalendarDefaults {
    /// Rolling window: from the start of the anchor day through the next N full days (see `CalendarScheduleFormatting.dateWindow`).
    public static let horizonDays = 7
}
