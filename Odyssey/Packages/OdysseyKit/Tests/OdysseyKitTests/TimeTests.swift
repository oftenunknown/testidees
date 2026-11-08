import Foundation
import Testing
@testable import OdysseyKit

@Suite("Days and ranges")
struct TimeTests {
    @Test func civilRoundTrip() {
        for index in stride(from: -800_000, through: 800_000, by: 997) {
            let day = LocalDay(index: index)
            let c = day.components
            #expect(LocalDay(year: c.year, month: c.month, day: c.day) == day)
        }
        #expect(LocalDay(year: 1970, month: 1, day: 1).index == 0)
        #expect(LocalDay(year: 2000, month: 3, day: 1).index == 11_017)
        #expect(LocalDay(year: 2024, month: 2, day: 29).description == "2024-02-29")
    }

    @Test func weekdays() {
        #expect(LocalDay(year: 1970, month: 1, day: 1).weekday == 3) // Thursday
        #expect(LocalDay(year: 2026, month: 9, day: 27).weekday == 6) // Sunday
        #expect(LocalDay(year: 2026, month: 11, day: 7).isWeekend)
        let wednesday = LocalDay(year: 2026, month: 11, day: 4)
        #expect(wednesday.startOfWeek(firstWeekday: 0) == LocalDay(year: 2026, month: 11, day: 2))
        #expect(wednesday.startOfWeek(firstWeekday: 6) == LocalDay(year: 2026, month: 11, day: 1))
    }

    @Test func monthArithmeticClamps() {
        #expect(LocalDay(year: 2026, month: 1, day: 31).adding(months: 1) == LocalDay(year: 2026, month: 2, day: 28))
        #expect(LocalDay(year: 2024, month: 1, day: 31).adding(months: 1) == LocalDay(year: 2024, month: 2, day: 29))
        #expect(LocalDay(year: 2026, month: 1, day: 15).adding(months: -1) == LocalDay(year: 2025, month: 12, day: 15))
        #expect(LocalDay(year: 2026, month: 8, day: 9).startOfQuarter == LocalDay(year: 2026, month: 7, day: 1))
    }

    @Test func floatingTimes() {
        let day = LocalDay(year: 2026, month: 3, day: 1)
        let t = Floating.date(day, hour: 6, minute: 5, second: 30)
        #expect(Floating.secondsOfDay(t) == 6 * 3600 + 5 * 60 + 30)
        #expect(LocalDay(t) == day)
        // 23:30 UTC on the 1st is 08:30 on the 2nd in Tokyo.
        let instant = Floating.date(day, hour: 23, minute: 30)
        let tokyo = Floating.from(instant, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(LocalDay(tokyo) == day.adding(days: 1))
        #expect(Floating.hour(tokyo) == 8)
    }

    @Test func calendarPeriods() {
        let today = LocalDay(year: 2026, month: 11, day: 7)
        let year = RecapRange(.year(2026))
        #expect(year.days.count == 365)
        #expect(year.effectiveDays(today: today).last == today)
        #expect(year.isInProgress(today: today))
        #expect(year.title() == "2026")
        #expect(year.granularity(today: today) == .month)

        let q = RecapRange.current(.quarter, today: today)
        #expect(q.days.start == LocalDay(year: 2026, month: 10, day: 1))
        #expect(q.title() == "Q4 2026")
        #expect(q.shifted(1).title() == "Q1 2027")
        #expect(q.shifted(-4).title() == "Q4 2025")
        #expect(q.granularity(today: today) == .week)

        let month = RecapRange(.month(year: 2026, month: 2))
        #expect(month.days.count == 28)
        #expect(month.shifted(-2).days.start == LocalDay(year: 2025, month: 12, day: 1))
        #expect(month.title(format: DayFormat(locale: enUS)) == "February 2026")

        let week = RecapRange.current(.week, today: today)
        #expect(week.days.start == LocalDay(year: 2026, month: 11, day: 2))
        #expect(week.days.count == 7)
        #expect(week.granularity(today: today) == .day)

        let rolling = RecapRange(.rolling(days: 30, through: today))
        #expect(rolling.days.count == 30)
        #expect(rolling.days.last == today)
        #expect(rolling.title() == "Last 30 days")
    }

    @Test func previousComparableMatchesElapsedSpan() {
        let today = LocalDay(year: 2026, month: 11, day: 7)
        let prev = RecapRange(.year(2026)).previousComparable(today: today)
        #expect(prev.start == LocalDay(year: 2025, month: 1, day: 1))
        #expect(prev.last == LocalDay(year: 2025, month: 11, day: 7))

        let finished = RecapRange(.year(2025)).previousComparable(today: today)
        #expect(finished.count == 366) // 2024 was a leap year: the whole year is compared

        let month = RecapRange(.month(year: 2026, month: 11)).previousComparable(today: today)
        #expect(month == DayRange(first: LocalDay(year: 2026, month: 10, day: 1), last: LocalDay(year: 2026, month: 10, day: 7)))

        let custom = RecapRange(.custom(DayRange(first: LocalDay(year: 2026, month: 3, day: 1), last: LocalDay(year: 2026, month: 3, day: 10))))
        let before = custom.previousComparable(today: today)
        #expect(before.count == 10)
        #expect(before.end == LocalDay(year: 2026, month: 3, day: 1))
    }

    @Test func labels() {
        let f = DayFormat(locale: enUS)
        let day = LocalDay(year: 2026, month: 9, day: 27)
        #expect(f.weekdayShort(day) == "Sun, Sep 27")
        #expect(f.monthYear(day) == "September 2026")
        #expect(f.weekdayName(0) == "Monday")
        #expect(f.range(DayRange(first: LocalDay(year: 2026, month: 3, day: 3), last: LocalDay(year: 2026, month: 6, day: 19))) == "Mar 3 – Jun 19, 2026")
        let today = LocalDay(year: 2026, month: 11, day: 7)
        #expect(RecapRange(.year(2026)).subtitle(format: f, today: today) == "Jan 1 – Nov 7, 2026 · so far")
    }

    @Test func presets() {
        let today = LocalDay(year: 2026, month: 11, day: 7)
        let presets = RecapRange.presets(today: today)
        #expect(presets.first?.range.period == .year(2026))
        #expect(presets.contains { $0.title == "Last month" && $0.range.period == .month(year: 2026, month: 10) })
        #expect(Set(presets.map(\.id)).count == presets.count)
    }
}
