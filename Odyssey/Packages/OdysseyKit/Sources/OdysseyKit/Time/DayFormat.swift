import Foundation

/// Locale-aware text for floating days. Everything is formatted in UTC because
/// floating dates already carry the wall-clock time.
public struct DayFormat: Sendable {
    public var locale: Locale

    public init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    private var base: Date.FormatStyle {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        calendar.locale = locale
        return Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// "October 2026"
    public func monthYear(_ day: LocalDay) -> String {
        day.date.formatted(base.month(.wide).year())
    }

    /// "October"
    public func month(_ day: LocalDay) -> String {
        day.date.formatted(base.month(.wide))
    }

    /// "Oct"
    public func monthShort(_ day: LocalDay) -> String {
        day.date.formatted(base.month(.abbreviated))
    }

    /// "Oct 3" / "3 Oct"
    public func short(_ day: LocalDay) -> String {
        day.date.formatted(base.month(.abbreviated).day())
    }

    /// "Oct 3, 2026" / "3 Oct 2026"
    public func shortWithYear(_ day: LocalDay) -> String {
        day.date.formatted(base.month(.abbreviated).day().year())
    }

    /// "Sun, Oct 3" / "Sun 3 Oct"
    public func weekdayShort(_ day: LocalDay) -> String {
        day.date.formatted(base.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Sunday, October 3" / "Sunday 3 October"
    public func weekdayLong(_ day: LocalDay) -> String {
        day.date.formatted(base.weekday(.wide).month(.wide).day())
    }

    /// "Sunday"
    public func weekdayName(_ isoWeekday: Int) -> String {
        // 2024-01-01 was a Monday.
        LocalDay(year: 2024, month: 1, day: 1 + isoWeekday).date.formatted(base.weekday(.wide))
    }

    /// "Sun"
    public func weekdayNameShort(_ isoWeekday: Int) -> String {
        LocalDay(year: 2024, month: 1, day: 1 + isoWeekday).date.formatted(base.weekday(.abbreviated))
    }

    /// "06:05" / "6:05 AM" for a floating time.
    public func time(_ floating: Date) -> String {
        floating.formatted(base.hour().minute())
    }

    /// "Oct 3 – Nov 2" or "Oct 3, 2025 – Jan 4, 2026".
    public func range(_ range: DayRange) -> String {
        let first = range.start, last = range.last
        if first == last { return shortWithYear(first) }
        if first.year == last.year {
            return "\(short(first)) – \(shortWithYear(last))"
        }
        return "\(shortWithYear(first)) – \(shortWithYear(last))"
    }
}
