import Foundation

/// A calendar day on the athlete's wall clock, independent of time zones.
///
/// Strava reports `start_date_local` as the local wall-clock time written as if
/// it were UTC. We keep that "floating" representation everywhere: a run that
/// started at 06:05 on a Tuesday in Tokyo stays a Tuesday-06:05 run, wherever
/// the phone is now. All day maths is plain integer arithmetic on days since
/// 1970-01-01, so it is fast and identical on every platform.
public struct LocalDay: Hashable, Comparable, Sendable, Strideable, CustomStringConvertible {
    /// Days since 1970-01-01.
    public var index: Int

    public init(index: Int) {
        self.index = index
    }

    public init(year: Int, month: Int, day: Int) {
        index = Civil.daysFromCivil(year, month, day)
    }

    /// The day a floating (wall-clock) date falls on.
    public init(_ floating: Date) {
        index = Int((floating.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// Parses `yyyy-MM-dd`.
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Floating midnight at the start of the day.
    public var date: Date { Date(timeIntervalSince1970: Double(index) * 86_400) }

    public var components: (year: Int, month: Int, day: Int) { Civil.civilFromDays(index) }
    public var year: Int { components.year }
    public var month: Int { components.month }
    public var day: Int { components.day }
    public var quarter: Int { (month - 1) / 3 + 1 }

    /// ISO weekday index: 0 = Monday … 6 = Sunday.
    public var weekday: Int { ((index + 3) % 7 + 7) % 7 }
    public var isWeekend: Bool { weekday >= 5 }

    public var dayOfYear: Int { index - LocalDay(year: year, month: 1, day: 1).index + 1 }

    public var startOfMonth: LocalDay { LocalDay(year: year, month: month, day: 1) }
    public var startOfYear: LocalDay { LocalDay(year: year, month: 1, day: 1) }
    public var startOfQuarter: LocalDay { LocalDay(year: year, month: (quarter - 1) * 3 + 1, day: 1) }

    /// Start of the week containing this day. `firstWeekday` uses the ISO index (0 = Monday).
    public func startOfWeek(firstWeekday: Int = 0) -> LocalDay {
        LocalDay(index: index - ((weekday - firstWeekday) % 7 + 7) % 7)
    }

    /// Same day-of-month `months` later, clamped to the month's length.
    public func adding(months: Int) -> LocalDay {
        let total = year * 12 + (month - 1) + months
        let y = Int((Double(total) / 12).rounded(.down))
        let m = total - y * 12 + 1
        return LocalDay(year: y, month: m, day: min(day, Civil.daysIn(month: m, year: y)))
    }

    public func adding(days: Int) -> LocalDay { LocalDay(index: index + days) }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool { lhs.index < rhs.index }
    public func advanced(by n: Int) -> LocalDay { LocalDay(index: index + n) }
    public func distance(to other: LocalDay) -> Int { other.index - index }

    public var description: String {
        let c = components
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }

    /// Today on the wall clock of `timeZone`.
    public static func today(in timeZone: TimeZone = .current, now: Date = Date()) -> LocalDay {
        LocalDay(Floating.from(now, timeZone: timeZone))
    }
}

extension LocalDay: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        index = try container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(index)
    }
}

/// A half-open range of days: `start` is included, `end` is not.
public struct DayRange: Hashable, Codable, Sendable, Sequence {
    public var start: LocalDay
    public var end: LocalDay

    public init(start: LocalDay, end: LocalDay) {
        self.start = start
        self.end = Swift.max(start, end)
    }

    /// Inclusive initialiser: `first...last`.
    public init(first: LocalDay, last: LocalDay) {
        self.init(start: first, end: last.adding(days: 1))
    }

    public var count: Int { end.index - start.index }
    public var last: LocalDay { end.adding(days: -1) }
    public var isEmpty: Bool { count <= 0 }

    public func contains(_ day: LocalDay) -> Bool { day >= start && day < end }

    public func clamped(to other: DayRange) -> DayRange {
        DayRange(start: Swift.max(start, other.start), end: Swift.max(Swift.max(start, other.start), Swift.min(end, other.end)))
    }

    /// Floating instants bounding the range.
    public var floatingInterval: (start: Date, end: Date) { (start.date, end.date) }

    public func makeIterator() -> AnyIterator<LocalDay> {
        var current = start
        let end = end
        return AnyIterator {
            guard current < end else { return nil }
            defer { current = current.adding(days: 1) }
            return current
        }
    }
}

/// Wall-clock helpers for floating dates.
public enum Floating {
    /// The wall-clock time in `timeZone` at the real instant `instant`, as a floating date.
    public static func from(_ instant: Date, timeZone: TimeZone) -> Date {
        instant.addingTimeInterval(TimeInterval(timeZone.secondsFromGMT(for: instant)))
    }

    /// Seconds since local midnight.
    public static func secondsOfDay(_ floating: Date) -> Int {
        let t = floating.timeIntervalSince1970
        return Int(t - (t / 86_400).rounded(.down) * 86_400)
    }

    public static func hour(_ floating: Date) -> Int { secondsOfDay(floating) / 3600 }

    public static func date(_ day: LocalDay, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        day.date.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60 + second))
    }
}

/// Proleptic Gregorian calendar conversions (Howard Hinnant's algorithms).
enum Civil {
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}
