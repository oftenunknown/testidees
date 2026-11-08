import Foundation

/// A span of real time.
public struct TimeSpan: Hashable, Codable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    public var isEmpty: Bool { end <= start }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// Real-time window certain to contain every activity whose wall-clock day
    /// falls in `days` (time zones range from UTC−12 to UTC+14).
    public static func covering(_ days: DayRange) -> TimeSpan {
        TimeSpan(start: days.start.date.addingTimeInterval(-15 * 3600), end: days.end.date.addingTimeInterval(13 * 3600))
    }

    static func union(_ spans: [TimeSpan]) -> [TimeSpan] {
        let sorted = spans.filter { !$0.isEmpty }.sorted { $0.start < $1.start }
        var out: [TimeSpan] = []
        for span in sorted {
            if let last = out.last, span.start <= last.end {
                out[out.count - 1].end = max(last.end, span.end)
            } else {
                out.append(span)
            }
        }
        return out
    }
}

/// Everything synced from Strava, kept on device. Tracks which time windows
/// have been fetched completely so a sync only asks Strava for the gaps.
public struct ActivityLibrary: Codable, Sendable, Equatable {
    public private(set) var byID: [Int64: Activity]
    public private(set) var coverage: [TimeSpan]
    public var athlete: Athlete?
    public var lastSync: Date?

    public init(activities: [Activity] = [], coverage: [TimeSpan] = [], athlete: Athlete? = nil, lastSync: Date? = nil) {
        byID = Dictionary(activities.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        self.coverage = TimeSpan.union(coverage)
        self.athlete = athlete
        self.lastSync = lastSync
    }

    public var count: Int { byID.count }
    public var isEmpty: Bool { byID.isEmpty }

    /// Oldest first.
    public var activities: [Activity] {
        byID.values.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    public func activities(in days: DayRange) -> [Activity] {
        activities.filter { days.contains($0.day) }
    }

    /// Replaces what we knew about `span` with a fresh, complete fetch: new and
    /// edited activities are stored, deleted ones disappear, and details we
    /// already fetched are kept.
    public mutating func merge(_ fetched: [Activity], covering span: TimeSpan) {
        let fetchedIDs = Set(fetched.map(\.id))
        for (id, activity) in byID where span.contains(activity.start) && !fetchedIDs.contains(id) {
            byID[id] = nil
        }
        for var activity in fetched {
            if activity.details == nil, let old = byID[activity.id]?.details {
                activity.details = old
            }
            byID[activity.id] = activity
        }
        coverage = TimeSpan.union(coverage + [span])
    }

    public mutating func attach(_ details: ActivityDetails, to id: Int64) {
        byID[id]?.details = details
    }

    /// Parts of `needed` not fetched yet.
    public func missing(_ needed: TimeSpan) -> [TimeSpan] {
        var gaps: [TimeSpan] = []
        var cursor = needed.start
        for span in coverage where span.end > needed.start && span.start < needed.end {
            if span.start > cursor { gaps.append(TimeSpan(start: cursor, end: span.start)) }
            cursor = max(cursor, span.end)
        }
        if cursor < needed.end { gaps.append(TimeSpan(start: cursor, end: needed.end)) }
        return gaps.filter { $0.end.timeIntervalSince($0.start) > 60 }
    }

    /// Plan for one sync: the gaps for each range we want, plus a refresh of the
    /// last few days so new and edited activities show up.
    public func syncPlan(for ranges: [DayRange], now: Date, recentDays: Double = 3) -> [TimeSpan] {
        var spans: [TimeSpan] = []
        for days in ranges {
            let needed = TimeSpan.covering(days)
            let clipped = TimeSpan(start: needed.start, end: min(needed.end, now))
            spans += missing(clipped)
        }
        if let lastSync {
            spans.append(TimeSpan(start: lastSync.addingTimeInterval(-recentDays * 86_400), end: now))
        }
        return TimeSpan.union(spans)
    }

    public mutating func removeAll() {
        byID = [:]
        coverage = []
        lastSync = nil
    }
}

/// Picks which activities are worth one extra API call each for details
/// (best efforts for PBs, descriptions for crew mentions, calories).
public enum DetailPlanner {
    public static func candidates(in activities: [Activity], limit: Int) -> [Int64] {
        let pending = activities.filter { $0.details == nil && !$0.isManual }
        let newestFirst = pending.sorted { $0.start > $1.start }
        var picked: [Int64] = []
        var seen = Set<Int64>()
        func take(_ list: [Activity]) {
            for a in list where picked.count < limit && !seen.contains(a.id) {
                picked.append(a.id)
                seen.insert(a.id)
            }
        }
        // Runs that set PRs carry the best efforts we need for the PB page.
        take(newestFirst.filter { $0.sport.family == .run && $0.prCount > 0 })
        // Group activities: descriptions often name who you were with.
        take(newestFirst.filter { $0.isGroup })
        // Races and long runs.
        take(newestFirst.filter { $0.sport.family == .run && ($0.isRace || $0.distance >= 15_000) })
        // Any run with achievements.
        take(newestFirst.filter { $0.sport.family == .run && $0.achievements > 0 })
        return picked
    }
}
