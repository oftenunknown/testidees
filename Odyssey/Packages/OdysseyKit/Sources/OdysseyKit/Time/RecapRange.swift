import Foundation

/// The period a recap covers. Calendar periods (year, quarter, month, week) are
/// the classic "annual summary" shapes; rolling and custom ranges are for
/// testing any slice of your history.
public enum RecapPeriod: Hashable, Codable, Sendable {
    case year(Int)
    case quarter(year: Int, quarter: Int)
    case month(year: Int, month: Int)
    case week(start: LocalDay)
    case rolling(days: Int, through: LocalDay)
    case custom(DayRange)
}

public enum RangeKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case year, quarter, month, week, rolling, custom
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .year: "Year"
        case .quarter: "Quarter"
        case .month: "Month"
        case .week: "Week"
        case .rolling: "Rolling"
        case .custom: "Custom"
        }
    }
}

/// How finely charts bucket the range.
public enum Granularity: String, Codable, Sendable {
    case day, week, month
}

public struct RecapRange: Hashable, Codable, Sendable {
    public var period: RecapPeriod
    /// ISO weekday index the week starts on (0 = Monday, 6 = Sunday).
    public var firstWeekday: Int

    public init(_ period: RecapPeriod, firstWeekday: Int = 0) {
        self.period = period
        self.firstWeekday = firstWeekday
    }

    public var kind: RangeKind {
        switch period {
        case .year: .year
        case .quarter: .quarter
        case .month: .month
        case .week: .week
        case .rolling: .rolling
        case .custom: .custom
        }
    }

    /// The full period, regardless of today.
    public var days: DayRange {
        switch period {
        case .year(let y):
            return DayRange(start: LocalDay(year: y, month: 1, day: 1), end: LocalDay(year: y + 1, month: 1, day: 1))
        case .quarter(let y, let q):
            let start = LocalDay(year: y, month: (q - 1) * 3 + 1, day: 1)
            return DayRange(start: start, end: start.adding(months: 3))
        case .month(let y, let m):
            let start = LocalDay(year: y, month: m, day: 1)
            return DayRange(start: start, end: start.adding(months: 1))
        case .week(let start):
            let s = start.startOfWeek(firstWeekday: firstWeekday)
            return DayRange(start: s, end: s.adding(days: 7))
        case .rolling(let n, let through):
            return DayRange(first: through.adding(days: -(max(n, 1) - 1)), last: through)
        case .custom(let range):
            return range
        }
    }

    /// The part of the period that has happened by `today` (inclusive).
    public func effectiveDays(today: LocalDay) -> DayRange {
        days.clamped(to: DayRange(start: LocalDay(index: Int.min / 4), end: today.adding(days: 1)))
    }

    public func isInProgress(today: LocalDay) -> Bool { days.contains(today) && days.last != today }
    public func isFuture(today: LocalDay) -> Bool { days.start > today }

    public func granularity(today: LocalDay) -> Granularity {
        let n = max(effectiveDays(today: today).count, days.count == 0 ? 0 : 1)
        if n <= 21 { return .day }
        if n <= 126 { return .week }
        return .month
    }

    // MARK: - Labels

    public func title(format: DayFormat = DayFormat()) -> String {
        switch period {
        case .year(let y): return String(y)
        case .quarter(let y, let q): return "Q\(q) \(y)"
        case .month: return format.monthYear(days.start)
        case .week: return "Week of \(format.short(days.start))"
        case .rolling(let n, _): return n == 365 ? "Last 12 months" : "Last \(n) days"
        case .custom(let range): return format.range(range)
        }
    }

    /// A second line with the exact dates, noting when the period isn't over yet.
    public func subtitle(format: DayFormat = DayFormat(), today: LocalDay) -> String {
        let effective = effectiveDays(today: today)
        if isFuture(today: today) { return "\(format.range(days)) · hasn't started yet" }
        let text = format.range(effective.isEmpty ? days : effective)
        return isInProgress(today: today) ? "\(text) · so far" : text
    }

    // MARK: - Navigation

    /// The previous (negative) or next (positive) period of the same shape.
    public func shifted(_ steps: Int) -> RecapRange {
        var copy = self
        switch period {
        case .year(let y):
            copy.period = .year(y + steps)
        case .quarter(let y, let q):
            let total = y * 4 + (q - 1) + steps
            let ny = Int((Double(total) / 4).rounded(.down))
            copy.period = .quarter(year: ny, quarter: total - ny * 4 + 1)
        case .month(let y, let m):
            let start = LocalDay(year: y, month: m, day: 1).adding(months: steps)
            copy.period = .month(year: start.year, month: start.month)
        case .week(let start):
            copy.period = .week(start: start.startOfWeek(firstWeekday: firstWeekday).adding(days: 7 * steps))
        case .rolling(let n, let through):
            copy.period = .rolling(days: n, through: through.adding(days: n * steps))
        case .custom(let range):
            copy.period = .custom(DayRange(start: range.start.adding(days: range.count * steps), end: range.end.adding(days: range.count * steps)))
        }
        return copy
    }

    /// The same span one period earlier, used for "vs last year" comparisons.
    /// For a period in progress, only the elapsed part is compared.
    public func previousComparable(today: LocalDay) -> DayRange {
        let effective = effectiveDays(today: today)
        let length = max(effective.count, 1)
        switch period {
        case .year, .quarter, .month, .week:
            let previous = shifted(-1).days
            // A finished period is compared with the whole previous one
            // (leap days and all); one in progress with the same elapsed span.
            if effective.count >= days.count { return previous }
            return DayRange(start: previous.start, end: min(previous.start.adding(days: length), previous.end))
        case .rolling, .custom:
            return DayRange(start: days.start.adding(days: -length), end: days.start)
        }
    }

    // MARK: - Presets

    public static func current(_ kind: RangeKind, today: LocalDay, firstWeekday: Int = 0) -> RecapRange {
        switch kind {
        case .year: RecapRange(.year(today.year), firstWeekday: firstWeekday)
        case .quarter: RecapRange(.quarter(year: today.year, quarter: today.quarter), firstWeekday: firstWeekday)
        case .month: RecapRange(.month(year: today.year, month: today.month), firstWeekday: firstWeekday)
        case .week: RecapRange(.week(start: today.startOfWeek(firstWeekday: firstWeekday)), firstWeekday: firstWeekday)
        case .rolling: RecapRange(.rolling(days: 30, through: today), firstWeekday: firstWeekday)
        case .custom: RecapRange(.custom(DayRange(first: today.adding(days: -89), last: today)), firstWeekday: firstWeekday)
        }
    }

    /// One-tap shortcuts shown as chips.
    public struct Preset: Hashable, Sendable, Identifiable {
        public var title: String
        public var range: RecapRange
        public var id: String { title }
    }

    public static func presets(today: LocalDay, firstWeekday: Int = 0) -> [Preset] {
        let w = firstWeekday
        return [
            Preset(title: "This year", range: current(.year, today: today, firstWeekday: w)),
            Preset(title: "Last year", range: RecapRange(.year(today.year - 1), firstWeekday: w)),
            Preset(title: "Last 12 months", range: RecapRange(.rolling(days: 365, through: today), firstWeekday: w)),
            Preset(title: "This quarter", range: current(.quarter, today: today, firstWeekday: w)),
            Preset(title: "Last quarter", range: current(.quarter, today: today, firstWeekday: w).shifted(-1)),
            Preset(title: "This month", range: current(.month, today: today, firstWeekday: w)),
            Preset(title: "Last month", range: current(.month, today: today, firstWeekday: w).shifted(-1)),
            Preset(title: "This week", range: current(.week, today: today, firstWeekday: w)),
            Preset(title: "Last 7 days", range: RecapRange(.rolling(days: 7, through: today), firstWeekday: w)),
            Preset(title: "Last 30 days", range: RecapRange(.rolling(days: 30, through: today), firstWeekday: w)),
            Preset(title: "Last 90 days", range: RecapRange(.rolling(days: 90, through: today), firstWeekday: w)),
        ]
    }
}
