import Foundation

/// Everything a recap shows, computed from activities for one range.
/// Raw numbers in SI units; formatting happens at display time.
public struct Recap: Hashable, Codable, Sendable {
    public var range: RecapRange
    /// The days actually covered (a period in progress ends today).
    public var days: DayRange
    public var filter: SportFilter
    public var athleteFirstName: String?
    public var totals: Totals
    /// Same span one period earlier, when that history is on the device.
    public var previous: Totals?
    public var previousDays: DayRange?
    public var sports: [SportSlice]
    public var calendar: CalendarSummary
    public var rhythm: Rhythm
    public var streaks: Streaks
    public var progression: Progression
    public var highlights: [Highlight]
    public var personalBests: PersonalBests
    public var crew: Crew
    public var places: Places
    public var equivalents: Equivalents
    public var persona: Persona
    public var routes: [RouteSketch]
    public var gear: [GearUsage]
    public var devices: [DeviceUsage]
    public var naming: NamingStats

    public var isEmpty: Bool { totals.count == 0 }

    /// The sport the story should talk about ("you ran"), when one dominates.
    public var mainFamily: SportFamily? {
        if case .family(let f) = filter { return f }
        guard let top = sports.first, top.share >= 0.55 else { return nil }
        return top.family
    }

    public func highlight(_ kind: Highlight.Kind) -> Highlight? {
        highlights.first { $0.kind == kind }
    }
}

public struct Totals: Hashable, Codable, Sendable {
    public var count = 0
    public var distance = 0.0
    public var movingTime = 0.0
    public var elevationGain = 0.0
    public var activeDays = 0
    public var kudos = 0
    public var comments = 0
    public var achievements = 0
    public var prs = 0
    public var photos = 0
    /// Kilocalories; partly estimated when Strava didn't report them.
    public var energy = 0.0
    public var energyEstimatedShare = 0.0
    public var commutes = 0
    public var indoor = 0
    public var groupActivities = 0
    public var races = 0
    public var runDistance = 0.0
    /// Running, walking and hiking.
    public var footDistance = 0.0
    public var rideDistance = 0.0
    public var swimDistance = 0.0

    public init() {}
}

public struct SportSlice: Hashable, Codable, Sendable, Identifiable {
    public var family: SportFamily
    public var count: Int
    public var distance: Double
    public var movingTime: Double
    public var elevationGain: Double
    /// Share of moving time.
    public var share: Double
    public var id: SportFamily { family }
}

public struct DayTotal: Hashable, Codable, Sendable {
    public var day: LocalDay
    public var distance: Double
    public var movingTime: Double
    public var elevationGain: Double
    public var count: Int
    public var family: SportFamily
}

public struct PeriodTotal: Hashable, Codable, Sendable, Identifiable {
    public var start: LocalDay
    public var length: Int
    public var distance: Double
    public var movingTime: Double
    public var elevationGain: Double
    public var count: Int
    public var id: LocalDay { start }

    init(start: LocalDay, length: Int) {
        self.start = start
        self.length = length
        distance = 0
        movingTime = 0
        elevationGain = 0
        count = 0
    }
}

public struct CalendarSummary: Hashable, Codable, Sendable {
    /// Days with at least one activity, in order.
    public var activeDays: [DayTotal]
    public var weeks: [PeriodTotal]
    public var months: [PeriodTotal]
    public var bestWeek: PeriodTotal?
    public var bestMonth: PeriodTotal?
    public var biggestDay: DayTotal?
}

/// A start time worth mentioning (earliest, latest).
public struct TimeOfDayMoment: Hashable, Codable, Sendable {
    public var activityID: Int64
    public var day: LocalDay
    public var secondsOfDay: Int
    public var name: String
    public var sport: Sport
}

public struct Rhythm: Hashable, Codable, Sendable {
    /// Monday first.
    public var weekdayCounts: [Int]
    public var hourCounts: [Int]
    public var favoriteWeekday: Int?
    public var peakHour: Int?
    /// Before 08:00.
    public var earlyShare: Double
    /// From 19:00.
    public var lateShare: Double
    /// 11:30–14:00.
    public var lunchShare: Double
    public var weekendShare: Double
    public var earliest: TimeOfDayMoment?
    public var latest: TimeOfDayMoment?
}

public struct Streak: Hashable, Codable, Sendable {
    public var length: Int
    public var start: LocalDay
    /// Inclusive.
    public var end: LocalDay
}

public struct Streaks: Hashable, Codable, Sendable {
    /// Consecutive active days.
    public var longestDays: Streak?
    /// Consecutive weeks with at least one activity.
    public var longestWeeks: Streak?
    /// Longest gap without activity.
    public var longestBreak: Streak?
    /// Active-day streak still running at the end of the range.
    public var current: Streak?
}

/// One bar of the progression chart.
public struct Bucket: Hashable, Codable, Sendable, Identifiable {
    public var start: LocalDay
    public var length: Int
    public var distance: Double
    public var movingTime: Double
    public var elevationGain: Double
    public var count: Int
    /// Seconds per metre for runs in the bucket.
    public var runPace: Double?
    public var id: LocalDay { start }
}

public struct TrendPoint: Hashable, Codable, Sendable {
    public var day: LocalDay
    public var value: Double
}

/// A fitted line through noisy samples, reported at its two ends.
public struct Trend: Hashable, Codable, Sendable {
    public var start: Double
    public var end: Double
    public var samples: Int
    public var points: [TrendPoint]

    public var change: Double { end - start }
    public var relativeChange: Double { start != 0 ? (end - start) / start : 0 }
}

/// Relative changes (0.12 = +12%).
public struct Comparison: Hashable, Codable, Sendable {
    public var distance: Double?
    public var movingTime: Double?
    public var count: Double?
    public var elevationGain: Double?
}

public struct Progression: Hashable, Codable, Sendable {
    public var granularity: Granularity
    public var buckets: [Bucket]
    /// Run pace in seconds per metre (going down is good).
    public var runPace: Trend?
    /// Ride speed in m/s.
    public var rideSpeed: Trend?
    /// Metres per heartbeat on runs (going up is good).
    public var runEfficiency: Trend?
    /// Each time your longest run got longer.
    public var longestRunSteps: [TrendPoint]
    public var vsPrevious: Comparison?
    /// Second half vs first half of the range.
    public var halves: Comparison?
}

public struct Highlight: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case longest, longestDuration, biggestClimb, fastestRun, fastestRide, mostKudos
        case earliestStart, latestStart, biggestWeek, busiestMonth, firstActivity
        case furthestAway, biggestGroup, race, longestSwim, personalBest
    }

    public var kind: Kind
    public var day: LocalDay
    public var activityID: Int64?
    public var name: String?
    public var sport: Sport?
    /// Meaning depends on `kind` (metres, seconds, s/m, m/s, count, km…).
    public var value: Double
    public var secondary: Double?
    public var id: String { kind.rawValue }
}

public struct EffortRecord: Hashable, Codable, Sendable {
    public var distance: StandardDistance
    public var time: Double
    public var day: LocalDay
    public var activityID: Int64
    public var activityName: String
    public var wasPR: Bool
}

public struct EffortProgress: Hashable, Codable, Sendable, Identifiable {
    public var distance: StandardDistance
    /// Fastest in the range.
    public var best: EffortRecord
    /// PRs set during the range, oldest first.
    public var prs: [EffortRecord]
    /// The first effort at this distance in the range, to show how far you came.
    public var first: EffortRecord
    public var id: StandardDistance { distance }

    /// Seconds saved from the first effort of the range to the best.
    public var improvement: Double { max(0, first.time - best.time) }
}

public struct PersonalBests: Hashable, Codable, Sendable {
    public var items: [EffortProgress]
    public var prCount: Int
    /// Runs whose details (best efforts) are on the device.
    public var runsChecked: Int
    public var runsTotal: Int

    public var headline: [EffortProgress] { items.filter { $0.distance.isHeadline } }
}

public struct Companion: Hashable, Codable, Sendable, Identifiable {
    public var name: String
    public var count: Int
    public var distance: Double
    public var movingTime: Double
    public var firstDay: LocalDay
    public var lastDay: LocalDay
    public var families: [SportFamily]
    public var activityIDs: [Int64]
    /// Tagged by you rather than read from titles and descriptions.
    public var confirmed: Bool
    public var id: String { name.lowercased() }
}

public struct Crew: Hashable, Codable, Sendable {
    public var groupCount: Int
    public var groupDistance: Double
    public var groupTime: Double
    /// Share of activities done with others.
    public var share: Double
    public var biggestGroup: Highlight?
    public var companions: [Companion]
    /// Group activities nobody is tagged on yet.
    public var untaggedGroupIDs: [Int64]
}

public struct FarPoint: Hashable, Codable, Sendable {
    public var activityID: Int64
    public var day: LocalDay
    public var name: String
    public var sport: Sport
    public var coordinate: Coordinate
    public var distanceKm: Double
}

public struct Places: Hashable, Codable, Sendable {
    /// Where most activities start (rounded, never shown on a map).
    public var home: Coordinate?
    /// Distinct ~1 km start areas.
    public var startAreas: Int
    public var furthest: FarPoint?
}

public struct RoutePoint: Hashable, Codable, Sendable {
    public var x: Float
    public var y: Float
}

/// A route shape for route art: no map, no scale, ends trimmed.
public struct RouteSketch: Hashable, Codable, Sendable, Identifiable {
    public var id: Int64
    public var family: SportFamily
    public var distance: Double
    /// Unit square, aspect preserved, centred.
    public var points: [RoutePoint]
}

public struct GearUsage: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: Gear.Kind
    public var distance: Double
    public var count: Int
}

public struct DeviceUsage: Hashable, Codable, Sendable, Identifiable {
    public var name: String
    public var count: Int
    public var id: String { name }
}

public struct NamingStats: Hashable, Codable, Sendable {
    public var total: Int
    /// Still called "Morning Run" and friends.
    public var defaultNamed: Int
    public var topDefaultName: String?
    public var topDefaultCount: Int

    public var defaultShare: Double { total > 0 ? Double(defaultNamed) / Double(total) : 0 }
}
